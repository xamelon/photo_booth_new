defmodule BotMachine.BotCore.Renderer do
  def render(template, context) when is_binary(template) do
    Regex.replace(~r/\{\{\s*([\w.]+)\s*\}\}/, template, fn _, path ->
      context
      |> get_path(path)
      |> case do
        nil -> ""
        value -> to_string(value)
      end
    end)
  end

  def get_path(source, path) when is_map(source) and is_binary(path) do
    Enum.reduce(String.split(path, "."), source, fn key, value ->
      cond do
        is_map(value) -> Map.get(value, key) || Map.get(value, String.to_atom(key))
        true -> nil
      end
    end)
  end
end
