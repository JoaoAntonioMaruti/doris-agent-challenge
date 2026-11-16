defmodule Doris.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      DorisWeb.Telemetry,
      Doris.Repo,
      {DNSCluster, query: Application.get_env(:doris, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Doris.PubSub},
      {Task.Supervisor, name: Doris.TaskSupervisor},
      # Start a worker by calling: Doris.Worker.start_link(arg)
      # {Doris.Worker, arg},
      # Start to serve requests, typically the last entry
      DorisWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Doris.Supervisor]

    with {:ok, pid} <- Supervisor.start_link(children, opts) do
      check_memory_mode!(Application.fetch_env!(:doris, :memory_mode))
      {:ok, pid}
    end
  end

  # MEMORY_MODE=v2 explicitly requested without pgvector/migration fails the boot early.
  defp check_memory_mode!(:v1), do: :ok

  defp check_memory_mode!(:v2) do
    %{rows: [[extension, table]]} =
      Ecto.Adapters.SQL.query!(
        Doris.Repo,
        "SELECT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'vector'), to_regclass('semantic_memories') IS NOT NULL",
        []
      )

    unless extension and table,
      do:
        raise("MEMORY_MODE=v2 requires the vector extension and the semantic_memories migration")
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    DorisWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
