defmodule BotMachine.Repo.Migrations.AddMessageHistoryIndexes do
  use Ecto.Migration

  def change do
    create_if_not_exists index(:bot_inbox_events, [
                           :bot_channel_connection_id,
                           :external_id,
                           :inserted_at
                         ])

    create_if_not_exists index(:bot_outbox_messages, [
                           :bot_channel_connection_id,
                           :external_id,
                           :inserted_at
                         ])
  end
end
