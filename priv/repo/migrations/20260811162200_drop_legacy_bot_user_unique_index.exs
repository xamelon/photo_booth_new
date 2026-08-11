defmodule BotMachine.Repo.Migrations.DropLegacyBotUserUniqueIndex do
  use Ecto.Migration

  def change do
    drop_if_exists unique_index(:bot_users, [:channel, :external_id])
    create_if_not_exists unique_index(:bot_users, [:bot_channel_connection_id, :external_id])
  end
end
