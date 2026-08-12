defmodule PhotoBoothBot do
  alias BotMachine.BotCore.{Registry, Renderer}

  @menu_buttons [
    [
      %{"label" => "✏️ Отредактировать фото", "payload" => "edit_photo", "to" => "ask_edit_photo"},
      %{
        "label" => "🎂 Открытка на день рождения",
        "payload" => "birthday_postcard",
        "to" => "ask_birthday_photo"
      }
    ],
    [
      %{
        "label" => "🧩 Реставрация фото",
        "payload" => "photo_restoration",
        "to" => "ask_restore_photo"
      },
      %{
        "label" => "🎁 Как получить фото бесплатно",
        "payload" => "free_photos",
        "to" => "free_photos"
      }
    ],
    [%{"label" => "💰 Баланс", "payload" => "balance", "to" => "balance"}]
  ]

  def registry do
    Registry.new()
    |> Registry.node("photo_input", &photo_input_enter/2, &photo_input_receive/2)
    |> Registry.action("prepare_generation", &prepare_generation/2)
  end

  def flow do
    %{
      "id" => "photo_booth",
      "version" => 3,
      "start_node_id" => "welcome",
      "nodes" => [
        %{
          "id" => "welcome",
          "type" => "message",
          "text" =>
            "👋 Я помогу отредактировать фото, сделать открытку на день рождения или восстановить старое фото. Выберите действие ниже.",
          "keyboard_mode" => "reply",
          "button_rows" => @menu_buttons
        },
        %{
          "id" => "ask_edit_photo",
          "type" => "photo_input",
          "input_key" => "photo_url",
          "prompt" => "🖼️ Пришлите фотографию, которую хотите отредактировать.",
          "next" => "ask_edit_prompt"
        },
        %{
          "id" => "ask_edit_prompt",
          "type" => "input",
          "input_key" => "edit_prompt",
          "prompt" => "📸 Фото получила. Теперь напишите, как хотите его отредактировать.",
          "next" => "prepare_edit"
        },
        %{
          "id" => "prepare_edit",
          "type" => "action",
          "action" => "prepare_generation",
          "params" => %{
            "mode" => "edit",
            "title" => "Редактирование фото",
            "prompt_key" => "edit_prompt"
          },
          "next" => "generation_stub"
        },
        %{
          "id" => "ask_birthday_photo",
          "type" => "photo_input",
          "input_key" => "photo_url",
          "prompt" => "🎉 Пришлите фотографию, и я сделаю из неё открытку на день рождения.",
          "next" => "prepare_birthday"
        },
        %{
          "id" => "prepare_birthday",
          "type" => "action",
          "action" => "prepare_generation",
          "params" => %{
            "mode" => "postcard",
            "title" => "Открытка на день рождения",
            "prompt" =>
              "СТРОГО: сохрани лица 1:1. Преврати это фото в праздничную открытку на день рождения. Добавь мягкий теплый свет, воздушные шары, конфетти, аккуратные праздничные декоративные элементы и нарядный фон. Без текста на изображении."
          },
          "next" => "generation_stub"
        },
        %{
          "id" => "ask_restore_photo",
          "type" => "photo_input",
          "input_key" => "photo_url",
          "prompt" =>
            "🧩 Пришлите старую или повреждённую фотографию, и я постараюсь её восстановить.",
          "next" => "prepare_restore"
        },
        %{
          "id" => "prepare_restore",
          "type" => "action",
          "action" => "prepare_generation",
          "params" => %{
            "mode" => "restoration",
            "title" => "Реставрация фото",
            "prompt" => "Сделай фото цветным. Убери все повреждения"
          },
          "next" => "generation_stub"
        },
        %{
          "id" => "generation_stub",
          "type" => "message",
          "text" =>
            "✨ Заявка подготовлена: {{generation_title}}.\nГенерацию через fal.ai подключим следующим шагом.",
          "keyboard_mode" => "reply",
          "button_rows" => @menu_buttons,
          "next" => "end"
        },
        %{
          "id" => "free_photos",
          "type" => "message",
          "text" =>
            "🎁 Бесплатные фото будут через реферальную программу: друг перейдёт по вашей ссылке и впервые оплатит пакет — вы оба получите по 1 фото. Подключим после баланса и оплат.",
          "keyboard_mode" => "reply",
          "button_rows" => @menu_buttons,
          "next" => "end"
        },
        %{
          "id" => "balance",
          "type" => "message",
          "text" =>
            "💰 Баланс и пакеты подключим вместе с оплатой. Пока можно протестировать основной фото-flow.",
          "keyboard_mode" => "reply",
          "button_rows" => @menu_buttons,
          "next" => "end"
        },
        %{"id" => "end", "type" => "end"}
      ]
    }
  end

  defp photo_input_enter(%{input: input, session: session}, node) do
    %{
      outputs: [
        %{
          "type" => "message",
          "channel" => input["channel"],
          "external_id" => input["external_id"],
          "text" => Renderer.render(node["prompt"] || "Пришлите фотографию.", session.context),
          "buttons" => [],
          "keyboard_mode" => "inline",
          "buttons_per_row" => 3
        }
      ]
    }
  end

  defp photo_input_receive(%{input: input, session: session}, node) do
    case first_photo(input) do
      nil ->
        %{
          outputs: [
            %{
              "type" => "message",
              "channel" => input["channel"],
              "external_id" => input["external_id"],
              "text" => "📷 Нужна именно фотография. Пришлите её следующим сообщением.",
              "buttons" => [],
              "keyboard_mode" => "inline",
              "buttons_per_row" => 3
            }
          ]
        }

      photo ->
        %{
          context: Map.put(session.context, node["input_key"], photo),
          next_node_id: node["next"]
        }
    end
  end

  defp first_photo(input) do
    input
    |> Map.get("attachments", [])
    |> Enum.find_value(fn
      %{"type" => "photo", "url" => url} when is_binary(url) and url != "" -> url
      %{"type" => "photo", "ref" => ref} when is_binary(ref) and ref != "" -> ref
      url when is_binary(url) and url != "" -> url
      _ -> nil
    end)
  end

  defp prepare_generation(%{session: session}, params) do
    prompt = params["prompt"] || session.context[params["prompt_key"]]

    %{
      context:
        Map.merge(session.context, %{
          "generation_mode" => params["mode"],
          "generation_title" => params["title"],
          "generation_prompt" => prompt
        })
    }
  end
end
