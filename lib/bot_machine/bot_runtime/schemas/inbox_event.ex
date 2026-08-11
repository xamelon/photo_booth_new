defmodule BotMachine.BotRuntime.InboxEvent do
  use Ecto.Schema
  import Ecto.Changeset

  schema "bot_inbox_events" do
    belongs_to :bot_channel_connection, BotMachine.BotRuntime.BotChannelConnection
    field :channel, :string
    field :external_id, :string
    field :idempotency_key, :string
    field :payload, :map
    field :status, :string, default: "pending"
    field :attempts, :integer, default: 0
    field :next_retry_at, :utc_datetime
    field :last_error, :string
    field :processed_at, :utc_datetime
    timestamps(type: :utc_datetime)
  end

  def changeset(event, attrs),
    do:
      cast(event, attrs, [
        :bot_channel_connection_id,
        :channel,
        :external_id,
        :idempotency_key,
        :payload,
        :status,
        :attempts,
        :next_retry_at,
        :last_error,
        :processed_at
      ])
      |> validate_required([
        :bot_channel_connection_id,
        :channel,
        :external_id,
        :idempotency_key,
        :payload,
        :status
      ])
      |> unique_constraint(:idempotency_key)
end
