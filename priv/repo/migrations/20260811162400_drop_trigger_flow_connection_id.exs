defmodule BotMachine.Repo.Migrations.DropTriggerFlowConnectionId do
  use Ecto.Migration

  def up do
    if column_exists?(:bot_triggers, "bot_flow_connection_id") do
      drop_if_exists index(:bot_triggers, [:bot_flow_connection_id, :enabled, :priority])

      alter table(:bot_triggers) do
        remove :bot_flow_connection_id
      end
    end
  end

  def down do
    alter table(:bot_triggers) do
      add :bot_flow_connection_id, references(:bot_flow_connections, on_delete: :delete_all)
    end
  end

  defp column_exists?(table, column) do
    %{rows: rows} = repo().query!("PRAGMA table_info(#{table})")
    Enum.any?(rows, &(Enum.at(&1, 1) == column))
  end
end
