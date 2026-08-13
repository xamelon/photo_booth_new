defmodule BotMachineWeb.Admin.AppHTML do
  use BotMachineWeb, :html

  alias BotMachineWeb.Admin.BotHTML

  embed_templates "app_html/*"

  def signed(value) when is_integer(value) and value > 0, do: "+#{value}"
  def signed(value), do: to_string(value || 0)
end
