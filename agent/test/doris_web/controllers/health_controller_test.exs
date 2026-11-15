defmodule DorisWeb.HealthControllerTest do
  use DorisWeb.ConnCase, async: true

  test "GET /health returns 200 when the database is reachable", %{conn: conn} do
    assert %{"status" => "ok"} = conn |> get("/health") |> json_response(200)
  end
end
