defmodule Doris.Agent.Runner do
  @moduledoc """
  Runs one turn. `emit` is a 1-arity function receiving already-encoded SSE events.
  T02: a single model call with no tools.
  """
  alias Doris.{ChatRequest, SSE}
  alias Doris.Agent.Prompt
  alias Doris.LLM.OpenRouter

  def run(%ChatRequest{} = req, emit) do
    messages = [
      %{role: "system", content: Prompt.system(req.profile)},
      %{role: "user", content: req.content}
    ]

    case OpenRouter.chat(messages) do
      {:ok, %{"content" => content}} when is_binary(content) and content != "" ->
        emit.(SSE.text(content))
        :ok

      {:ok, _} ->
        {:error, "o modelo não retornou texto"}

      {:error, reason} ->
        {:error, "falha ao consultar o modelo: #{short(reason)}"}
    end
  end

  defp short({:http, status, _body}), do: "HTTP #{status}"
  defp short(%{__exception__: true} = e), do: Exception.message(e)
  defp short(other), do: inspect(other)
end
