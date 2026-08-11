defmodule BotMachine.Repo.Migrations.AddChannelAndFlowConnections do
  use Ecto.Migration

  def change do
    create table(:bot_channel_connections) do
      add :channel, :text, null: false
      add :name, :text, null: false
      add :external_id, :text
      add :public_id, :text, null: false
      add :status, :text, null: false, default: "active"
      add :credentials, :map, null: false, default: %{}
      add :config, :map, null: false, default: %{}
      timestamps(type: :utc_datetime)
    end

    create unique_index(:bot_channel_connections, [:public_id])
    create index(:bot_channel_connections, [:channel, :external_id])

    create table(:bot_flow_connections) do
      add :bot_flow_id, references(:bot_flows, on_delete: :delete_all), null: false

      add :bot_channel_connection_id,
          references(:bot_channel_connections, on_delete: :delete_all), null: false

      add :enabled, :boolean, null: false, default: true
      add :priority, :integer, null: false, default: 0
      add :config, :map, null: false, default: %{}
      timestamps(type: :utc_datetime)
    end

    create unique_index(:bot_flow_connections, [:bot_flow_id, :bot_channel_connection_id])
    create index(:bot_flow_connections, [:bot_channel_connection_id, :enabled, :priority])

    alter table(:bot_users) do
      add :bot_channel_connection_id, references(:bot_channel_connections, on_delete: :delete_all)
    end

    alter table(:bot_sessions) do
      add :bot_channel_connection_id, references(:bot_channel_connections, on_delete: :delete_all)
    end

    alter table(:bot_inbox_events) do
      add :bot_channel_connection_id, references(:bot_channel_connections, on_delete: :delete_all)
    end

    alter table(:bot_outbox_messages) do
      add :bot_channel_connection_id, references(:bot_channel_connections, on_delete: :delete_all)
    end

    alter table(:bot_events) do
      add :bot_channel_connection_id, references(:bot_channel_connections, on_delete: :nilify_all)
    end

    drop_if_exists unique_index(:bot_users, [:channel, :external_id])
    create unique_index(:bot_users, [:bot_channel_connection_id, :external_id])
    create index(:bot_sessions, [:bot_channel_connection_id, :bot_user_id, :completed_at])
    create index(:bot_inbox_events, [:bot_channel_connection_id, :status, :next_retry_at])
    create index(:bot_outbox_messages, [:bot_channel_connection_id, :status, :next_retry_at])
    create index(:bot_events, [:bot_channel_connection_id, :flow_id, :inserted_at])
  end
end
