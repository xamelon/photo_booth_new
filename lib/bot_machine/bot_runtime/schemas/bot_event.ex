defmodule BotMachine.BotRuntime.BotEvent do
  use Ecto.Schema
  import Ecto.Changeset

  schema "bot_events" do
    belongs_to :bot_session, BotMachine.BotRuntime.BotSession
    field :flow_id, :string
    field :node_id, :string
    field :event_type, :string
    field :payload, :map, default: %{}
    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(event, attrs),
    do:
      cast(event, attrs, [:bot_session_id, :flow_id, :node_id, :event_type, :payload])
      |> validate_required([:flow_id, :event_type])
end
