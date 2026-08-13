defmodule BotMachine.Repo.Migrations.AddPaymentEmailToPhotoBoothBalances do
  use Ecto.Migration

  def change do
    alter table(:photo_booth_balances) do
      add :payment_email, :text
    end
  end
end
