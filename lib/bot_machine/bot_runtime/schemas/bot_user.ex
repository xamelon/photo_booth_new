defmodule BotMachine.BotRuntime.BotUser do
  use Ecto.Schema
  import Ecto.Changeset

  schema "bot_users" do
    belongs_to :bot_channel_connection, BotMachine.BotRuntime.BotChannelConnection
    field :channel, :string
    field :external_id, :string
    field :display_name, :string
    field :metadata, :map, default: %{}
    field :blocked_at, :utc_datetime
    timestamps(type: :utc_datetime)
  end

  def changeset(user, attrs),
    do:
      cast(user, attrs, [
        :bot_channel_connection_id,
        :channel,
        :external_id,
        :display_name,
        :metadata,
        :blocked_at
      ])
      |> validate_required([:bot_channel_connection_id, :channel, :external_id])
      |> unique_constraint([:bot_channel_connection_id, :external_id])
end
