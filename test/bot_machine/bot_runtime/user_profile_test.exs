defmodule BotMachine.BotRuntime.UserProfileTest do
  use BotMachine.DataCase

  alias BotMachine.BotRuntime
  alias BotMachine.BotRuntime.BotUser
  alias BotMachine.Repo

  test "updates existing bot user from inbound profile" do
    connection = BotRuntime.default_connection("echo")

    user =
      %BotUser{}
      |> BotUser.changeset(%{
        bot_channel_connection_id: connection.id,
        channel: "echo",
        external_id: "profile-1",
        metadata: %{}
      })
      |> Repo.insert!()

    BotRuntime.enqueue_inbox(%{
      "kind" => "user_message",
      "channel" => "echo",
      "external_id" => "profile-1",
      "text" => "hello",
      "display_name" => "Ada Lovelace",
      "metadata" => %{"username" => "ada"}
    })

    BotRuntime.process_pending_inbox()

    user = Repo.get!(BotUser, user.id)
    assert user.display_name == "Ada Lovelace"
    assert user.metadata == %{"username" => "ada"}
  end
end
