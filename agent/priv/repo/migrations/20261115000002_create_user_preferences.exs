defmodule Doris.Repo.Migrations.CreateUserPreferences do
  use Ecto.Migration

  def change do
    create table(:user_preferences, primary_key: false) do
      add :user_id, references(:users, type: :text, on_delete: :delete_all), primary_key: true
      add :size, :text
      add :disliked_colors, {:array, :text}, null: false, default: []
      add :preferred_styles, {:array, :text}, null: false, default: []
      add :budget_max, :decimal
      add :notes, :text
      # optimistic lock
      add :version, :integer, null: false, default: 1
      timestamps(type: :utc_datetime_usec)
    end
  end
end
