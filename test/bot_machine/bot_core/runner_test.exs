defmodule BotMachine.BotCore.RunnerTest do
  use BotMachine.DataCase

  alias BotMachine.BotCore.Runner
  alias BotMachine.BotRuntime
  alias PhotoBoothBot.{Balance, GenerationJob}

  test "runs photo booth edit flow until generation wait" do
    flow = PhotoBoothBot.flow()
    registry = PhotoBoothBot.registry()

    first = Runner.run(flow, input("/start"), registry)

    assert Enum.map(first.outputs, & &1["text"]) == [
             "👋 Я помогу отредактировать фото, сделать открытку на день рождения или восстановить старое фото. Выберите действие ниже."
           ]

    second = Runner.run(flow, input("✏️ Отредактировать фото"), registry, first.session)

    assert Enum.map(second.outputs, & &1["text"]) == [
             "🖼️ Пришлите фотографию, которую хотите отредактировать."
           ]

    third =
      Runner.run(flow, photo_input("https://example.com/photo.jpg"), registry, second.session)

    assert Enum.map(third.outputs, & &1["text"]) == [
             "📸 Фото получила. Теперь напишите, как хотите его отредактировать."
           ]

    assert third.session.context["photo_url"] == "https://example.com/photo.jpg"

    fourth = Runner.run(flow, input("Добавь кинематографичный свет"), registry, third.session)
    refute fourth.session.completed
    assert fourth.session.current_node_id == "generation_accepted"
    assert fourth.session.context["generation_title"] == "Редактирование фото"
    assert fourth.session.context["generation_prompt"] == "Добавь кинематографичный свет"

    assert Enum.map(fourth.outputs, & &1["text"]) == [
             "✨ Приняла заявку: Редактирование фото. Запускаю генерацию."
           ]

    assert fourth.session.context["photo_balance"] == 0

    assert Repo.get!(GenerationJob, fourth.session.context["generation_job_id"]).status ==
             "pending"
  end

  test "photo booth generation pauses for payment when balance is empty" do
    flow = PhotoBoothBot.flow()
    registry = PhotoBoothBot.registry()
    connection = BotRuntime.default_connection("echo")

    %Balance{}
    |> Balance.changeset(%{
      bot_channel_connection_id: connection.id,
      channel: "echo",
      external_id: "1",
      photos_remaining: 0,
      photos_spent: 1
    })
    |> Repo.insert!()

    session = %{
      channel: "echo",
      external_id: "1",
      flow_id: "photo_booth",
      flow_version: 9,
      current_node_id: "generation_wait",
      context: %{
        "generation_mode" => "edit",
        "generation_title" => "Редактирование фото",
        "photo_url" => "https://example.com/photo.jpg",
        "generation_prompt" => "test"
      },
      completed: false
    }

    result = Runner.run(flow, input(""), registry, session)

    refute result.session.completed
    assert result.session.current_node_id == "balance_message"
    assert result.session.context["photo_balance"] == 0
    assert result.session.context["resume_after_payment"] == "generation_wait"

    assert Enum.map(result.outputs, & &1["text"]) == [
             "💸 На балансе нет доступных фото. Пополните баланс — после оплаты я сразу продолжу обработку.",
             "💰 Баланс: 0 фото. Каждая генерация списывает 1 фото. Выберите пакет для пополнения."
           ]

    assert Repo.aggregate(GenerationJob, :count) == 0
  end

  test "photo input retry output does not require next node" do
    flow = PhotoBoothBot.flow()
    registry = PhotoBoothBot.registry()

    session = %{
      channel: "echo",
      external_id: "1",
      flow_id: "photo_booth",
      flow_version: 9,
      current_node_id: "ask_edit_photo",
      context: %{},
      completed: false
    }

    result = Runner.run(flow, input("not a photo"), registry, session)

    assert result.session.current_node_id == "ask_edit_photo"

    assert [%{"text" => "📷 Нужна именно фотография. Пришлите её следующим сообщением."}] =
             result.outputs
  end

  test "notify-only generation event sends result and preserves parked node" do
    flow = PhotoBoothBot.flow()
    registry = PhotoBoothBot.registry()

    session = %{
      channel: "echo",
      external_id: "1",
      flow_id: "photo_booth",
      flow_version: 9,
      current_node_id: "ask_edit_prompt",
      context: %{"edit_prompt" => "old draft"},
      completed: false
    }

    trigger = %{
      "start_node_id" => "act_generation_completed_notify",
      "session_mode" => "notify_only"
    }

    result =
      Runner.run(
        flow,
        domain_event_input("photo_generation.completed", %{
          "generation_job_id" => 123,
          "image_url" => "https://example.com/result.jpg"
        }),
        registry,
        session,
        trigger
      )

    assert result.session.current_node_id == "ask_edit_prompt"
    refute result.session.completed

    assert [output] = result.outputs
    assert output["text"] == "✨ Фото готово!"

    assert output["attachments"] == [
             %{"type" => "photo", "url" => "https://example.com/result.jpg"}
           ]

    assert output["button_rows"] != []
  end

  test "payment event resumes parked generation" do
    flow = PhotoBoothBot.flow()
    registry = PhotoBoothBot.registry()
    connection = BotRuntime.default_connection("echo")

    %Balance{}
    |> Balance.changeset(%{
      bot_channel_connection_id: connection.id,
      channel: "echo",
      external_id: "1",
      photos_remaining: 1,
      photos_spent: 1
    })
    |> Repo.insert!()

    session = %{
      channel: "echo",
      external_id: "1",
      flow_id: "photo_booth",
      flow_version: 9,
      current_node_id: "payment_created",
      context: %{
        "resume_after_payment" => "generation_wait",
        "generation_mode" => "edit",
        "generation_title" => "Редактирование фото",
        "photo_url" => "https://example.com/photo.jpg",
        "generation_prompt" => "test"
      },
      completed: false
    }

    trigger = %{
      "start_node_id" => "act_payment_succeeded",
      "session_mode" => "start_or_jump"
    }

    result =
      Runner.run(
        flow,
        domain_event_input("payment.yookassa.succeeded", %{
          "payment_id" => "pay-1",
          "credited_photos" => 1,
          "photo_balance" => 1
        }),
        registry,
        session,
        trigger
      )

    refute result.session.completed
    assert result.session.current_node_id == "generation_accepted"
    assert result.session.context["photo_balance"] == 0
    refute Map.has_key?(result.session.context, "resume_after_payment")
    refute Map.has_key?(result.session.context, "payment_id")

    assert Repo.get!(GenerationJob, result.session.context["generation_job_id"]).status ==
             "pending"

    assert Enum.map(result.outputs, & &1["text"]) == [
             "✨ Оплата прошла успешно. Добавила 1 фото. Сейчас на балансе: 1. Продолжаю обработку.",
             "✨ Приняла заявку: Редактирование фото. Запускаю генерацию."
           ]
  end

  test "payment event without parked generation sends credited balance" do
    flow = PhotoBoothBot.flow()
    registry = PhotoBoothBot.registry()

    session = %{
      channel: "echo",
      external_id: "1",
      flow_id: "photo_booth",
      flow_version: 9,
      current_node_id: "payment_created",
      context: %{},
      completed: false
    }

    trigger = %{
      "start_node_id" => "act_payment_succeeded",
      "session_mode" => "start_or_jump"
    }

    result =
      Runner.run(
        flow,
        domain_event_input("payment.yookassa.succeeded", %{
          "payment_id" => "pay-1",
          "credited_photos" => 3,
          "photo_balance" => 4
        }),
        registry,
        session,
        trigger
      )

    refute result.session.completed
    assert result.session.current_node_id == "payment_success_notify"
    assert [%{"text" => text}] = result.outputs
    assert text == "✨ Оплата прошла успешно. Добавила 3 фото. Сейчас на балансе: 4."
  end

  defp input(text),
    do: %{"kind" => "user_message", "channel" => "echo", "external_id" => "1", "text" => text}

  defp photo_input(url),
    do: Map.put(input(""), "attachments", [%{"type" => "photo", "url" => url}])

  defp domain_event_input(event, payload),
    do:
      input("")
      |> Map.merge(%{
        "kind" => "domain_event",
        "event" => event,
        "payload" => payload
      })
end
