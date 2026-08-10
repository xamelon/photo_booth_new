defmodule BotMachine.BotRuntime.BotTrigger do
  use Ecto.Schema
  import Ecto.Changeset

  schema "bot_triggers" do
    belongs_to :bot_flow, BotMachine.BotRuntime.BotFlow
    field :name, :string
    field :channel, :string
    field :type, :string
    field :match, :map
    field :start_node_id, :string
    field :session_mode, :string, default: "start_or_jump"
    field :priority, :integer, default: 0
    field :enabled, :boolean, default: true
    timestamps(type: :utc_datetime)
  end

  def changeset(trigger, attrs) do
    trigger
    |> cast(attrs, [
      :bot_flow_id,
      :name,
      :channel,
      :type,
      :match,
      :start_node_id,
      :session_mode,
      :priority,
      :enabled
    ])
    |> validate_required([
      :bot_flow_id,
      :name,
      :channel,
      :type,
      :match,
      :start_node_id,
      :session_mode,
      :priority,
      :enabled
    ])
  end
end
