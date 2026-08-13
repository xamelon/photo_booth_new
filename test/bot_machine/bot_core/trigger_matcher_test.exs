defmodule BotMachine.BotCore.TriggerMatcherTest do
  use ExUnit.Case, async: true

  alias BotMachine.BotCore.TriggerMatcher

  test "matches payload triggers" do
    trigger = %{
      "id" => "menu-balance",
      "enabled" => true,
      "channel" => "echo",
      "type" => "payload",
      "match" => %{"payload" => "balance"},
      "priority" => 0
    }

    assert TriggerMatcher.match(
             %{"kind" => "user_message", "channel" => "echo", "payload" => "balance"},
             [trigger]
           ) == trigger
  end

  test "matches payload triggers by reply keyboard text" do
    trigger = %{
      "id" => "menu-balance",
      "enabled" => true,
      "channel" => "telegram",
      "type" => "payload",
      "match" => %{"payload" => "balance", "text" => "💰 Баланс"},
      "priority" => 0
    }

    assert TriggerMatcher.match(
             %{"kind" => "user_message", "channel" => "telegram", "text" => "💰 Баланс"},
             [trigger]
           ) == trigger
  end

  test "matches global triggers" do
    trigger = %{
      "id" => "global-start",
      "enabled" => true,
      "channel" => "*",
      "type" => "command",
      "match" => %{"command" => "start"},
      "priority" => 0
    }

    assert TriggerMatcher.match(
             %{"kind" => "user_message", "channel" => "telegram", "text" => "/start"},
             [trigger]
           ) == trigger
  end

  test "prefers channel-specific trigger over global trigger at same priority" do
    global = %{
      "id" => "global-start",
      "enabled" => true,
      "channel" => "*",
      "type" => "command",
      "match" => %{"command" => "start"},
      "priority" => 10
    }

    specific = %{global | "id" => "telegram-start", "channel" => "telegram"}

    assert TriggerMatcher.match(
             %{"kind" => "user_message", "channel" => "telegram", "text" => "/start"},
             [global, specific]
           ) == specific
  end

  test "matches domain event triggers" do
    trigger = %{
      "id" => "generation-completed",
      "enabled" => true,
      "channel" => "echo",
      "type" => "event",
      "match" => %{"event" => "photo_generation.completed"},
      "priority" => 0
    }

    assert TriggerMatcher.match(
             %{
               "kind" => "domain_event",
               "channel" => "echo",
               "event" => "photo_generation.completed"
             },
             [trigger]
           ) == trigger
  end
end
