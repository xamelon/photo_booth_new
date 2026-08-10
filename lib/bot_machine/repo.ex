defmodule BotMachine.Repo do
  use Ecto.Repo,
    otp_app: :bot_machine,
    adapter: Ecto.Adapters.SQLite3
end
