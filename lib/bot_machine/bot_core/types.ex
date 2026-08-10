defmodule BotMachine.BotCore.Types do
  @moduledoc "Shared bot flow/input/output types. Runtime storage uses JSON maps."

  @type json :: nil | boolean() | number() | String.t() | [json()] | %{String.t() => json()}
  @type json_object :: %{optional(String.t()) => term()}

  @type bot_attachment :: json_object()
  @type bot_button :: json_object()
  @type bot_input :: json_object()
  @type bot_output :: json_object()
  @type flow_definition :: json_object()
  @type flow_node :: json_object()
end
