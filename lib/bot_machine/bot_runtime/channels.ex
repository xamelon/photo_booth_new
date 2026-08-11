defmodule BotMachine.BotRuntime.Channels do
  require Logger

  def send(%{channel: "echo"}, payload) do
    Logger.info("echo delivery: #{payload["text"]}")
    {:ok, "echo:" <> Integer.to_string(System.unique_integer([:positive]))}
  end

  def send(%{channel: "vk"} = connection, payload),
    do: BotMachine.BotRuntime.Channels.VK.send(connection, payload)

  def send(%{channel: channel}, _payload), do: {:error, "unknown channel #{channel}"}
end
