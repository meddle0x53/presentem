defmodule PresentemWeb.Router do
  use PresentemWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, {PresentemWeb.LayoutView, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", PresentemWeb do
    pipe_through :browser

    get "/", PageController, :index
    get "/slides", PageController, :index
  end

  # Other scopes may use custom stacks.
  # scope "/api", PresentemWeb do
  #   pipe_through :api
  # end
end
