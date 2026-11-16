defmodule Doris.Tools.Executor do
  @moduledoc """
  Calls proxy tools over HTTP. Validates arguments first, always sends `conversation_id`,
  unwraps the `{ok, data | error}` envelope and retries only errors marked `retryable`.
  """
  require Logger
  alias Doris.Tools.Registry

  @type error :: %{code: String.t(), message: String.t(), retryable: boolean()}

  @doc """
  Returns `{:ok, data}` or `{:error, error}`. `show_artifact` returns `{:ok, %{}}`.

  Options: `:max_attempts` (default 2), `:deadline` (monotonic ms; no retry after it).
  """
  @spec call(String.t(), String.t(), map(), keyword()) :: {:ok, map()} | {:error, error()}
  def call(conversation_id, tool, args, opts \\ []) do
    case Registry.validate(tool, args) do
      {:ok, args} ->
        body = Map.put(args, "conversation_id", conversation_id)
        attempt(tool, body, 1, Keyword.get(opts, :max_attempts, 2), Keyword.get(opts, :deadline))

      {:error, message} ->
        {:error, %{code: "invalid_arguments", message: message, retryable: false}}
    end
  end

  defp attempt(tool, body, n, max, deadline) do
    case post(tool, body) do
      {:error, %{retryable: true} = error} when n < max ->
        if time_left?(deadline) do
          Logger.warning("tool #{tool} failed (#{error.code}), retry #{n + 1}/#{max}")
          Process.sleep(backoff_ms(n))
          attempt(tool, body, n + 1, max, deadline)
        else
          {:error, error}
        end

      result ->
        result
    end
  end

  defp post(tool, body) do
    started = System.monotonic_time(:millisecond)
    result = do_post(tool, body)
    ms = System.monotonic_time(:millisecond) - started

    case result do
      {:ok, _} ->
        Logger.info("tool call tool=#{tool} status=ok duration_ms=#{ms}")

      {:error, e} ->
        Logger.warning(
          "tool call tool=#{tool} status=error code=#{e.code} retryable=#{e.retryable} duration_ms=#{ms}"
        )
    end

    result
  end

  defp do_post(tool, body) do
    case Req.post(req(), url: "/tools/" <> tool, json: body) do
      {:ok, %{status: status, body: %{"ok" => true} = envelope}} when status in 200..299 ->
        {:ok, Map.get(envelope, "data") || %{}}

      {:ok, %{status: status, body: %{"ok" => false, "error" => error}}} ->
        {:error,
         %{
           code: error["code"] || "http_#{status}",
           message: error["message"] || "",
           retryable: error["retryable"] == true
         }}

      {:ok, %{status: status}} ->
        {:error,
         %{code: "http_#{status}", message: "unexpected response", retryable: status >= 500}}

      {:error, exception} ->
        {:error,
         %{code: "transport_error", message: Exception.message(exception), retryable: true}}
    end
  end

  defp time_left?(nil), do: true
  defp time_left?(deadline), do: System.monotonic_time(:millisecond) + 2_000 < deadline

  defp backoff_ms(n), do: Application.get_env(:doris, :tool_backoff_ms, 500) * n

  defp req do
    Req.new(
      base_url: Application.fetch_env!(:doris, :proxy_url),
      receive_timeout: 30_000,
      retry: false
    )
    |> Req.merge(Application.get_env(:doris, :proxy_req_options, []))
  end
end
