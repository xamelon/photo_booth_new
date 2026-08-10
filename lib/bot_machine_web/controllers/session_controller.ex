defmodule BotMachineWeb.SessionController do
  use BotMachineWeb, :controller

  alias BotMachine.Accounts

  def new(conn, _params), do: render(conn, :new, error: nil)

  def create(conn, %{"email" => email, "password" => password}) do
    case Accounts.authenticate_admin(email, password) do
      {:ok, user} ->
        conn
        |> renew_session()
        |> put_session(:admin_user_id, user.id)
        |> redirect(to: "/admin/bot")

      {:error, _} ->
        conn
        |> put_status(:unauthorized)
        |> render(:new, error: "Неверная почта или пароль")
    end
  end

  def delete(conn, _params) do
    conn
    |> configure_session(drop: true)
    |> redirect(to: "/login")
  end

  defp renew_session(conn) do
    conn
    |> configure_session(renew: true)
    |> clear_session()
  end
end
