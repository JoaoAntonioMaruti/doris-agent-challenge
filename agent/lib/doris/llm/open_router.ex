defmodule Doris.LLM.OpenRouter do
  @moduledoc """
  Non-streaming Chat Completions client for OpenRouter.

  Tries the agent model first and, on a transport/5xx/429 failure, the fallback model once.
  Both models were verified to support native tool calling (see code-agent/decisions.md).
  """
  require Logger

  @doc """
  Returns `{:ok, message}` where `message` is the assistant message map from the API
  (`"content"` and optionally `"tool_calls"`), or `{:error, reason}`.

  Options: `:tools`, `:model` (`:agent` | `:memory` | a model id), `:max_tokens`, `:response_format`.
  """
  def chat(messages, opts \\ []) do
    models = candidate_models(Keyword.get(opts, :model, :agent))
    try_models(models, messages, opts)
  end

  defp try_models([model | rest], messages, opts) do
    case request(model, messages, opts) do
      {:ok, message} ->
        {:ok, message}

      {:error, {:retryable, reason}} when rest != [] ->
        Logger.warning("model #{model} failed (#{inspect(reason)}), trying #{hd(rest)}")
        try_models(rest, messages, opts)

      {:error, {_kind, reason}} ->
        {:error, reason}
    end
  end

  defp request(model, messages, opts) do
    body =
      %{
        model: model,
        messages: messages,
        max_tokens: Keyword.get(opts, :max_tokens, config(:max_tokens)),
        temperature: Keyword.get(opts, :temperature, config(:temperature))
      }
      |> put_optional(:tools, Keyword.get(opts, :tools))
      |> put_optional(:response_format, Keyword.get(opts, :response_format))

    case Req.post(req(), url: "/chat/completions", json: body) do
      {:ok, %{status: 200, body: %{"choices" => [%{"message" => message} | _]}}} ->
        {:ok, message}

      {:ok, %{status: status, body: body}} when status == 429 or status >= 500 ->
        {:error, {:retryable, {:http, status, body}}}

      {:ok, %{status: status, body: body}} ->
        {:error, {:permanent, {:http, status, body}}}

      {:error, exception} ->
        {:error, {:retryable, exception}}
    end
  end

  defp candidate_models(:agent), do: Enum.uniq([model(:agent), model(:fallback)])
  defp candidate_models(role) when is_atom(role), do: [model(role)]
  defp candidate_models(model_id) when is_binary(model_id), do: [model_id]

  defp model(role), do: Application.fetch_env!(:doris, :models) |> Keyword.fetch!(role)

  defp put_optional(map, _key, nil), do: map
  defp put_optional(map, key, value), do: Map.put(map, key, value)

  defp req do
    Req.new(
      base_url: config(:base_url),
      auth: {:bearer, config(:api_key) || ""},
      receive_timeout: config(:receive_timeout),
      retry: false
    )
    |> Req.merge(Application.get_env(:doris, :openrouter_req_options, []))
  end

  defp config(key), do: Application.fetch_env!(:doris, :openrouter) |> Keyword.fetch!(key)
end
