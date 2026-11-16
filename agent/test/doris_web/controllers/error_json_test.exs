defmodule DorisWeb.ErrorJSONTest do
  use DorisWeb.ConnCase, async: true

  test "renders 404" do
    assert DorisWeb.ErrorJSON.render("404.json", %{}) == %{errors: %{detail: "Not Found"}}
  end

  test "renders 500" do
    assert DorisWeb.ErrorJSON.render("500.json", %{}) ==
             %{errors: %{detail: "Internal Server Error"}}
  end
end
