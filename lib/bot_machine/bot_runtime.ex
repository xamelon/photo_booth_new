defmodule BotMachine.BotRuntime do
  import Ecto.Query

  alias BotMachine.Repo
  alias BotMachine.BotCore.{Runner, TriggerMatcher, Validator}

  alias BotMachine.BotRuntime.{
    BotChannelConnection,
    BotEvent,
    BotFlow,
    BotFlowConnection,
    BotFlowVersion,
    BotSession,
    BotTrigger,
    BotUser,
    Channels,
    InboxEvent,
    OutboxMessage
  }

  def enqueue_inbox(input, idempotency_key \\ nil) do
    connection = connection_for_input!(input)

    attrs = %{
      bot_channel_connection_id: connection.id,
      channel: connection.channel,
      external_id: input["external_id"],
      idempotency_key: idempotency_key || hash(input),
      payload: input,
      status: "pending"
    }

    %InboxEvent{}
    |> InboxEvent.changeset(attrs)
    |> Repo.insert(on_conflict: :nothing)
  end

  def list_channel_connections do
    Repo.all(
      from c in BotChannelConnection,
        left_join: fc in BotFlowConnection,
        on: fc.bot_channel_connection_id == c.id and fc.enabled == true,
        group_by: c.id,
        order_by: [asc: c.channel, asc: c.name],
        select_merge: %{flow_connection_count: count(fc.id)}
    )
  end

  def get_channel_connection!(id), do: Repo.get!(BotChannelConnection, id)

  def delete_channel_connection!(id) do
    id
    |> get_channel_connection!()
    |> Repo.delete!()
  end

  def create_vk_connection(attrs) do
    public_id = "conn_vk_" <> (:crypto.strong_rand_bytes(5) |> Base.url_encode64(padding: false))

    %BotChannelConnection{}
    |> BotChannelConnection.changeset(%{
      channel: "vk",
      name: attrs["name"] || "VK group",
      external_id: attrs["group_id"],
      public_id: public_id,
      status: "active",
      credentials: %{},
      config: %{}
    })
    |> Repo.insert()
    |> case do
      {:ok, connection} ->
        with {:ok, connection} <-
               BotMachine.BotRuntime.Credentials.put_connection(connection, attrs) do
          refresh_vk_connection_info(connection)
          {:ok, connection}
        end

      error ->
        error
    end
  end

  def update_vk_connection(id, attrs) do
    connection = get_channel_connection!(id)

    connection
    |> BotChannelConnection.changeset(%{name: attrs["name"] || connection.name})
    |> Repo.update()
    |> case do
      {:ok, connection} ->
        with {:ok, connection} <-
               BotMachine.BotRuntime.Credentials.put_connection(connection, attrs) do
          refresh_vk_connection_info(connection)
          {:ok, connection}
        end

      error ->
        error
    end
  end

  def create_telegram_connection(attrs) do
    public_id = "conn_tg_" <> (:crypto.strong_rand_bytes(5) |> Base.url_encode64(padding: false))

    %BotChannelConnection{}
    |> BotChannelConnection.changeset(%{
      channel: "telegram",
      name: attrs["name"] || "Telegram bot",
      external_id: attrs["external_id"],
      public_id: public_id,
      status: "active",
      credentials: %{},
      config: %{}
    })
    |> Repo.insert()
    |> case do
      {:ok, connection} ->
        with {:ok, connection} <-
               BotMachine.BotRuntime.Credentials.put_connection(connection, attrs) do
          provision_telegram_connection(connection)
          {:ok, connection}
        end

      error ->
        error
    end
  end

  def update_telegram_connection(id, attrs) do
    connection = get_channel_connection!(id)

    connection
    |> BotChannelConnection.changeset(%{
      name: attrs["name"] || connection.name,
      external_id: attrs["external_id"] || connection.external_id
    })
    |> Repo.update()
    |> case do
      {:ok, connection} ->
        with {:ok, connection} <-
               BotMachine.BotRuntime.Credentials.put_connection(connection, attrs) do
          provision_telegram_connection(connection)
          {:ok, connection}
        end

      error ->
        error
    end
  end

  def provision_telegram_connection(%BotChannelConnection{channel: "telegram"} = connection) do
    creds = BotMachine.BotRuntime.Credentials.for_connection(connection)
    webhook_url = BotMachine.BotRuntime.Channels.Telegram.callback_url(connection)

    with {:ok, info} <- BotMachine.BotRuntime.Channels.Telegram.get_me(creds),
         {:ok, _} <- BotMachine.BotRuntime.Channels.Telegram.set_webhook(creds, webhook_url) do
      connection
      |> BotChannelConnection.changeset(%{
        external_id: info["bot_username"] || connection.external_id,
        config:
          Map.merge(
            connection.config || %{},
            Map.merge(info, %{"webhook_url" => webhook_url, "last_provision_error" => nil})
          )
      })
      |> Repo.update()
    else
      {:error, reason} ->
        connection
        |> BotChannelConnection.changeset(%{
          config:
            Map.merge(connection.config || %{}, %{
              "webhook_url" => webhook_url,
              "last_provision_error" => reason
            })
        })
        |> Repo.update()

        {:error, reason}
    end
  end

  def provision_telegram_connection(_connection), do: {:error, "not a Telegram connection"}

  def refresh_vk_connection_info(id) when is_binary(id) or is_integer(id),
    do: id |> get_channel_connection!() |> refresh_vk_connection_info()

  def refresh_vk_connection_info(%BotChannelConnection{channel: "vk"} = connection) do
    creds = BotMachine.BotRuntime.Credentials.for_connection(connection)

    case BotMachine.BotRuntime.Channels.VK.group_info(creds) do
      {:ok, info} ->
        connection
        |> BotChannelConnection.changeset(%{
          external_id: creds["group_id"] || connection.external_id,
          config: Map.merge(connection.config || %{}, info)
        })
        |> Repo.update()

      {:error, reason} ->
        {:error, reason}
    end
  end

  def refresh_vk_connection_info(_connection), do: {:error, "not a VK connection"}

  def flow_connection_matrix do
    flows = list_flows()
    connections = list_channel_connections()

    enabled =
      Repo.all(
        from fc in BotFlowConnection,
          select: {fc.bot_channel_connection_id, fc.bot_flow_id, fc.enabled}
      )
      |> Map.new(fn {connection_id, flow_id, enabled} -> {{connection_id, flow_id}, enabled} end)

    %{flows: flows, connections: connections, enabled: enabled}
  end

  def set_connection_flows(connection_id, flow_ids) do
    connection = get_channel_connection!(connection_id)
    flow_ids = MapSet.new(Enum.map(flow_ids, &String.to_integer(to_string(&1))))

    Repo.transaction(fn ->
      Repo.all(BotFlow)
      |> Enum.each(fn flow ->
        enabled? = MapSet.member?(flow_ids, flow.id)

        flow_connection =
          Repo.get_by(BotFlowConnection,
            bot_flow_id: flow.id,
            bot_channel_connection_id: connection.id
          ) || %BotFlowConnection{}

        flow_connection
        |> BotFlowConnection.changeset(%{
          bot_flow_id: flow.id,
          bot_channel_connection_id: connection.id,
          enabled: enabled?,
          priority: 0,
          config: %{}
        })
        |> Repo.insert_or_update!()
      end)
    end)
  end

  def default_connection(channel \\ "echo") do
    Repo.get_by(BotChannelConnection, channel: channel) ||
      %BotChannelConnection{}
      |> BotChannelConnection.changeset(%{
        channel: channel,
        name: "#{String.upcase(channel)} default",
        external_id: if(channel == "echo", do: "sandbox"),
        public_id: "conn_#{channel}",
        status: "active",
        credentials: %{},
        config: %{}
      })
      |> Repo.insert!()
  end

  def connection_for_public_id(public_id),
    do: Repo.get_by(BotChannelConnection, public_id: public_id, status: "active")

  defp connection_for_input!(%{"bot_channel_connection_id" => id}) when not is_nil(id),
    do: Repo.get!(BotChannelConnection, id)

  defp connection_for_input!(%{"connection_public_id" => public_id}) when is_binary(public_id),
    do: connection_for_public_id(public_id) || raise("unknown channel connection #{public_id}")

  defp connection_for_input!(%{"channel" => channel}), do: default_connection(channel)

  def process_pending_inbox(limit \\ 10) do
    due_inbox_query(limit)
    |> Repo.all(log: false)
    |> Enum.each(&process_inbox/1)
  end

  def process_pending_outbox(limit \\ 10) do
    due_outbox_query(limit)
    |> Repo.all(log: false)
    |> Enum.each(&deliver_outbox/1)
  end

  def counts do
    %{
      bot_users: Repo.aggregate(BotUser, :count),
      sessions: Repo.aggregate(BotSession, :count),
      inbox: Repo.aggregate(InboxEvent, :count),
      inbox_failed: Repo.aggregate(from(e in InboxEvent, where: e.status == "failed"), :count),
      inbox_pending: Repo.aggregate(from(e in InboxEvent, where: e.status == "pending"), :count),
      outbox: Repo.aggregate(OutboxMessage, :count),
      outbox_failed:
        Repo.aggregate(from(m in OutboxMessage, where: m.status == "failed"), :count),
      outbox_pending:
        Repo.aggregate(from(m in OutboxMessage, where: m.status == "pending"), :count),
      events: Repo.aggregate(BotEvent, :count),
      flows: Repo.aggregate(BotFlow, :count),
      triggers: Repo.aggregate(BotTrigger, :count)
    }
  end

  def list_users do
    Repo.all(
      from u in BotUser,
        left_join: c in assoc(u, :bot_channel_connection),
        left_join: s in BotSession,
        on: s.bot_user_id == u.id,
        group_by: [u.id, c.id],
        order_by: [desc: max(s.updated_at), desc: u.updated_at],
        limit: 100,
        select: %{
          id: u.id,
          channel: u.channel,
          connection_name: c.name,
          external_id: u.external_id,
          display_name: u.display_name,
          metadata: u.metadata,
          blocked_at: u.blocked_at,
          inserted_at: u.inserted_at,
          updated_at: u.updated_at,
          sessions_count: count(s.id),
          last_seen_at: max(s.updated_at)
        }
    )
    |> Enum.map(&Map.put(&1, :active_session, active_session_for_user(&1.id)))
  end

  def list_chats do
    Repo.all(
      from u in BotUser,
        left_join: c in assoc(u, :bot_channel_connection),
        preload: [bot_channel_connection: c],
        order_by: [desc: u.updated_at],
        limit: 100
    )
    |> Enum.map(fn user ->
      Map.put(user, :last_message, chat_transcript(user, 1) |> List.last())
    end)
    |> Enum.sort_by(
      &((&1.last_message && &1.last_message.at) || &1.updated_at),
      {:desc, DateTime}
    )
  end

  def get_user_detail(id) do
    user = Repo.get(BotUser, id) |> Repo.preload(:bot_channel_connection)

    if user do
      sessions =
        Repo.all(
          from s in BotSession,
            where: s.bot_user_id == ^user.id,
            order_by: [desc: s.updated_at],
            limit: 20
        )

      inbox =
        Repo.all(
          from e in InboxEvent,
            where:
              e.bot_channel_connection_id == ^user.bot_channel_connection_id and
                e.external_id == ^user.external_id,
            order_by: [desc: e.inserted_at],
            limit: 30
        )

      outbox =
        Repo.all(
          from m in OutboxMessage,
            where:
              m.bot_channel_connection_id == ^user.bot_channel_connection_id and
                m.external_id == ^user.external_id,
            order_by: [desc: m.inserted_at],
            limit: 30
        )

      %{
        user: user,
        sessions: sessions,
        inbox: inbox,
        outbox: outbox,
        transcript: chat_transcript(user)
      }
    end
  end

  def admin_send_message(user_id, text) do
    text = String.trim(text || "")

    with false <- text == "",
         %BotUser{} = user <- Repo.get(BotUser, user_id) do
      %OutboxMessage{}
      |> OutboxMessage.changeset(%{
        bot_channel_connection_id: user.bot_channel_connection_id,
        channel: user.channel,
        external_id: user.external_id,
        idempotency_key: "admin:#{user.id}:#{System.unique_integer([:positive])}",
        payload: %{"type" => "message", "text" => text, "source" => "admin"},
        status: "pending"
      })
      |> Repo.insert()
    else
      true -> {:error, :empty_message}
      nil -> {:error, :user_not_found}
    end
  end

  def chat_transcript(user, limit \\ 200) do
    inbox =
      Repo.all(
        from e in InboxEvent,
          where:
            e.bot_channel_connection_id == ^user.bot_channel_connection_id and
              e.external_id == ^user.external_id,
          order_by: [desc: e.inserted_at],
          limit: ^limit
      )
      |> Enum.map(&inbox_to_chat_message/1)

    outbox =
      Repo.all(
        from m in OutboxMessage,
          where:
            m.bot_channel_connection_id == ^user.bot_channel_connection_id and
              m.external_id == ^user.external_id,
          order_by: [desc: m.inserted_at],
          limit: ^limit
      )
      |> Enum.map(&outbox_to_chat_message/1)

    (inbox ++ outbox)
    |> Enum.sort_by(& &1.at, {:asc, DateTime})
    |> Enum.take(-limit)
  end

  defp inbox_to_chat_message(event) do
    %{
      author: "user",
      text:
        event.payload["text"] || event.payload["button_label"] || event.payload["payload"] || "—",
      status: event.status,
      at: event.inserted_at,
      raw: event.payload
    }
  end

  defp outbox_to_chat_message(message) do
    source = message.payload["source"] || "bot"

    %{
      author: source,
      text: message.payload["text"] || "—",
      status: message.status,
      at: message.inserted_at,
      raw: message.payload
    }
  end

  def list_sessions(filters \\ %{}) do
    BotSession
    |> join(:inner, [s], u in assoc(s, :bot_user))
    |> join(:left, [s, u], c in assoc(s, :bot_channel_connection))
    |> maybe_filter_connection(filters)
    |> maybe_filter_flow(filters)
    |> maybe_filter_session_user(filters)
    |> order_by([s], desc: s.updated_at)
    |> limit(50)
    |> preload([s, u, c], bot_user: u, bot_channel_connection: c)
    |> Repo.all()
  end

  def list_inbox(filters \\ %{}), do: list_queue(InboxEvent, filters)
  def list_outbox(filters \\ %{}), do: list_queue(OutboxMessage, filters)

  def list_events(filters \\ %{}) do
    BotEvent
    |> join(:left, [e], c in assoc(e, :bot_channel_connection))
    |> maybe_filter_connection(filters)
    |> maybe_filter_flow(filters)
    |> maybe_filter_event_type(filters)
    |> order_by([e], desc: e.inserted_at)
    |> limit(100)
    |> preload([e, c], bot_channel_connection: c)
    |> Repo.all()
  end

  defp list_queue(schema, filters) do
    schema
    |> join(:left, [q], c in assoc(q, :bot_channel_connection))
    |> maybe_filter_connection(filters)
    |> maybe_filter_status(filters)
    |> maybe_filter_user(filters)
    |> order_by([q], desc: q.inserted_at)
    |> limit(50)
    |> preload([q, c], bot_channel_connection: c)
    |> Repo.all()
  end

  defp maybe_filter_connection(query, %{"connection_id" => id}) when id not in [nil, ""],
    do: where(query, [row], row.bot_channel_connection_id == ^id)

  defp maybe_filter_connection(query, _filters), do: query

  defp maybe_filter_status(query, %{"status" => status}) when status not in [nil, ""],
    do: where(query, [row], row.status == ^status)

  defp maybe_filter_status(query, _filters), do: query

  defp maybe_filter_flow(query, %{"flow_id" => flow_id}) when flow_id not in [nil, ""],
    do: where(query, [row], row.flow_id == ^flow_id)

  defp maybe_filter_flow(query, _filters), do: query

  defp maybe_filter_event_type(query, %{"event_type" => event_type})
       when event_type not in [nil, ""],
       do: where(query, [row], row.event_type == ^event_type)

  defp maybe_filter_event_type(query, _filters), do: query

  defp maybe_filter_user(query, %{"q" => q}) when q not in [nil, ""] do
    q = "%#{q}%"
    where(query, [row], like(row.external_id, ^q))
  end

  defp maybe_filter_user(query, _filters), do: query

  defp maybe_filter_session_user(query, %{"q" => q}) when q not in [nil, ""] do
    q = "%#{q}%"
    where(query, [_s, u, _c], like(u.external_id, ^q))
  end

  defp maybe_filter_session_user(query, _filters), do: query

  def list_flows do
    Repo.all(from f in BotFlow, order_by: [asc: f.slug])
    |> Enum.map(fn flow ->
      latest =
        Repo.one(
          from v in BotFlowVersion,
            where: v.bot_flow_id == ^flow.id,
            order_by: [desc: v.version],
            limit: 1
        )

      %{flow | versions: Enum.reject([latest], &is_nil/1)}
    end)
  end

  def list_triggers do
    Repo.all(
      from t in BotTrigger,
        join: f in assoc(t, :bot_flow),
        preload: [bot_flow: f],
        order_by: [desc: t.priority, asc: t.name]
    )
  end

  def get_flow_version(id) do
    Repo.one(
      from v in BotFlowVersion,
        join: f in assoc(v, :bot_flow),
        where: v.id == ^id,
        preload: [bot_flow: f]
    )
  end

  def validate_flow_definition(definition),
    do: Validator.validate(definition, BotMachine.BotApp.registry())

  def save_flow_definition(%BotFlowVersion{} = version, definition) do
    issues = validate_flow_definition(definition)

    if issues == [] do
      version
      |> BotFlowVersion.changeset(%{definition: definition})
      |> Repo.update()
    else
      {:error, issues}
    end
  end

  def sandbox_state(channel \\ "echo", external_id \\ "sandbox") do
    connection = default_connection(channel)

    user =
      Repo.get_by(BotUser, bot_channel_connection_id: connection.id, external_id: external_id)

    inbox =
      Repo.all(
        from e in InboxEvent,
          where: e.bot_channel_connection_id == ^connection.id and e.external_id == ^external_id,
          order_by: [asc: e.inserted_at]
      )

    outbox =
      Repo.all(
        from m in OutboxMessage,
          where: m.bot_channel_connection_id == ^connection.id and m.external_id == ^external_id,
          order_by: [asc: m.inserted_at]
      )

    session =
      if user do
        Repo.one(
          from s in BotSession,
            where: s.bot_user_id == ^user.id and is_nil(s.completed_at),
            order_by: [desc: s.updated_at],
            limit: 1
        )
      end

    last_outbox = List.last(outbox)

    last_buttons_at =
      if last_outbox && (last_outbox.payload["buttons"] || []) != [], do: last_outbox.inserted_at

    transcript =
      (Enum.map(
         inbox,
         &%{
           author: "user",
           text: &1.payload["text"] || inspect(&1.payload),
           at: &1.inserted_at,
           status: &1.status
         }
       ) ++
         Enum.map(
           outbox,
           &%{
             author: "bot",
             text: &1.payload["text"] || inspect(&1.payload),
             at: &1.inserted_at,
             status: &1.status,
             buttons: &1.payload["buttons"] || [],
             active_buttons: &1.inserted_at == last_buttons_at
           }
         ))
      |> Enum.sort_by(& &1.at, DateTime)

    %{user: user, session: session, inbox: inbox, outbox: outbox, transcript: transcript}
  end

  def reset_sandbox(channel \\ "echo", external_id \\ "sandbox") do
    connection = default_connection(channel)

    if user =
         Repo.get_by(BotUser, bot_channel_connection_id: connection.id, external_id: external_id),
       do: Repo.delete!(user)

    Repo.delete_all(
      from e in InboxEvent,
        where: e.bot_channel_connection_id == ^connection.id and e.external_id == ^external_id
    )

    Repo.delete_all(
      from m in OutboxMessage,
        where: m.bot_channel_connection_id == ^connection.id and m.external_id == ^external_id
    )

    :ok
  end

  def build_flow_viewer(%BotFlowVersion{} = version) do
    flow = version.definition
    flow_id = flow["id"]
    bot_flow_id = version.bot_flow_id

    triggers =
      Repo.all(from t in BotTrigger, where: t.bot_flow_id == ^bot_flow_id and t.enabled == true)

    sessions =
      Repo.all(from s in BotSession, where: s.flow_id == ^flow_id and is_nil(s.completed_at))

    events = Repo.all(from e in BotEvent, where: e.flow_id == ^flow_id)
    edges = flow_edges(flow)

    %{
      flow: %{
        id: flow_id,
        name: version.bot_flow.name,
        version: version.version,
        status: version.status,
        start_node_id: flow["start_node_id"]
      },
      metrics: %{
        node_count: length(flow["nodes"] || []),
        trigger_count: length(triggers),
        active_sessions: length(sessions),
        event_count: length(events)
      },
      nodes:
        Enum.map(flow["nodes"] || [], fn node ->
          node_events = Enum.filter(events, &(&1.node_id == node["id"]))

          %{
            id: node["id"],
            type: node["type"],
            label: node_label(node),
            condition: condition_detail(node),
            buttons: buttons_detail(node),
            outgoing: Enum.filter(edges, &(&1.from == node["id"])),
            incoming: Enum.filter(edges, &(&1.to == node["id"])),
            triggers:
              triggers
              |> Enum.filter(&(&1.start_node_id == node["id"]))
              |> Enum.map(&%{name: &1.name, type: &1.type}),
            validationIssues: [],
            metrics: %{
              reachedUsers:
                node_events
                |> Enum.filter(&(&1.event_type == "node_entered"))
                |> Enum.map(& &1.bot_session_id)
                |> Enum.uniq()
                |> length(),
              visits: Enum.count(node_events, &(&1.event_type == "node_entered")),
              currentSessions: Enum.count(sessions, &(&1.current_node_id == node["id"])),
              completedUsers:
                node_events
                |> Enum.filter(&(&1.event_type == "node_completed"))
                |> Enum.map(& &1.bot_session_id)
                |> Enum.uniq()
                |> length(),
              errors: Enum.count(node_events, &(&1.event_type == "flow_error"))
            }
          }
        end)
    }
  end

  # ponytail: single SQLite app instance; replace with SKIP LOCKED/Oban when moving to Postgres.
  defp due_inbox_query(limit) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    from e in InboxEvent,
      where:
        e.status in ["pending", "failed"] and (is_nil(e.next_retry_at) or e.next_retry_at <= ^now),
      order_by: [asc: e.inserted_at],
      limit: ^limit
  end

  defp due_outbox_query(limit) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    from m in OutboxMessage,
      where:
        m.status in ["pending", "failed"] and (is_nil(m.next_retry_at) or m.next_retry_at <= ^now),
      order_by: [asc: m.inserted_at],
      limit: ^limit
  end

  defp process_inbox(event) do
    event = mark_processing(event)

    Repo.transaction(fn ->
      connection = Repo.get!(BotChannelConnection, event.bot_channel_connection_id)
      input = event.payload |> Map.put("channel", connection.channel)
      user = get_or_create_user(connection, input)
      session = active_session(connection, user)
      trigger = find_trigger(connection, input)

      if is_nil(session) and is_nil(trigger) do
        mark_processed(event)
      else
        version = flow_version!(session, trigger)

        result =
          Runner.run(
            version.definition,
            input,
            BotMachine.BotApp.registry(),
            session && to_core_session(session),
            trigger && to_core_trigger(trigger)
          )

        session = save_session(connection, user, result.session)

        Enum.each(result.events, &save_event(&1, connection, session))

        Enum.with_index(
          result.outputs,
          &save_outbox(&1, connection, "#{event.idempotency_key}:out:#{&2}")
        )

        mark_processed(event)
      end
    end)
  rescue
    error -> fail_inbox(event, Exception.message(error))
  end

  defp mark_processed(event) do
    event
    |> InboxEvent.changeset(%{
      status: "processed",
      processed_at: DateTime.utc_now() |> DateTime.truncate(:second),
      last_error: nil
    })
    |> Repo.update!()
  end

  defp deliver_outbox(message) do
    message =
      message
      |> OutboxMessage.changeset(%{status: "processing", attempts: message.attempts + 1})
      |> Repo.update!()

    connection = Repo.get!(BotChannelConnection, message.bot_channel_connection_id)

    case Channels.send(connection, Map.put(message.payload, "_outbox_id", message.id)) do
      {:ok, external_message_id} ->
        message
        |> OutboxMessage.changeset(%{
          status: "sent",
          sent_at: DateTime.utc_now() |> DateTime.truncate(:second),
          external_message_id: external_message_id,
          last_error: nil
        })
        |> Repo.update!()

      {:error, reason} ->
        fail_outbox(message, to_string(reason))
    end
  rescue
    error -> fail_outbox(message, Exception.message(error))
  end

  defp get_or_create_user(connection, input) do
    user =
      Repo.get_by(BotUser,
        bot_channel_connection_id: connection.id,
        external_id: input["external_id"]
      )

    cond do
      user && user_profile_changed?(user, input) ->
        update_user_profile(user, input)

      user && user.display_name in [nil, ""] && connection.channel == "vk" ->
        enrich_vk_user(user, connection)

      user ->
        user

      true ->
        attrs =
          %{
            bot_channel_connection_id: connection.id,
            channel: connection.channel,
            external_id: input["external_id"],
            display_name: input["display_name"],
            metadata: input["metadata"] || %{}
          }
          |> maybe_put_vk_user_info(connection)

        %BotUser{}
        |> BotUser.changeset(attrs)
        |> Repo.insert!()
    end
  end

  defp user_profile_changed?(user, input) do
    (input["display_name"] not in [nil, ""] and input["display_name"] != user.display_name) or
      (is_map(input["metadata"]) and input["metadata"] != %{} and
         Map.merge(user.metadata || %{}, input["metadata"]) != (user.metadata || %{}))
  end

  defp update_user_profile(user, input) do
    user
    |> BotUser.changeset(%{
      display_name: input["display_name"] || user.display_name,
      metadata: Map.merge(user.metadata || %{}, input["metadata"] || %{})
    })
    |> Repo.update!()
  end

  defp maybe_put_vk_user_info(attrs, %{channel: "vk"} = connection) do
    creds = BotMachine.BotRuntime.Credentials.for_connection(connection)

    case BotMachine.BotRuntime.Channels.VK.user_info(creds, attrs.external_id) do
      {:ok, %{"display_name" => name, "photo_url" => photo_url}} ->
        attrs
        |> Map.put(:display_name, name)
        |> Map.put(:metadata, %{"photo_url" => photo_url})

      _ ->
        attrs
    end
  end

  defp maybe_put_vk_user_info(attrs, _connection), do: attrs

  defp enrich_vk_user(user, connection) do
    creds = BotMachine.BotRuntime.Credentials.for_connection(connection)

    case BotMachine.BotRuntime.Channels.VK.user_info(creds, user.external_id) do
      {:ok, %{"display_name" => name, "photo_url" => photo_url}} ->
        user
        |> BotUser.changeset(%{
          display_name: name,
          metadata: Map.put(user.metadata || %{}, "photo_url", photo_url)
        })
        |> Repo.update!()

      _ ->
        user
    end
  end

  defp flow_edges(flow) do
    Enum.flat_map(flow["nodes"] || [], fn node ->
      button_edges =
        node
        |> button_rows()
        |> List.flatten()
        |> Enum.map(&%{from: node["id"], to: &1["to"], label: &1["label"], kind: "button"})

      branch_edges =
        Enum.map(
          node["branches"] || [],
          &%{from: node["id"], to: &1["to"], label: condition_label(&1["when"]), kind: "branch"}
        )

      outcome_edges =
        Enum.map(
          node["outcomes"] || [],
          &%{from: node["id"], to: &1["to"], label: &1["label"], kind: "outcome"}
        )

      next_edges =
        if node["next"],
          do: [%{from: node["id"], to: node["next"], label: "next", kind: "next"}],
          else: []

      default_edges =
        if node["default"],
          do: [%{from: node["id"], to: node["default"], label: "else", kind: "default"}],
          else: []

      Enum.reject(
        button_edges ++ branch_edges ++ outcome_edges ++ next_edges ++ default_edges,
        &is_nil(&1.to)
      )
    end)
  end

  defp button_rows(%{"button_rows" => rows}) when is_list(rows), do: rows
  defp button_rows(%{"buttons" => buttons}) when is_list(buttons), do: [buttons]
  defp button_rows(_node), do: []

  defp node_label(%{"type" => "message"} = node), do: node["text"] || ""
  defp node_label(%{"type" => "input"} = node), do: node["prompt"] || node["input_key"] || ""
  defp node_label(%{"type" => "action"} = node), do: node["action"] || ""

  defp node_label(%{"type" => "condition"} = node),
    do: Enum.map_join(node["branches"] || [], " · ", &condition_label(&1["when"]))

  defp node_label(node), do: node["type"] || ""

  defp buttons_detail(%{"type" => "message"} = node),
    do: node |> button_rows() |> List.flatten() |> Enum.map(&%{label: &1["label"], to: &1["to"]})

  defp buttons_detail(_node), do: nil

  defp condition_detail(%{"type" => "condition"} = node) do
    %{
      defaultTo: node["default"],
      branches:
        Enum.map(node["branches"] || [], &%{when: condition_label(&1["when"]), to: &1["to"]})
    }
  end

  defp condition_detail(_node), do: nil

  defp condition_label(%{"op" => "exists", "path" => path}), do: "exists #{path}"

  defp condition_label(%{"op" => "equals", "path" => path, "value" => value}),
    do: "#{path} = #{inspect(value)}"

  defp condition_label(_), do: "branch"

  defp find_trigger(connection, input) do
    triggers =
      Repo.all(
        from t in BotTrigger,
          join: fc in BotFlowConnection,
          on: fc.bot_flow_id == t.bot_flow_id,
          where:
            fc.bot_channel_connection_id == ^connection.id and fc.enabled == true and
              t.channel in [^connection.channel, "*"] and t.enabled == true,
          order_by: [desc: t.priority, desc: t.channel]
      )

    matched = TriggerMatcher.match(input, Enum.map(triggers, &trigger_to_map/1))
    matched && Enum.find(triggers, &(to_string(&1.id) == matched["id"]))
  end

  defp flow_version!(session, trigger) do
    version =
      cond do
        trigger -> latest_flow_version(trigger.bot_flow_id)
        session -> session_flow_version(session)
        true -> nil
      end

    version || raise("no runnable bot flow version")
  end

  defp latest_flow_version(bot_flow_id) do
    Repo.one(
      from v in BotFlowVersion,
        where: v.bot_flow_id == ^bot_flow_id and v.status in ["published", "draft"],
        order_by: [desc: v.version],
        limit: 1
    )
  end

  defp session_flow_version(session) do
    Repo.one(
      from v in BotFlowVersion,
        join: f in assoc(v, :bot_flow),
        where: f.slug == ^session.flow_id and v.status in ["published", "draft"],
        order_by: [desc: v.version],
        limit: 1
    )
  end

  defp active_session_for_user(user_id) do
    Repo.one(
      from s in BotSession,
        where: s.bot_user_id == ^user_id and is_nil(s.completed_at),
        order_by: [desc: s.updated_at],
        limit: 1
    )
  end

  defp active_session(connection, user) do
    Repo.one(
      from s in BotSession,
        where:
          s.bot_channel_connection_id == ^connection.id and s.bot_user_id == ^user.id and
            is_nil(s.completed_at),
        order_by: [desc: s.updated_at],
        limit: 1
    )
  end

  defp save_session(connection, user, state) do
    attrs = %{
      bot_user_id: user.id,
      bot_channel_connection_id: connection.id,
      flow_id: state.flow_id,
      flow_version: state.flow_version,
      current_node_id: state.current_node_id,
      context: state.context,
      completed_at:
        if(state.completed, do: DateTime.utc_now() |> DateTime.truncate(:second), else: nil)
    }

    query =
      from s in BotSession,
        where:
          s.bot_channel_connection_id == ^connection.id and s.bot_user_id == ^user.id and
            is_nil(s.completed_at),
        limit: 1

    case Repo.one(query) do
      nil -> %BotSession{} |> BotSession.changeset(attrs) |> Repo.insert!()
      session -> session |> BotSession.changeset(attrs) |> Repo.update!()
    end
  end

  defp save_event(event, connection, session) do
    %BotEvent{}
    |> BotEvent.changeset(%{
      bot_session_id: session.id,
      bot_channel_connection_id: connection.id,
      flow_id: event["flow_id"],
      node_id: event["node_id"],
      event_type: event["event_type"],
      payload: %{}
    })
    |> Repo.insert!()
  end

  defp save_outbox(output, connection, key) do
    %OutboxMessage{}
    |> OutboxMessage.changeset(%{
      bot_channel_connection_id: connection.id,
      channel: connection.channel,
      external_id: output["external_id"],
      idempotency_key: key,
      payload: output,
      status: "pending"
    })
    |> Repo.insert!(on_conflict: :nothing)
  end

  defp mark_processing(event) do
    event
    |> InboxEvent.changeset(%{status: "processing", attempts: event.attempts + 1})
    |> Repo.update!()
  end

  defp fail_inbox(event, reason) do
    event
    |> InboxEvent.changeset(%{
      status: "failed",
      last_error: reason,
      next_retry_at: retry_at(event.attempts)
    })
    |> Repo.update!()
  end

  defp fail_outbox(message, reason) do
    message
    |> OutboxMessage.changeset(%{
      status: "failed",
      last_error: reason,
      next_retry_at: retry_at(message.attempts)
    })
    |> Repo.update!()
  end

  defp retry_at(attempts),
    do:
      DateTime.utc_now()
      |> DateTime.add(min(60, attempts + 1), :second)
      |> DateTime.truncate(:second)

  defp trigger_to_map(trigger) do
    %{
      "id" => to_string(trigger.id),
      "name" => trigger.name,
      "channel" => trigger.channel,
      "type" => trigger.type,
      "match" => trigger.match,
      "start_node_id" => trigger.start_node_id,
      "session_mode" => trigger.session_mode,
      "priority" => trigger.priority,
      "enabled" => trigger.enabled
    }
  end

  defp to_core_trigger(trigger), do: trigger_to_map(trigger)

  defp to_core_session(session) do
    %{
      id: session.id,
      channel: nil,
      external_id: nil,
      flow_id: session.flow_id,
      flow_version: session.flow_version,
      current_node_id: session.current_node_id,
      context: session.context || %{},
      completed: false
    }
  end

  defp hash(term),
    do: :crypto.hash(:sha256, :erlang.term_to_binary(term)) |> Base.encode16(case: :lower)
end
