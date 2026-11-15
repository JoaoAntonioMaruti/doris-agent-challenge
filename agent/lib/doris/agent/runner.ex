defmodule Doris.Agent.Runner do
  @moduledoc """
  The agent loop for one turn: model → tool calls → orchestrators → tool results → model,
  until the model answers with text, the iteration cap is hit or the deadline passes.

  `emit` is a 1-arity function receiving encoded SSE events (text and feedback).
  Returns `{:ok, turn}` with the messages produced in this turn (for persistence) or
  `{:error, message}` when the model could not be reached at all.
  """
  require Logger
  alias Doris.{ChatRequest, SSE}
  alias Doris.Agent.{Prompt, State, Tools}
  alias Doris.LLM.OpenRouter

  @max_iterations 6
  @fallback_text "Desculpe, não consegui concluir agora. Pode tentar de novo?"
  @timeout_text "Demorei mais do que devia e parei por aqui. Quer que eu tente de novo?"

  def run(%ChatRequest{} = req, emit, opts \\ []) do
    state = Keyword.get_lazy(opts, :state, fn -> State.new(req, emit) end)
    history = Keyword.get(opts, :history, [])
    system = Prompt.system(req.profile, Keyword.get(opts, :memory))

    user_message = %{role: "user", content: req.content}
    context = [%{role: "system", content: system} | history] ++ [user_message]

    loop(context, [user_message], state, 0, MapSet.new())
  end

  defp loop(_context, turn, state, iteration, _seen) when iteration >= @max_iterations do
    Logger.warning("iteration cap reached in #{state.conversation_id}")
    finish(turn, state, @fallback_text)
  end

  defp loop(context, turn, state, iteration, seen) do
    if State.remaining_ms(state) <= 0 do
      finish(turn, state, @timeout_text)
    else
      case OpenRouter.chat(context,
             tools: Tools.definitions(),
             receive_timeout: State.remaining_ms(state)
           ) do
        {:ok, %{"tool_calls" => [_ | _] = calls} = message} ->
          {results, state, seen} = run_calls(calls, state, seen)
          assistant = assistant_message(message, calls)
          {extra, state} = {state.extra_messages, %{state | extra_messages: []}}
          new = [assistant | results] ++ extra
          loop(context ++ new, turn ++ new, state, iteration + 1, seen)

        {:ok, %{"content" => text}} when is_binary(text) and text != "" ->
          finish(turn, state, text)

        {:ok, _empty} ->
          finish(turn, state, @fallback_text)

        {:error, reason} when iteration == 0 ->
          {:error, "falha ao consultar o modelo: #{short(reason)}"}

        {:error, reason} ->
          Logger.error("model failed mid-turn: #{short(reason)}")
          finish(turn, state, @fallback_text)
      end
    end
  end

  defp finish(turn, state, text) do
    state.emit.(SSE.text(text))
    {:ok, %{messages: turn ++ [%{role: "assistant", content: text}], state: state}}
  end

  # Every tool_call gets exactly one tool message with the same id, in order.
  # A call identical to an earlier one in this turn is not executed again (no-progress guard).
  defp run_calls(calls, state, seen) do
    Enum.reduce(calls, {[], state, seen}, fn call, {acc, state, seen} ->
      %{"id" => id, "function" => %{"name" => name} = function} = call
      args = function["arguments"] || "{}"
      key = {name, args}

      {result, state} =
        if MapSet.member?(seen, key),
          do:
            {%{
               ok: false,
               error: "chamada repetida sem progresso; responda à pessoa com o que já tem"
             }, state},
          else: Tools.run(name, args, state)

      state = collect_executions(state, id)

      message = %{role: "tool", tool_call_id: id, content: Jason.encode!(result)}
      {acc ++ [message], state, MapSet.put(seen, key)}
    end)
  end

  # Proxy calls made by the orchestrators arrive as messages to this process; each gets
  # an id derived from the model's tool_call_id (unique per conversation).
  defp collect_executions(state, tool_call_id) do
    executions =
      Stream.repeatedly(fn ->
        receive do
          {:doris_tool_execution, e} -> e
        after
          0 -> nil
        end
      end)
      |> Enum.take_while(& &1)
      |> Enum.with_index(1)
      |> Enum.map(fn {e, n} -> Map.put(e, :tool_call_id, "#{tool_call_id}##{n}") end)

    %{state | executions: state.executions ++ executions}
  end

  defp assistant_message(message, calls) do
    %{
      role: "assistant",
      content: message["content"],
      tool_calls:
        Enum.map(calls, fn c ->
          %{
            id: c["id"],
            type: "function",
            function: Map.take(c["function"], ["name", "arguments"])
          }
        end)
    }
  end

  defp short({:http, status, _body}), do: "HTTP #{status}"
  defp short(%{__exception__: true} = e), do: Exception.message(e)
  defp short(other), do: inspect(other)
end
