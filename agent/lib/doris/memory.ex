defmodule Doris.Memory do
  @moduledoc """
  Cross-conversation memory, selected by `MEMORY_MODE` (default `v2`; validated at boot in runtime.exs).

    * `load/2` → `%{prompt: text | nil, avoid_colors: [String.t()]}` for the user.
    * `update/2` → extracts and persists what the user's message says about them.

  v1 (`Doris.Memory.Structured`) is always the source of truth for hard constraints.
  """

  require Logger

  def load(user_id, query_text) do
    memory = strategy().load(user_id, query_text)

    Logger.info(
      "memory load mode=#{mode()} user=#{user_id} has_profile=#{memory.prompt != nil} " <>
        "avoid_colors=#{inspect(memory.avoid_colors)}"
    )

    memory
  end

  def update(user_id, turn) do
    Logger.info("memory update start mode=#{mode()} user=#{user_id}")
    started = System.monotonic_time(:millisecond)
    result = strategy().update(user_id, turn)
    ms = System.monotonic_time(:millisecond) - started

    Logger.info(
      "memory update done mode=#{mode()} user=#{user_id} result=#{describe(result)} duration_ms=#{ms}"
    )

    result
  end

  defp describe({:ok, %{version: v} = p}),
    do:
      "saved(version=#{v} size=#{p.size} colors=#{inspect(p.disliked_colors)} styles=#{inspect(p.preferred_styles)} notes=#{inspect(p.notes)})"

  defp describe(:unchanged), do: "unchanged"
  defp describe({:error, reason}), do: "error(#{inspect(reason)})"
  defp describe(other), do: inspect(other)

  defp mode, do: Application.fetch_env!(:doris, :memory_mode)

  defp strategy do
    case mode() do
      :v1 -> Doris.Memory.Structured
      :v2 -> Doris.Memory.Semantic
    end
  end
end
