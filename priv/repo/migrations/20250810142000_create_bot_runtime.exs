defmodule BotMachine.Repo.Migrations.CreateBotRuntime do
  use Ecto.Migration

  def change do
    create table(:admin_users) do
      add :email, :text, null: false
      add :hashed_password, :text
      add :role, :text, null: false, default: "admin"
      timestamps(type: :utc_datetime)
    end

    create unique_index(:admin_users, [:email])

    create table(:bot_users) do
      add :channel, :text, null: false
      add :external_id, :text, null: false
      add :display_name, :text
      add :metadata, :map, null: false, default: %{}
      add :blocked_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create unique_index(:bot_users, [:channel, :external_id])

    create table(:bot_sessions) do
      add :bot_user_id, references(:bot_users, on_delete: :delete_all), null: false
      add :flow_id, :text, null: false
      add :flow_version, :integer, null: false
      add :current_node_id, :text, null: false
      add :context, :map, null: false, default: %{}
      add :completed_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create index(:bot_sessions, [:bot_user_id, :completed_at])

    create table(:bot_inbox_events) do
      add :channel, :text, null: false
      add :external_id, :text, null: false
      add :idempotency_key, :text, null: false
      add :payload, :map, null: false
      add :status, :text, null: false, default: "pending"
      add :attempts, :integer, null: false, default: 0
      add :next_retry_at, :utc_datetime
      add :last_error, :text
      add :processed_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create unique_index(:bot_inbox_events, [:idempotency_key])
    create index(:bot_inbox_events, [:status, :next_retry_at])

    create table(:bot_outbox_messages) do
      add :channel, :text, null: false
      add :external_id, :text, null: false
      add :idempotency_key, :text, null: false
      add :payload, :map, null: false
      add :status, :text, null: false, default: "pending"
      add :attempts, :integer, null: false, default: 0
      add :next_retry_at, :utc_datetime
      add :last_error, :text
      add :sent_at, :utc_datetime
      add :external_message_id, :text
      timestamps(type: :utc_datetime)
    end

    create unique_index(:bot_outbox_messages, [:idempotency_key])
    create index(:bot_outbox_messages, [:status, :next_retry_at])

    create table(:bot_events) do
      add :bot_session_id, references(:bot_sessions, on_delete: :nilify_all)
      add :flow_id, :text, null: false
      add :node_id, :text
      add :event_type, :text, null: false
      add :payload, :map, null: false, default: %{}
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:bot_events, [:flow_id, :inserted_at])
  end
end
