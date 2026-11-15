defmodule DorisWeb.ChatController do
  @moduledoc "Streams one Doris turn as OpenAI-compatible SSE."
  use DorisWeb, :controller
  require Logger

  alias Doris.{ChatRequest, History, SSE}
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
    state = req |> State.new(emit) |> History.allowlist(req.conversation_id)
    history = History.context(req.conversation_id)

    case Runner.run(req, emit, state: state, history: history) do
      {:ok, %{messages: messages, state: state}} ->
        {:ok, :ok} = History.save_turn(req.conversation_id, messages, state.executions)
        :ok

      {:error, message} ->
        {:ok, :ok} =
          History.save_turn(req.conversation_id, [%{role: "user", content: req.content}], [])

        {:error, message}
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
