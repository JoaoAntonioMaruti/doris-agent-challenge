defmodule DorisWeb.TurnRecoveryTest do
  use DorisWeb.ConnCase, async: true
  alias Doris.History
  alias Doris.Agent.State

  @body %{
    "user" => "u_ana",
    "messages" => [%{"role" => "user", "content" => "Quero provar uma camisa"}],
    "metadata" => %{"conversation_id" => "crash-1"}
  }

  defp call(id, name, args),
    do: %{
      "id" => id,
      "type" => "function",
      "function" => %{"name" => name, "arguments" => Jason.encode!(args)}
    }

  defp ask(calls),
    do: %{
      "choices" => [
        %{"message" => %{"role" => "assistant", "content" => nil, "tool_calls" => calls}}
      ]
    }

  setup do
    Req.Test.stub(Doris.Tools.Executor, fn conn ->
      "/tools/" <> tool = conn.request_path

      data =
        case tool do
          "search_by_text" ->
            %{"products" => [%{"search_item_id" => "p01", "name" => "Camisa", "price" => 100}]}

          "garment_creation" ->
            %{"garment_id" => "g-p01"}

          "tryon" ->
            %{"tryon_id" => "t-1", "look_id" => "l-1"}

          "show_artifact" ->
            nil
        end

      Req.Test.json(conn, if(data, do: %{"ok" => true, "data" => data}, else: %{"ok" => true}))
    end)

    :ok
  end

  test "a crash after the try-on keeps the user message, the tool pairs and the ids", %{
    conn: conn
  } do
    {:ok, n} = Agent.start_link(fn -> 0 end)

    Doris.LLMStub.stub(fn req, _body ->
      case Agent.get_and_update(n, &{&1, &1 + 1}) do
        0 -> Req.Test.json(req, ask([call("c1", "find_products", %{"query" => "camisa"})]))
        1 -> Req.Test.json(req, ask([call("c2", "try_on", %{"product_id" => "p01"})]))
        _ -> raise "boom after try-on"
      end
    end)

    response = conn |> post("/v1/chat/completions", @body) |> response(200)
    assert response =~ ~s("error") and response =~ "[DONE]"

    roles = History.context("crash-1") |> Enum.map(& &1["role"])
    assert roles == ["user", "assistant", "tool", "assistant", "tool"]

    state = History.allowlist(%State{}, "crash-1")
    assert State.known_product?(state, "p01")
    assert State.known_garment?(state, "g-p01")
    assert State.known_tryon?(state, "t-1")
  end

  test "the next turn after a crash sees the earlier context", %{conn: conn} do
    {:ok, n} = Agent.start_link(fn -> 0 end)
    {:ok, last} = Agent.start_link(fn -> nil end)

    Doris.LLMStub.stub(fn req, body ->
      case Agent.get_and_update(n, &{&1, &1 + 1}) do
        0 ->
          Req.Test.json(req, ask([call("c1", "find_products", %{"query" => "camisa"})]))

        1 ->
          raise "boom"

        _ ->
          Agent.update(last, fn _ -> body["messages"] end)
          Req.Test.json(req, Doris.LLMStub.completion("Voltei"))
      end
    end)

    post(conn, "/v1/chat/completions", @body)

    post(
      build_conn(),
      "/v1/chat/completions",
      put_in(@body, ["messages"], [%{"role" => "user", "content" => "e aí?"}])
    )

    roles = Agent.get(last, & &1) |> Enum.map(& &1["role"])
    assert roles == ["system", "user", "assistant", "tool", "user"]
  end
end
