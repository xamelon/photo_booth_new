defmodule BotMachine.Repo.Migrations.CreateBotFlows do
  use Ecto.Migration

  def change do
    create table(:bot_flows) do
      add :slug, :text, null: false
      add :name, :text, null: false
      add :status, :text, null: false, default: "draft"
      timestamps(type: :utc_datetime)
    end

    create unique_index(:bot_flows, [:slug])

    create table(:bot_flow_versions) do
      add :bot_flow_id, references(:bot_flows, on_delete: :delete_all), null: false
      add :version, :integer, null: false
      add :status, :text, null: false, default: "draft"
      add :definition, :map, null: false
      add :published_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create unique_index(:bot_flow_versions, [:bot_flow_id, :version])
    create index(:bot_flow_versions, [:status, :version])

    create table(:bot_triggers) do
      add :bot_flow_id, references(:bot_flows, on_delete: :delete_all), null: false
      add :name, :text, null: false
      add :channel, :text, null: false
      add :type, :text, null: false
      add :match, :map, null: false
      add :start_node_id, :text, null: false
      add :session_mode, :text, null: false, default: "start_or_jump"
      add :priority, :integer, null: false, default: 0
      add :enabled, :boolean, null: false, default: true
      timestamps(type: :utc_datetime)
    end

    create index(:bot_triggers, [:channel, :enabled, :priority])
    create index(:bot_triggers, [:bot_flow_id])
  end
end
