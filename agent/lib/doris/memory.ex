defmodule Doris.Memory do
  @moduledoc """
  Cross-conversation memory, selected by `MEMORY_MODE` (validated at boot in runtime.exs).

    * `load/2` → `%{prompt: text | nil, avoid_colors: [String.t()]}` for the user.
    * `update/2` → extracts and persists what the user's message says about them.

  v1 (`Doris.Memory.Structured`) is always the source of truth for hard constraints.
  """

  def load(user_id, query_text), do: strategy().load(user_id, query_text)
  def update(user_id, turn), do: strategy().update(user_id, turn)

  defp strategy do
    case Application.fetch_env!(:doris, :memory_mode) do
      :v1 -> Doris.Memory.Structured
      :v2 -> Doris.Memory.Semantic
    end
  end
end
