defmodule PresentemWeb.PageController do
  use PresentemWeb, :controller

  def index(conn, _params) do
    redirect(conn, to: "/slides/")
  end
end
