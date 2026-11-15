defmodule Doris.Repo.Migrations.CreateHistory do
  use Ecto.Migration

  def change do
    create table(:users, primary_key: false) do
      # full `request.user` value, suffix included (u_ana__abc != u_ana)
      add :id, :text, primary_key: true
      add :profile, :map, null: false, default: %{}
      timestamps(type: :utc_datetime_usec)
    end

    create table(:conversations, primary_key: false) do
      add :id, :text, primary_key: true
      add :user_id, references(:users, type: :text, on_delete: :delete_all), null: false
      add :started_at, :utc_datetime_usec, null: false
      add :updated_at, :utc_datetime_usec, null: false
    end

    create index(:conversations, [:user_id, :updated_at])

    create table(:messages, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :conversation_id, references(:conversations, type: :text, on_delete: :delete_all),
        null: false

      add :role, :text, null: false
      # the message map in the format sent to the model (content, tool_calls, …)
      add :content, :map, null: false
      add :tool_call_id, :text
      add :sequence, :bigint, null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:messages, [:conversation_id, :sequence])

    create table(:tool_executions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :conversation_id, references(:conversations, type: :text, on_delete: :delete_all),
        null: false

      add :message_id, references(:messages, type: :binary_id, on_delete: :nilify_all)
      add :tool_call_id, :text
      add :tool_name, :text, null: false
      add :arguments, :map, null: false
      add :result, :map
      add :status, :text, null: false
      add :duration_ms, :integer
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:tool_executions, [:conversation_id, :tool_call_id],
             where: "tool_call_id IS NOT NULL"
           )

    create index(:tool_executions, [:conversation_id])
  end
end
