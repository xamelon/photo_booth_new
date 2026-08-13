defmodule BotMachine.BotCore.Runner do
  alias BotMachine.BotCore.Registry

  @max_steps 50

  def run(flow, input, registry, session \\ nil, trigger \\ nil) do
    receiving? = !!session && is_nil(trigger)
    preserve_node_id = if notify_only?(trigger) && session, do: session.current_node_id
    preserve_completed = if notify_only?(trigger) && session, do: session.completed
    session = prepare_session(flow, input, session, trigger)
    events = [event("input_received", flow, session)]
    outputs = []
    start_node_id = get_in(trigger || %{}, ["start_node_id"]) || session.current_node_id
    current_node = node!(flow, start_node_id)

    handler = Registry.get_node(registry, current_node["type"])

    result =
      if receiving? && handler && handler.receive do
        result = handler.receive.(ctx(flow, input, registry, session), current_node)
        session = apply_result(session, result, current_node)

        if Map.get(result, :next_node_id) do
          walk(
            flow,
            input,
            registry,
            session,
            node!(flow, Map.get(result, :next_node_id)),
            outputs ++ Map.get(result, :outputs, []),
            events,
            0
          )
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

    preserve_session(result, preserve_node_id, preserve_completed)
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

  defp prepare_session(flow, _input, session, %{
         "start_node_id" => start_node_id,
         "session_mode" => mode
       })
       when mode != "notify_only",
       do: %{session | current_node_id: start_node_id, flow_version: flow["version"]}

  defp prepare_session(flow, _input, session, _trigger),
    do: %{session | flow_version: flow["version"]}

  defp ctx(flow, input, registry, session),
    do: %{flow: flow, input: input, registry: registry, session: session}

  defp apply_result(session, result, node) do
    %{
      session
      | context: Map.get(result, :context, session.context),
        current_node_id: Map.get(result, :next_node_id) || node["id"]
    }
  end

  defp preserve_session(result, nil, _completed), do: result

  defp preserve_session(result, node_id, completed) do
    %{result | session: %{result.session | current_node_id: node_id, completed: completed}}
  end

  defp notify_only?(%{"session_mode" => "notify_only"}), do: true
  defp notify_only?(_), do: false

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
