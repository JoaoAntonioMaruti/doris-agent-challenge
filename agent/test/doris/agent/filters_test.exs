defmodule Doris.Agent.FiltersTest do
  use ExUnit.Case, async: true
  alias Doris.Agent.Filters

  @products [
    %{"search_item_id" => "a", "name" => "Camisa branca", "price" => 249.9, "description" => ""},
    %{
      "search_item_id" => "b",
      "name" => "Camisa de linho",
      "price" => 349.0,
      "description" => ""
    },
    %{"search_item_id" => "c", "name" => "Blusa Amarela", "price" => 99.0, "description" => ""},
    %{
      "search_item_id" => "d",
      "name" => "Vestido",
      "price" => 120.0,
      "description" => "tons de amarelo"
    }
  ]

  defp ids(list), do: Enum.map(list, & &1["search_item_id"])

  test "price ceiling is inclusive and drops items above it" do
    assert ids(Filters.apply(@products, 249.9, [])) == ["a", "c", "d"]
  end

  test "avoided colours match gender/number variants and accents, in name or description" do
    assert ids(Filters.apply(@products, nil, ["amarelo"])) == ["a", "b"]
    assert ids(Filters.apply(@products, nil, ["Amarela"])) == ["a", "b"]
  end

  test "no constraints keeps everything" do
    assert length(Filters.apply(@products, nil, [])) == 4
  end
end
