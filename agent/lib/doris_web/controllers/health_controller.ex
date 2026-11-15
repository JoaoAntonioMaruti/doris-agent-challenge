defmodule DorisWeb.HealthController do
  use DorisWeb, :controller

  @doc "200 when the database answers; 503 otherwise."
  def show(conn, _params) do
    case Ecto.Adapters.SQL.query(Doris.Repo, "SELECT 1", []) do
      {:ok, _} -> json(conn, %{status: "ok"})
      {:error, _} -> conn |> put_status(503) |> json(%{status: "unavailable"})
    end
  end
end
