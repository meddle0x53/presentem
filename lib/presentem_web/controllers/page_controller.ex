defmodule PresentemWeb.PageController do
  use PresentemWeb, :controller

  def index(conn, _params) do
    render(conn, "index.html")
  end
end
