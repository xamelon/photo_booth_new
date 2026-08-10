defmodule BotMachine.BotRuntime.Channels.VKTypes do
  @moduledoc """
  Small typed subset of VK callback/API shapes used by this template.

  Source of truth for the full API: https://github.com/VKCOM/vk-api-schema
  """

  @type callback_body :: %{optional(String.t()) => term()}
  @type callback_object :: %{optional(String.t()) => term()}
  @type message :: %{optional(String.t()) => term()}
  @type attachment :: photo_attachment() | %{optional(String.t()) => term()}
  @type photo_attachment :: %{optional(String.t()) => term()}
  @type photo :: %{optional(String.t()) => term()}
  @type photo_size :: %{optional(String.t()) => term()}

  @type inbound_event :: %{
          required(:idempotency_key) => String.t(),
          required(:input) => BotMachine.BotCore.Types.bot_input(),
          required(:raw) => callback_body()
        }

  @type api_response(_response) :: %{optional(String.t()) => term()}
  @type api_error :: %{optional(String.t()) => term()}
  @type callback_server :: %{optional(String.t()) => term()}
end
