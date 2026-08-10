defmodule BotMachine.BotRuntime.Channels.VKProvisioning do
  alias BotMachine.BotRuntime.Credentials

  @api_version System.get_env("VK_API_VERSION") || "5.199"
  @timeout_ms 15_000
  @poll_ms 250

  @spec provision() :: {:ok, %{server_id: integer(), group_id: integer()}} | {:error, String.t()}
  def provision do
    creds = Credentials.get("vk") || %{}
    token = creds["group_access_token"]
    group_id = parse_int(creds["group_id"])
    callback_url = callback_url()

    cond do
      !token ->
        {:error, "Group access token is required"}

      !group_id ->
        {:error, "Group ID is required"}

      error = public_url_error(callback_url) ->
        {:error, error}

      true ->
        do_provision(creds, group_id, token, callback_url)
    end
  end

  @spec mark_confirmation_received() :: {:ok, term()} | {:error, term()}
  def mark_confirmation_received do
    Credentials.put("vk", %{
      "confirmation_received_at" =>
        DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    })
  end

  @spec callback_url() :: String.t()
  def callback_url, do: String.trim_trailing(public_base_url(), "/") <> "/webhooks/vk"

  defp do_provision(creds, group_id, token, callback_url) do
    callback_secret = creds["callback_secret"] || random_hex(16)

    with {:ok, confirmation_code} <- get_confirmation_code(group_id, token),
         {:ok, _} <-
           Credentials.put("vk", %{
             "confirmation_code" => confirmation_code,
             "callback_secret" => callback_secret,
             "provision_status" => "provisioning",
             "last_provision_error" => ""
           }),
         {:ok, server_id} <-
           upsert_server(
             group_id,
             token,
             callback_url,
             callback_secret,
             creds["callback_server_id"]
           ),
         {:ok, _} <- Credentials.put("vk", %{"callback_server_id" => to_string(server_id)}),
         true <- wait_for_confirmation(server_id, group_id, token),
         {:ok, _} <-
           call_vk("groups.setCallbackSettings", %{
             "group_id" => group_id,
             "server_id" => server_id,
             "api_version" => @api_version,
             "message_new" => 1,
             "message_event" => 0,
             "access_token" => token
           }) do
      Credentials.put("vk", %{
        "provision_status" => "active",
        "last_provision_error" => "",
        "provisioned_at" =>
          DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
      })

      {:ok, %{server_id: server_id, group_id: group_id}}
    else
      false -> mark_error("VK did not confirm callback URL in #{@timeout_ms}ms")
      {:error, reason} -> mark_error(reason)
      other -> mark_error("VK provisioning failed: #{inspect(other)}")
    end
  end

  defp upsert_server(group_id, token, callback_url, callback_secret, stored_server_id) do
    with {:ok, %{"items" => servers}} <-
           call_vk("groups.getCallbackServers", %{"group_id" => group_id, "access_token" => token}) do
      server = find_server(servers, callback_url, parse_int(stored_server_id))

      if server do
        id = server["id"]

        with {:ok, _} <-
               call_vk("groups.editCallbackServer", %{
                 "group_id" => group_id,
                 "server_id" => id,
                 "url" => callback_url,
                 "title" => "bot_machine",
                 "secret_key" => callback_secret,
                 "access_token" => token
               }),
             do: {:ok, id}
      else
        case call_vk("groups.addCallbackServer", %{
               "group_id" => group_id,
               "url" => callback_url,
               "title" => "bot_machine",
               "secret_key" => callback_secret,
               "access_token" => token
             }) do
          {:ok, %{"server_id" => id}} -> {:ok, id}
          {:ok, _} -> {:error, "VK did not return server_id"}
          error -> error
        end
      end
    end
  end

  defp get_confirmation_code(group_id, token) do
    case call_vk("groups.getCallbackConfirmationCode", %{
           "group_id" => group_id,
           "access_token" => token
         }) do
      {:ok, %{"code" => code}} -> {:ok, code}
      {:ok, _} -> {:error, "VK did not return confirmation code"}
      error -> error
    end
  end

  defp wait_for_confirmation(server_id, group_id, token) do
    deadline = System.monotonic_time(:millisecond) + @timeout_ms
    wait_loop(deadline, server_id, group_id, token)
  end

  defp wait_loop(deadline, server_id, group_id, token) do
    creds = Credentials.get("vk") || %{}

    cond do
      creds["confirmation_received_at"] ->
        true

      System.monotonic_time(:millisecond) >= deadline ->
        false

      server_ok?(server_id, group_id, token) ->
        mark_confirmation_received()
        true

      true ->
        Process.sleep(@poll_ms)
        wait_loop(deadline, server_id, group_id, token)
    end
  end

  defp server_ok?(server_id, group_id, token) do
    case call_vk("groups.getCallbackServers", %{"group_id" => group_id, "access_token" => token}) do
      {:ok, %{"items" => servers}} ->
        Enum.any?(servers, &(&1["id"] == server_id && &1["status"] == "ok"))

      _ ->
        false
    end
  end

  @spec call_vk(String.t(), map()) :: {:ok, term()} | {:error, String.t()}
  defp call_vk(method, params) do
    params = Map.put(params, "v", @api_version)

    case Req.post("https://api.vk.ru/method/#{method}", form: params) do
      {:ok, %{status: status, body: %{"response" => response}}} when status in 200..299 ->
        {:ok, response}

      {:ok, %{status: status, body: %{"error" => error}}} when status in 200..299 ->
        {:error,
         "VK #{method}: [#{error["error_code"] || "?"}] #{error["error_msg"] || "Unknown error"}"}

      {:ok, %{status: status, body: body}} ->
        {:error, "VK HTTP #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, Exception.message(reason)}
    end
  end

  defp find_server(servers, callback_url, stored_id) do
    Enum.find(servers, &(&1["id"] == stored_id)) ||
      Enum.find(servers, &(normalize_url(&1["url"]) == normalize_url(callback_url)))
  end

  defp normalize_url(nil), do: nil
  defp normalize_url(url), do: String.trim_trailing(url, "/")

  defp public_url_error(url) do
    uri = URI.parse(url)

    cond do
      uri.host in [nil, "localhost", "127.0.0.1"] ->
        "PUBLIC_BASE_URL must be a public HTTPS URL, not localhost"

      uri.scheme != "https" ->
        "PUBLIC_BASE_URL must use https"

      true ->
        nil
    end
  end

  defp public_base_url do
    System.get_env("PUBLIC_BASE_URL") ||
      case BotMachineWeb.Endpoint.config(:url) do
        nil ->
          "http://localhost:4000"

        url ->
          "#{url[:scheme] || "http"}://#{url[:host]}#{if url[:port], do: ":#{url[:port]}", else: ""}"
      end
  end

  defp mark_error(reason) do
    Credentials.put("vk", %{
      "provision_status" => "error",
      "last_provision_error" => to_string(reason)
    })

    {:error, to_string(reason)}
  end

  defp parse_int(nil), do: nil
  defp parse_int(value) when is_integer(value), do: value

  defp parse_int(value) do
    case Integer.parse(to_string(value)) do
      {int, _} -> int
      :error -> nil
    end
  end

  defp random_hex(bytes), do: :crypto.strong_rand_bytes(bytes) |> Base.encode16(case: :lower)
end
