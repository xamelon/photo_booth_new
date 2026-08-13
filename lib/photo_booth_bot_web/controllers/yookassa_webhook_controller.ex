defmodule PhotoBoothBotWeb.YooKassaWebhookController do
  use BotMachineWeb, :controller

  require Logger

  alias BotMachine.BotRuntime
  alias PhotoBoothBot.{Balance, YooKassa}

  def callback(conn, %{"event" => "payment.succeeded", "object" => %{"id" => payment_id}}) do
    with true <- YooKassa.configured?(),
         {:ok, payment} <- YooKassa.get_payment(payment_id),
         true <- payment["status"] == "succeeded" and payment["paid"] != false,
         {:ok, result} <- credit_payment(payment) do
      enqueue_success(payment, result)
    else
      false -> :ok
      {:error, reason} -> Logger.warning("YooKassa webhook ignored: #{inspect(reason)}")
    end

    json(conn, %{ok: true})
  end

  def callback(conn, _params), do: json(conn, %{ok: true})

  defp credit_payment(payment) do
    metadata = payment["metadata"] || %{}

    attrs = %{
      connection_id: parse_int(metadata["bot_channel_connection_id"]),
      channel: metadata["channel"],
      external_id: metadata["external_id"],
      package_code: metadata["package_code"],
      payment_id: payment["id"]
    }

    if Enum.any?(attrs, fn {_key, value} -> value in [nil, ""] end) do
      {:error, :missing_metadata}
    else
      Balance.credit_from_yookassa(attrs)
    end
  end

  defp enqueue_success(payment, result) do
    balance = result.balance
    package = result.package

    BotRuntime.enqueue_inbox(
      %{
        "kind" => "domain_event",
        "event" => "payment.yookassa.succeeded",
        "payload" => %{
          "payment_id" => payment["id"],
          "package_code" => package["code"],
          "credited_photos" => package["photo_count"],
          "photo_balance" => balance.photos_remaining,
          "applied" => result.applied
        },
        "payment_id" => payment["id"],
        "bot_channel_connection_id" => balance.bot_channel_connection_id,
        "channel" => balance.channel,
        "external_id" => balance.external_id,
        "text" => ""
      },
      "yookassa:#{payment["id"]}:succeeded:#{balance.external_id}"
    )
  end

  defp parse_int(value) when is_integer(value), do: value

  defp parse_int(value) do
    case Integer.parse(to_string(value)) do
      {int, _} -> int
      :error -> nil
    end
  end
end
