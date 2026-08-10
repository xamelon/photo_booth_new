defmodule BotMachine.BotCore.Runner do
  alias BotMachine.BotCore.Registry

  @max_steps 50

  def run(flow, input, registry, session \\ nil, trigger \\ nil) do
    receiving? = !!session && is_nil(trigger)
    session = prepare_session(flow, input, session, trigger)
    events = [event("input_received", flow, session)]
    outputs = []
    start_node_id = get_in(trigger || %{}, ["start_node_id"]) || session.current_node_id
    current_node = node!(flow, start_node_id)

    handler = Registry.get_node(registry, current_node["type"])

    if receiving? && handler && handler.receive do
      result = handler.receive.(ctx(flow, input, registry, session), current_node)
      session = apply_result(session, result, current_node)

      if result.next_node_id do
        walk(flow, input, registry, session, node!(flow, result.next_node_id), outputs, events, 0)
      else
        %{
          session: %{session | current_node_id: current_node["id"]},
          outputs: Map.get(result, :outputs, []),
          events: Enum.reverse(events)
        }
      end
    else
      walk(flow, input, registry, session, current_node, outputs, events, 0)
    end
  end

  defp walk(_flow, _input, _registry, _session, _node, _outputs, _events, steps)
       when steps >= @max_steps,
       do: raise("bot flow exceeded max steps")

  defp walk(flow, input, registry, session, node, outputs, events, steps) do
    events = [event("node_entered", flow, session, node) | events]
    result = enter_node(flow, input, registry, session, node)
    session = apply_result(session, result, node)
    outputs = outputs ++ Map.get(result, :outputs, [])
    events = [event("node_completed", flow, session, node) | events]

    cond do
      Map.get(result, :completed) ->
        %{
          session: %{session | completed: true},
          outputs: outputs,
          events: Enum.reverse([event("flow_completed", flow, session, node) | events])
        }

      next = Map.get(result, :next_node_id) ->
        walk(flow, input, registry, session, node!(flow, next), outputs, events, steps + 1)

      true ->
        %{
          session: %{session | current_node_id: node["id"]},
          outputs: outputs,
          events: Enum.reverse(events)
        }
    end
  end

  defp enter_node(flow, input, registry, session, node) do
    case Registry.get_node(registry, node["type"]) do
      nil -> raise("unknown node type: #{node["type"]}")
      handler -> handler.enter.(ctx(flow, input, registry, session), node)
    end
  end

  defp prepare_session(flow, input, nil, trigger) do
    %{
      channel: input["channel"],
      external_id: input["external_id"],
      flow_id: flow["id"],
      flow_version: flow["version"],
      current_node_id: get_in(trigger || %{}, ["start_node_id"]) || flow["start_node_id"],
      context: %{},
      completed: false
    }
  end

  defp prepare_session(flow, input, _session, %{"session_mode" => "restart"} = trigger),
    do: prepare_session(flow, input, nil, trigger)

  defp prepare_session(_flow, _input, session, %{
         "start_node_id" => start_node_id,
         "session_mode" => mode
       })
       when mode != "notify_only",
       do: %{session | current_node_id: start_node_id}

  defp prepare_session(_flow, _input, session, _trigger), do: session

  defp ctx(flow, input, registry, session),
    do: %{flow: flow, input: input, registry: registry, session: session}

  defp apply_result(session, result, node) do
    %{
      session
      | context: Map.get(result, :context, session.context),
        current_node_id: Map.get(result, :next_node_id) || node["id"]
    }
  end

  defp node!(flow, id) do
    Enum.find(flow["nodes"] || [], &(&1["id"] == id)) || raise("missing bot flow node: #{id}")
  end

  defp event(type, flow, session, node \\ nil) do
    %{
      "event_type" => type,
      "flow_id" => flow["id"],
      "node_id" => node && node["id"],
      "session_id" => Map.get(session, :id)
    }
  end
end
