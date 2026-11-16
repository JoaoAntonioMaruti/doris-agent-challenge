defmodule Doris.Memory.Worker do
  @moduledoc """
  Runs `Doris.Memory.update/2` under `Doris.TaskSupervisor` with automatic retry for
  transient failures (timeouts, 429/5xx, truncated JSON, optimistic-lock conflicts).

  The caller awaits the task for a while; if it is still retrying when the turn ends, it
  keeps running in the background and logs its final result. Being an in-memory task, it
  does not survive a container restart (accepted trade-off: no job queue in this POC).
  """
  require Logger
  alias Doris.Memory

  @max_attempts 3

  @doc "Starts the update in a supervised, unlinked task."
  def start(user_id, turn) do
    Task.Supervisor.async_nolink(Doris.TaskSupervisor, fn -> run(user_id, turn) end)
  end

  @doc "Waits up to `timeout_ms`; when time runs out the task is left running, not killed."
  def await(task, user_id, timeout_ms \\ 10_000) do
    case Task.yield(task, timeout_ms) do
      {:ok, result} ->
        result

      {:exit, reason} ->
        Logger.warning("memory task crashed user=#{user_id} reason=#{inspect(reason)}")
        {:error, {:exit, reason}}

      nil ->
        Logger.warning("memory task still running in background user=#{user_id}")
        Task.ignore(task)
        :pending
    end
  end

  @doc false
  def run(user_id, turn, attempt \\ 1) do
    result = Memory.update(user_id, turn)

    if transient?(result) and attempt < @max_attempts do
      Logger.warning(
        "memory attempt #{attempt}/#{@max_attempts} failed user=#{user_id} result=#{inspect(result)}; retrying"
      )

      Process.sleep(backoff_ms(attempt))
      run(user_id, turn, attempt + 1)
    else
      if match?({:error, _}, result),
        do:
          Logger.error(
            "memory gave up after #{attempt} attempt(s) user=#{user_id} result=#{inspect(result)}"
          )

      result
    end
  end

  @doc "Errors worth retrying; 4xx (except 429) and anything else are permanent."
  def transient?({:error, %Req.TransportError{}}), do: true
  def transient?({:error, {:http, status, _body}}), do: status == 429 or status >= 500

  def transient?({:error, reason})
      when reason in [:invalid_json, :empty_extraction, :version_conflict],
      do: true

  def transient?(_result), do: false

  defp backoff_ms(attempt) do
    Application.get_env(:doris, :memory_backoff_ms, [500, 1_500]) |> Enum.at(attempt - 1, 1_500)
  end
end
