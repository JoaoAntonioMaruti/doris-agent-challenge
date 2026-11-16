defmodule Doris.Agent.Tools do
  @moduledoc """
  Tools the model sees. Each one is a deterministic orchestration of proxy tools
  (see `Doris.Agent.Orchestrators`); the model chooses intent and candidates, the code
  controls ordering, ids and constraints.
  """
  alias Doris.Agent.Orchestrators

  @specs [
    {"find_products",
     "Busca produtos no catálogo. Use termos curtos em português (peça + atributo, ex.: 'camisa linho branca'). Aplica teto de preço e cores evitadas no código.",
     %{
       "query" => %{"type" => "string"},
       "max_price" => %{
         "type" => "number",
         "description" => "Teto de preço em R$, se a pessoa pediu."
       },
       "avoid_colors" => %{"type" => "array", "items" => %{"type" => "string"}},
       "limit" => %{"type" => "integer", "minimum" => 1, "maximum" => 8}
     }, ["query"]},
    {"recommend_outfit",
     "Monta um look: uma busca por peça (ex.: camisa, calça, sapato). Devolve candidatos por peça para você escolher uma combinação coerente.",
     %{
       "pieces" => %{
         "type" => "array",
         "minItems" => 1,
         "maxItems" => 4,
         "items" => %{
           "type" => "object",
           "properties" => %{"piece" => %{"type" => "string"}, "query" => %{"type" => "string"}},
           "required" => ["piece", "query"]
         }
       },
       "max_price_per_piece" => %{"type" => "number"},
       "avoid_colors" => %{"type" => "array", "items" => %{"type" => "string"}}
     }, ["pieces"]},
    {"show_products",
     "Mostra cards de produtos para a pessoa. Só ids retornados por find_products/recommend_outfit.",
     %{
       "product_ids" => %{
         "type" => "array",
         "items" => %{"type" => "string"},
         "minItems" => 1,
         "maxItems" => 4
       }
     }, ["product_ids"]},
    {"try_on",
     "Gera e mostra o try-on de UMA peça no avatar da pessoa: product_id (do catálogo) OU garment_id (do guarda-roupa). Para várias peças, escolha a principal.",
     %{"product_id" => %{"type" => "string"}, "garment_id" => %{"type" => "string"}}, []},
    {"get_looks",
     "Busca os looks da pessoa (mais recente primeiro). As imagens dos primeiros looks são anexadas para você avaliar.",
     %{"limit" => %{"type" => "integer", "minimum" => 1, "maximum" => 5}}, []},
    {"show_look", "Mostra um look/try-on existente (look_id ou tryon_id já retornado).",
     %{"look_id" => %{"type" => "string"}}, ["look_id"]},
    {"get_wardrobe",
     "Lista as peças do guarda-roupa da pessoa, opcionalmente por tipo (TOP, BOTTOM, DRESS, SHOES…).",
     %{"garment_types" => %{"type" => "array", "items" => %{"type" => "string"}}}, []}
  ]

  @dispatch %{
    "find_products" => &Orchestrators.find_products/2,
    "recommend_outfit" => &Orchestrators.recommend_outfit/2,
    "show_products" => &Orchestrators.show_products/2,
    "try_on" => &Orchestrators.try_on/2,
    "get_looks" => &Orchestrators.get_looks/2,
    "show_look" => &Orchestrators.show_look/2,
    "get_wardrobe" => &Orchestrators.get_wardrobe/2
  }

  def definitions do
    for {name, description, properties, required} <- @specs do
      %{
        type: "function",
        function: %{
          name: name,
          description: description,
          parameters: %{type: "object", properties: properties, required: required}
        }
      }
    end
  end

  @doc "Runs a tool call. Returns `{result_map, state}`; never raises on bad model input."
  def run(name, raw_args, state) do
    case {Map.fetch(@dispatch, name), decode(raw_args)} do
      {{:ok, fun}, {:ok, args}} -> fun.(args, state)
      {{:ok, _fun}, :error} -> {%{ok: false, error: "argumentos não são JSON válido"}, state}
      {:error, _} -> {%{ok: false, error: "tool desconhecida: #{name}"}, state}
    end
  end

  defp decode(args) when is_map(args), do: {:ok, args}

  defp decode(args) when is_binary(args) do
    case Jason.decode(if(args == "", do: "{}", else: args)) do
      {:ok, map} when is_map(map) -> {:ok, map}
      _ -> :error
    end
  end

  defp decode(_), do: :error
end
