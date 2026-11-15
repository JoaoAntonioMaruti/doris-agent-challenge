defmodule Doris.Agent.Orchestrators do
  @moduledoc """
  Deterministic pipelines behind the model-facing tools. Every function takes the decoded
  arguments and the turn state, and returns `{result_for_model, state}`.

  Rules enforced here, not in the prompt:
    * ids must be in the conversation allowlist (`Doris.Agent.State`);
    * price ceiling and avoided colours filter search results and are re-checked on show;
    * try-on always runs garment_creation → tryon (one garment) → show_artifact,
      falling back to the product card when it fails.
  """
  alias Doris.{SSE}
  alias Doris.Agent.{Filters, State}
  alias Doris.Tools.Executor

  @description_chars 240

  # ── search ──────────────────────────────────────────────────────────────────

  def find_products(%{"query" => query} = args, state) when is_binary(query) do
    state = put_constraints(state, args["max_price"], args["avoid_colors"])
    limit = clamp(args["limit"], 1, 8, 6)

    with_feedback(state, "search", "Buscando #{query}…", fn state ->
      case search(state, query, limit) do
        {:ok, products, state} ->
          {:ok, %{ok: true, products: Enum.map(products, &summary/1)}, state}

        {:error, error, state} ->
          {:error, tool_error(error), state}
      end
    end)
  end

  def find_products(_args, state), do: {invalid("query é obrigatório"), state}

  def recommend_outfit(%{"pieces" => pieces} = args, state)
      when is_list(pieces) and pieces != [] do
    state = put_constraints(state, args["max_price_per_piece"], args["avoid_colors"])

    with_feedback(state, "outfit", "Montando o look…", fn state ->
      {groups, state} =
        pieces
        |> Enum.take(4)
        |> Enum.map_reduce(state, fn piece, state ->
          case search(state, piece["query"] || "", 3) do
            {:ok, products, state} ->
              {%{piece: piece["piece"], candidates: Enum.map(products, &summary/1)}, state}

            {:error, error, state} ->
              {%{piece: piece["piece"], error: error.message}, state}
          end
        end)

      {:ok, %{ok: true, pieces: groups}, state}
    end)
  end

  def recommend_outfit(_args, state), do: {invalid("pieces é obrigatório"), state}

  defp search(state, query, limit) do
    if String.trim(query) == "" do
      {:error, %{code: "invalid_arguments", message: "query vazia", retryable: false}, state}
    else
      case call(state, "search_by_text", %{"query" => query, "limit" => min(limit * 2, 12)}) do
        {:ok, %{"products" => products}} ->
          state = State.add_products(state, products)
          kept = Filters.apply(products, state.max_price, state.avoid_colors) |> Enum.take(limit)
          {:ok, kept, state}

        {:ok, _} ->
          {:ok, [], state}

        {:error, error} ->
          {:error, error, state}
      end
    end
  end

  # ── showing ─────────────────────────────────────────────────────────────────

  def show_products(%{"product_ids" => ids}, state) when is_list(ids) do
    {results, state} =
      ids
      |> Enum.uniq()
      |> Enum.take(4)
      |> Enum.map_reduce(state, &show_product/2)

    {%{ok: Enum.any?(results, & &1.shown), results: results}, state}
  end

  def show_products(_args, state), do: {invalid("product_ids é obrigatório"), state}

  defp show_product(id, state) do
    product = state.products[id]

    cond do
      product == nil ->
        {%{id: id, shown: false, reason: "id desconhecido: use só ids retornados pela busca"},
         state}

      not Filters.within_budget?(product, state.max_price) ->
        {%{id: id, shown: false, reason: "acima do teto de R$#{state.max_price}"}, state}

      Enum.any?(state.avoid_colors, &Filters.mentions_color?(product, &1)) ->
        {%{id: id, shown: false, reason: "cor que a pessoa evita"}, state}

      true ->
        show(state, "PRODUCT", id, %{id: id})
    end
  end

  def show_look(%{"look_id" => id}, state) when is_binary(id) do
    if State.known_tryon?(state, id) do
      {result, state} = show(state, "TRYON_CARD", id, %{look_id: id})
      {Map.put(result, :ok, result.shown), state}
    else
      {%{ok: false, error: "look_id desconhecido: chame get_looks antes"}, state}
    end
  end

  def show_look(_args, state), do: {invalid("look_id é obrigatório"), state}

  defp show(state, type, value, base) do
    if MapSet.member?(state.shown, {type, value}) do
      {Map.put(base, :shown, true), state}
    else
      case call(state, "show_artifact", %{"type" => type, "value" => value}) do
        {:ok, _} ->
          {Map.put(base, :shown, true), %{state | shown: MapSet.put(state.shown, {type, value})}}

        {:error, error} ->
          {Map.merge(base, %{shown: false, reason: error.message}), state}
      end
    end
  end

  # ── try-on pipeline ───────────────────────────────────────────────────────────

  def try_on(%{"product_id" => id}, state) when is_binary(id) do
    cond do
      not State.known_product?(state, id) ->
        {%{ok: false, error: "product_id desconhecido: use só ids retornados pela busca"}, state}

      not Filters.within_budget?(state.products[id], state.max_price) ->
        {%{ok: false, error: "produto acima do teto de preço"}, state}

      true ->
        with_feedback(state, "tryon", "Gerando seu try-on…", fn state ->
          case call(state, "garment_creation", %{"search_item_id" => id}) do
            {:ok, %{"garment_id" => garment_id}} ->
              state = State.add_garment(state, garment_id, id)
              run_tryon(state, garment_id, id)

            {:error, error} ->
              fallback_to_product(state, id, error)
          end
        end)
    end
  end

  def try_on(%{"garment_id" => id}, state) when is_binary(id) do
    if State.known_garment?(state, id) do
      with_feedback(state, "tryon", "Gerando seu try-on…", fn state ->
        run_tryon(state, id, state.garment_products[id])
      end)
    else
      {%{ok: false, error: "garment_id desconhecido: chame get_wardrobe ou use product_id"},
       state}
    end
  end

  def try_on(_args, state), do: {invalid("informe product_id ou garment_id (uma peça)"), state}

  defp run_tryon(state, garment_id, product_id) do
    case call(state, "tryon", %{"garment_ids" => [garment_id], "avatar_pose" => "NORMAL"}) do
      {:ok, %{"tryon_id" => tryon_id} = data} ->
        state = State.add_tryon(state, Enum.reject([tryon_id, data["look_id"]], &is_nil/1))
        {shown, state} = show(state, "TRYON_CARD", tryon_id, %{})

        if shown.shown do
          {:ok, %{ok: true, tryon_id: tryon_id, shown: true}, state}
        else
          fallback_to_product(state, product_id, %{message: "não foi possível mostrar o try-on"})
        end

      {:error, error} ->
        fallback_to_product(state, product_id, error)
    end
  end

  defp fallback_to_product(state, nil, error), do: {:error, tool_error(error), state}

  defp fallback_to_product(state, product_id, error) do
    {shown, state} = show_product(product_id, state)

    {:error,
     %{
       ok: false,
       error: "try-on indisponível: #{error.message}",
       fallback: if(shown.shown, do: "card do produto mostrado", else: "nada mostrado")
     }, state}
  end

  # ── looks and wardrobe ───────────────────────────────────────────────────────

  def get_looks(args, state) do
    limit = clamp(args["limit"], 1, 5, 3)

    with_feedback(state, "looks", "Olhando seus looks…", fn state ->
      case call(state, "looks", %{"limit" => limit}) do
        {:ok, %{"looks" => looks}} ->
          state = State.add_looks(state, Enum.map(looks, & &1["look_id"]))
          state = attach_images(state, Enum.take(looks, 2))

          summary =
            Enum.map(
              looks,
              &Map.take(&1, ["look_id", "description", "created_at", "garment_ids"])
            )

          {:ok,
           %{ok: true, looks: summary, note: "imagens dos 2 mais recentes anexadas a seguir"},
           state}

        {:error, error} ->
          {:error, tool_error(error), state}
      end
    end)
  end

  def get_wardrobe(args, state) do
    types = if is_list(args["garment_types"]), do: args["garment_types"], else: nil

    case call(state, "wardrobe", if(types, do: %{"garment_types" => types}, else: %{})) do
      {:ok, %{"garments" => garments}} ->
        state = Enum.reduce(garments, state, &State.add_garment(&2, &1["garment_id"]))

        {%{
           ok: true,
           garments:
             Enum.map(garments, fn g ->
               %{
                 garment_id: g["garment_id"],
                 type: g["type"],
                 category: g["category"],
                 tags: get_in(g, ["metadata", "tags"])
               }
             end)
         }, state}

      {:error, error} ->
        {tool_error(error), state}
    end
  end

  # Looks are images: tool results are text-only, so the images go in a follow-up user
  # message that the runner appends after the tool results.
  defp attach_images(state, []), do: state

  defp attach_images(state, looks) do
    parts =
      [
        %{
          type: "text",
          text: "[Sistema] Imagens dos looks retornados por get_looks, para avaliação:"
        }
      ] ++
        Enum.flat_map(looks, fn look ->
          [
            %{type: "text", text: "look_id #{look["look_id"]}: #{look["description"]}"},
            %{type: "image_url", image_url: %{url: look["tryon_image_url"]}}
          ]
        end)

    %{state | extra_messages: state.extra_messages ++ [%{role: "user", content: parts}]}
  end

  # ── helpers ─────────────────────────────────────────────────────────────────

  defp call(state, tool, args) do
    Executor.call(state.conversation_id, tool, args, deadline: state.deadline)
  end

  # Wraps a pipeline with a feedback line (running → done/error).
  defp with_feedback(state, prefix, text, fun) do
    {id, state} = State.next_feedback_id(state, prefix)
    state.emit.(SSE.feedback(id, text, :running))

    {status, result, state} = fun.(state)

    state.emit.(
      SSE.feedback(id, text_for(status, text), if(status == :ok, do: :done, else: :error))
    )

    {result, state}
  end

  defp text_for(:ok, text), do: String.replace_suffix(text, "…", "")
  defp text_for(:error, text), do: String.replace_suffix(text, "…", "") <> " — falhou"

  # Constraints only tighten within a turn: a lower ceiling or new colours win.
  defp put_constraints(state, max_price, colors) do
    max_price =
      case {state.max_price, max_price} do
        {nil, p} when is_number(p) and p > 0 -> p
        {cur, p} when is_number(p) and p > 0 -> min(cur, p)
        {cur, _} -> cur
      end

    colors = if is_list(colors), do: Enum.filter(colors, &is_binary/1), else: []
    %{state | max_price: max_price, avoid_colors: Enum.uniq(state.avoid_colors ++ colors)}
  end

  # Catalog text is untrusted (it may contain prompt injection): truncate it and label it.
  defp summary(p) do
    %{
      id: p["search_item_id"],
      name: p["name"],
      store: p["store"],
      price: p["price"],
      untrusted_store_description: String.slice(p["description"] || "", 0, @description_chars)
    }
  end

  defp tool_error(error), do: %{ok: false, error: error.message, code: error.code}
  defp invalid(message), do: %{ok: false, error: message}

  defp clamp(n, lo, hi, _default) when is_integer(n), do: n |> max(lo) |> min(hi)
  defp clamp(_n, _lo, _hi, default), do: default
end
