defmodule DorisWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :doris

  # Code reloading can be explicitly enabled under the
  # :code_reloader configuration of your endpoint.
  if code_reloading? do
    plug Phoenix.CodeReloader
    plug Phoenix.Ecto.CheckRepoStatus, otp_app: :doris
  end

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:json],
    # attached images arrive as base64 data URIs
    length: 40_000_000,
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug DorisWeb.Router
end
