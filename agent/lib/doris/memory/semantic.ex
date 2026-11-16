defmodule Doris.Memory.Semantic do
  @moduledoc "Memory v2 (T09, optional). Until implemented it delegates to v1."
  defdelegate load(user_id, query_text), to: Doris.Memory.Structured
  defdelegate update(user_id, turn), to: Doris.Memory.Structured
end
