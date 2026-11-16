defmodule Doris.SSE do
  @moduledoc """
  Encodes the OpenAI-compatible `chat.completion.chunk` events plus the Doris extensions
  (`doris` feedback and the error object). Pure functions: they only build `data:` lines.
  """

  def text(content), do: chunk([%{index: 0, delta: %{content: content}, finish_reason: nil}])

  def finish(reason \\ "stop"), do: chunk([%{index: 0, delta: %{}, finish_reason: reason}])

  def feedback(id, text, state) when state in [:running, :done, :error] do
    chunk([], %{doris: %{type: "feedback", id: id, text: text, state: state}})
  end

  def error(message), do: event(%{error: %{message: message, type: "agent_error"}})

  def done, do: "data: [DONE]\n\n"

  defp chunk(choices, extra \\ %{}) do
    %{object: "chat.completion.chunk", choices: choices}
    |> Map.merge(extra)
    |> event()
  end

  defp event(payload), do: "data: " <> Jason.encode!(payload) <> "\n\n"
end
