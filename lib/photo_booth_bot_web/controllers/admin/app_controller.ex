defmodule BotMachineWeb.Admin.AppController do
  use BotMachineWeb, :controller

  plug :assign_current_path

  def dashboard(conn, _params), do: render(conn, :dashboard)

  defp assign_current_path(conn, _opts), do: assign(conn, :current_path, conn.request_path)
end
