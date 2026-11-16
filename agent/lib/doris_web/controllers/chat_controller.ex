defmodule DorisWeb.ChatController do
  @moduledoc "Streams one Doris turn as OpenAI-compatible SSE."
  use DorisWeb, :controller
  require Logger

  alias Doris.{ChatRequest, History, Memory, SSE}
  alias Doris.Agent.{Runner, State}

  def create(conn, params) do
    conn =
      conn
      |> put_resp_content_type("text/event-stream")
      |> put_resp_header("cache-control", "no-cache")
      |> send_chunked(200)

    # chunk/2 returns an updated conn (the test adapter accumulates the body in it), so the
    # emitter keeps the latest conn; the runner only sees a plain `emit.(event)` function.
    Process.put(:doris_sse_conn, conn)
    emit = &write_event/1

    # Whatever happens, the stream ends with exactly one terminal event and [DONE].
    try do
      with {:ok, req} <- ChatRequest.parse(params),
           :ok <- open_conversation(req),
           :ok <- run_turn(req, emit) do
        emit.(SSE.finish())
      else
        {:error, message} -> emit.(SSE.error(message))
      end
    rescue
      exception ->
        Logger.error(Exception.format(:error, exception, __STACKTRACE__))
        emit.(SSE.error("erro interno do agente"))
    after
      emit.(SSE.done())
    end

    Process.delete(:doris_sse_conn)
  end

  defp open_conversation(req) do
    case History.open(req.user_id, req.conversation_id, req.profile) do
      :ok -> :ok
      {:error, :conversation_owned} -> {:error, "esta conversa pertence a outro usuário"}
    end
  end

  defp run_turn(req, emit) do
    text = ChatRequest.text(req)
    memory = Memory.load(req.user_id, text)

    # Preferences are extracted from the user's message in parallel with the agent loop
    # and awaited before the turn ends, so a new conversation always sees them.
    extraction =
      Task.Supervisor.async_nolink(Doris.TaskSupervisor, fn ->
        Memory.update(req.user_id, %{user_text: text, conversation_id: req.conversation_id})
      end)

    state =
      req
      |> State.new(emit)
      |> Map.put(:avoid_colors, memory.avoid_colors)
      |> History.allowlist(req.conversation_id)

    history = History.context(req.conversation_id)
    result = Runner.run(req, emit, state: state, history: history, memory: memory.prompt)
    await_memory(extraction, req.user_id)

    case result do
      {:ok, %{messages: messages, state: state}} ->
        {:ok, :ok} = History.save_turn(req.conversation_id, messages, state.executions)
        :ok

      {:error, message} ->
        {:ok, :ok} =
          History.save_turn(req.conversation_id, [%{role: "user", content: req.content}], [])

        {:error, message}
    end
  end

  # A memory failure never breaks the chat; it is logged and the previous profile stays.
  defp await_memory(task, user_id) do
    case Task.yield(task, 15_000) || Task.shutdown(task) do
      {:ok, {:error, reason}} ->
        Logger.warning("memory update failed for #{user_id}: #{inspect(reason)}")

      {:ok, _} ->
        :ok

      nil ->
        Logger.warning("memory update timed out for #{user_id}")

      {:exit, reason} ->
        Logger.warning("memory update crashed for #{user_id}: #{inspect(reason)}")
    end
  end

  defp write_event(event) do
    case chunk(Process.get(:doris_sse_conn), event) do
      {:ok, conn} -> Process.put(:doris_sse_conn, conn)
      # client went away (proxy turn cut); keep running so persistence still completes
      {:error, _closed} -> :ok
    end

    :ok
  end
end
