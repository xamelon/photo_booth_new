defmodule PhotoBoothBot.Balance do
  use Ecto.Schema
  import Ecto.Changeset

  import Ecto.Query

  alias BotMachine.Repo
  alias PhotoBoothBot.BalanceTransaction

  @initial_free_photos 1
  @packages [
    %{"code" => "photo_1", "label" => "1 фото", "photo_count" => 1, "amount_value" => "49.00"},
    %{"code" => "photo_3", "label" => "3 фото", "photo_count" => 3, "amount_value" => "129.00"},
    %{"code" => "photo_5", "label" => "5 фото", "photo_count" => 5, "amount_value" => "199.00"}
  ]

  def packages, do: @packages
  def package(code), do: Enum.find(@packages, &(&1["code"] == code))

  schema "photo_booth_balances" do
    belongs_to :bot_channel_connection, BotMachine.BotRuntime.BotChannelConnection
    field :channel, :string
    field :external_id, :string
    field :photos_remaining, :integer, default: @initial_free_photos
    field :photos_spent, :integer, default: 0
    field :payment_email, :string
    timestamps(type: :utc_datetime)
  end

  def changeset(balance, attrs) do
    balance
    |> cast(attrs, [
      :bot_channel_connection_id,
      :channel,
      :external_id,
      :photos_remaining,
      :photos_spent,
      :payment_email
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
    balance = get_or_create(connection_id, channel, external_id)

    if balance.photos_remaining > 0 do
      balance
      |> changeset(%{
        photos_remaining: balance.photos_remaining - 1,
        photos_spent: balance.photos_spent + 1
      })
      |> Repo.update()
    else
      {:error, :insufficient_balance}
    end
  end

  def put_payment_email(connection_id, channel, external_id, email) do
    balance = get_or_create(connection_id, channel, external_id)

    balance
    |> changeset(%{payment_email: email})
    |> Repo.update!()
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

  def credit_from_yookassa(attrs) do
    selected_package =
      package(attrs.package_code) || raise "unknown package: #{attrs.package_code}"

    Repo.transaction(fn ->
      balance = get_or_create(attrs.connection_id, attrs.channel, attrs.external_id)

      inserted =
        %BalanceTransaction{}
        |> BalanceTransaction.changeset(%{
          photo_booth_balance_id: balance.id,
          source: "yookassa",
          payment_id: attrs.payment_id,
          package_code: selected_package["code"],
          delta_photos: selected_package["photo_count"],
          amount_value: selected_package["amount_value"],
          amount_currency: "RUB"
        })
        |> Repo.insert(on_conflict: :nothing)

      case inserted do
        {:ok, %BalanceTransaction{id: nil}} ->
          %{applied: false, balance: Repo.get!(__MODULE__, balance.id), package: selected_package}

        {:ok, _transaction} ->
          balance =
            balance
            |> changeset(%{
              photos_remaining: balance.photos_remaining + selected_package["photo_count"]
            })
            |> Repo.update!()

          %{applied: true, balance: balance, package: selected_package}
      end
    end)
  end

  def transactions_count(payment_id) do
    Repo.aggregate(from(t in BalanceTransaction, where: t.payment_id == ^payment_id), :count)
  end
end
