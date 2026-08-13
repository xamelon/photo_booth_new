defmodule BotMachineWeb.Admin.AppController do
  use BotMachineWeb, :controller

  plug :assign_current_path

  def dashboard(conn, _params), do: render(conn, :dashboard)

  def balances(conn, _params) do
    data = PhotoBoothBot.Balance.admin_balances()
    render(conn, :balances, balances: data.balances, transactions: data.transactions)
  end

  def adjust_balance(conn, %{"balance_id" => balance_id, "delta_photos" => delta} = params) do
    note = params["note"] || "admin_manual_balance_adjustment"

    case Integer.parse(to_string(delta)) do
      {delta, ""} ->
        PhotoBoothBot.Balance.adjust_manually(balance_id, delta, note)

      _ ->
        {:error, :invalid_delta}
    end

    redirect(conn, to: ~p"/admin/app/balances")
  end

  defp assign_current_path(conn, _opts), do: assign(conn, :current_path, conn.request_path)
end
