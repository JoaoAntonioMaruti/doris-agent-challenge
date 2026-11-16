defmodule Doris.Repo.Migrations.CreateSemanticMemories do
  use Ecto.Migration

  # 1536 = dimension returned by openai/text-embedding-3-small via OpenRouter, checked on
  # 2026-11-15 (see code-agent/decisions.md). The client rejects any other size.
  def change do
    execute("CREATE EXTENSION IF NOT EXISTS vector", "DROP EXTENSION IF EXISTS vector")

    create table(:semantic_memories, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :text, on_delete: :delete_all), null: false
      add :source_conversation_id, references(:conversations, type: :text, on_delete: :nilify_all)
      add :source_key, :text, null: false
      add :content, :text, null: false
      add :embedding, :vector, size: 1536, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:semantic_memories, [:user_id, :source_key])
    create index(:semantic_memories, [:user_id])
  end
end
