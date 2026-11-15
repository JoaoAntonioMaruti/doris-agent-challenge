defmodule Doris.History.User do
  use Ecto.Schema
  @primary_key {:id, :string, autogenerate: false}
  schema "users" do
    field :profile, :map, default: %{}
    timestamps(type: :utc_datetime_usec)
  end
end

defmodule Doris.History.Conversation do
  use Ecto.Schema
  @primary_key {:id, :string, autogenerate: false}
  schema "conversations" do
    field :user_id, :string
    field :started_at, :utc_datetime_usec
    field :updated_at, :utc_datetime_usec
  end
end

defmodule Doris.History.Message do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "messages" do
    field :conversation_id, :string
    field :role, :string
    field :content, :map
    field :tool_call_id, :string
    field :sequence, :integer
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end

defmodule Doris.History.ToolExecution do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "tool_executions" do
    field :conversation_id, :string
    field :message_id, :binary_id
    field :tool_call_id, :string
    field :tool_name, :string
    field :arguments, :map
    field :result, :map
    field :status, :string
    field :duration_ms, :integer
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
