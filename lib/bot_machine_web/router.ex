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

  scope "/", BotMachineWeb do
    pipe_through :browser

    get "/", PageController, :home
    get "/login", SessionController, :new
    post "/login", SessionController, :create
    delete "/logout", SessionController, :delete
    post "/logout", SessionController, :delete
  end

  scope "/admin", BotMachineWeb.Admin do
    pipe_through [:browser, :admin]

    get "/bot", BotController, :dashboard
    get "/bot/users", BotController, :users
    get "/bot/users/:user_id", BotController, :user_detail
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
    post "/bot/channels/vk", BotController, :save_vk
    post "/bot/channels/vk/provision", BotController, :provision_vk
    get "/bot/sandbox", BotController, :sandbox
    post "/bot/sandbox/send", BotController, :sandbox_send
    post "/bot/sandbox/reset", BotController, :sandbox_reset
  end

  scope "/webhooks", BotMachineWeb do
    pipe_through :api

    post "/echo", WebhookController, :echo
    post "/vk", VKWebhookController, :callback
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
