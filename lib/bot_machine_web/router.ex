defmodule BotMachineWeb.Router do
  use BotMachineWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {BotMachineWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug BotMachineWeb.AdminAuth, :fetch_current_admin
  end

  pipeline :admin do
    plug BotMachineWeb.AdminAuth, :require_admin
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :admin_api do
    plug :accepts, ["json", "multipart"]
    plug :fetch_session
    plug :put_secure_browser_headers
    plug BotMachineWeb.AdminAuth, :fetch_current_admin
    plug BotMachineWeb.AdminAuth, :require_admin_json
  end

  scope "/", BotMachineWeb do
    pipe_through :browser

    get "/", PageController, :home
    get "/uploads/bot/:filename", UploadController, :bot
    get "/login", SessionController, :new
    post "/login", SessionController, :create
    delete "/logout", SessionController, :delete
    post "/logout", SessionController, :delete
  end

  scope "/admin", BotMachineWeb.Admin do
    pipe_through [:browser, :admin]

    get "/app", AppController, :dashboard
    get "/bot", BotController, :dashboard
    get "/bot/users", BotController, :users
    get "/bot/chats", BotController, :chats
    get "/bot/users/:user_id", BotController, :user_detail
    post "/bot/users/:user_id/send", BotController, :send_user_message
    get "/bot/sessions", BotController, :sessions
    get "/bot/inbox", BotController, :inbox
    get "/bot/outbox", BotController, :outbox
    get "/bot/events", BotController, :events
    get "/bot/flows", BotController, :flows
    get "/bot/flows/:version_id/view", BotController, :flow_viewer
    get "/bot/flows/:version_id/edit", BotController, :flow_editor
    post "/bot/flows/:version_id/edit", BotController, :save_flow_editor
    get "/bot/triggers", BotController, :triggers
    get "/bot/channels", BotController, :channels
    post "/bot/channels/vk", BotController, :create_vk
    post "/bot/channels/vk/:connection_id", BotController, :save_vk
    post "/bot/channels/vk/:connection_id/provision", BotController, :provision_vk
    post "/bot/channels/vk/:connection_id/refresh", BotController, :refresh_vk
    post "/bot/channels/:connection_id/flows", BotController, :save_connection_flows
    get "/bot/sandbox", BotController, :sandbox
    post "/bot/sandbox/send", BotController, :sandbox_send
    post "/bot/sandbox/reset", BotController, :sandbox_reset
  end

  scope "/admin/api/agent", BotMachineWeb.Admin do
    pipe_through :admin_api

    get "/overview", AgentController, :overview
    get "/flows/:version_id", AgentController, :flow
    post "/flows/:version_id/validate", AgentController, :validate_flow
    post "/flows/:version_id/save", AgentController, :save_flow
    post "/media/vk-photo", AgentController, :upload_vk_photo
  end

  scope "/webhooks", BotMachineWeb do
    pipe_through :api

    post "/echo", WebhookController, :echo
    post "/vk", VKWebhookController, :callback
    post "/vk/:connection_public_id", VKWebhookController, :callback
    post "/telegram", TelegramWebhookController, :callback
    post "/telegram/:connection_public_id", TelegramWebhookController, :callback
  end

  # Enable LiveDashboard in development
  if Application.compile_env(:bot_machine, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: BotMachineWeb.Telemetry
    end
  end
end
