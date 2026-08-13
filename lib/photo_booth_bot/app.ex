defmodule PhotoBoothBot do
  alias BotMachine.BotCore.Registry
  alias BotMachine.BotRuntime
  alias BotMachine.Repo
  alias PhotoBoothBot.{Balance, GenerationJob}

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
    |> Registry.node("generation_wait", &generation_wait_enter/2)
    |> Registry.action("prepare_generation", &prepare_generation/2)
    |> Registry.action("prepare_generation_result", &prepare_generation_result/2)
    |> Registry.action("prepare_balance", &prepare_balance/2)
  end

  def flow do
    %{
      "id" => "photo_booth",
      "version" => 7,
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
          "type" => "input",
          "input_type" => "photo",
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
          "next" => "generation_wait"
        },
        %{
          "id" => "ask_birthday_photo",
          "type" => "input",
          "input_type" => "photo",
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
          "next" => "generation_wait"
        },
        %{
          "id" => "ask_restore_photo",
          "type" => "input",
          "input_type" => "photo",
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
          "next" => "generation_wait"
        },
        %{
          "id" => "generation_wait",
          "type" => "generation_wait",
          "next" => "generation_accepted"
        },
        %{
          "id" => "generation_accepted",
          "type" => "message",
          "text" => "✨ Приняла заявку: {{generation_title}}. Запускаю генерацию."
        },
        %{
          "id" => "generation_no_balance",
          "type" => "message",
          "text" =>
            "💸 На балансе нет доступных фото. Скоро подключим оплату, а пока можно получить бесплатное фото через реферальную программу.",
          "keyboard_mode" => "reply",
          "button_rows" => @menu_buttons,
          "next" => "end"
        },
        %{
          "id" => "act_generation_completed_notify",
          "type" => "action",
          "action" => "prepare_generation_result",
          "next" => "generation_completed_notify"
        },
        %{
          "id" => "generation_completed_notify",
          "type" => "message",
          "text" => "✨ Фото готово!",
          "attachments" => [%{"type" => "photo", "url" => "{{generation_result_url}}"}],
          "keyboard_mode" => "reply",
          "button_rows" => @menu_buttons,
          "buttons_per_row" => 2
        },
        %{
          "id" => "act_generation_failed_notify",
          "type" => "action",
          "action" => "prepare_generation_result",
          "next" => "generation_failed_notify"
        },
        %{
          "id" => "generation_failed_notify",
          "type" => "message",
          "text" => "😔 Не получилось сгенерировать фото. Попробуйте ещё раз.",
          "keyboard_mode" => "reply",
          "button_rows" => @menu_buttons,
          "buttons_per_row" => 2
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
          "type" => "action",
          "action" => "prepare_balance",
          "next" => "balance_message"
        },
        %{
          "id" => "balance_message",
          "type" => "message",
          "text" =>
            "💰 Баланс: {{photo_balance}} фото. Каждая генерация списывает 1 фото. Оплату подключим следующим шагом.",
          "keyboard_mode" => "reply",
          "button_rows" => @menu_buttons,
          "next" => "end"
        },
        %{"id" => "end", "type" => "end"}
      ]
    }
  end

  defp generation_wait_enter(%{input: input, session: session}, node) do
    connection_id = connection_id(input)

    case Balance.debit_photo(connection_id, input["channel"], input["external_id"]) do
      {:ok, balance} ->
        job =
          %GenerationJob{}
          |> GenerationJob.changeset(%{
            bot_channel_connection_id: connection_id,
            channel: input["channel"],
            external_id: input["external_id"],
            status: "pending",
            mode: session.context["generation_mode"],
            title: session.context["generation_title"],
            photo_url: session.context["photo_url"],
            prompt: session.context["generation_prompt"]
          })
          |> Repo.insert!()

        %{
          context:
            Map.merge(session.context, %{
              "generation_job_id" => job.id,
              "photo_balance" => balance.photos_remaining
            }),
          next_node_id: node["next"]
        }

      {:error, :insufficient_balance} ->
        balance = Balance.get_or_create(connection_id, input["channel"], input["external_id"])

        %{
          context: Map.put(session.context, "photo_balance", balance.photos_remaining),
          next_node_id: "generation_no_balance"
        }
    end
  end

  defp connection_id(input),
    do: input["bot_channel_connection_id"] || BotRuntime.default_connection(input["channel"]).id

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

  defp prepare_balance(%{input: input, session: session}, _params) do
    balance =
      input
      |> connection_id()
      |> Balance.get_or_create(input["channel"], input["external_id"])

    %{context: Map.put(session.context, "photo_balance", balance.photos_remaining)}
  end

  defp prepare_generation_result(%{input: input, session: session}, _params) do
    payload = input["payload"] || %{}

    %{
      context:
        Map.merge(session.context, %{
          "generation_job_id" => payload["generation_job_id"] || input["generation_job_id"],
          "generation_result_url" => payload["image_url"] || input["image_url"],
          "generation_error" => payload["error"] || input["error"]
        })
    }
  end
end
