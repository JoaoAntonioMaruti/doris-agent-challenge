defmodule DorisWeb.ChatControllerTest do
  use DorisWeb.ConnCase, async: true

  @image "data:image/jpeg;base64,AAAA"
  @body %{
    "model" => "doris-agent",
    "stream" => true,
    "user" => "u_bruno",
    "messages" => [
      %{
        "role" => "user",
        "content" => [
          %{"type" => "text", "text" => "Oi"},
          %{"type" => "image_url", "image_url" => %{"url" => @image}}
        ]
      }
    ],
    "metadata" => %{"conversation_id" => "c1", "profile" => %{"name" => "Bruno"}}
  }

  defp events(conn) do
    conn
    |> response(200)
    |> String.split("\n\n", trim: true)
    |> Enum.map(fn "data: " <> payload ->
      if payload == "[DONE]", do: :done, else: Jason.decode!(payload)
    end)
  end

  defp completion(content) do
    %{"choices" => [%{"message" => %{"role" => "assistant", "content" => content}}]}
  end

  test "streams the model text, finish_reason and exactly one [DONE]; image reaches the model", %{
    conn: conn
  } do
    Req.Test.stub(Doris.LLM.OpenRouter, fn req ->
      {:ok, body, _} = Plug.Conn.read_body(req)

      %{"messages" => [_system, %{"content" => content}], "max_tokens" => max} =
        Jason.decode!(body)

      assert %{"type" => "image_url", "image_url" => %{"url" => @image}} in content
      assert is_integer(max)
      Req.Test.json(req, completion("Olá, Bruno!"))
    end)

    events = conn |> post("/v1/chat/completions", @body) |> events()

    assert [
             %{"choices" => [%{"delta" => %{"content" => "Olá, Bruno!"}}]},
             %{"choices" => [%{"finish_reason" => "stop"}]},
             :done
           ] = events
  end

  test "falls back to the second model when the first fails with 5xx", %{conn: conn} do
    Req.Test.stub(Doris.LLM.OpenRouter, fn req ->
      {:ok, body, _} = Plug.Conn.read_body(req)

      case Jason.decode!(body)["model"] do
        "openai/gpt-6-luna" -> req |> Plug.Conn.put_status(503) |> Req.Test.json(%{})
        "google/gemini-3.8-flash" -> Req.Test.json(req, completion("fallback"))
      end
    end)

    assert [%{"choices" => [%{"delta" => %{"content" => "fallback"}}]}, _, :done] =
             conn |> post("/v1/chat/completions", @body) |> events()
  end

  test "a model error ends the turn with an error event and [DONE]", %{conn: conn} do
    Req.Test.stub(Doris.LLM.OpenRouter, fn req ->
      req |> Plug.Conn.put_status(400) |> Req.Test.json(%{"error" => "bad"})
    end)

    assert [%{"error" => %{"type" => "agent_error"}}, :done] =
             conn |> post("/v1/chat/completions", @body) |> events()
  end

  test "an invalid body ends with an error event", %{conn: conn} do
    assert [%{"error" => _}, :done] =
             conn |> post("/v1/chat/completions", %{"messages" => []}) |> events()
  end

  test "a second message in the same conversation sends the previous turn to the model", %{
    conn: conn
  } do
    {:ok, bodies} = Agent.start_link(fn -> [] end)

    Req.Test.stub(Doris.LLM.OpenRouter, fn req ->
      {:ok, body, _} = Plug.Conn.read_body(req)
      Agent.update(bodies, &(&1 ++ [Jason.decode!(body)]))
      Req.Test.json(req, completion("resposta"))
    end)

    post(conn, "/v1/chat/completions", @body)
    second = put_in(@body, ["messages"], [%{"role" => "user", "content" => "e agora?"}])
    post(build_conn(), "/v1/chat/completions", second)

    [_, %{"messages" => messages}] = Agent.get(bodies, & &1)
    assert Enum.map(messages, & &1["role"]) == ["system", "user", "assistant", "user"]
    assert Enum.at(messages, 2)["content"] == "resposta"
  end

  test "another user reusing the conversation id gets an error and no history", %{conn: conn} do
    Req.Test.stub(Doris.LLM.OpenRouter, &Req.Test.json(&1, completion("segredo da Ana")))
    post(conn, "/v1/chat/completions", @body)

    intruder = Map.put(@body, "user", "u_bruno__x")
    events = build_conn() |> post("/v1/chat/completions", intruder) |> events()
    assert [%{"error" => %{"message" => message}}, :done] = events
    assert message =~ "outro usuário"
  end
end
