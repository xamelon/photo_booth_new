# Flow definition

Flow definitions are JSON maps stored in `bot_flow_versions.definition`. Elixir code sees them as string-keyed maps decoded by Jason.

The live source of truth is the database. Seed/example Elixir flow exists only to initialize a fresh database.

## Top-level shape

```json
{
  "id": "demo",
  "version": 1,
  "start_node_id": "welcome",
  "nodes": []
}
```

Required:

- `id`: stable flow id, also stored in sessions/events
- `start_node_id`: id of the first node
- `nodes`: array of nodes

Optional:

- `version`: informational version number inside the definition

## Common node fields

All nodes have:

```json
{
  "id": "welcome",
  "type": "message",
  "position": { "x": 100, "y": 100 }
}
```

- `id`: unique inside the flow
- `type`: one of `message`, `input`, `action`, `condition`, `end`
- `position`: optional editor canvas position

## Message node

Sends a bot message when entered.

```json
{
  "id": "welcome",
  "type": "message",
  "text": "Hello {{name}}",
  "keyboard_mode": "inline",
  "button_rows": [
    [
      { "label": "Start", "payload": "btn_start", "to": "ask_name" }
    ]
  ],
  "attachments": [
    { "type": "photo", "ref": "photo-123_456", "url": "/uploads/bot/photo-123_456.jpg" }
  ],
  "next": "next_node"
}
```

Fields:

- `text`: message text. Supports `{{context.path}}` templates.
- `keyboard_mode`: `inline` or `reply`.
- `button_rows`: preferred button layout, array of rows.
- `buttons`: legacy flat button list. Prefer `button_rows`.
- `attachments`: photo attachments.
- `next`: optional automatic next node after sending.

Buttons:

```json
{ "label": "Start", "payload": "btn_start", "to": "ask_name" }
```

- `label`: visible text.
- `payload`: stable hidden value. UI should generate/keep this, not expose it casually.
- `to`: target node id when clicked.

Channel note: Telegram `inline` keyboards carry payload through `callback_data`; Telegram
`reply` keyboards send only visible button text as a normal message. Use payload triggers
with a text fallback when reply keyboards should work as a global menu.

Attachments:

```json
{ "type": "photo", "ref": "photo-123_456", "url": "/uploads/bot/photo-123_456.jpg" }
```

- `type`: currently only `photo`.
- `ref`: channel media ref, preferred for VK because it avoids re-upload.
- `url`: local preview URL or fallback remote URL. Runtime may upload by URL if no `ref` exists.

## Input node

Prompts the user and stores the next user message/payload in context.

```json
{
  "id": "ask_name",
  "type": "input",
  "prompt": "What is your name?",
  "input_key": "name",
  "next": "remember_name"
}

{
  "id": "ask_photo",
  "type": "input",
  "input_type": "photo",
  "prompt": "Send a photo",
  "retry_prompt": "Need a photo, please send one.",
  "input_key": "photo_url",
  "next": "next_node"
}
```

Required:

- `input_key`: context key to write

Optional:

- `prompt`: message sent before waiting for input
- `input_type`: `text`/absent stores text or payload; `photo` stores the first inbound photo `url`/`ref`
- `retry_prompt`: message sent when `input_type: photo` receives no photo
- `next`: target after input is received

## Custom/app nodes

Custom node handlers are for app-specific side effects or waits, not presentation.
They should update context and route to standard nodes with `next_node_id`.
Prefer a visible `next` field on the node and have the handler return that target.
User-facing messages should be modeled as `message` nodes so the flow remains visible in the editor.

## Action node

Calls a registered app action by name.

```json
{
  "id": "remember_name",
  "type": "action",
  "action": "remember_name",
  "params": { "mode": "short" },
  "next": "done"
}
```

- `action`: must exist in `BotMachine.BotApp.registry()`.
- `params`: JSON object passed to the action.
- `next`: default target after action.

The UI must reference registered actions. It must not evaluate user-provided code.

## Condition node

Routes by context values.

```json
{
  "id": "premium_check",
  "type": "condition",
  "branches": [
    {
      "when": { "op": "equals", "path": "premium", "value": true },
      "to": "premium_offer"
    }
  ],
  "default": "regular_offer"
}
```

Supported operations:

```json
{ "op": "exists", "path": "name" }
{ "op": "equals", "path": "premium", "value": true }
```

Branches are checked in order. First match wins. `default` is used when no branch matches.

## End node

Completes the session.

```json
{ "id": "end", "type": "end" }
```

## Validation

Runtime validation lives in:

```text
lib/bot_machine/bot_core/validator.ex
```

It checks:

- top-level `id`
- `start_node_id`
- start node exists
- action names exist in registry
- target node ids exist
- photo attachments have `ref` or `url`

Agent API endpoints:

```text
GET  /admin/api/agent/flows/:version_id
POST /admin/api/agent/flows/:version_id/validate
POST /admin/api/agent/flows/:version_id/save
```

POST body:

```json
{ "definition": { "id": "demo", "start_node_id": "welcome", "nodes": [] } }
```
