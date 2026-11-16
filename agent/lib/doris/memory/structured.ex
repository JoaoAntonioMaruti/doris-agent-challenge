defmodule Doris.Memory.Structured do
  @moduledoc """
  Memory v1: a structured profile per user (`user_preferences`), always keyed by the full
  `user_id`. The LLM only proposes a validated change set from the user's own message;
  merging and persistence are done in code with an optimistic lock.
  """
  require Logger
  import Ecto.Query
  alias Doris.Repo
  alias Doris.LLM.OpenRouter
  alias Doris.Memory.Preferences

  @max_items 8
  @max_text 300

  def load(user_id, _query_text) do
    prefs = get(user_id)

    %{
      prompt: if(Preferences.empty?(prefs), do: nil, else: Preferences.to_prompt(prefs)),
      avoid_colors: prefs.disliked_colors
    }
  end

  @doc """
  `turn` is `%{user_text: String.t()}`. Returns `{:ok, prefs}`, `:unchanged` or `{:error, reason}`.
  """
  def update(user_id, %{user_text: text}) when is_binary(text) do
    current = get(user_id)

    with {:ok, changes} <- extract(text, current),
         false <- changes == %{} do
      save(user_id, changes, 2)
    else
      true -> :unchanged
      {:error, reason} -> {:error, reason}
    end
  end

  def get(user_id), do: Repo.get(Preferences, user_id) || %Preferences{user_id: user_id}

  defp save(_user_id, _changes, 0), do: {:error, :version_conflict}

  defp save(user_id, changes, attempts) do
    current = get(user_id)
    merged = Preferences.merge(current, changes)

    result =
      if current.inserted_at do
        fields =
          Map.take(merged, [:size, :disliked_colors, :preferred_styles, :budget_max, :notes])

        {count, _} =
          Repo.update_all(
            from(p in Preferences, where: p.user_id == ^user_id and p.version == ^current.version),
            set:
              Enum.to_list(fields) ++
                [version: current.version + 1, updated_at: DateTime.utc_now()]
          )

        count == 1
      else
        match?({:ok, _}, Repo.insert(merged, on_conflict: :nothing, conflict_target: :user_id)) and
          Repo.get(Preferences, user_id) != nil
      end

    if result, do: {:ok, get(user_id)}, else: save(user_id, changes, attempts - 1)
  end

  # ── extraction ────────────────────────────────────────────────────────────────

  @instructions """
  Extraia preferências de moda que a PESSOA declarou sobre si mesma na mensagem abaixo.
  Responda só com JSON, com estas chaves (use null ou [] quando a mensagem não disser nada):
  {"size": string|null, "add_disliked_colors": [string], "remove_disliked_colors": [string],
   "add_styles": [string], "remove_styles": [string], "budget_max": number|null, "notes": string|null}
  Regras: cores e estilos em minúsculas e no masculino singular (ex.: "amarelo", "minimalista").
  "remove_*" só quando a pessoa disser explicitamente que mudou de ideia (ex.: "agora gosto de amarelo").
  budget_max só se ela declarar um orçamento geral (não o preço de um pedido pontual).
  notes: um fato estável curto (ex.: "trabalha em escritório"), senão null. Ignore pedidos pontuais.
  """

  defp extract(text, current) do
    messages = [
      %{role: "system", content: @instructions},
      %{
        role: "user",
        content:
          "Perfil atual: #{Preferences.to_prompt(current)}\n\nMensagem: #{String.slice(text, 0, 2000)}"
      }
    ]

    case OpenRouter.chat(messages,
           model: :memory,
           purpose: "memory.preferences",
           max_tokens: 300,
           temperature: 0.0,
           response_format: %{type: "json_object"}
         ) do
      {:ok, %{"content" => content}} when is_binary(content) ->
        with {:error, :invalid_json} = error <- parse(content) do
          Logger.warning(
            "memory extraction returned invalid JSON: #{inspect(String.slice(content, 0, 300))}"
          )

          error
        end

      {:ok, _} ->
        {:error, :empty_extraction}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc false
  def parse(content) do
    json = content |> String.replace(~r/^```(json)?|```$/m, "") |> String.trim()

    case Jason.decode(json) do
      {:ok, map} when is_map(map) -> {:ok, validate(map)}
      _ -> {:error, :invalid_json}
    end
  end

  # Keeps only well-typed, bounded values; anything else is treated as "not mentioned".
  defp validate(map) do
    %{}
    |> put_text(:size, map["size"], 10)
    |> put_list(:add_disliked_colors, map["add_disliked_colors"])
    |> put_list(:remove_disliked_colors, map["remove_disliked_colors"])
    |> put_list(:add_styles, map["add_styles"])
    |> put_list(:remove_styles, map["remove_styles"])
    |> put_budget(map["budget_max"])
    |> put_text(:notes, map["notes"], @max_text)
  end

  defp put_text(acc, key, value, max) when is_binary(value) do
    case String.trim(value) do
      "" -> acc
      v -> Map.put(acc, key, String.slice(v, 0, max))
    end
  end

  defp put_text(acc, _key, _value, _max), do: acc

  defp put_list(acc, key, values) when is_list(values) do
    case values
         |> Enum.filter(&is_binary/1)
         |> Enum.map(&(&1 |> String.trim() |> String.downcase()))
         |> Enum.reject(&(&1 == ""))
         |> Enum.take(@max_items) do
      [] -> acc
      list -> Map.put(acc, key, Enum.uniq(list))
    end
  end

  defp put_list(acc, _key, _values), do: acc

  defp put_budget(acc, n) when is_number(n) and n > 0 and n < 100_000,
    do: Map.put(acc, :budget_max, Decimal.from_float(n / 1))

  defp put_budget(acc, _), do: acc
end
