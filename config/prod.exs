import Config

# For production, don't forget to configure the url host
# to something meaningful, Phoenix uses this information
# when generating URLs.
#
# Note we also include the path to a cache manifest
# containing the digested version of static files. This
# manifest is generated by the `mix phx.digest` task,
# which you should run after static files are built and
# before starting your production server.
config :presentem, PresentemWeb.Endpoint,
  cache_static_manifest: "priv/static/cache_manifest.json",
  server: true

config :logger,
  level: :info,
  format: "[$level] $message\n",
  backends: [
    {LoggerFileBackend, :error_log},
    {LoggerFileBackend, :info_log},
    :console
  ]

config :logger, :error_log, path: "log/error.log", level: :error
config :logger, :info_log, path: "log/info.log", level: :info

config :presentem, repository_url: "git@github.com:meddle0x53/presentem_test.git"
