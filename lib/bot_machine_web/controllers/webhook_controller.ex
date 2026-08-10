defmodule BotMachineWeb.WebhookController do
  use BotMachineWeb, :controller

  def echo(conn, params) do
    external_id = to_string(params["external_id"] || params["user_id"] || "demo")

    input = %{
      "kind" => "user_message",
      "channel" => "echo",
      "external_id" => external_id,
      "text" => to_string(params["text"] || "")
    }

    {:ok, _} = BotMachine.BotRuntime.enqueue_inbox(input, params["idempotency_key"])
    json(conn, %{ok: true})
  end
end
