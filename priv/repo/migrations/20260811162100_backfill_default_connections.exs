defmodule BotMachine.Repo.Migrations.BackfillDefaultConnections do
  use Ecto.Migration

  def up do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second) |> NaiveDateTime.to_string()

    execute("""
    INSERT INTO bot_channel_connections (channel, name, external_id, public_id, status, credentials, config, inserted_at, updated_at)
    SELECT channel,
           channel || ' default',
           NULL,
           'conn_' || lower(hex(randomblob(8))),
           'active',
           data,
           '{}',
           '#{now}',
           '#{now}'
    FROM bot_channel_credentials
    WHERE NOT EXISTS (
      SELECT 1 FROM bot_channel_connections c WHERE c.channel = bot_channel_credentials.channel
    )
    """)

    execute("""
    INSERT INTO bot_channel_connections (channel, name, external_id, public_id, status, credentials, config, inserted_at, updated_at)
    SELECT 'echo', 'Echo sandbox', 'sandbox', 'conn_echo', 'active', '{}', '{}', '#{now}', '#{now}'
    WHERE NOT EXISTS (SELECT 1 FROM bot_channel_connections WHERE channel = 'echo')
    """)

    execute("""
    INSERT INTO bot_flow_connections (bot_flow_id, bot_channel_connection_id, enabled, priority, config, inserted_at, updated_at)
    SELECT f.id, c.id, 1, 0, '{}', '#{now}', '#{now}'
    FROM bot_flows f
    JOIN bot_channel_connections c ON c.channel = 'echo'
    WHERE NOT EXISTS (
      SELECT 1 FROM bot_flow_connections fc
      WHERE fc.bot_flow_id = f.id AND fc.bot_channel_connection_id = c.id
    )
    """)

    execute("""
    INSERT INTO bot_flow_connections (bot_flow_id, bot_channel_connection_id, enabled, priority, config, inserted_at, updated_at)
    SELECT DISTINCT t.bot_flow_id, c.id, 1, 0, '{}', '#{now}', '#{now}'
    FROM bot_triggers t
    JOIN bot_channel_connections c ON c.channel = t.channel
    WHERE NOT EXISTS (
      SELECT 1 FROM bot_flow_connections fc
      WHERE fc.bot_flow_id = t.bot_flow_id AND fc.bot_channel_connection_id = c.id
    )
    """)

    for table <- ["bot_users", "bot_inbox_events", "bot_outbox_messages"] do
      execute("""
      UPDATE #{table}
      SET bot_channel_connection_id = (
        SELECT id FROM bot_channel_connections c
        WHERE c.channel = #{table}.channel
        LIMIT 1
      )
      WHERE bot_channel_connection_id IS NULL
      """)
    end

    execute("""
    UPDATE bot_sessions
    SET bot_channel_connection_id = (
      SELECT bot_channel_connection_id FROM bot_users WHERE bot_users.id = bot_sessions.bot_user_id
    )
    WHERE bot_channel_connection_id IS NULL
    """)

    execute("""
    UPDATE bot_events
    SET bot_channel_connection_id = (
      SELECT bot_channel_connection_id FROM bot_sessions WHERE bot_sessions.id = bot_events.bot_session_id
    )
    WHERE bot_channel_connection_id IS NULL
    """)
  end

  def down do
    :ok
  end
end
