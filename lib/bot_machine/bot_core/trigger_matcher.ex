defmodule BotMachine.BotCore.TriggerMatcher do
  def match(input, triggers) do
    triggers
    |> Enum.filter(&(&1["enabled"] && &1["channel"] == input["channel"]))
    |> Enum.filter(&matches?(input, &1))
    |> Enum.sort_by(&(&1["priority"] || 0), :desc)
    |> List.first()
  end

  defp matches?(%{"kind" => "user_message", "text" => text}, %{
         "type" => "command",
         "match" => %{"command" => command}
       }),
       do: normalize_command(text) == command

  defp matches?(%{"kind" => "user_message", "text" => text}, %{
         "type" => "text_exact",
         "match" => %{"text" => match}
       }),
       do: normalize(text) == normalize(match)

  defp matches?(%{"kind" => "user_message", "text" => text}, %{
         "type" => "text_contains",
         "match" => %{"text" => match}
       }),
       do: String.contains?(normalize(text), normalize(match))

  defp matches?(%{"kind" => "user_message"} = input, %{
         "type" => "payload",
         "match" => match
       }) do
    payload = input["payload"]
    text = input["text"]

    cond do
      payload && Map.has_key?(match, "payload") ->
        payload == match["payload"]

      payload && match["payloadPrefix"] ->
        String.starts_with?(to_string(payload), to_string(match["payloadPrefix"]))

      text && match["text"] ->
        normalize(text) == normalize(match["text"])

      true ->
        false
    end
  end

  defp matches?(%{"kind" => kind, "event" => event}, %{
         "type" => type,
         "match" => %{"event" => event}
       })
       when kind in ["domain_event", "schedule", "manual", "system_event"] and
              type in ["event", "schedule", "manual"],
       do: type == kind_to_type(kind)

  defp matches?(_, _), do: false

  defp kind_to_type("domain_event"), do: "event"
  defp kind_to_type("system_event"), do: "event"
  defp kind_to_type(kind), do: kind

  defp normalize(value), do: value |> to_string() |> String.trim() |> String.downcase()
  defp normalize_command(value), do: value |> normalize() |> String.trim_leading("/")
end
