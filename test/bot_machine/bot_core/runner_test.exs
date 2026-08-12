defmodule BotMachine.BotCore.RunnerTest do
  use BotMachine.DataCase

  alias BotMachine.BotCore.Runner
  alias PhotoBoothBot.GenerationJob

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
    assert fourth.session.current_node_id == "generation_wait"
    assert fourth.session.context["generation_title"] == "Редактирование фото"
    assert fourth.session.context["generation_prompt"] == "Добавь кинематографичный свет"

    assert Enum.map(fourth.outputs, & &1["text"]) == [
             "✨ Приняла заявку: Редактирование фото. Запускаю генерацию."
           ]

    assert Repo.get!(GenerationJob, fourth.session.context["generation_job_id"]).status ==
             "pending"
  end

  test "generation wait handles completed event" do
    flow = PhotoBoothBot.flow()
    registry = PhotoBoothBot.registry()

    session = %{
      channel: "echo",
      external_id: "1",
      flow_id: "photo_booth",
      flow_version: 5,
      current_node_id: "generation_wait",
      context: %{},
      completed: false
    }

    result =
      Runner.run(flow, generation_done_input("https://example.com/result.jpg"), registry, session)

    assert result.session.completed
    assert [%{"attachments" => [%{"url" => "https://example.com/result.jpg"}]}] = result.outputs
  end

  defp input(text),
    do: %{"kind" => "user_message", "channel" => "echo", "external_id" => "1", "text" => text}

  defp photo_input(url),
    do: Map.put(input(""), "attachments", [%{"type" => "photo", "url" => url}])

  defp generation_done_input(url),
    do:
      input("")
      |> Map.merge(%{
        "kind" => "system_event",
        "event_type" => "photo_generation_completed",
        "image_url" => url
      })
end
