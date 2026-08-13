defmodule BotMachineWeb.Admin.BotController do
  use BotMachineWeb, :controller

  alias BotMachine.BotRuntime

  plug :assign_current_path

  def dashboard(conn, _params),
    do: render(conn, :dashboard, counts: BotRuntime.counts())

  def users(conn, _params),
    do: render(conn, :users, users: BotRuntime.list_users())

  def chats(conn, params) do
    chats = BotRuntime.list_chats()
    selected_id = params["user_id"] || (List.first(chats) && to_string(List.first(chats).id))
    selected = selected_id && BotRuntime.get_user_detail(selected_id)

    render(conn, :chats, chats: chats, selected: selected, selected_id: selected_id)
  end

  def user_detail(conn, %{"user_id" => user_id}) do
    case BotRuntime.get_user_detail(user_id) do
      nil -> send_resp(conn, 404, "bot user not found")
      user -> render(conn, :user_detail, user: user)
    end
  end

  def send_user_message(conn, %{"user_id" => user_id, "text" => text} = params) do
    return_to = params["return_to"] || ~p"/admin/bot/users/#{user_id}"

    case BotRuntime.admin_send_message(user_id, text) do
      {:ok, _} ->
        BotRuntime.process_pending_outbox()
        redirect(conn, to: return_to)

      {:error, _} ->
        redirect(conn, to: return_to)
    end
  end

  def sessions(conn, params),
    do:
      render(conn, :sessions,
        sessions: BotRuntime.list_sessions(params),
        filters: params,
        connections: BotRuntime.list_channel_connections(),
        flows: BotRuntime.list_flows()
      )

  def inbox(conn, params),
    do:
      render(conn, :queue,
        title: "Inbox",
        rows: BotRuntime.list_inbox(params),
        filters: params,
        connections: BotRuntime.list_channel_connections(),
        path: ~p"/admin/bot/inbox"
      )

  def outbox(conn, params),
    do:
      render(conn, :queue,
        title: "Outbox",
        rows: BotRuntime.list_outbox(params),
        filters: params,
        connections: BotRuntime.list_channel_connections(),
        path: ~p"/admin/bot/outbox"
      )

  def events(conn, params),
    do:
      render(conn, :events,
        events: BotRuntime.list_events(params),
        filters: params,
        connections: BotRuntime.list_channel_connections(),
        flows: BotRuntime.list_flows()
      )

  def flows(conn, _params),
    do: render(conn, :flows, flows: BotRuntime.list_flows())

  def flow_viewer(conn, %{"version_id" => version_id}) do
    case BotRuntime.get_flow_version(version_id) do
      nil ->
        send_resp(conn, 404, "flow version not found")

      version ->
        render(conn, :flow_viewer,
          version: version,
          flow_json: Jason.encode!(BotRuntime.build_flow_viewer(version))
        )
    end
  end

  def flow_editor(conn, %{"version_id" => version_id}) do
    case BotRuntime.get_flow_version(version_id) do
      nil ->
        send_resp(conn, 404, "flow version not found")

      version ->
        render_flow_editor(conn, version)
    end
  end

  def save_flow_editor(conn, %{"version_id" => version_id, "definition" => definition_json}) do
    with version when not is_nil(version) <- BotRuntime.get_flow_version(version_id),
         {:ok, definition} <- Jason.decode(definition_json),
         {:ok, saved} <- BotRuntime.save_flow_definition(version, definition) do
      redirect(conn, to: ~p"/admin/bot/flows/#{saved.id}/edit")
    else
      nil ->
        send_resp(conn, 404, "flow version not found")

      {:error, %Jason.DecodeError{} = error} ->
        render_flow_editor(conn, BotRuntime.get_flow_version(version_id), [
          Exception.message(error)
        ])

      {:error, issues} when is_list(issues) ->
        render_flow_editor(
          conn,
          BotRuntime.get_flow_version(version_id),
          Enum.map(issues, & &1.message)
        )

      {:error, changeset} ->
        render_flow_editor(conn, BotRuntime.get_flow_version(version_id), [
          inspect(changeset.errors)
        ])
    end
  end

  def triggers(conn, _params),
    do: render(conn, :triggers, triggers: BotRuntime.list_triggers())

  def channels(conn, _params) do
    matrix = BotRuntime.flow_connection_matrix()

    render(conn, :channels,
      connections: matrix.connections,
      flows: matrix.flows,
      enabled_flows: matrix.enabled,
      credential: &BotMachine.BotRuntime.Credentials.for_connection/1,
      callback_url: &BotMachine.BotRuntime.Channels.VKProvisioning.callback_url/1,
      telegram_callback_url: &BotMachine.BotRuntime.Channels.Telegram.callback_url/1
    )
  end

  def delete_channel(conn, %{"connection_id" => id}) do
    BotRuntime.delete_channel_connection!(id)
    redirect(conn, to: ~p"/admin/bot/channels")
  end

  def create_vk(conn, %{"vk" => attrs}) do
    case BotRuntime.create_vk_connection(attrs) do
      {:ok, _} -> redirect(conn, to: ~p"/admin/bot/channels")
      {:error, _} -> send_resp(conn, 422, "failed to create VK connection")
    end
  end

  def save_vk(conn, %{"connection_id" => id, "vk" => attrs}) do
    case BotRuntime.update_vk_connection(id, attrs) do
      {:ok, _} -> redirect(conn, to: ~p"/admin/bot/channels")
      {:error, _} -> send_resp(conn, 422, "failed to save credentials")
    end
  end

  def create_telegram(conn, %{"telegram" => attrs}) do
    case BotRuntime.create_telegram_connection(attrs) do
      {:ok, _} ->
        redirect(conn, to: ~p"/admin/bot/channels")

      {:error, error} ->
        send_resp(conn, 422, "failed to create Telegram connection: #{inspect(error)}")
    end
  end

  def save_telegram(conn, %{"connection_id" => id, "telegram" => attrs}) do
    case BotRuntime.update_telegram_connection(id, attrs) do
      {:ok, _} ->
        redirect(conn, to: ~p"/admin/bot/channels")

      {:error, error} ->
        send_resp(conn, 422, "failed to save Telegram credentials: #{inspect(error)}")
    end
  end

  def provision_telegram(conn, %{"connection_id" => id}) do
    case id
         |> BotRuntime.get_channel_connection!()
         |> BotRuntime.provision_telegram_connection() do
      {:ok, _} ->
        redirect(conn, to: ~p"/admin/bot/channels")

      {:error, error} ->
        send_resp(conn, 422, "failed to provision Telegram webhook: #{inspect(error)}")
    end
  end

  def provision_vk(conn, %{"connection_id" => id}) do
    connection = BotRuntime.get_channel_connection!(id)

    case BotMachine.BotRuntime.Channels.VKProvisioning.provision(connection) do
      {:ok, _} ->
        BotRuntime.refresh_vk_connection_info(connection)
        redirect(conn, to: ~p"/admin/bot/channels")

      {:error, error} ->
        send_resp(conn, 422, error)
    end
  end

  def refresh_vk(conn, %{"connection_id" => id}) do
    BotRuntime.refresh_vk_connection_info(id)
    redirect(conn, to: ~p"/admin/bot/channels")
  end

  def save_connection_flows(conn, %{"connection_id" => id} = params) do
    BotRuntime.set_connection_flows(id, Map.get(params, "flow_ids", []))
    redirect(conn, to: ~p"/admin/bot/channels")
  end

  def sandbox(conn, _params),
    do: render(conn, :sandbox, state: BotRuntime.sandbox_state())

  def sandbox_send(conn, params) do
    text = String.trim(params["text"] || params["button_label"] || "")
    payload = params["payload"]

    if text != "" || payload not in [nil, ""] do
      BotRuntime.enqueue_inbox(
        %{
          "kind" => "user_message",
          "channel" => "echo",
          "external_id" => "sandbox",
          "text" => text,
          "payload" => if(payload in [nil, ""], do: nil, else: payload)
        },
        "sandbox:#{System.unique_integer([:positive])}"
      )

      BotRuntime.process_pending_inbox()
      BotRuntime.process_pending_outbox()
    end

    redirect(conn, to: ~p"/admin/bot/sandbox")
  end

  def sandbox_reset(conn, _params) do
    BotRuntime.reset_sandbox()
    redirect(conn, to: ~p"/admin/bot/sandbox")
  end

  defp render_flow_editor(conn, version, errors \\ []) do
    render(conn, :flow_editor,
      version: version,
      editor_json:
        Jason.encode!(%{
          definition: version.definition,
          actions: BotMachine.BotApp.registry() |> BotMachine.BotCore.Registry.actions()
        }),
      errors: errors
    )
  end

  defp assign_current_path(conn, _opts), do: assign(conn, :current_path, conn.request_path)
end
