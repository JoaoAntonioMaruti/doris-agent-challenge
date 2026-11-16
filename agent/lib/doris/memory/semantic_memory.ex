defmodule Doris.Memory.SemanticMemory do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "semantic_memories" do
    field :user_id, :string
    field :source_conversation_id, :string
    field :source_key, :string
    field :content, :string
    field :embedding, Pgvector.Ecto.Vector
    timestamps(type: :utc_datetime_usec)
  end
end
