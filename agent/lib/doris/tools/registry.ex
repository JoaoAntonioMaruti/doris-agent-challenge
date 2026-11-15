defmodule Doris.Tools.Registry do
  @moduledoc """
  Contracts of the proxy tools (docs/proxy-api.md): JSON schema of the arguments and a
  validator that runs before any HTTP call. `conversation_id` is never part of the
  arguments: the executor always injects it.
  """

  @tools %{
    "search_by_text" => %{
      description: "Busca produtos no catálogo por texto. Não filtra preço, tamanho nem cor.",
      properties: %{
        "query" => %{"type" => "string", "minLength" => 1},
        "limit" => %{"type" => "integer", "minimum" => 1, "maximum" => 12}
      },
      required: ["query"]
    },
    "garment_creation" => %{
      description:
        "Cria a peça (garment) a partir de um search_item_id. Necessária antes do try-on.",
      properties: %{"search_item_id" => %{"type" => "string", "minLength" => 1}},
      required: ["search_item_id"]
    },
    "tryon" => %{
      description: "Veste UMA peça no avatar da pessoa.",
      properties: %{
        "garment_ids" => %{
          "type" => "array",
          "items" => %{"type" => "string"},
          "minItems" => 1,
          "maxItems" => 1
        },
        "avatar_pose" => %{"type" => "string", "enum" => ["NORMAL"]}
      },
      required: ["garment_ids"]
    },
    "avatar" => %{description: "Avatar da pessoa.", properties: %{}, required: []},
    "looks" => %{
      description: "Looks da pessoa, do mais recente para o mais antigo.",
      properties: %{"limit" => %{"type" => "integer", "minimum" => 1, "maximum" => 50}},
      required: []
    },
    "wardrobe" => %{
      description: "Peças que a pessoa já tem.",
      properties: %{"garment_types" => %{"type" => "array", "items" => %{"type" => "string"}}},
      required: []
    },
    "show_artifact" => %{
      description: "Mostra um card no chat.",
      properties: %{
        "type" => %{"type" => "string", "enum" => ["PRODUCT", "GARMENT", "TRYON_CARD"]},
        "value" => %{"type" => "string", "minLength" => 1}
      },
      required: ["type", "value"]
    }
  }

  def names, do: Map.keys(@tools)

  @doc "OpenAI-style JSON schema for a tool's arguments."
  def schema(name) do
    spec = Map.fetch!(@tools, name)

    %{
      "type" => "object",
      "properties" => spec.properties,
      "required" => spec.required,
      "additionalProperties" => false
    }
  end

  @doc """
  Validates arguments against the contract. Unknown keys are dropped (the proxy ignores
  them anyway). Returns `{:ok, args}` or `{:error, message}`.
  """
  def validate(name, args) when is_map(args) do
    case Map.fetch(@tools, name) do
      :error ->
        {:error, "unknown tool #{inspect(name)}"}

      {:ok, spec} ->
        args = Map.take(args, Map.keys(spec.properties))

        with :ok <- check_required(spec.required, args) do
          Enum.reduce_while(args, {:ok, args}, fn {key, value}, acc ->
            case check(spec.properties[key], value) do
              :ok -> {:cont, acc}
              {:error, why} -> {:halt, {:error, "#{name}.#{key} #{why}"}}
            end
          end)
        end
    end
  end

  def validate(name, _args), do: {:error, "#{name} arguments must be an object"}

  defp check_required(required, args) do
    case Enum.reject(required, &Map.has_key?(args, &1)) do
      [] -> :ok
      missing -> {:error, "missing required argument(s): #{Enum.join(missing, ", ")}"}
    end
  end

  defp check(%{"type" => "string"} = s, v) when is_binary(v) do
    cond do
      String.length(String.trim(v)) < Map.get(s, "minLength", 0) ->
        {:error, "must not be empty"}

      Map.has_key?(s, "enum") and v not in s["enum"] ->
        {:error, "must be one of #{inspect(s["enum"])}"}

      true ->
        :ok
    end
  end

  defp check(%{"type" => "integer"} = s, v) when is_integer(v) do
    if v < Map.get(s, "minimum", v) or v > Map.get(s, "maximum", v),
      do: {:error, "out of range"},
      else: :ok
  end

  defp check(%{"type" => "array"} = s, v) when is_list(v) do
    cond do
      not Enum.all?(v, &is_binary/1) -> {:error, "must contain only strings"}
      length(v) < Map.get(s, "minItems", 0) -> {:error, "has too few items"}
      length(v) > Map.get(s, "maxItems", length(v)) -> {:error, "has too many items"}
      true -> :ok
    end
  end

  defp check(%{"type" => type}, _v), do: {:error, "must be of type #{type}"}
end
