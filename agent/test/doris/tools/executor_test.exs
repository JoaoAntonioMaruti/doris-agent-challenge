defmodule Doris.Tools.ExecutorTest do
  use ExUnit.Case, async: true
  alias Doris.Tools.Executor

  defp body(conn) do
    {:ok, raw, _} = Plug.Conn.read_body(conn)
    Jason.decode!(raw)
  end

  defp fail(conn, status, code, retryable) do
    conn
    |> Plug.Conn.put_status(status)
    |> Req.Test.json(%{
      "ok" => false,
      "error" => %{"code" => code, "message" => "x", "retryable" => retryable}
    })
  end

  test "posts to /tools/<name> with conversation_id and unwraps data" do
    Req.Test.stub(Executor, fn conn ->
      assert conn.request_path == "/tools/search_by_text"
      assert %{"conversation_id" => "c1", "query" => "camisa", "limit" => 6} = body(conn)

      Req.Test.json(conn, %{
        "ok" => true,
        "data" => %{"products" => [%{"search_item_id" => "p01"}]}
      })
    end)

    assert {:ok, %{"products" => [%{"search_item_id" => "p01"}]}} =
             Executor.call("c1", "search_by_text", %{"query" => "camisa", "limit" => 6})
  end

  test "show_artifact returns {:ok, %{}} for an envelope without data" do
    Req.Test.stub(Executor, &Req.Test.json(&1, %{"ok" => true}))

    assert {:ok, %{}} =
             Executor.call("c1", "show_artifact", %{"type" => "PRODUCT", "value" => "p01"})
  end

  test "retries a retryable error and succeeds" do
    counter = :counters.new(1, [])

    Req.Test.stub(Executor, fn conn ->
      :counters.add(counter, 1, 1)

      if :counters.get(counter, 1) == 1,
        do: fail(conn, 504, "upstream_timeout", true),
        else: Req.Test.json(conn, %{"ok" => true, "data" => %{"looks" => []}})
    end)

    assert {:ok, %{"looks" => []}} = Executor.call("c1", "looks", %{})
    assert :counters.get(counter, 1) == 2
  end

  test "does not retry a non-retryable error" do
    counter = :counters.new(1, [])

    Req.Test.stub(Executor, fn conn ->
      :counters.add(counter, 1, 1)
      fail(conn, 422, "not_found", false)
    end)

    assert {:error, %{code: "not_found", retryable: false}} =
             Executor.call("c1", "garment_creation", %{"search_item_id" => "zzz"})

    assert :counters.get(counter, 1) == 1
  end

  test "invalid arguments never reach the proxy" do
    Req.Test.stub(Executor, fn _ -> flunk("proxy must not be called") end)

    assert {:error, %{code: "invalid_arguments"}} =
             Executor.call("c1", "tryon", %{"garment_ids" => ["g1", "g2"]})

    assert {:error, %{code: "invalid_arguments"}} = Executor.call("c1", "search_by_text", %{})
    assert {:error, %{code: "invalid_arguments"}} = Executor.call("c1", "nope", %{})

    assert {:error, %{code: "invalid_arguments"}} =
             Executor.call("c1", "show_artifact", %{"type" => "BANNER", "value" => "x"})
  end

  defp counting(fun) do
    counter = :counters.new(1, [])

    Req.Test.stub(Executor, fn conn ->
      :counters.add(counter, 1, 1)
      fun.(conn, :counters.get(counter, 1))
    end)

    counter
  end

  test "tryon with a retryable 5xx is not repeated (effect unknown)" do
    counter = counting(fn conn, _ -> fail(conn, 503, "upstream_timeout", true) end)

    assert {:error, %{code: "upstream_timeout"}} =
             Executor.call("c1", "tryon", %{"garment_ids" => ["g1"]})

    assert :counters.get(counter, 1) == 1
  end

  test "tryon timeout is not repeated" do
    counter = counting(fn conn, _ -> Req.Test.transport_error(conn, :timeout) end)

    assert {:error, %{reason: :timeout}} =
             Executor.call("c1", "tryon", %{"garment_ids" => ["g1"]})

    assert :counters.get(counter, 1) == 1
  end

  test "tryon is retried when the connection was refused (never sent)" do
    counter =
      counting(fn conn, n ->
        if n == 1,
          do: Req.Test.transport_error(conn, :econnrefused),
          else: Req.Test.json(conn, %{"ok" => true, "data" => %{"tryon_id" => "t1"}})
      end)

    assert {:ok, %{"tryon_id" => "t1"}} = Executor.call("c1", "tryon", %{"garment_ids" => ["g1"]})
    assert :counters.get(counter, 1) == 2
  end

  test "show_artifact with a retryable 5xx is not repeated" do
    counter = counting(fn conn, _ -> fail(conn, 503, "upstream_timeout", true) end)
    Executor.call("c1", "show_artifact", %{"type" => "PRODUCT", "value" => "p01"})
    assert :counters.get(counter, 1) == 1
  end

  test "idempotent search is still retried on a retryable 5xx" do
    counter =
      counting(fn conn, n ->
        if n == 1,
          do: fail(conn, 503, "upstream_timeout", true),
          else: Req.Test.json(conn, %{"ok" => true, "data" => %{"products" => []}})
      end)

    assert {:ok, _} = Executor.call("c1", "search_by_text", %{"query" => "x"})
    assert :counters.get(counter, 1) == 2
  end
end
