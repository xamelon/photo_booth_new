defmodule BotMachineWeb.Admin.BotHTML do
  use BotMachineWeb, :html

  embed_templates "bot_html/*"

  attr :current_admin, :map, default: nil
  attr :current_path, :string, default: nil
  attr :wide, :boolean, default: false
  slot :inner_block, required: true

  def admin_shell(assigns) do
    ~H"""
    <div class="admin-shell">
      <aside class="admin-sidebar">
        <strong class="admin-brand">Bot Machine</strong>
        <nav>
          <div class="admin-nav-group-label">Project</div>
          <.admin_link href={~p"/admin/app"} icon="hero-briefcase-mini" current_path={@current_path}>App</.admin_link>

          <div class="admin-nav-group-label">Bot</div>
          <.admin_link href={~p"/admin/bot"} icon="hero-squares-2x2-mini" current_path={@current_path}>Dashboard</.admin_link>
          <.admin_link href={~p"/admin/bot/flows"} icon="hero-share-mini" current_path={@current_path}>Flows</.admin_link>
          <.admin_link href={~p"/admin/bot/users"} icon="hero-users-mini" current_path={@current_path}>Users</.admin_link>
          <.admin_link
            href={~p"/admin/bot/chats"}
            icon="hero-chat-bubble-left-right-mini"
            current_path={@current_path}
          >Chats</.admin_link>

          <div class="admin-nav-group-label">Activity</div>
          <.admin_link
            href={~p"/admin/bot/sessions"}
            icon="hero-circle-stack-mini"
            current_path={@current_path}
          >Sessions</.admin_link>
          <.admin_link
            href={~p"/admin/bot/inbox"}
            icon="hero-inbox-arrow-down-mini"
            current_path={@current_path}
          >Inbox</.admin_link>
          <.admin_link
            href={~p"/admin/bot/outbox"}
            icon="hero-paper-airplane-mini"
            current_path={@current_path}
          >Outbox</.admin_link>
          <.admin_link
            href={~p"/admin/bot/events"}
            icon="hero-clock-mini"
            current_path={@current_path}
          >Events</.admin_link>

          <div class="admin-nav-group-label">Setup</div>
          <.admin_link
            href={~p"/admin/bot/triggers"}
            icon="hero-bolt-mini"
            current_path={@current_path}
          >Triggers</.admin_link>
          <.admin_link
            href={~p"/admin/bot/channels"}
            icon="hero-link-mini"
            current_path={@current_path}
          >Channels</.admin_link>

          <div class="admin-nav-group-label">Test</div>
          <.admin_link
            href={~p"/admin/bot/sandbox"}
            icon="hero-chat-bubble-left-right-mini"
            current_path={@current_path}
          >Sandbox</.admin_link>
        </nav>
        <div class="admin-sidebar-footer">
          <span>{@current_admin && @current_admin.email}</span>
          <form method="post" action={~p"/logout"}>
            <input type="hidden" name="_csrf_token" value={get_csrf_token()} />
            <button class="link-button">Logout</button>
          </form>
        </div>
      </aside>
      <main class={["admin-main", @wide && "admin-main-wide"]}>
        {render_slot(@inner_block)}
      </main>
    </div>
    """
  end

  attr :href, :string, required: true
  attr :icon, :string, required: true
  attr :current_path, :string, default: nil
  slot :inner_block, required: true

  def admin_link(assigns) do
    ~H"""
    <a href={@href} class={active_link_class(@href, @current_path)}><.icon
      name={@icon}
      class="admin-nav-icon"
    />{render_slot(@inner_block)}</a>
    """
  end

  defp active_link_class("/admin/bot", "/admin/bot"), do: "is-active"
  defp active_link_class("/admin/bot", _path), do: nil

  defp active_link_class("/admin/bot/flows", path) when is_binary(path),
    do: if(String.starts_with?(path, "/admin/bot/flows"), do: "is-active")

  defp active_link_class(href, path) when is_binary(path),
    do: if(String.starts_with?(path, href), do: "is-active")

  defp active_link_class(_, _), do: nil

  attr :label, :string, required: true
  attr :value, :any, required: true

  def stat(assigns) do
    ~H"""
    <div class="stat">
      <span>{@label}</span>
      <strong>{@value}</strong>
    </div>
    """
  end

  attr :status, :string, required: true

  def badge(assigns) do
    ~H"""
    <span class={["badge", @status]}>{@status}</span>
    """
  end

  def json(value), do: Jason.encode!(value || %{})
  def pretty_json(value), do: Jason.encode!(value || %{}, pretty: true)

  def connection_label(%{bot_channel_connection: %{name: name}}) when is_binary(name), do: name
  def connection_label(%{channel: channel}), do: channel || "—"
  def connection_label(_), do: "—"

  def payload_summary(nil), do: "—"

  def payload_summary(payload) do
    text = payload["text"] || payload[:text]
    buttons = length(payload["buttons"] || payload[:buttons] || [])
    rows = length(payload["button_rows"] || payload[:button_rows] || [])
    attachments = length(payload["attachments"] || payload[:attachments] || [])

    [
      if(text, do: text |> to_string() |> String.replace(~r/\s+/, " ") |> String.slice(0, 80)),
      if(buttons > 0, do: "#{buttons} buttons"),
      if(rows > 0, do: "#{rows} rows"),
      if(attachments > 0, do: "#{attachments} attachments")
    ]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> case do
      [] -> payload["kind"] || payload["type"] || "payload"
      parts -> Enum.join(parts, " · ")
    end
  end

  def event_types(events),
    do:
      events |> Enum.map(& &1.event_type) |> Enum.reject(&is_nil/1) |> Enum.uniq() |> Enum.sort()

  def event_groups(events) do
    events
    |> Enum.chunk_by(& &1.bot_session_id)
    |> Enum.map(fn events -> %{id: List.first(events).bot_session_id, events: events} end)
  end

  def format_time(nil), do: "—"
  def format_time(%DateTime{} = value), do: Calendar.strftime(value, "%Y-%m-%d %H:%M")
  def format_time(value), do: to_string(value)
end
