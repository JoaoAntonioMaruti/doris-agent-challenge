defmodule Doris.Tools.Executor do
  @moduledoc """
  Calls proxy tools over HTTP. Validates arguments first, always sends `conversation_id`,
  unwraps the `{ok, data | error}` envelope and retries only errors marked `retryable`.

  Tools with side effects (`tryon`, `show_artifact`) are retried only when the request
  provably never reached the proxy (connection refused / DNS failure). A 5xx or a timeout
  leaves the effect unknown, so they are not repeated; the orchestrator falls back instead.
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

  @call_cap_ms 30_000
  # below this there is no point in calling the proxy
  @min_call_ms 1_000

  @doc """
  Timeout for one proxy call: #{@call_cap_ms} ms, limited by the time left before the turn
  deadline. `:no_time` when less than #{@min_call_ms} ms would be left.
  """
  def call_timeout(now_ms, deadline_ms) do
    timeout = if deadline_ms, do: min(@call_cap_ms, deadline_ms - now_ms), else: @call_cap_ms
    if timeout < @min_call_ms, do: :no_time, else: timeout
  end

  defp attempt(tool, body, n, max, deadline) do
    result =
      case call_timeout(System.monotonic_time(:millisecond), deadline) do
        :no_time ->
          Logger.warning("tool call tool=#{tool} skipped reason=no_time_left")

          {:error,
           %{code: "no_time_left", message: "sem tempo restante no turno", retryable: false}}

        timeout ->
          post(tool, body, timeout)
      end

    case result do
      {:error, %{retryable: true} = error} when n < max ->
        if time_left?(deadline) and safe_to_retry?(tool, error) do
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

  defp post(tool, body, timeout) do
    started = System.monotonic_time(:millisecond)
    result = do_post(tool, body, timeout)
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

  defp do_post(tool, body, timeout) do
    case Req.post(req(), url: "/tools/" <> tool, json: body, receive_timeout: timeout) do
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
         %{
           code: "transport_error",
           message: Exception.message(exception),
           retryable: true,
           reason: Map.get(exception, :reason)
         }}
    end
  end

  @not_sent [:econnrefused, :nxdomain]

  defp safe_to_retry?(tool, error) do
    not Registry.side_effect?(tool) or Map.get(error, :reason) in @not_sent
  end

  defp time_left?(nil), do: true
  defp time_left?(deadline), do: System.monotonic_time(:millisecond) + 2_000 < deadline

  defp backoff_ms(n), do: Application.get_env(:doris, :tool_backoff_ms, 500) * n

  defp req do
    Req.new(
      base_url: Application.fetch_env!(:doris, :proxy_url),
      retry: false
    )
    |> Req.merge(Application.get_env(:doris, :proxy_req_options, []))
  end
end
