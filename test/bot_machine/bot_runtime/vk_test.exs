defmodule BotMachine.BotRuntime.VKTest do
  use ExUnit.Case, async: true

  alias BotMachine.BotRuntime.Channels.VK

  test "parses VK message_new into bot input" do
    event =
      VK.parse_inbound(%{
        "type" => "message_new",
        "group_id" => 1,
        "event_id" => "abc",
        "object" => %{
          "message" => %{
            "from_id" => 42,
            "text" => " /start ",
            "payload" => Jason.encode!(%{p: "menu"}),
            "attachments" => [
              %{
                "type" => "photo",
                "photo" => %{
                  "owner_id" => -1,
                  "id" => 2,
                  "sizes" => [%{"width" => 10, "height" => 10, "url" => "small"}]
                }
              }
            ]
          }
        }
      })

    assert event.idempotency_key == "vk:1:abc"
    assert event.input["channel"] == "vk"
    assert event.input["external_id"] == "42"
    assert event.input["text"] == "/start"
    assert event.input["payload"] == "menu"

    assert event.input["attachments"] == [
             %{"type" => "photo", "ref" => "photo-1_2", "url" => "small"}
           ]
  end
end
