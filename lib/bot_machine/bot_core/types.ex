defmodule BotMachine.BotCore.Types do
  @moduledoc """
  Shared bot flow/input/output types.

  Runtime storage uses JSON maps decoded by Jason, so keys are strings.
  Elixir typespecs cannot express exact string literal map keys like `"id"`,
  so these types document broad JSON shapes. See `docs/flow-definition.md` for
  the precise field contract.
  """

  @type json :: nil | boolean() | number() | String.t() | [json()] | %{String.t() => json()}
  @type json_object :: %{optional(String.t()) => json()}

  @typedoc "Top-level flow JSON: id, start_node_id, optional version, nodes."
  @type flow_definition :: json_object()

  @typedoc "One node in a flow. Supported node types: message, input, action, condition, end."
  @type flow_node :: message_node() | input_node() | action_node() | condition_node() | end_node()

  @typedoc "Common node fields: id, type, optional editor position."
  @type node_base :: json_object()

  @typedoc "Message node: text, keyboard_mode, button_rows/buttons, attachments, next."
  @type message_node :: json_object()

  @typedoc "Input node: prompt, input_key, next."
  @type input_node :: json_object()

  @typedoc "Action node: action name, params, next. Action must be registered in BotMachine.BotApp.registry()."
  @type action_node :: json_object()

  @typedoc "Condition node: ordered branches and default target."
  @type condition_node :: json_object()

  @typedoc "End node: completes the session."
  @type end_node :: json_object()

  @typedoc "Condition branch: when + target node id."
  @type condition_branch :: json_object()

  @typedoc "Condition expression. Supported ops: exists, equals."
  @type condition :: json_object()

  @typedoc "Button: visible label, hidden stable payload, optional target node id."
  @type bot_button :: json_object()

  @typedoc "Attachment. Currently only photo is supported. Prefer VK/media ref; url is preview or fallback."
  @type bot_attachment :: json_object()

  @typedoc "Normalized inbound bot input from any channel adapter."
  @type bot_input :: json_object()

  @typedoc "Bot output produced by BotCore and consumed by channel adapters."
  @type bot_output :: json_object()
end
