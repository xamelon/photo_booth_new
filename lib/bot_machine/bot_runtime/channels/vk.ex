defmodule BotMachine.BotRuntime.Channels.VK do
  alias BotMachine.BotRuntime.Credentials
  alias BotMachine.BotRuntime.Channels.VKTypes

  @api_version System.get_env("VK_API_VERSION") || "5.199"

  @spec handle_protocol(VKTypes.callback_body()) :: String.t() | nil
  def handle_protocol(%{"type" => "confirmation"}) do
    get_in(Credentials.get("vk") || %{}, ["confirmation_code"])
  end

  def handle_protocol(_), do: nil

  @spec parse_inbound(VKTypes.callback_body()) :: VKTypes.inbound_event() | nil
  def parse_inbound(%{"type" => "message_new"} = body) do
    message = get_in(body, ["object", "message"]) || body["object"] || %{}
    user_id = message["from_id"] || message["peer_id"]

    if user_id do
      %{
        idempotency_key: "vk:#{body["group_id"]}:#{body["event_id"]}",
        input: %{
          "kind" => "user_message",
          "channel" => "vk",
          "external_id" => to_string(user_id),
          "text" => blank_to_nil(String.trim(to_string(message["text"] || ""))),
          "payload" => parse_payload(message["payload"]),
          "attachments" => normalize_attachments(message["attachments"] || [])
        },
        raw: body
      }
    end
  end

  def parse_inbound(_), do: nil

  @spec send(map(), BotMachine.BotCore.Types.bot_output()) ::
          {:ok, String.t()} | {:error, String.t()}
  def send(connection, payload) do
    creds = Credentials.for_connection(connection) || %{}
    token = creds["group_access_token"]

    cond do
      !token ->
        {:error, "VK credentials are not configured"}

      true ->
        with {:ok, attachment} <-
               resolve_attachments(payload["attachments"] || [], payload["external_id"], token) do
          form =
            %{
              "peer_id" => payload["external_id"],
              "message" => payload["text"] || "",
              "random_id" => stable_random_id(payload),
              "v" => @api_version
            }
            |> maybe_put(
              "keyboard",
              keyboard(
                payload["button_rows"] || payload["buttons"] || [],
                Map.get(payload, "keyboard_mode", "inline"),
                Map.get(payload, "buttons_per_row", 3)
              )
            )
            |> maybe_put("attachment", attachment)

          case post_vk("messages.send", form, token) do
            {:ok, %{"response" => id}} -> {:ok, to_string(id)}
            {:ok, %{"error" => error}} -> {:error, error["error_msg"] || "VK API error"}
            {:error, reason} -> {:error, reason}
          end
        end
    end
  end

  defp resolve_attachments([], _peer_id, _token), do: {:ok, nil}

  defp resolve_attachments(attachments, peer_id, token) do
    attachments
    |> Enum.take(10)
    |> Enum.reduce_while({:ok, []}, fn attachment, {:ok, refs} ->
      case resolve_attachment(attachment, peer_id, token) do
        {:ok, nil} -> {:cont, {:ok, refs}}
        {:ok, ref} -> {:cont, {:ok, [ref | refs]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, refs} -> {:ok, refs |> Enum.reverse() |> Enum.join(",") |> blank_to_nil()}
      error -> error
    end
  end

  defp resolve_attachment(%{"ref" => ref}, _peer_id, _token) when is_binary(ref) and ref != "",
    do: {:ok, ref}

  defp resolve_attachment(%{"url" => url, "type" => "photo"}, peer_id, token)
       when is_binary(url) and url != "" do
    with {:ok, upload_url} <- get_message_photo_upload_url(%{"peer_id" => peer_id}, token),
         {:ok, image} <- fetch_image(url),
         {:ok, uploaded} <- upload_photo(upload_url, image),
         {:ok, ref} <- save_message_photo(uploaded, token) do
      {:ok, ref}
    end
  end

  defp resolve_attachment(_attachment, _peer_id, _token), do: {:ok, nil}

  def get_message_photo_upload_url(params, token) do
    params = Map.put(params, "v", @api_version)

    case post_vk("photos.getMessagesUploadServer", params, token) do
      {:ok, %{"response" => %{"upload_url" => url}}} -> {:ok, url}
      {:ok, %{"error" => error}} -> {:error, error["error_msg"] || "VK upload server error"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch_image(url) do
    case Req.get(url) do
      {:ok, %{status: status, body: body, headers: headers}} when status in 200..299 ->
        content_type = headers |> Map.get("content-type", ["image/jpeg"]) |> List.first()
        ext = if String.contains?(content_type, "png"), do: "png", else: "jpg"
        {:ok, {"photo.#{ext}", body, content_type}}

      {:ok, %{status: status}} ->
        {:error, "image fetch failed with HTTP #{status}"}

      {:error, reason} ->
        {:error, Exception.message(reason)}
    end
  end

  def upload_photo(upload_url, {filename, body, content_type}) do
    case Req.post(upload_url,
           form_multipart: [{"photo", {body, filename: filename, content_type: content_type}}]
         ) do
      {:ok, %{status: status, body: response}} when status in 200..299 ->
        response = if is_map(response), do: {:ok, response}, else: Jason.decode(response)

        case response do
          {:ok, %{"server" => _, "photo" => photo, "hash" => _} = uploaded}
          when photo not in [nil, "", "[]"] ->
            {:ok, uploaded}

          {:ok, invalid} ->
            {:error, "VK photo upload returned invalid payload: #{inspect(invalid)}"}

          error ->
            error
        end

      {:ok, %{status: status, body: response}} ->
        {:error, "VK photo upload failed with HTTP #{status}: #{inspect(response)}"}

      {:error, reason} ->
        {:error, Exception.message(reason)}
    end
  end

  def save_message_photo(%{"server" => server, "photo" => photo, "hash" => hash}, token) do
    case post_vk(
           "photos.saveMessagesPhoto",
           %{"server" => server, "photo" => photo, "hash" => hash, "v" => @api_version},
           token
         ) do
      {:ok, %{"response" => [photo | _]}} -> {:ok, "photo#{photo["owner_id"]}_#{photo["id"]}"}
      {:ok, %{"error" => error}} -> {:error, error["error_msg"] || "VK save photo error"}
      {:error, reason} -> {:error, reason}
      _ -> {:error, "VK save photo returned invalid response"}
    end
  end

  def save_message_photo(_uploaded, _token), do: {:error, "VK upload returned invalid response"}

  defp post_vk(method, params, token) do
    case Req.post("https://api.vk.ru/method/#{method}",
           headers: [{"authorization", "Bearer #{token}"}],
           form: params
         ) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        if is_map(body), do: {:ok, body}, else: Jason.decode(body)

      {:ok, %{status: status, body: body}} ->
        {:error, "VK HTTP #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, Exception.message(reason)}
    end
  end

  defp keyboard([], _mode, _per_row), do: nil

  defp keyboard(button_rows, mode, per_row) do
    rows =
      if List.first(button_rows) |> is_list(),
        do: button_rows,
        else: Enum.chunk_every(button_rows, per_row |> parse_int(3) |> min(5) |> max(1))

    %{
      one_time: false,
      inline: mode != "reply",
      buttons:
        Enum.map(rows, fn row ->
          Enum.map(
            row,
            &%{
              action: %{
                type: "text",
                label: &1["label"],
                payload: wrap_payload(to_string(&1["payload"] || &1["label"]))
              },
              color: "primary"
            }
          )
        end)
    }
    |> Jason.encode!()
  end

  defp wrap_payload(payload), do: Jason.encode!(%{p: payload})

  defp parse_payload(nil), do: nil

  defp parse_payload(raw) do
    case Jason.decode(raw) do
      {:ok, %{"p" => payload}} -> payload
      {:ok, %{"payload" => payload}} -> payload
      _ -> nil
    end
  end

  @spec normalize_attachments([VKTypes.attachment()]) :: [
          BotMachine.BotCore.Types.bot_attachment()
        ]
  defp normalize_attachments([]), do: []
  defp normalize_attachments(attachments), do: Enum.flat_map(attachments, &normalize_attachment/1)

  @spec normalize_attachment(VKTypes.attachment()) :: [BotMachine.BotCore.Types.bot_attachment()]
  defp normalize_attachment(%{
         "type" => "photo",
         "photo" => %{"owner_id" => owner_id, "id" => id} = photo
       }) do
    [
      %{
        "type" => "photo",
        "ref" => "photo#{owner_id}_#{id}",
        "url" => best_photo_url(photo["sizes"] || [])
      }
    ]
  end

  defp normalize_attachment(_), do: []

  defp best_photo_url(sizes) do
    sizes
    |> Enum.sort_by(&((&1["width"] || 0) * (&1["height"] || 0)), :desc)
    |> List.first()
    |> case do
      nil -> nil
      size -> size["url"]
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp parse_int(value, _default) when is_integer(value), do: value

  defp parse_int(value, default) do
    case Integer.parse(to_string(value)) do
      {int, _} -> int
      :error -> default
    end
  end

  defp stable_random_id(%{"_outbox_id" => id}), do: to_string(id)

  defp stable_random_id(payload) do
    <<int::signed-32, _::binary>> = :crypto.hash(:sha256, :erlang.term_to_binary(payload))
    Integer.to_string(Bitwise.band(int, 0x7FFFFFFF))
  end
end
