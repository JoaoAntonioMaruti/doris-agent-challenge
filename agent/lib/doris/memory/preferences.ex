defmodule Doris.Memory.Preferences do
  @moduledoc "Structured profile of a user (memory v1)."
  use Ecto.Schema

  @primary_key {:user_id, :string, autogenerate: false}
  schema "user_preferences" do
    field :size, :string
    field :disliked_colors, {:array, :string}, default: []
    field :preferred_styles, {:array, :string}, default: []
    field :budget_max, :decimal
    field :notes, :string
    field :version, :integer, default: 1
    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Applies an extracted change set. Only fields the user mentioned change: explicit new
  values win, list removals are explicit, missing fields keep the stored value.
  """
  def merge(%__MODULE__{} = prefs, changes) do
    %{
      prefs
      | size: changes[:size] || prefs.size,
        disliked_colors:
          update_list(
            prefs.disliked_colors,
            changes[:add_disliked_colors],
            changes[:remove_disliked_colors]
          ),
        preferred_styles:
          update_list(prefs.preferred_styles, changes[:add_styles], changes[:remove_styles]),
        budget_max:
          if(Map.has_key?(changes, :budget_max), do: changes.budget_max, else: prefs.budget_max),
        notes: changes[:notes] || prefs.notes
    }
  end

  defp update_list(current, add, remove) do
    removed = MapSet.new(remove || [])

    Enum.uniq(
      (current -- MapSet.to_list(removed)) ++ Enum.reject(add || [], &MapSet.member?(removed, &1))
    )
  end

  def empty?(%__MODULE__{} = p),
    do:
      is_nil(p.size) and p.disliked_colors == [] and p.preferred_styles == [] and
        is_nil(p.budget_max) and is_nil(p.notes)

  @doc "Facts for the system prompt."
  def to_prompt(%__MODULE__{} = p) do
    [
      p.size && "- Tamanho: #{p.size}",
      p.disliked_colors != [] &&
        "- Cores que evita (nunca sugira): #{Enum.join(p.disliked_colors, ", ")}",
      p.preferred_styles != [] && "- Estilos preferidos: #{Enum.join(p.preferred_styles, ", ")}",
      p.budget_max && "- Orçamento usual: até R$#{p.budget_max}",
      p.notes && "- Notas: #{p.notes}"
    ]
    |> Enum.filter(& &1)
    |> Enum.join("\n")
  end
end
