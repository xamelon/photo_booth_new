defmodule BotMachine.BotRuntime do
  import Ecto.Query

  alias BotMachine.Repo
  alias BotMachine.BotCore.{Runner, TriggerMatcher, Validator}

  alias BotMachine.BotRuntime.{
    BotEvent,
    BotFlow,
    BotFlowVersion,
    BotSession,
    BotTrigger,
    BotUser,
    Channels,
    InboxEvent,
    OutboxMessage
  }

  def enqueue_inbox(input, idempotency_key \\ nil) do
    attrs = %{
      channel: input["channel"],
      external_id: input["external_id"],
      idempotency_key: idempotency_key || hash(input),
      payload: input,
      status: "pending"
    }

    %InboxEvent{}
    |> InboxEvent.changeset(attrs)
    |> Repo.insert(on_conflict: :nothing)
  end

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
      outbox: Repo.aggregate(OutboxMessage, :count),
      events: Repo.aggregate(BotEvent, :count),
      flows: Repo.aggregate(BotFlow, :count),
      triggers: Repo.aggregate(BotTrigger, :count)
    }
  end

  def list_users do
    Repo.all(
      from u in BotUser,
        left_join: s in BotSession,
        on: s.bot_user_id == u.id,
        group_by: u.id,
        order_by: [desc: max(s.updated_at), desc: u.updated_at],
        limit: 100,
        select: %{
          id: u.id,
          channel: u.channel,
          external_id: u.external_id,
          display_name: u.display_name,
          blocked_at: u.blocked_at,
          inserted_at: u.inserted_at,
          updated_at: u.updated_at,
          sessions_count: count(s.id),
          last_seen_at: max(s.updated_at)
        }
    )
    |> Enum.map(&Map.put(&1, :active_session, active_session_for_user(&1.id)))
  end

  def get_user_detail(id) do
    user = Repo.get(BotUser, id)

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
            where: e.channel == ^user.channel and e.external_id == ^user.external_id,
            order_by: [desc: e.inserted_at],
            limit: 30
        )

      outbox =
        Repo.all(
          from m in OutboxMessage,
            where: m.channel == ^user.channel and m.external_id == ^user.external_id,
            order_by: [desc: m.inserted_at],
            limit: 30
        )

      %{user: user, sessions: sessions, inbox: inbox, outbox: outbox}
    end
  end

  def list_sessions,
    do:
      Repo.all(
        from s in BotSession,
          join: u in assoc(s, :bot_user),
          preload: [bot_user: u],
          order_by: [desc: s.updated_at],
          limit: 50
      )

  def list_inbox, do: Repo.all(from e in InboxEvent, order_by: [desc: e.inserted_at], limit: 50)

  def list_outbox,
    do: Repo.all(from m in OutboxMessage, order_by: [desc: m.inserted_at], limit: 50)

  def list_events, do: Repo.all(from e in BotEvent, order_by: [desc: e.inserted_at], limit: 100)

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

  def save_flow_definition(%BotFlowVersion{} = version, definition) do
    issues = Validator.validate(definition, BotMachine.ExampleBot.registry())

    if issues == [] do
      version
      |> BotFlowVersion.changeset(%{definition: definition})
      |> Repo.update()
    else
      {:error, issues}
    end
  end

  def sandbox_state(channel \\ "echo", external_id \\ "sandbox") do
    user = Repo.get_by(BotUser, channel: channel, external_id: external_id)

    inbox =
      Repo.all(
        from e in InboxEvent,
          where: e.channel == ^channel and e.external_id == ^external_id,
          order_by: [asc: e.inserted_at]
      )

    outbox =
      Repo.all(
        from m in OutboxMessage,
          where: m.channel == ^channel and m.external_id == ^external_id,
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
    if user = Repo.get_by(BotUser, channel: channel, external_id: external_id),
      do: Repo.delete!(user)

    Repo.delete_all(
      from e in InboxEvent, where: e.channel == ^channel and e.external_id == ^external_id
    )

    Repo.delete_all(
      from m in OutboxMessage, where: m.channel == ^channel and m.external_id == ^external_id
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
      input = event.payload
      user = get_or_create_user(input)
      session = active_session(user)
      trigger = find_trigger(input)
      version = flow_version!(session, trigger)

      result =
        Runner.run(
          version.definition,
          input,
          BotMachine.ExampleBot.registry(),
          session && to_core_session(session),
          trigger && to_core_trigger(trigger)
        )

      session = save_session(user, result.session)

      Enum.each(result.events, &save_event(&1, session))
      Enum.with_index(result.outputs, &save_outbox(&1, "#{event.idempotency_key}:out:#{&2}"))

      event
      |> InboxEvent.changeset(%{
        status: "processed",
        processed_at: DateTime.utc_now() |> DateTime.truncate(:second),
        last_error: nil
      })
      |> Repo.update!()
    end)
  rescue
    error -> fail_inbox(event, Exception.message(error))
  end

  defp deliver_outbox(message) do
    message =
      message
      |> OutboxMessage.changeset(%{status: "processing", attempts: message.attempts + 1})
      |> Repo.update!()

    case Channels.send(message.channel, Map.put(message.payload, "_outbox_id", message.id)) do
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

  defp get_or_create_user(input) do
    Repo.get_by(BotUser, channel: input["channel"], external_id: input["external_id"]) ||
      %BotUser{}
      |> BotUser.changeset(%{
        channel: input["channel"],
        external_id: input["external_id"],
        display_name: input["display_name"]
      })
      |> Repo.insert!()
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

  defp find_trigger(input) do
    triggers =
      Repo.all(
        from t in BotTrigger,
          where: t.channel == ^input["channel"] and t.enabled == true,
          order_by: [desc: t.priority]
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

  defp active_session(user) do
    Repo.one(
      from s in BotSession,
        where: s.bot_user_id == ^user.id and is_nil(s.completed_at),
        order_by: [desc: s.updated_at],
        limit: 1
    )
  end

  defp save_session(user, state) do
    attrs = %{
      bot_user_id: user.id,
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
          s.bot_user_id == ^user.id and s.flow_id == ^state.flow_id and is_nil(s.completed_at),
        limit: 1

    case Repo.one(query) do
      nil -> %BotSession{} |> BotSession.changeset(attrs) |> Repo.insert!()
      session -> session |> BotSession.changeset(attrs) |> Repo.update!()
    end
  end

  defp save_event(event, session) do
    %BotEvent{}
    |> BotEvent.changeset(%{
      bot_session_id: session.id,
      flow_id: event["flow_id"],
      node_id: event["node_id"],
      event_type: event["event_type"],
      payload: %{}
    })
    |> Repo.insert!()
  end

  defp save_outbox(output, key) do
    %OutboxMessage{}
    |> OutboxMessage.changeset(%{
      channel: output["channel"],
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
