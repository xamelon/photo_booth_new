defmodule BotMachine.BotRuntime.NotifyTriggerTest do
  use BotMachine.DataCase

  alias BotMachine.BotRuntime

  alias BotMachine.BotRuntime.{
    BotChannelConnection,
    BotFlow,
    BotFlowConnection,
    BotFlowVersion,
    BotSession,
    BotTrigger,
    BotUser,
    OutboxMessage
  }

  test "notify-only event trigger sends output without moving parked session" do
    connection =
      Repo.insert!(%BotChannelConnection{
        channel: "echo",
        name: "Echo",
        external_id: "sandbox",
        public_id: "conn_echo_test",
        status: "active",
        credentials: %{},
        config: %{}
      })

    flow = Repo.insert!(%BotFlow{slug: "photo_booth", name: "PhotoBooth", status: "published"})

    Repo.insert!(%BotFlowConnection{
      bot_flow_id: flow.id,
      bot_channel_connection_id: connection.id,
      enabled: true,
      priority: 0,
      config: %{}
    })

    Repo.insert!(%BotFlowVersion{
      bot_flow_id: flow.id,
      version: PhotoBoothBot.flow()["version"],
      status: "published",
      definition: PhotoBoothBot.flow(),
      published_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })

    Repo.insert!(%BotTrigger{
      bot_flow_id: flow.id,
      name: "Generation completed",
      channel: "echo",
      type: "event",
      match: %{"event" => "photo_generation.completed"},
      start_node_id: "act_generation_completed_notify",
      session_mode: "notify_only",
      priority: 100,
      enabled: true
    })

    user =
      Repo.insert!(%BotUser{
        bot_channel_connection_id: connection.id,
        channel: "echo",
        external_id: "42"
      })

    session =
      Repo.insert!(%BotSession{
        bot_channel_connection_id: connection.id,
        bot_user_id: user.id,
        flow_id: "photo_booth",
        flow_version: PhotoBoothBot.flow()["version"],
        current_node_id: "ask_edit_prompt",
        context: %{"edit_prompt" => "old draft"}
      })

    {:ok, _event} =
      BotRuntime.enqueue_inbox(
        %{
          "kind" => "domain_event",
          "event" => "photo_generation.completed",
          "channel" => "echo",
          "external_id" => "42",
          "bot_channel_connection_id" => connection.id,
          "payload" => %{
            "generation_job_id" => 1,
            "image_url" => "https://example.com/result.jpg"
          }
        },
        "generation-completed-test"
      )

    BotRuntime.process_pending_inbox()

    assert Repo.reload!(session).current_node_id == "ask_edit_prompt"

    assert %OutboxMessage{payload: payload} = Repo.one!(OutboxMessage)
    assert payload["text"] == "✨ Фото готово!"

    assert payload["attachments"] == [
             %{"type" => "photo", "url" => "https://example.com/result.jpg"}
           ]
  end
end
