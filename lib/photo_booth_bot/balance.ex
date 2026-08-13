defmodule PhotoBoothBot.Balance do
  use Ecto.Schema
  import Ecto.Changeset

  alias BotMachine.Repo

  @initial_free_photos 1

  schema "photo_booth_balances" do
    belongs_to :bot_channel_connection, BotMachine.BotRuntime.BotChannelConnection
    field :channel, :string
    field :external_id, :string
    field :photos_remaining, :integer, default: @initial_free_photos
    field :photos_spent, :integer, default: 0
    timestamps(type: :utc_datetime)
  end

  def changeset(balance, attrs) do
    balance
    |> cast(attrs, [
      :bot_channel_connection_id,
      :channel,
      :external_id,
      :photos_remaining,
      :photos_spent
    ])
    |> validate_required([
      :bot_channel_connection_id,
      :channel,
      :external_id,
      :photos_remaining,
      :photos_spent
    ])
    |> unique_constraint([:bot_channel_connection_id, :external_id])
  end

  def get_or_create(connection_id, channel, external_id) do
    Repo.get_by(__MODULE__, bot_channel_connection_id: connection_id, external_id: external_id) ||
      %__MODULE__{}
      |> changeset(%{
        bot_channel_connection_id: connection_id,
        channel: channel,
        external_id: external_id,
        photos_remaining: @initial_free_photos,
        photos_spent: 0
      })
      |> Repo.insert!()
  end

  def debit_photo(connection_id, channel, external_id) do
    Repo.transaction(fn ->
      balance = get_or_create(connection_id, channel, external_id)

      if balance.photos_remaining > 0 do
        balance
        |> changeset(%{
          photos_remaining: balance.photos_remaining - 1,
          photos_spent: balance.photos_spent + 1
        })
        |> Repo.update!()
      else
        Repo.rollback(:insufficient_balance)
      end
    end)
  end

  def refund_photo(connection_id, channel, external_id) do
    balance = get_or_create(connection_id, channel, external_id)

    balance
    |> changeset(%{
      photos_remaining: balance.photos_remaining + 1,
      photos_spent: max(balance.photos_spent - 1, 0)
    })
    |> Repo.update!()
  end
end
