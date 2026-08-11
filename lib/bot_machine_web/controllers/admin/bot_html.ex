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
  def format_time(nil), do: "—"
  def format_time(%DateTime{} = value), do: Calendar.strftime(value, "%Y-%m-%d %H:%M")
  def format_time(value), do: to_string(value)
end
