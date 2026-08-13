defmodule BotMachine.BotRuntime.ChannelResetTest do
  use BotMachine.DataCase

  alias BotMachine.BotRuntime

  alias BotMachine.BotRuntime.{
    BotChannelConnection,
    BotFlow,
    BotFlowConnection,
    BotSession,
    BotUser,
    InboxEvent,
    OutboxMessage
  }

  test "delete_channel_connection! deletes one connection and dependent runtime rows" do
    %{connection: connection} = insert_connection_with_runtime("telegram", "conn_tg_delete")

    BotRuntime.delete_channel_connection!(connection.id)

    refute Repo.get(BotChannelConnection, connection.id)
    assert Repo.aggregate(BotUser, :count) == 0
    assert Repo.aggregate(BotSession, :count) == 0
    assert Repo.aggregate(BotFlowConnection, :count) == 0
    assert Repo.aggregate(InboxEvent, :count) == 0
    assert Repo.aggregate(OutboxMessage, :count) == 0
  end

  defp insert_connection_with_runtime(channel, public_id) do
    flow = Repo.insert!(%BotFlow{slug: public_id, name: "Delete test", status: "published"})

    connection =
      Repo.insert!(%BotChannelConnection{
        channel: channel,
        name: "Connection",
        external_id: "bot",
        public_id: public_id,
        status: "active",
        credentials: %{},
        config: %{}
      })

    user =
      Repo.insert!(%BotUser{
        bot_channel_connection_id: connection.id,
        channel: channel,
        external_id: "42"
      })

    Repo.insert!(%BotFlowConnection{
      bot_flow_id: flow.id,
      bot_channel_connection_id: connection.id,
      enabled: true,
      priority: 0,
      config: %{}
    })

    Repo.insert!(%BotSession{
      bot_channel_connection_id: connection.id,
      bot_user_id: user.id,
      flow_id: public_id,
      flow_version: 1,
      current_node_id: "start",
      context: %{}
    })

    Repo.insert!(%InboxEvent{
      bot_channel_connection_id: connection.id,
      channel: channel,
      external_id: "42",
      idempotency_key: public_id <> "-in",
      payload: %{},
      status: "pending"
    })

    Repo.insert!(%OutboxMessage{
      bot_channel_connection_id: connection.id,
      channel: channel,
      external_id: "42",
      idempotency_key: public_id <> "-out",
      payload: %{},
      status: "pending"
    })

    %{connection: connection, user: user, flow: flow}
  end
end
