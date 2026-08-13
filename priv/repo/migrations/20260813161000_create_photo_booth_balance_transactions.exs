defmodule BotMachine.Repo.Migrations.CreatePhotoBoothBalanceTransactions do
  use Ecto.Migration

  def change do
    create table(:photo_booth_balance_transactions) do
      add :photo_booth_balance_id,
          references(:photo_booth_balances, on_delete: :delete_all), null: false

      add :source, :text, null: false, default: "yookassa"
      add :payment_id, :text, null: false
      add :package_code, :text, null: false
      add :delta_photos, :integer, null: false
      add :amount_value, :text, null: false
      add :amount_currency, :text, null: false, default: "RUB"
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:photo_booth_balance_transactions, [:payment_id])
    create index(:photo_booth_balance_transactions, [:photo_booth_balance_id])
  end
end
