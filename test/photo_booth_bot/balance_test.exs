defmodule PhotoBoothBot.BalanceTest do
  use BotMachine.DataCase

  alias BotMachine.BotRuntime
  alias PhotoBoothBot.Balance

  test "insufficient debit does not roll back caller transaction" do
    connection = BotRuntime.default_connection("echo")

    %Balance{}
    |> Balance.changeset(%{
      bot_channel_connection_id: connection.id,
      channel: "echo",
      external_id: "empty-1",
      photos_remaining: 0,
      photos_spent: 1
    })
    |> Repo.insert!()

    assert {:ok, :ok} =
             Repo.transaction(fn ->
               assert Balance.debit_photo(connection.id, "echo", "empty-1") ==
                        {:error, :insufficient_balance}

               assert Balance.get_or_create(connection.id, "echo", "empty-1").photos_remaining ==
                        0

               :ok
             end)
  end

  test "manual adjustment creates transaction" do
    connection = BotRuntime.default_connection("echo")

    balance =
      %Balance{}
      |> Balance.changeset(%{
        bot_channel_connection_id: connection.id,
        channel: "echo",
        external_id: "manual-1",
        photos_remaining: 1,
        photos_spent: 0
      })
      |> Repo.insert!()

    assert {:ok, updated} = Balance.adjust_manually(balance.id, 2, "bonus")
    assert updated.photos_remaining == 3

    assert %{source: "admin_manual", delta_photos: 2, package_code: "bonus"} =
             Repo.one!(PhotoBoothBot.BalanceTransaction)
  end

  test "manual adjustment refuses negative balance" do
    connection = BotRuntime.default_connection("echo")

    balance =
      %Balance{}
      |> Balance.changeset(%{
        bot_channel_connection_id: connection.id,
        channel: "echo",
        external_id: "manual-2",
        photos_remaining: 1,
        photos_spent: 0
      })
      |> Repo.insert!()

    assert Balance.adjust_manually(balance.id, -2, "oops") == {:error, :invalid_delta}
    assert Balance.get_or_create(connection.id, "echo", "manual-2").photos_remaining == 1
  end

  test "stores payment email" do
    connection = BotRuntime.default_connection("echo")

    balance = Balance.put_payment_email(connection.id, "echo", "email-1", "user@example.com")

    assert balance.payment_email == "user@example.com"

    assert Balance.get_or_create(connection.id, "echo", "email-1").payment_email ==
             "user@example.com"
  end

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
