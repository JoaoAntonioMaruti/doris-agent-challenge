defmodule Doris.LLM.Embeddings do
  @moduledoc """
  Embeddings via OpenRouter (`/embeddings`, model `:embedding` from config).
  Validates the vector size so a provider change never silently corrupts the table.
  """

  @dimensions 1536

  def dimensions, do: @dimensions

  @spec embed([String.t()]) :: {:ok, [[float()]]} | {:error, term()}
  def embed([]), do: {:ok, []}

  def embed(texts) when is_list(texts) do
    config = Application.fetch_env!(:doris, :openrouter)
    model = Application.fetch_env!(:doris, :models) |> Keyword.fetch!(:embedding)

    options =
      [
        base_url: config[:base_url],
        url: "/embeddings",
        auth: {:bearer, config[:api_key] || ""},
        json: %{model: model, input: texts},
        receive_timeout: 20_000,
        retry: false
      ] ++ Application.get_env(:doris, :openrouter_req_options, [])

    case Req.post(options) do
      {:ok, %{status: 200, body: %{"data" => data}}} when length(data) == length(texts) ->
        vectors = data |> Enum.sort_by(& &1["index"]) |> Enum.map(& &1["embedding"])

        if Enum.all?(vectors, &(is_list(&1) and length(&1) == @dimensions)),
          do: {:ok, vectors},
          else: {:error, {:unexpected_dimensions, Enum.map(vectors, &length/1)}}

      {:ok, %{status: status}} ->
        {:error, {:http, status}}

      {:error, exception} ->
        {:error, Exception.message(exception)}
    end
  end
end
