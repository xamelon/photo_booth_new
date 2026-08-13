defmodule PhotoBoothBot.BalanceTest do
  use BotMachine.DataCase

  alias BotMachine.BotRuntime
  alias PhotoBoothBot.Balance

  test "credits YooKassa package idempotently" do
    connection = BotRuntime.default_connection("echo")

    attrs = %{
      connection_id: connection.id,
      channel: "echo",
      external_id: "payer-1",
      package_code: "photo_3",
      payment_id: "pay-1"
    }

    assert {:ok, first} = Balance.credit_from_yookassa(attrs)
    assert first.applied
    assert first.balance.photos_remaining == 4

    assert {:ok, second} = Balance.credit_from_yookassa(attrs)
    refute second.applied
    assert second.balance.photos_remaining == 4
    assert Balance.transactions_count("pay-1") == 1
  end
end
