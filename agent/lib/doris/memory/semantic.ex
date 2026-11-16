defmodule Doris.Memory.Semantic do
  @moduledoc """
  Memory v2 = v1 (structured profile, still the only source of hard constraints) plus
  free-text facts stored with embeddings and recalled by similarity, per user.

  Any v2 failure (extraction, embedding, database) is logged and degrades to v1: it never
  breaks the chat and never touches `user_preferences`.
  """
  require Logger
  import Ecto.Query
  import Pgvector.Ecto.Query
  alias Doris.Repo
  alias Doris.LLM.{Embeddings, OpenRouter}
  alias Doris.Memory.{SemanticMemory, Structured}

  @top_k 3
  @max_distance 0.65
  @max_facts 3
  @fact_chars 200

  def load(user_id, query_text) do
    base = Structured.load(user_id, query_text)

    case recall(user_id, query_text) do
      {:ok, []} ->
        Logger.info("memory recall user=#{user_id} facts=0")
        base

      {:ok, facts} ->
        Logger.info("memory recall user=#{user_id} facts=#{length(facts)}")
        lines = Enum.map_join(facts, "\n", &"- #{&1}")

        %{
          base
          | prompt:
              Enum.join(
                Enum.reject(
                  [base.prompt, "Lembranças relevantes de conversas anteriores:\n" <> lines],
                  &is_nil/1
                ),
                "\n"
              )
        }

      {:error, reason} ->
        Logger.warning("semantic recall failed for #{user_id}: #{inspect(reason)}")
        base
    end
  end

  @doc "Returns the facts most similar to the query, only from this user."
  def recall(user_id, query_text) do
    if String.trim(query_text || "") == "" do
      {:ok, []}
    else
      with {:ok, [vector]} <- Embeddings.embed([query_text]) do
        vector = Pgvector.new(vector)

        facts =
          from(m in SemanticMemory,
            where:
              m.user_id == ^user_id and cosine_distance(m.embedding, ^vector) <= ^@max_distance,
            order_by: cosine_distance(m.embedding, ^vector),
            limit: @top_k,
            select: m.content
          )
          |> Repo.all()

        {:ok, facts}
      end
    end
  rescue
    error in [DBConnection.ConnectionError, Postgrex.Error] -> {:error, error}
  end

  @doc "Runs the v1 update and the fact extraction concurrently; returns the v1 result."
  def update(user_id, turn) do
    facts_task = Task.async(fn -> remember(user_id, turn) end)
    structured = Structured.update(user_id, turn)

    case Task.yield(facts_task, 15_000) || Task.shutdown(facts_task) do
      {:ok, {:error, reason}} ->
        Logger.warning("semantic update failed for #{user_id}: #{inspect(reason)}")

      nil ->
        Logger.warning("semantic update timed out for #{user_id}")

      _ ->
        :ok
    end

    structured
  end

  @doc false
  def remember(user_id, %{user_text: text} = turn) do
    with {:ok, facts} when facts != [] <- extract_facts(text),
         {:ok, vectors} <- Embeddings.embed(facts) do
      store(user_id, turn[:conversation_id], Enum.zip(facts, vectors))
    else
      {:ok, []} -> {:ok, 0}
      {:error, reason} -> {:error, reason}
    end
  rescue
    error in [DBConnection.ConnectionError, Postgrex.Error] -> {:error, error}
  end

  # The same fact from the same user is stored once (unique user_id + source_key). The
  # advisory lock serialises concurrent writers of the same user.
  defp store(user_id, conversation_id, pairs) do
    Repo.transaction(fn ->
      Repo.query!("SELECT pg_advisory_xact_lock(hashtext($1))", ["semantic:" <> user_id])
      now = DateTime.utc_now()

      rows =
        Enum.map(pairs, fn {fact, vector} ->
          %{
            id: Ecto.UUID.generate(),
            user_id: user_id,
            source_conversation_id: conversation_id,
            source_key: source_key(fact),
            content: fact,
            embedding: Pgvector.new(vector),
            inserted_at: now,
            updated_at: now
          }
        end)

      {count, _} =
        Repo.insert_all(SemanticMemory, rows,
          on_conflict: :nothing,
          conflict_target: [:user_id, :source_key]
        )

      count
    end)
  end

  @doc "Idempotency key: extraction version + normalised fact text."
  def source_key(fact) do
    normalized = fact |> String.downcase() |> String.replace(~r/\s+/u, " ") |> String.trim()
    "facts-v1:" <> Base.encode16(:crypto.hash(:sha256, normalized), case: :lower)
  end

  @instructions """
  Liste fatos estáveis e úteis para uma assistente de moda que a PESSOA contou sobre si mesma
  na mensagem (rotina, ocasiões, gostos, restrições, corpo, clima onde vive...). Ignore pedidos
  pontuais ("me acha X") e perguntas. Cada fato: frase curta começando com "A pessoa" (nunca suponha gênero).
  Responda só JSON: {"facts": [string]} (lista vazia se não houver).
  """

  defp extract_facts(text) do
    messages = [
      %{role: "system", content: @instructions},
      %{role: "user", content: String.slice(text, 0, 2000)}
    ]

    case OpenRouter.chat(messages,
           model: :memory,
           purpose: "memory.facts",
           max_tokens: 400,
           temperature: 0.0,
           response_format: %{type: "json_object"}
         ) do
      {:ok, %{"content" => content}} when is_binary(content) ->
        case Jason.decode(content) do
          {:ok, %{"facts" => facts}} when is_list(facts) ->
            {:ok,
             facts
             |> Enum.filter(&is_binary/1)
             |> Enum.map(&(&1 |> String.trim() |> String.slice(0, @fact_chars)))
             |> Enum.reject(&(&1 == ""))
             |> Enum.uniq()
             |> Enum.take(@max_facts)}

          _ ->
            {:error, :invalid_json}
        end

      {:ok, _} ->
        {:error, :empty_extraction}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
