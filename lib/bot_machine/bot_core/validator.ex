defmodule BotMachine.BotCore.Validator do
  def validate(flow, registry) do
    nodes = flow["nodes"] || []
    ids = MapSet.new(Enum.map(nodes, & &1["id"]))

    []
    |> require_field(flow, "id", "flow id is required")
    |> require_field(flow, "start_node_id", "start node is required")
    |> add_missing_start(flow, ids)
    |> add_node_issues(nodes, ids, registry)
    |> Enum.reverse()
  end

  defp require_field(issues, map, key, message),
    do: if(map[key] in [nil, ""], do: [%{path: key, message: message} | issues], else: issues)

  defp add_missing_start(issues, flow, ids),
    do:
      if(flow["start_node_id"] && !MapSet.member?(ids, flow["start_node_id"]),
        do: [%{path: "start_node_id", message: "missing start node"} | issues],
        else: issues
      )

  defp add_node_issues(issues, nodes, ids, registry) do
    Enum.reduce(nodes, issues, fn node, acc ->
      acc
      |> validate_action(node, registry)
      |> validate_attachments(node)
      |> validate_targets(node, ids)
    end)
  end

  defp validate_action(issues, %{"type" => "action", "action" => action}, registry) do
    if BotMachine.BotCore.Registry.get_action(registry, action),
      do: issues,
      else: [%{path: "nodes.#{action}", message: "unknown action #{action}"} | issues]
  end

  defp validate_action(issues, _node, _registry), do: issues

  defp validate_attachments(issues, %{
         "type" => "message",
         "attachments" => attachments,
         "id" => id
       })
       when is_list(attachments) do
    Enum.with_index(attachments)
    |> Enum.reduce(issues, fn {attachment, index}, acc ->
      cond do
        attachment["type"] != "photo" ->
          [
            %{
              path: "nodes.#{id}.attachments.#{index}.type",
              message: "only photo attachments are supported"
            }
            | acc
          ]

        attachment["ref"] in [nil, ""] and attachment["url"] in [nil, ""] ->
          [
            %{
              path: "nodes.#{id}.attachments.#{index}",
              message: "photo attachment requires ref or url"
            }
            | acc
          ]

        true ->
          acc
      end
    end)
  end

  defp validate_attachments(issues, _node), do: issues

  defp validate_targets(issues, node, ids) do
    targets =
      [node["next"], node["default"]] ++
        Enum.map(node["buttons"] || [], & &1["to"]) ++
        Enum.map(node["branches"] || [], & &1["to"])

    Enum.reduce(Enum.reject(targets, &is_nil/1), issues, fn target, acc ->
      if MapSet.member?(ids, target),
        do: acc,
        else: [%{path: "nodes.#{node["id"]}", message: "missing target #{target}"} | acc]
    end)
  end
end
