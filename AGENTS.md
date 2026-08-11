# Agent rules for this repo

This is a reusable Phoenix/SQLite bot template, not one final bot.

## Boundaries

- `lib/bot_machine/` is generic bot engine/runtime code.
- `lib/bot_machine_web/` is generic admin/core UI.
- `lib/bot_machine_example_app/` is deletable demo bot logic.
- `lib/bot_machine_example_app_web/` is deletable demo app-specific admin UI.
- Do not put project/business-specific code into `BotCore` or generic runtime.

## App-specific bots

A real bot should provide a module with:

```elixir
def registry, do: ...
def flow, do: ...
```

and configure it with:

```elixir
config :bot_machine, bot_app: MyBotApp
```

The generic code should call:

```elixir
BotMachine.BotApp.registry()
BotMachine.BotApp.flow()
```

not the example app directly.

## Flow editing

The current live flow is stored in DB. Change it through the admin UI or agent API, not by editing seed Elixir code.

Agent API requires an admin browser session:

```text
GET  /admin/api/agent/overview
GET  /admin/api/agent/flows/:version_id
POST /admin/api/agent/flows/:version_id/validate
POST /admin/api/agent/flows/:version_id/save
```

POST body:

```json
{ "definition": { } }
```

Seed/example Elixir flow is only the default for new DB setup.

## Versions

The UI now treats each flow as one current version. `save` updates the current `bot_flow_versions` row instead of creating new versions.

## Channels

`BotCore` must stay channel-agnostic. VK-specific behavior belongs under:

```text
lib/bot_machine/bot_runtime/channels/vk*.ex
```

Button payloads are hidden/stable; do not expose payload editing in the UI unless explicitly requested.

## Admin users vs bot users

Admin users and bot users are separate. Do not merge their schemas/auth.

## Preferred implementation style

- Keep SQLite/simple workers unless scale requires Postgres/Oban.
- Prefer small changes over abstractions.
- No new dependency unless existing code/stdlib cannot do it simply.
- Backport only generic improvements to the template; keep concrete bot business logic in app-specific folders.

## Checks

Run when possible:

```bash
mix format
mix test
mix assets.build
```
