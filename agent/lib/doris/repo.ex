defmodule Doris.Repo do
  use Ecto.Repo,
    otp_app: :doris,
    adapter: Ecto.Adapters.Postgres
end
