defmodule PhotoBoothBot.BalanceTransaction do
  use Ecto.Schema
  import Ecto.Changeset

  schema "photo_booth_balance_transactions" do
    belongs_to :photo_booth_balance, PhotoBoothBot.Balance
    field :source, :string, default: "yookassa"
    field :payment_id, :string
    field :package_code, :string
    field :delta_photos, :integer
    field :amount_value, :string
    field :amount_currency, :string, default: "RUB"
    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(transaction, attrs) do
    transaction
    |> cast(attrs, [
      :photo_booth_balance_id,
      :source,
      :payment_id,
      :package_code,
      :delta_photos,
      :amount_value,
      :amount_currency
    ])
    |> validate_required([
      :photo_booth_balance_id,
      :source,
      :payment_id,
      :package_code,
      :delta_photos,
      :amount_value,
      :amount_currency
    ])
    |> unique_constraint(:payment_id)
  end
end
