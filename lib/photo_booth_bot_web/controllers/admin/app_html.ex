defmodule BotMachineWeb.Admin.AppHTML do
  use BotMachineWeb, :html

  alias BotMachineWeb.Admin.BotHTML

  embed_templates "app_html/*"
end
