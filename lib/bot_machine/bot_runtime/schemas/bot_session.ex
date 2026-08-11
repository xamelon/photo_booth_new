defmodule BotMachine.BotRuntime.BotSession do
  use Ecto.Schema
  import Ecto.Changeset

  schema "bot_sessions" do
    belongs_to :bot_user, BotMachine.BotRuntime.BotUser
    belongs_to :bot_channel_connection, BotMachine.BotRuntime.BotChannelConnection
    field :flow_id, :string
    field :flow_version, :integer
    field :current_node_id, :string
    field :context, :map, default: %{}
    field :completed_at, :utc_datetime
    timestamps(type: :utc_datetime)
  end

  def changeset(session, attrs),
    do:
      cast(session, attrs, [
        :bot_user_id,
        :bot_channel_connection_id,
        :flow_id,
        :flow_version,
        :current_node_id,
        :context,
        :completed_at
      ])
      |> validate_required([
        :bot_user_id,
        :bot_channel_connection_id,
        :flow_id,
        :flow_version,
        :current_node_id
      ])
end
