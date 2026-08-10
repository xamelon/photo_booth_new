defmodule BotMachine.BotRuntime.BotFlow do
  use Ecto.Schema
  import Ecto.Changeset

  schema "bot_flows" do
    field :slug, :string
    field :name, :string
    field :status, :string, default: "draft"
    has_many :versions, BotMachine.BotRuntime.BotFlowVersion
    timestamps(type: :utc_datetime)
  end

  def changeset(flow, attrs) do
    flow
    |> cast(attrs, [:slug, :name, :status])
    |> validate_required([:slug, :name, :status])
    |> unique_constraint(:slug)
  end
end
