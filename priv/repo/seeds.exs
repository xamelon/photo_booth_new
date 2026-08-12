import Ecto.Query

alias BotMachine.BotRuntime.{
  BotChannelConnection,
  BotFlow,
  BotFlowConnection,
  BotFlowVersion,
  BotTrigger
}

alias BotMachine.Repo

email = System.get_env("ADMIN_EMAIL") || "admin@example.com"
password = System.get_env("ADMIN_PASSWORD") || "admin12345"

case BotMachine.Accounts.get_admin_user_by_email(email) do
  nil ->
    {:ok, _} =
      BotMachine.Accounts.create_admin(%{email: email, password: password, role: "super_admin"})

    IO.puts("Created admin #{email} / #{password}")

  _ ->
    IO.puts("Admin #{email} already exists")
end

flow =
  Repo.get_by(BotFlow, slug: "photo_booth") ||
    Repo.insert!(%BotFlow{slug: "photo_booth", name: "PhotoBooth flow", status: "published"})

Repo.delete_all(from t in BotTrigger, where: t.name in ["Start", "Start echo", "Start VK"])

app_flow = BotMachine.BotApp.flow()

unless Repo.get_by(BotFlowVersion, bot_flow_id: flow.id, version: app_flow["version"]) do
  Repo.insert!(%BotFlowVersion{
    bot_flow_id: flow.id,
    version: app_flow["version"],
    status: "published",
    definition: app_flow,
    published_at: DateTime.utc_now() |> DateTime.truncate(:second)
  })
end

for {name, channel} <- [{"Start echo", "echo"}, {"Start VK", "vk"}] do
  connection =
    Repo.get_by(BotChannelConnection, channel: channel) ||
      Repo.insert!(%BotChannelConnection{
        channel: channel,
        name: "#{String.upcase(channel)} default",
        external_id: if(channel == "echo", do: "sandbox"),
        public_id: "conn_#{channel}",
        status: "active",
        credentials: %{},
        config: %{}
      })

  Repo.get_by(BotFlowConnection,
    bot_flow_id: flow.id,
    bot_channel_connection_id: connection.id
  ) ||
    Repo.insert!(%BotFlowConnection{
      bot_flow_id: flow.id,
      bot_channel_connection_id: connection.id,
      enabled: true,
      priority: 0,
      config: %{}
    })

  attrs = %{
    bot_flow_id: flow.id,
    name: name,
    channel: channel,
    type: "command",
    match: %{"command" => "start"},
    start_node_id: "welcome",
    session_mode: "restart",
    priority: 100,
    enabled: true
  }

  case Repo.get_by(BotTrigger, bot_flow_id: flow.id, name: name) do
    nil -> %BotTrigger{} |> BotTrigger.changeset(attrs) |> Repo.insert!()
    trigger -> trigger |> BotTrigger.changeset(attrs) |> Repo.update!()
  end
end
