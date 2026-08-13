defmodule BotMachine.BotRuntime.TelegramTest do
  use ExUnit.Case, async: true

  alias BotMachine.BotRuntime.Channels.Telegram

  test "parses Telegram message into bot input" do
    event =
      Telegram.parse_inbound(%{
        "update_id" => 123,
        "message" => %{
          "chat" => %{"id" => 42},
          "from" => %{
            "id" => 7,
            "first_name" => "Ada",
            "last_name" => "Lovelace",
            "username" => "ada",
            "language_code" => "en"
          },
          "text" => " /start ",
          "photo" => [
            %{"file_id" => "small", "file_size" => 1},
            %{"file_id" => "large", "file_size" => 2}
          ]
        }
      })

    assert event.idempotency_key == "telegram:123"
    assert event.input["channel"] == "telegram"
    assert event.input["external_id"] == "42"
    assert event.input["display_name"] == "Ada Lovelace"

    assert event.input["metadata"] == %{
             "telegram_user_id" => "7",
             "username" => "ada",
             "language_code" => "en"
           }

    assert event.input["text"] == "/start"
    assert event.input["attachments"] == [%{"type" => "photo", "ref" => "large"}]
  end

  test "parses Telegram callback query payload" do
    event =
      Telegram.parse_inbound(%{
        "update_id" => 124,
        "callback_query" => %{
          "data" => Jason.encode!(%{p: "menu"}),
          "message" => %{"chat" => %{"id" => 42}}
        }
      })

    assert event.idempotency_key == "telegram:124"
    assert event.input["external_id"] == "42"
    assert event.input["payload"] == "menu"
  end
end
