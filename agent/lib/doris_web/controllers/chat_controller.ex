defmodule DorisWeb.ChatController do
  @moduledoc "Streams one Doris turn as OpenAI-compatible SSE."
  use DorisWeb, :controller
  require Logger

  alias Doris.{ChatRequest, SSE}
  alias Doris.Agent.Runner

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
           :ok <- Runner.run(req, emit) do
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

  defp write_event(event) do
    case chunk(Process.get(:doris_sse_conn), event) do
      {:ok, conn} -> Process.put(:doris_sse_conn, conn)
      # client went away (proxy turn cut); keep running so persistence still completes
      {:error, _closed} -> :ok
    end

    :ok
  end
end
