defmodule Presentem.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @repository_provider Application.compile_env(
                         :presentem,
                         :repository_provider,
                         Presentem.RepositoryProviders.Git
                       )

  @impl true
  def start(_type, _args) do
    children = [
      # Start the Telemetry supervisor
      PresentemWeb.Telemetry,
      # Start the PubSub system
      {Phoenix.PubSub, name: Presentem.PubSub},
      # Start the Endpoint (http/https)
      PresentemWeb.Endpoint,
      {Presentem.Updater, [@repository_provider]}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Presentem.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    PresentemWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
