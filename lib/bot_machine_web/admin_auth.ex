defmodule BotMachineWeb.AdminAuth do
  import Plug.Conn
  import Phoenix.Controller

  alias BotMachine.Accounts

  def init(opts), do: opts
  def call(conn, :fetch_current_admin), do: fetch_current_admin(conn, [])
  def call(conn, :require_admin), do: require_admin(conn, [])

  def fetch_current_admin(conn, _opts) do
    admin_id = get_session(conn, :admin_user_id)
    assign(conn, :current_admin, admin_id && Accounts.get_admin_user(admin_id))
  end

  def require_admin(conn, _opts) do
    if conn.assigns[:current_admin] do
      conn
    else
      conn
      |> put_flash(:error, "Войдите в админку")
      |> redirect(to: "/login")
      |> halt()
    end
  end
end
