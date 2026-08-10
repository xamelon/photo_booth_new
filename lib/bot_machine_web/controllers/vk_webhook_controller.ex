defmodule BotMachineWeb.VKWebhookController do
  use BotMachineWeb, :controller

  require Logger

  alias BotMachine.BotRuntime
  alias BotMachine.BotRuntime.Channels.VK

  def callback(conn, params) do
    cond do
      response = VK.handle_protocol(params) ->
        Logger.info("VK webhook confirmation group_id=#{params["group_id"] || "?"}")
        BotMachine.BotRuntime.Channels.VKProvisioning.mark_confirmation_received()
        text(conn, response)

      event = VK.parse_inbound(params) ->
        Logger.info(
          "VK webhook message_new external_id=#{event.input["external_id"]} event_id=#{params["event_id"] || "?"}"
        )

        BotRuntime.enqueue_inbox(event.input, event.idempotency_key)
        text(conn, "ok")

      true ->
        Logger.info("VK webhook ignored type=#{params["type"] || "?"}")
        text(conn, "ok")
    end
  end
end
