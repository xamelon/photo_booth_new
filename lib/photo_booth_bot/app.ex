defmodule PhotoBoothBot do
  alias BotMachine.BotCore.Registry

  def registry do
    Registry.new()
    |> Registry.action("remember_name", fn ctx, _params ->
      name = ctx.session.context["name"] || "друг"

      %{
        context:
          Map.merge(ctx.session.context, %{"name" => name, "greeting" => "Привет, #{name}"})
      }
    end)
    |> Registry.action("apply_mood", fn ctx, params ->
      mood = params["mood"] || ctx.session.context["mood"] || "curious"
      points = if mood == "hungry", do: 5, else: 2

      %{
        context:
          Map.merge(ctx.session.context, %{
            "mood" => mood,
            "points" => points,
            "premium" => points >= 5
          })
      }
    end)
    |> Registry.action("build_summary", fn ctx, _params ->
      summary = "#{ctx.session.context["name"]}: #{ctx.session.context["points"]} pts"
      %{context: Map.put(ctx.session.context, "summary", summary)}
    end)
  end

  def flow do
    %{
      "id" => "demo",
      "version" => 2,
      "start_node_id" => "welcome",
      "nodes" => [
        %{
          "id" => "welcome",
          "type" => "message",
          "text" => "Привет. Я demo bot-machine 🤖\nСоберём мини-профиль?",
          "keyboard_mode" => "reply",
          "button_rows" => [
            [
              %{"label" => "Погнали", "payload" => "start_profile", "to" => "ask_name"},
              %{"label" => "Что умеешь?", "payload" => "help", "to" => "help"}
            ]
          ]
        },
        %{
          "id" => "help",
          "type" => "message",
          "text" =>
            "Я показываю message/input/action/condition, кнопки, context и ветки. Теперь давай имя.",
          "next" => "ask_name"
        },
        %{
          "id" => "ask_name",
          "type" => "input",
          "input_key" => "name",
          "prompt" => "Как тебя зовут?",
          "next" => "remember_name"
        },
        %{
          "id" => "remember_name",
          "type" => "action",
          "action" => "remember_name",
          "next" => "choose_mood"
        },
        %{
          "id" => "choose_mood",
          "type" => "message",
          "text" => "{{greeting}}. Что сейчас ближе?",
          "keyboard_mode" => "reply",
          "button_rows" => [
            [
              %{"label" => "Хочу пиццу 🍕", "payload" => "hungry", "to" => "save_hungry"},
              %{"label" => "Просто смотрю 👀", "payload" => "curious", "to" => "save_curious"}
            ]
          ]
        },
        %{
          "id" => "save_hungry",
          "type" => "action",
          "action" => "apply_mood",
          "params" => %{"mood" => "hungry"},
          "next" => "premium_check"
        },
        %{
          "id" => "save_curious",
          "type" => "action",
          "action" => "apply_mood",
          "params" => %{"mood" => "curious"},
          "next" => "premium_check"
        },
        %{
          "id" => "premium_check",
          "type" => "condition",
          "branches" => [
            %{
              "when" => %{"op" => "equals", "path" => "premium", "value" => true},
              "to" => "premium_offer"
            }
          ],
          "default" => "regular_offer"
        },
        %{
          "id" => "premium_offer",
          "type" => "message",
          "text" => "О, голодный режим. Держи +5 demo points и быстрый путь к купону.",
          "next" => "summary"
        },
        %{
          "id" => "regular_offer",
          "type" => "message",
          "text" => "Ок, спокойный режим. Держи +2 demo points и обзор сценария.",
          "next" => "summary"
        },
        %{
          "id" => "summary",
          "type" => "action",
          "action" => "build_summary",
          "next" => "done_message"
        },
        %{
          "id" => "done_message",
          "type" => "message",
          "text" =>
            "Готово: {{summary}}\nКонтекст сохранился в session. Viewer покажет, где ты прошёл.",
          "next" => "end"
        },
        %{"id" => "end", "type" => "end"}
      ]
    }
  end
end
