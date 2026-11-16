defmodule Doris.Memory.SemanticTest do
  use Doris.DataCase, async: true
  alias Doris.History
  alias Doris.Memory.{Semantic, SemanticMemory, Structured}

  # Bag-of-words vector: texts sharing words are close in cosine distance.
  defp fake_vector(text) do
    words = text |> String.downcase() |> String.split(~r/[^\p{L}]+/u, trim: true)
    hot = MapSet.new(words, &rem(:erlang.phash2(&1), 1536))
    for i <- 0..1535, do: if(MapSet.member?(hot, i), do: 1.0, else: 0.001)
  end

  # facts: what the fact extractor returns; prefs: what the v1 extractor returns.
  defp stub(opts) do
    Req.Test.stub(Doris.LLM.OpenRouter, fn conn ->
      {:ok, raw, _} = Plug.Conn.read_body(conn)
      body = Jason.decode!(raw)

      cond do
        String.ends_with?(conn.request_path, "/embeddings") and opts[:embeddings] == :fail ->
          conn |> Plug.Conn.put_status(502) |> Req.Test.json(%{})

        String.ends_with?(conn.request_path, "/embeddings") ->
          size = Keyword.get(opts, :size)

          data =
            body["input"]
            |> Enum.with_index()
            |> Enum.map(fn {t, i} ->
              v = fake_vector(t)
              %{"index" => i, "embedding" => if(size, do: Enum.take(v, size), else: v)}
            end)

          Req.Test.json(conn, %{"data" => data})

        hd(body["messages"])["content"] =~ "fatos estáveis" ->
          Req.Test.json(
            conn,
            Doris.LLMStub.completion(Jason.encode!(%{facts: opts[:facts] || []}))
          )

        true ->
          Req.Test.json(conn, Doris.LLMStub.completion(opts[:prefs] || "{}"))
      end
    end)
  end

  setup do
    for {u, c} <- [{"u_ana__abc", "c1"}, {"u_ana__def", "c2"}], do: :ok = History.open(u, c)
    :ok
  end

  test "facts are stored per user and recalled by similarity, never across users" do
    stub(facts: ["Trabalha em escritório com dress code formal", "Mora em cidade fria"])
    assert {:ok, 2} = Semantic.remember("u_ana__abc", %{user_text: "…", conversation_id: "c1"})

    assert {:ok, ["Trabalha em escritório com dress code formal" | _]} =
             Semantic.recall("u_ana__abc", "escritório formal dress code")

    assert {:ok, []} = Semantic.recall("u_ana__def", "escritório formal dress code")

    %{prompt: prompt} = Semantic.load("u_ana__abc", "escritório formal dress code")
    assert prompt =~ "Lembranças relevantes" and prompt =~ "escritório"
  end

  test "the same fact is stored once (idempotent source_key)" do
    stub(facts: ["Mora em cidade fria"])
    {:ok, 1} = Semantic.remember("u_ana__abc", %{user_text: "a", conversation_id: "c1"})
    {:ok, 0} = Semantic.remember("u_ana__abc", %{user_text: "b", conversation_id: "c1"})
    assert Repo.aggregate(SemanticMemory, :count) == 1
  end

  test "embedding failure degrades to v1: chat context and structured profile survive" do
    stub(
      prefs: ~s({"add_disliked_colors":["amarelo"]}),
      facts: ["Odeia amarelo"],
      embeddings: :fail
    )

    assert {:ok, prefs} =
             Semantic.update("u_ana__abc", %{user_text: "odeio amarelo", conversation_id: "c1"})

    assert prefs.disliked_colors == ["amarelo"]

    assert %{avoid_colors: ["amarelo"], prompt: prompt} = Semantic.load("u_ana__abc", "jantar")
    refute prompt =~ "Lembranças"
    assert Structured.get("u_ana__abc").version == 1
  end

  test "a vector with an unexpected size is rejected, nothing stored" do
    stub(facts: ["Mora em cidade fria"], size: 768)

    assert {:error, {:unexpected_dimensions, [768]}} =
             Semantic.remember("u_ana__abc", %{user_text: "x", conversation_id: "c1"})

    assert Repo.aggregate(SemanticMemory, :count) == 0
  end
end
