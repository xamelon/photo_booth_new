defmodule BotMachine.BotApp do
  def module, do: Application.get_env(:bot_machine, :bot_app, PhotoBoothBot)
  def registry, do: module().registry()
  def flow, do: module().flow()
end
