defmodule BotMachine.BotRuntime.Channels do
  require Logger

  def send("echo", payload) do
    Logger.info("echo delivery: #{payload["text"]}")
    {:ok, "echo:" <> Integer.to_string(System.unique_integer([:positive]))}
  end

  def send("vk", payload), do: BotMachine.BotRuntime.Channels.VK.send(payload)

  def send(channel, _payload), do: {:error, "unknown channel #{channel}"}
end
