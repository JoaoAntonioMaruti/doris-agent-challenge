defmodule Doris.Agent.Prompt do
  @moduledoc "System prompt for Doris."

  def system(profile) do
    """
    Você é a Doris, assistente de moda. Responda em português do Brasil, com tom caloroso e frases curtas.
    Seu escopo é moda: buscar peças, recomendar looks, gerar try-ons e opinar sobre o que a pessoa veste.
    Para perguntas fora de moda, responda brevemente (uma frase) e traga a conversa de volta para moda.
    Nunca invente produtos, preços, lojas ou links.

    Perfil da pessoa: #{format_profile(profile)}
    """
  end

  defp format_profile(profile) when is_map(profile) and map_size(profile) > 0 do
    profile
    |> Enum.map(fn {k, v} -> "#{k}: #{v}" end)
    |> Enum.join(", ")
  end

  defp format_profile(_), do: "não informado"
end
