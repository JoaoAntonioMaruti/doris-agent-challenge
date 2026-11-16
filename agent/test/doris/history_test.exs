defmodule Doris.HistoryTest do
  use Doris.DataCase, async: true
  alias Doris.History
  alias Doris.Agent.State

  defp tool_turn(text) do
    [
      %{role: "user", content: text},
      %{
        role: "assistant",
        content: nil,
        tool_calls: [
          %{id: "call_1", type: "function", function: %{name: "find_products", arguments: "{}"}}
        ]
      },
      %{role: "tool", tool_call_id: "call_1", content: ~s({"ok":true})},
      %{role: "assistant", content: "Achei."}
    ]
  end

  test "a conversation belongs to its first user; another user is rejected" do
    assert :ok = History.open("u_ana", "conv-1")
    assert :ok = History.open("u_ana", "conv-1")
    assert {:error, :conversation_owned} = History.open("u_ana__abc", "conv-1")
  end

  test "context keeps messages in order and per conversation" do
    :ok = History.open("u_ana", "a")
    :ok = History.open("u_bruno", "b")
    {:ok, :ok} = History.save_turn("a", tool_turn("camisa"), [])

    {:ok, :ok} =
      History.save_turn(
        "a",
        [%{role: "user", content: "e couro?"}, %{role: "assistant", content: "Tenho."}],
        []
      )

    {:ok, :ok} =
      History.save_turn(
        "b",
        [%{role: "user", content: "oi"}, %{role: "assistant", content: "Oi!"}],
        []
      )

    assert ["user", "assistant", "tool", "assistant", "user", "assistant"] =
             Enum.map(History.context("a"), & &1["role"])

    assert [%{"content" => "oi"}, _] = History.context("b")
    assert History.context("unknown") == []
  end

  test "the context window never starts inside a tool_call/tool pair" do
    :ok = History.open("u_ana", "long")
    for i <- 1..15, do: {:ok, :ok} = History.save_turn("long", tool_turn("pedido #{i}"), [])

    [first | _] = context = History.context("long")
    assert first["role"] == "user"
    tool_ids = for %{"role" => "tool", "tool_call_id" => id} <- context, do: id
    call_ids = for %{"tool_calls" => calls} <- context, c <- calls, do: c["id"]
    assert length(tool_ids) == length(call_ids)
  end

  test "base64 images are replaced by a placeholder" do
    :ok = History.open("u_ana", "img")

    msg = %{
      role: "user",
      content: [
        %{type: "text", text: "olha"},
        %{
          type: "image_url",
          image_url: %{url: "data:image/jpeg;base64,#{String.duplicate("A", 5000)}"}
        }
      ]
    }

    {:ok, :ok} = History.save_turn("img", [msg], [])
    [%{"content" => [_, %{"type" => "text", "text" => placeholder}]}] = History.context("img")
    assert placeholder =~ "imagem"
    refute inspect(History.context("img")) =~ "base64"
  end

  test "allowlist is rebuilt from successful executions of the same conversation only" do
    :ok = History.open("u_ana", "x")
    :ok = History.open("u_ana", "y")

    execs = [
      %{
        tool_call_id: "c#1",
        tool_name: "search_by_text",
        arguments: %{},
        status: "ok",
        result: %{"products" => [%{"search_item_id" => "p08", "price" => 100}]}
      },
      %{
        tool_call_id: "c#2",
        tool_name: "garment_creation",
        arguments: %{"search_item_id" => "p08"},
        status: "ok",
        result: %{"garment_id" => "g8"}
      },
      %{
        tool_call_id: "c#3",
        tool_name: "tryon",
        arguments: %{},
        status: "error",
        result: %{"error" => %{}}
      }
    ]

    {:ok, :ok} = History.save_turn("x", [%{role: "user", content: "x"}], execs)
    # same tool_call_id again is ignored (idempotent)
    {:ok, :ok} = History.save_turn("x", [], Enum.take(execs, 1))

    base = %State{conversation_id: "x", user_id: "u_ana"}
    state = History.allowlist(base, "x")
    assert State.known_product?(state, "p08")
    assert State.known_garment?(state, "g8")
    assert state.garment_products["g8"] == "p08"
    refute State.known_product?(History.allowlist(base, "y"), "p08")
  end
end
