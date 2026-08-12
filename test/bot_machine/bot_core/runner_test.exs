defmodule BotMachine.BotCore.RunnerTest do
  use ExUnit.Case, async: true

  alias BotMachine.BotCore.Runner

  test "runs buttons, input, actions, condition, end" do
    flow = PhotoBoothBot.flow()
    registry = PhotoBoothBot.registry()

    first = Runner.run(flow, input("/start"), registry)

    assert Enum.map(first.outputs, & &1["text"]) == [
             "Привет. Я demo bot-machine 🤖\nСоберём мини-профиль?"
           ]

    assert first.session.current_node_id == "welcome"

    second = Runner.run(flow, input("Погнали"), registry, first.session)
    assert Enum.map(second.outputs, & &1["text"]) == ["Как тебя зовут?"]
    assert second.session.current_node_id == "ask_name"

    third = Runner.run(flow, input("Аня"), registry, second.session)
    assert Enum.map(third.outputs, & &1["text"]) == ["Привет, Аня. Что сейчас ближе?"]
    assert third.session.context["name"] == "Аня"
    assert third.session.current_node_id == "choose_mood"

    fourth = Runner.run(flow, input("Хочу пиццу 🍕"), registry, third.session)
    assert fourth.session.completed
    assert fourth.session.context["points"] == 5

    assert Enum.map(fourth.outputs, & &1["text"]) == [
             "О, голодный режим. Держи +5 demo points и быстрый путь к купону.",
             "Готово: Аня: 5 pts\nКонтекст сохранился в session. Viewer покажет, где ты прошёл."
           ]
  end

  defp input(text),
    do: %{"kind" => "user_message", "channel" => "echo", "external_id" => "1", "text" => text}
end
