defmodule BotMachine.BotRuntime.Channels.Telegram do
  alias BotMachine.BotRuntime.Credentials

  @api_url "https://api.telegram.org"

  def parse_inbound(%{"update_id" => update_id, "message" => message}) do
    chat_id = get_in(message, ["chat", "id"])

    if chat_id do
      %{
        idempotency_key: "telegram:#{update_id}",
        input: %{
          "kind" => "user_message",
          "channel" => "telegram",
          "external_id" => to_string(chat_id),
          "text" =>
            blank_to_nil(String.trim(to_string(message["text"] || message["caption"] || ""))),
          "payload" => nil,
          "attachments" => normalize_attachments(message)
        }
      }
    end
  end

  def parse_inbound(%{"update_id" => update_id, "callback_query" => callback}) do
    chat_id = get_in(callback, ["message", "chat", "id"])

    if chat_id do
      %{
        idempotency_key: "telegram:#{update_id}",
        input: %{
          "kind" => "user_message",
          "channel" => "telegram",
          "external_id" => to_string(chat_id),
          "text" => callback["data"] || "",
          "payload" => parse_payload(callback["data"]),
          "attachments" => []
        }
      }
    end
  end

  def parse_inbound(_), do: nil

  def send(connection, payload) do
    token = token(connection)

    cond do
      token in [nil, ""] ->
        {:error, "Telegram credentials are not configured"}

      photo = first_photo(payload["attachments"] || []) ->
        post(token, "sendPhoto", %{
          "chat_id" => payload["external_id"],
          "photo" => photo,
          "caption" => payload["text"] || "",
          "reply_markup" => keyboard(payload)
        })

      true ->
        post(token, "sendMessage", %{
          "chat_id" => payload["external_id"],
          "text" => payload["text"] || "",
          "reply_markup" => keyboard(payload)
        })
    end
  end

  def file_url(file_id, connection) do
    token = token(connection)

    with true <- token not in [nil, ""],
         {:ok, %{"file_path" => path}} <- get_file(token, file_id) do
      @api_url <> "/file/bot" <> token <> "/" <> path
    else
      _ -> nil
    end
  end

  defp get_file(token, file_id) do
    case Req.get(@api_url <> "/bot" <> token <> "/getFile", params: %{"file_id" => file_id}) do
      {:ok, %{status: status, body: %{"ok" => true, "result" => result}}}
      when status in 200..299 ->
        {:ok, result}

      _ ->
        :error
    end
  end

  defp post(token, method, payload) do
    payload = Enum.reject(payload, fn {_key, value} -> value in [nil, ""] end) |> Map.new()

    case Req.post(@api_url <> "/bot" <> token <> "/" <> method, json: payload) do
      {:ok, %{status: status, body: %{"ok" => true, "result" => result}}}
      when status in 200..299 ->
        {:ok, to_string(result["message_id"] || System.unique_integer([:positive]))}

      {:ok, %{status: status, body: body}} ->
        {:error, "Telegram HTTP #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, Exception.message(reason)}
    end
  end

  defp normalize_attachments(%{"photo" => photos}) when is_list(photos) do
    photos
    |> Enum.max_by(&(&1["file_size"] || 0), fn -> nil end)
    |> case do
      %{"file_id" => file_id} -> [%{"type" => "photo", "ref" => file_id}]
      _ -> []
    end
  end

  defp normalize_attachments(_), do: []

  defp first_photo(attachments) do
    Enum.find_value(attachments, fn
      %{"type" => "photo", "url" => url} when is_binary(url) and url != "" -> url
      %{"type" => "photo", "ref" => ref} when is_binary(ref) and ref != "" -> ref
      _ -> nil
    end)
  end

  defp keyboard(payload) do
    rows =
      payload["button_rows"] ||
        rows_from_buttons(payload["buttons"], payload["buttons_per_row"] || 3)

    case {rows, payload["keyboard_mode"]} do
      {rows, _} when rows in [nil, []] -> nil
      {rows, "reply"} -> %{"keyboard" => labels(rows), "resize_keyboard" => true}
      {rows, _} -> %{"inline_keyboard" => callbacks(rows)}
    end
  end

  defp rows_from_buttons(nil, _per_row), do: []
  defp rows_from_buttons(buttons, per_row), do: Enum.chunk_every(buttons, parse_int(per_row, 3))
  defp labels(rows), do: Enum.map(rows, fn row -> Enum.map(row, &%{"text" => &1["label"]}) end)

  defp callbacks(rows) do
    Enum.map(rows, fn row ->
      Enum.map(row, fn button ->
        %{
          "text" => button["label"],
          "callback_data" => wrap_payload(button["payload"] || button["label"])
        }
      end)
    end)
  end

  defp wrap_payload(payload), do: Jason.encode!(%{"p" => to_string(payload)})

  defp parse_payload(nil), do: nil

  defp parse_payload(raw) do
    case Jason.decode(raw) do
      {:ok, %{"p" => payload}} -> payload
      _ -> raw
    end
  end

  defp token(connection), do: (Credentials.for_connection(connection) || %{})["bot_token"]
  defp parse_int(value, _default) when is_integer(value), do: value

  defp parse_int(value, default) do
    case Integer.parse(to_string(value)) do
      {int, _} -> int |> min(8) |> max(1)
      :error -> default
    end
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
end
