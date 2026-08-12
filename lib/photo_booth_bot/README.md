# PhotoBoothBot

Deletable demo bot logic.

This folder exists so the template runs immediately. For a real bot, replace it with your own app folder/module, then configure:

```elixir
config :bot_machine, bot_app: MyBotApp
```

Your app module must expose:

```elixir
def registry, do: ...
def flow, do: ...
```

Generic engine code stays under `lib/bot_machine`.
