defmodule Doris.Memory.WorkerTest do
  use Doris.DataCase, async: true
  alias Doris.History
  alias Doris.Memory.{Structured, Worker}

  @turn %{user_text: "Odeio amarelo e visto M", conversation_id: "w1"}

  # Memory model answers from a script: :timeout, {:status, n} or a JSON string.
  defp script(steps) do
    {:ok, queue} = Agent.start_link(fn -> steps end)
    {:ok, calls} = Agent.start_link(fn -> 0 end)

    Req.Test.stub(Doris.LLM.OpenRouter, fn conn ->
      Agent.update(calls, &(&1 + 1))

      case Agent.get_and_update(queue, fn
             [h | t] -> {h, t}
             [] -> {:timeout, []}
           end) do
        :timeout -> Req.Test.transport_error(conn, :timeout)
        {:status, n} -> conn |> Plug.Conn.put_status(n) |> Req.Test.json(%{})
        json -> Req.Test.json(conn, Doris.LLMStub.completion(json))
      end
    end)

    calls
  end

  setup do
    :ok = History.open("u_ana__w", "w1")
    :ok
  end

  test "retries transient failures and saves on the third attempt" do
    calls = script([:timeout, :timeout, ~s({"size":"M","add_disliked_colors":["amarelo"]})])

    assert {:ok, prefs} = Worker.start("u_ana__w", @turn) |> Worker.await("u_ana__w")
    assert prefs.size == "M" and prefs.disliked_colors == ["amarelo"]
    assert Agent.get(calls, & &1) == 3
  end

  test "a permanent 4xx error is not retried" do
    calls = script([{:status, 400}])
    assert {:error, {:http, 400, _}} = Worker.start("u_ana__w", @turn) |> Worker.await("u_ana__w")
    assert Agent.get(calls, & &1) == 1
  end

  test "truncated JSON is retried" do
    calls = script([~s({"size":), ~s({"size":"G"})])
    assert {:ok, %{size: "G"}} = Worker.start("u_ana__w", @turn) |> Worker.await("u_ana__w")
    assert Agent.get(calls, & &1) == 2
  end

  test "gives up after 3 attempts and keeps the previous profile" do
    script([~s({"size":"P"})])
    {:ok, _} = Worker.run("u_ana__w", @turn)

    calls = script([:timeout, :timeout, :timeout])
    assert {:error, %Req.TransportError{reason: :timeout}} = Worker.run("u_ana__w", @turn)
    assert Agent.get(calls, & &1) == 3
    assert %{size: "P", version: 1} = Structured.get("u_ana__w")
  end

  test "await leaves a slow task running instead of killing it" do
    test_pid = self()

    task =
      Task.Supervisor.async_nolink(Doris.TaskSupervisor, fn ->
        receive do: (:go -> send(test_pid, :finished))
      end)

    assert :pending = Worker.await(task, "u_ana__w", 10)
    send(task.pid, :go)
    assert_receive :finished
  end
end
