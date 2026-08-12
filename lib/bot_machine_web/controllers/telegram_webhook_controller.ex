defmodule BotMachineWeb.TelegramWebhookController do
  use BotMachineWeb, :controller

  require Logger

  alias BotMachine.BotRuntime
  alias BotMachine.BotRuntime.Channels.Telegram

  def callback(conn, params) do
    connection =
      case params["connection_public_id"] do
        nil -> BotRuntime.default_connection("telegram")
        public_id -> BotRuntime.connection_for_public_id(public_id)
      end

    cond do
      is_nil(connection) ->
        send_resp(conn, 404, "connection not found")

      event = Telegram.parse_inbound(params) ->
        input =
          event.input
          |> Map.put("bot_channel_connection_id", connection.id)
          |> put_telegram_file_urls(connection)

        BotRuntime.enqueue_inbox(input, event.idempotency_key)
        json(conn, %{ok: true})

      true ->
        Logger.info("Telegram webhook ignored update_id=#{params["update_id"] || "?"}")
        json(conn, %{ok: true})
    end
  end

  defp put_telegram_file_urls(input, connection) do
    attachments =
      Enum.map(input["attachments"] || [], fn
        %{"type" => "photo", "ref" => file_id} = attachment ->
          case Telegram.file_url(file_id, connection) do
            nil -> attachment
            url -> Map.put(attachment, "url", url)
          end

        attachment ->
          attachment
      end)

    Map.put(input, "attachments", attachments)
  end
end
