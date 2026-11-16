defmodule Doris.LLMStub do
  @moduledoc "Helpers for OpenRouter stubs in tests."

  @doc """
  Stubs OpenRouter: memory-extraction calls get `memory_json`, every other call is
  answered by `fun.(conn, decoded_body)`.
  """
  def stub(fun, memory_json \\ "{}") do
    Req.Test.stub(Doris.LLM.OpenRouter, fn conn ->
      {:ok, raw, _} = Plug.Conn.read_body(conn)
      body = Jason.decode!(raw)

      if body["model"] == "test/memory-model",
        do: Req.Test.json(conn, completion(memory_json)),
        else: fun.(conn, body)
    end)
  end

  def completion(content),
    do: %{"choices" => [%{"message" => %{"role" => "assistant", "content" => content}}]}
end
