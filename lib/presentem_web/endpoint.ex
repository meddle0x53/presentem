defmodule PresentemWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :presentem

  # The session will be stored in the cookie and signed,
  # this means its contents can be read but not tampered with.
  # Set :encryption_salt if you would also like to encrypt it.
  @session_options [
    store: :cookie,
    key: "_presentem_key",
    signing_salt: "kR0DdkC8"
  ]

  socket "/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]]

  plug Plug.Static.IndexHtml, at: "/slides"

  plug Plug.Static,
    at: "/",
    from: :presentem,
    gzip: false,
    only: ~w(assets fonts images favicon.ico robots.txt)

  plug Plug.Static,
    at: "slides/",
    from: "_presentations",
    gzip: false

  # Code reloading can be explicitly enabled under the
  # :code_reloader configuration of your endpoint.
  if code_reloading? do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
  end

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug PresentemWeb.Router
end
