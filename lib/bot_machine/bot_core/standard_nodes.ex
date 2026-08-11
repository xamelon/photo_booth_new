defmodule BotMachine.BotCore.StandardNodes do
  alias BotMachine.BotCore.{Registry, Renderer}

  def message_enter(%{input: input, session: session}, node) do
    button_rows = button_rows(node)

    buttons =
      button_rows
      |> List.flatten()
      |> Enum.map(
        &%{"label" => &1["label"], "payload" => &1["payload"] || &1["label"], "to" => &1["to"]}
      )

    %{
      outputs: [
        %{
          "type" => "message",
          "channel" => input["channel"],
          "external_id" => input["external_id"],
          "text" => Renderer.render(node["text"] || "", session.context),
          "buttons" => buttons,
          "button_rows" => button_rows,
          "attachments" => attachments(node, session.context),
          "keyboard_mode" => keyboard_mode(node),
          "buttons_per_row" => Map.get(node, "buttons_per_row", 3)
        }
      ],
      next_node_id: node["next"]
    }
  end

  def message_receive(%{input: input}, node) do
    value = input["payload"] || input["text"]

    matched =
      Enum.find(button_rows(node) |> List.flatten(), fn button ->
        value in [button["payload"], button["label"], button["to"]]
      end)

    if matched && matched["to"] do
      %{next_node_id: matched["to"]}
    else
      %{outputs: [], next_node_id: nil}
    end
  end

  def action_enter(%{registry: registry, session: session}, node) do
    case Registry.get_action(registry, node["action"]) do
      nil ->
        raise("unknown bot action: #{node["action"]}")

      fun ->
        fun.(%{session: session}, node["params"] || %{})
        |> Map.put_new(:next_node_id, node["next"])
    end
  end

  def input_enter(%{input: input, session: session}, node) do
    outputs =
      if node["prompt"] do
        [
          %{
            "type" => "message",
            "channel" => input["channel"],
            "external_id" => input["external_id"],
            "text" => Renderer.render(node["prompt"], session.context),
            "buttons" => [],
            "keyboard_mode" => "inline",
            "buttons_per_row" => 3
          }
        ]
      else
        []
      end

    %{outputs: outputs}
  end

  def input_receive(%{input: input, session: session}, node) do
    value = input["payload"] || input["text"]
    %{context: Map.put(session.context, node["input_key"], value), next_node_id: node["next"]}
  end

  def condition_enter(%{session: session}, node) do
    branch = Enum.find(node["branches"] || [], &branch_matches?(&1, session.context))
    %{next_node_id: get_in(branch || %{}, ["to"]) || node["default"]}
  end

  def end_enter(_ctx, _node), do: %{completed: true}

  defp attachments(node, context) do
    node
    |> Map.get("attachments", [])
    |> Enum.filter(&(&1["type"] == "photo"))
    |> Enum.map(fn attachment ->
      %{
        "type" => "photo",
        "ref" => render_optional(attachment["ref"], context),
        "url" => render_optional(attachment["url"], context)
      }
      |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
      |> Map.new()
    end)
  end

  defp render_optional(nil, _context), do: nil
  defp render_optional(value, context), do: Renderer.render(to_string(value), context)

  defp button_rows(%{"button_rows" => rows}) when is_list(rows), do: rows
  defp button_rows(%{"buttons" => buttons}) when is_list(buttons), do: [buttons]
  defp button_rows(_node), do: []

  defp keyboard_mode(%{"keyboard_mode" => mode}) when mode in ["inline", "reply"], do: mode
  defp keyboard_mode(_node), do: "inline"

  defp branch_matches?(%{"when" => %{"op" => "exists", "path" => path}}, context),
    do: Renderer.get_path(context, path) not in [nil, ""]

  defp branch_matches?(
         %{"when" => %{"op" => "equals", "path" => path, "value" => value}},
         context
       ),
       do: Renderer.get_path(context, path) == value

  defp branch_matches?(_, _), do: false
end
