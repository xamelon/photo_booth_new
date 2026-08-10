defmodule BotMachine.BotCore.Registry do
  @moduledoc """
  Tiny node/action registry. Use this in each bot/usecase module.
  """

  defstruct actions: %{}, node_handlers: %{}, interceptors: []

  def new do
    %__MODULE__{}
    |> node(
      "message",
      &BotMachine.BotCore.StandardNodes.message_enter/2,
      &BotMachine.BotCore.StandardNodes.message_receive/2
    )
    |> node("action", &BotMachine.BotCore.StandardNodes.action_enter/2)
    |> node(
      "input",
      &BotMachine.BotCore.StandardNodes.input_enter/2,
      &BotMachine.BotCore.StandardNodes.input_receive/2
    )
    |> node("condition", &BotMachine.BotCore.StandardNodes.condition_enter/2)
    |> node("end", &BotMachine.BotCore.StandardNodes.end_enter/2)
  end

  def node(%__MODULE__{} = registry, type, enter, receive \\ nil)
      when is_binary(type) and is_function(enter, 2) do
    put_in(registry.node_handlers[type], %{enter: enter, receive: receive})
  end

  def action(%__MODULE__{} = registry, name, fun) when is_binary(name) and is_function(fun, 2) do
    put_in(registry.actions[name], fun)
  end

  def get_action(%__MODULE__{actions: actions}, name), do: Map.get(actions, name)
  def actions(%__MODULE__{actions: actions}), do: Map.keys(actions) |> Enum.sort()
  def get_node(%__MODULE__{node_handlers: handlers}, type), do: Map.get(handlers, type)
end
