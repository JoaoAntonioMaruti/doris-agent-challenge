defmodule Doris.Agent.Filters do
  @moduledoc """
  Hard rules applied to search results in code. `search_by_text` only offers candidates:
  it ignores price and colour, so the agent must never trust it for constraints.
  """

  @doc "Keeps products within `max_price` (nil = no ceiling) and without avoided colours."
  def apply(products, max_price, avoid_colors) do
    patterns = Enum.map(avoid_colors, &color_pattern/1)

    Enum.filter(products, fn p ->
      within_budget?(p, max_price) and not Enum.any?(patterns, &Regex.match?(&1, haystack(p)))
    end)
  end

  def within_budget?(_product, nil), do: true
  def within_budget?(%{"price" => price}, max) when is_number(price), do: price <= max
  def within_budget?(_product, _max), do: false

  def mentions_color?(product, color), do: Regex.match?(color_pattern(color), haystack(product))

  defp haystack(p), do: normalize("#{p["name"]} #{p["description"]}")

  # "amarelo" also matches amarela/amarelos/amarelas; "azul" matches azuis.
  defp color_pattern(color) do
    color = normalize(color) |> String.trim()

    stem =
      cond do
        String.ends_with?(color, ["o", "a"]) -> String.slice(color, 0..-2//1) <> "(o|a|os|as)"
        String.ends_with?(color, "l") -> String.slice(color, 0..-2//1) <> "(l|is)"
        true -> Regex.escape(color) <> "(s|es)?"
      end

    Regex.compile!("\\b" <> stem <> "\\b", "u")
  end

  defp normalize(text) do
    text
    |> String.downcase()
    |> :unicode.characters_to_nfd_binary()
    |> String.replace(~r/\p{Mn}/u, "")
  end
end
