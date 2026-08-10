defmodule BotMachine.BotRuntime.BotFlowVersion do
  use Ecto.Schema
  import Ecto.Changeset

  schema "bot_flow_versions" do
    belongs_to :bot_flow, BotMachine.BotRuntime.BotFlow
    field :version, :integer
    field :status, :string, default: "draft"
    field :definition, :map
    field :published_at, :utc_datetime
    timestamps(type: :utc_datetime)
  end

  def changeset(version, attrs) do
    version
    |> cast(attrs, [:bot_flow_id, :version, :status, :definition, :published_at])
    |> validate_required([:bot_flow_id, :version, :status, :definition])
    |> unique_constraint([:bot_flow_id, :version])
  end
end
