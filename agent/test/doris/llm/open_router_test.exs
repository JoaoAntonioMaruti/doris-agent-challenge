defmodule Doris.LLM.OpenRouterTest do
  use ExUnit.Case, async: true
  alias Doris.LLM.OpenRouter

  describe "call_timeout/3" do
    test "uses the per-call cap when there is plenty of time" do
      assert OpenRouter.call_timeout(0, 80_000, 20_000) == 20_000
    end

    test "is limited by the time left before the deadline" do
      assert OpenRouter.call_timeout(70_000, 80_000, 20_000) == 10_000
    end

    test "gives up when less than 3 s are left" do
      assert OpenRouter.call_timeout(78_000, 80_000, 20_000) == :no_time
    end

    test "without a deadline only the cap applies" do
      assert OpenRouter.call_timeout(0, nil, 20_000) == 20_000
    end
  end

  test "a timeout on the main model falls back to the second model" do
    {:ok, models} = Agent.start_link(fn -> [] end)

    Doris.LLMStub.stub(fn conn, body ->
      Agent.update(models, &(&1 ++ [body["model"]]))

      case body["model"] do
        "openai/gpt-6-luna" -> Req.Test.transport_error(conn, :timeout)
        _ -> Req.Test.json(conn, Doris.LLMStub.completion("fallback ok"))
      end
    end)

    deadline = System.monotonic_time(:millisecond) + 60_000

    assert {:ok, %{"content" => "fallback ok"}} =
             OpenRouter.chat([%{role: "user", content: "oi"}], deadline: deadline)

    assert Agent.get(models, & &1) == ["openai/gpt-6-luna", "google/gemini-3.8-flash"]
  end

  test "no attempt is made when the deadline is too close" do
    Doris.LLMStub.stub(fn _conn, _body -> flunk("must not call the model") end)
    deadline = System.monotonic_time(:millisecond) + 1_000

    assert {:error, :no_time_left} =
             OpenRouter.chat([%{role: "user", content: "oi"}], deadline: deadline)
  end
end
