defmodule BotMachine.Repo.Migrations.CreateBotChannelCredentials do
  use Ecto.Migration

  def change do
    create table(:bot_channel_credentials) do
      add :channel, :text, null: false
      add :data, :map, null: false, default: %{}
      timestamps(type: :utc_datetime)
    end

    create unique_index(:bot_channel_credentials, [:channel])
  end
end
