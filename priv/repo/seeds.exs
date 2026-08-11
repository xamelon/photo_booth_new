import Ecto.Query

alias BotMachine.BotRuntime.{BotFlow, BotFlowVersion, BotTrigger}
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
  Repo.get_by(BotFlow, slug: "demo") ||
    Repo.insert!(%BotFlow{slug: "demo", name: "Demo flow", status: "published"})

Repo.delete_all(from t in BotTrigger, where: t.bot_flow_id == ^flow.id and t.name == "Start")

demo_flow = BotMachine.BotApp.flow()

unless Repo.get_by(BotFlowVersion, bot_flow_id: flow.id, version: demo_flow["version"]) do
  Repo.insert!(%BotFlowVersion{
    bot_flow_id: flow.id,
    version: demo_flow["version"],
    status: "published",
    definition: demo_flow,
    published_at: DateTime.utc_now() |> DateTime.truncate(:second)
  })
end

for {name, channel} <- [{"Start echo", "echo"}, {"Start VK", "vk"}] do
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
