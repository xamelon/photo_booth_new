defmodule BotMachine.BotRuntime.OutboxMessage do
  use Ecto.Schema
  import Ecto.Changeset

  schema "bot_outbox_messages" do
    field :channel, :string
    field :external_id, :string
    field :idempotency_key, :string
    field :payload, :map
    field :status, :string, default: "pending"
    field :attempts, :integer, default: 0
    field :next_retry_at, :utc_datetime
    field :last_error, :string
    field :sent_at, :utc_datetime
    field :external_message_id, :string
    timestamps(type: :utc_datetime)
  end

  def changeset(message, attrs),
    do:
      cast(message, attrs, [
        :channel,
        :external_id,
        :idempotency_key,
        :payload,
        :status,
        :attempts,
        :next_retry_at,
        :last_error,
        :sent_at,
        :external_message_id
      ])
      |> validate_required([:channel, :external_id, :idempotency_key, :payload, :status])
      |> unique_constraint(:idempotency_key)
end
