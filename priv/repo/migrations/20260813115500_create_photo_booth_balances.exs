defmodule BotMachine.Repo.Migrations.CreatePhotoBoothBalances do
  use Ecto.Migration

  def change do
    create table(:photo_booth_balances) do
      add :bot_channel_connection_id,
          references(:bot_channel_connections, on_delete: :delete_all), null: false

      add :channel, :text, null: false
      add :external_id, :text, null: false
      add :photos_remaining, :integer, null: false, default: 1
      add :photos_spent, :integer, null: false, default: 0
      timestamps(type: :utc_datetime)
    end

    create unique_index(:photo_booth_balances, [:bot_channel_connection_id, :external_id])
  end
end
