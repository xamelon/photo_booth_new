# BotMachine

Phoenix + SQLite template for data-driven bots.

```text
webhook -> bot_inbox_events -> InboxWorker -> BotCore.Runner -> bot_outbox_messages -> OutboxWorker -> channel adapter
```

## Run

```bash
mix setup
mix phx.server
```

Seed creates a default admin unless one exists:

```text
admin@example.com / admin12345
```

Override with `ADMIN_EMAIL` / `ADMIN_PASSWORD`.

Open:

```text
http://localhost:4000/login
http://localhost:4000/admin/bot
```

Try the echo webhook:

```bash
curl -X POST http://localhost:4000/webhooks/echo \
  -H 'content-type: application/json' \
  -d '{"external_id":"1","text":"/start","idempotency_key":"demo-1"}'
```

Then answer in sandbox or webhook:

```bash
curl -X POST http://localhost:4000/webhooks/echo \
  -H 'content-type: application/json' \
  -d '{"external_id":"1","text":"Аня","idempotency_key":"demo-2"}'
```

## Extension points

- `lib/bot_machine/accounts/*` - admin users/auth.
- `lib/bot_machine/example_bot.ex` - replace with your flow/actions.
- `lib/bot_machine/bot_runtime/channels.ex` - add VK/Telegram/etc adapters.
- `lib/bot_machine/bot_runtime/channels/vk.ex` - VK callback/send adapter with photo upload.
- `lib/bot_machine/bot_core/*` - pure runner/registry/validator, no DB.
- `lib/bot_machine/bot_runtime.ex` - SQLite inbox/outbox/session runtime.

## VK

Admin UI:

```text
/admin/bot/channels
```

Webhook URL:

```text
POST /webhooks/vk
```

Credentials can be saved in the UI or provided via env:

```bash
VK_GROUP_ID=...
VK_CONFIRMATION_CODE=...
VK_GROUP_ACCESS_TOKEN=...
VK_API_VERSION=5.199
```

Outbound photo attachments support either:

```elixir
%{"type" => "photo", "ref" => "photo-1_2"}
%{"type" => "photo", "url" => "https://.../image.jpg"}
```

## SQLite queue

This template intentionally skips Oban/Postgres. The queue is just tables plus supervised pollers. Move to Oban later by replacing the queue/poller layer, not BotCore/actions/adapters.
