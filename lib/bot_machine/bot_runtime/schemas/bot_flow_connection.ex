defmodule BotMachine.BotRuntime.BotFlowConnection do
  use Ecto.Schema
  import Ecto.Changeset

  schema "bot_flow_connections" do
    belongs_to :bot_flow, BotMachine.BotRuntime.BotFlow
    belongs_to :bot_channel_connection, BotMachine.BotRuntime.BotChannelConnection
    field :enabled, :boolean, default: true
    field :priority, :integer, default: 0
    field :config, :map, default: %{}
    timestamps(type: :utc_datetime)
  end

  def changeset(connection, attrs) do
    connection
    |> cast(attrs, [:bot_flow_id, :bot_channel_connection_id, :enabled, :priority, :config])
    |> validate_required([:bot_flow_id, :bot_channel_connection_id, :enabled, :priority, :config])
    |> unique_constraint([:bot_flow_id, :bot_channel_connection_id])
  end
end
