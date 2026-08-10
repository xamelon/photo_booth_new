defmodule BotMachine.BotRuntime.BotChannelCredential do
  use Ecto.Schema
  import Ecto.Changeset

  schema "bot_channel_credentials" do
    field :channel, :string
    field :data, :map, default: %{}
    timestamps(type: :utc_datetime)
  end

  def changeset(credential, attrs) do
    credential
    |> cast(attrs, [:channel, :data])
    |> validate_required([:channel, :data])
    |> unique_constraint(:channel)
  end
end
