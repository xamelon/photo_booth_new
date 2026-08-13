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

Repo.delete_all(from t in BotTrigger, where: t.name in ["Start", "Start echo"])

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

connection =
  Repo.get_by(BotChannelConnection, channel: "echo") ||
    Repo.insert!(%BotChannelConnection{
      channel: "echo",
      name: "ECHO default",
      external_id: "sandbox",
      public_id: "conn_echo",
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

upsert_trigger = fn attrs ->
  case Repo.get_by(BotTrigger, bot_flow_id: flow.id, name: attrs.name) do
    nil -> %BotTrigger{} |> BotTrigger.changeset(attrs) |> Repo.insert!()
    trigger -> trigger |> BotTrigger.changeset(attrs) |> Repo.update!()
  end
end

for channel <- ["echo", "vk", "telegram"] do
  upsert_trigger.(%{
    bot_flow_id: flow.id,
    name: "Start #{channel}",
    channel: channel,
    type: "command",
    match: %{"command" => "start"},
    start_node_id: "welcome",
    session_mode: "restart",
    priority: 100,
    enabled: true
  })

  for {payload, label, node_id} <- [
        {"edit_photo", "✏️ Отредактировать фото", "ask_edit_photo"},
        {"birthday_postcard", "🎂 Открытка на день рождения", "ask_birthday_photo"},
        {"photo_restoration", "🧩 Реставрация фото", "ask_restore_photo"},
        {"free_photos", "🎁 Как получить фото бесплатно", "free_photos"},
        {"balance", "💰 Баланс", "balance"}
      ] do
    upsert_trigger.(%{
      bot_flow_id: flow.id,
      name: "Menu #{channel} #{payload}",
      channel: channel,
      type: "payload",
      match: %{"payload" => payload, "text" => label},
      start_node_id: node_id,
      session_mode: "start_or_jump",
      priority: 90,
      enabled: true
    })
  end

  upsert_trigger.(%{
    bot_flow_id: flow.id,
    name: "Generation completed #{channel}",
    channel: channel,
    type: "event",
    match: %{"event" => "photo_generation.completed"},
    start_node_id: "act_generation_completed_notify",
    session_mode: "notify_only",
    priority: 80,
    enabled: true
  })

  upsert_trigger.(%{
    bot_flow_id: flow.id,
    name: "Generation failed #{channel}",
    channel: channel,
    type: "event",
    match: %{"event" => "photo_generation.failed"},
    start_node_id: "act_generation_failed_notify",
    session_mode: "notify_only",
    priority: 80,
    enabled: true
  })
end
