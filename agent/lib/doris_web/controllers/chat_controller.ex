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
    Logger.metadata(user_id: req.user_id, conversation_id: req.conversation_id)
    Logger.info("turn start mode=#{Application.fetch_env!(:doris, :memory_mode)}")
    text = ChatRequest.text(req)
    memory = Memory.load(req.user_id, text)

    # Preferences are extracted from the user's message in parallel with the agent loop
    # (with automatic retry) and awaited before the turn ends, so a new conversation
    # normally sees them; a slow retry keeps going in the background.
    extraction =
      Memory.Worker.start(req.user_id, %{user_text: text, conversation_id: req.conversation_id})

    # read the context first, then store the user message: everything after this point is
    # persisted as it happens, so a crash mid-turn keeps the message, tool calls and ids.
    history = History.context(req.conversation_id)

    {:ok, :ok} =
      History.append_messages(req.conversation_id, [%{role: "user", content: req.content}])

    state =
      req
      |> State.new(emit)
      |> Map.put(:avoid_colors, memory.avoid_colors)
      |> History.allowlist(req.conversation_id)
      |> Map.merge(persistence(req.conversation_id))

    result = Runner.run(req, emit, state: state, history: history, memory: memory.prompt)
    Memory.Worker.await(extraction, req.user_id)

    case result do
      {:ok, _turn} -> :ok
      {:error, message} -> {:error, message}
    end
  end

  defp persistence(conversation_id) do
    %{
      on_executions: fn executions ->
        {:ok, :ok} = History.record_executions(conversation_id, executions)
      end,
      on_messages: fn messages ->
        {:ok, :ok} = History.append_messages(conversation_id, messages)
      end
    }
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
