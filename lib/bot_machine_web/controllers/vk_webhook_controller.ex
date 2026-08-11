defmodule BotMachineWeb.VKWebhookController do
  use BotMachineWeb, :controller

  require Logger

  alias BotMachine.BotRuntime
  alias BotMachine.BotRuntime.Channels.VK

  def callback(conn, params) do
    connection =
      case params["connection_public_id"] do
        nil -> BotRuntime.default_connection("vk")
        public_id -> BotRuntime.connection_for_public_id(public_id)
      end

    if is_nil(connection),
      do: send_resp(conn, 404, "connection not found"),
      else: handle(conn, params, connection)
  end

  defp handle(conn, params, connection) do
    cond do
      response = VK.handle_protocol(params, connection) ->
        Logger.info("VK webhook confirmation group_id=#{params["group_id"] || "?"}")
        BotMachine.BotRuntime.Channels.VKProvisioning.mark_confirmation_received(connection)
        text(conn, response)

      event = VK.parse_inbound(params) ->
        Logger.info(
          "VK webhook message_new external_id=#{event.input["external_id"]} event_id=#{params["event_id"] || "?"}"
        )

        input = Map.put(event.input, "bot_channel_connection_id", connection.id)
        BotRuntime.enqueue_inbox(input, event.idempotency_key)
        text(conn, "ok")

      true ->
        Logger.info("VK webhook ignored type=#{params["type"] || "?"}")
        text(conn, "ok")
    end
  end
end
