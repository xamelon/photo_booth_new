defmodule BotMachine.BotRuntime.BotChannelConnection do
  use Ecto.Schema
  import Ecto.Changeset

  schema "bot_channel_connections" do
    field :channel, :string
    field :name, :string
    field :external_id, :string
    field :public_id, :string
    field :status, :string, default: "active"
    field :credentials, :map, default: %{}
    field :config, :map, default: %{}
    field :flow_connection_count, :integer, virtual: true
    has_many :flow_connections, BotMachine.BotRuntime.BotFlowConnection
    timestamps(type: :utc_datetime)
  end

  def changeset(connection, attrs) do
    connection
    |> cast(attrs, [:channel, :name, :external_id, :public_id, :status, :credentials, :config])
    |> validate_required([:channel, :name, :public_id, :status, :credentials, :config])
    |> unique_constraint(:public_id)
  end
end
