defmodule BotMachine.BotCore.RunnerTest do
  use ExUnit.Case, async: true

  alias BotMachine.BotCore.Runner

  test "runs photo booth edit flow" do
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
    assert fourth.session.completed
    assert fourth.session.context["generation_title"] == "Редактирование фото"
    assert fourth.session.context["generation_prompt"] == "Добавь кинематографичный свет"

    assert Enum.map(fourth.outputs, & &1["text"]) == [
             "✨ Заявка подготовлена: Редактирование фото.\nГенерацию через fal.ai подключим следующим шагом."
           ]
  end

  defp input(text),
    do: %{"kind" => "user_message", "channel" => "echo", "external_id" => "1", "text" => text}

  defp photo_input(url),
    do: Map.put(input(""), "attachments", [%{"type" => "photo", "url" => url}])
end
