defmodule Doris.SSETest do
  use ExUnit.Case, async: true
  alias Doris.SSE

  defp decode("data: " <> rest), do: rest |> String.trim_trailing() |> Jason.decode!()

  test "text chunk follows the OpenAI shape" do
    assert %{
             "object" => "chat.completion.chunk",
             "choices" => [%{"delta" => %{"content" => "oi"}, "finish_reason" => nil}]
           } = decode(SSE.text("oi"))
  end

  test "feedback uses empty choices and the doris extension" do
    assert %{
             "choices" => [],
             "doris" => %{"id" => "t1", "state" => "running", "type" => "feedback"}
           } =
             decode(SSE.feedback("t1", "Buscando…", :running))
  end

  test "finish, error and done" do
    assert %{"choices" => [%{"finish_reason" => "stop"}]} = decode(SSE.finish())
    assert %{"error" => %{"type" => "agent_error"}} = decode(SSE.error("x"))
    assert SSE.done() == "data: [DONE]\n\n"
  end
end
