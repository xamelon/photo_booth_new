defmodule BotMachine.BotRuntime.Credentials do
  alias BotMachine.BotRuntime.{BotChannelConnection, BotChannelCredential}
  alias BotMachine.Repo

  @aad "bot_machine:channel_credentials:v1"

  def get(channel) do
    case Repo.get_by(BotChannelConnection, channel: channel) do
      nil ->
        case Repo.get_by(BotChannelCredential, channel: channel) do
          nil -> env_credentials(channel)
          credential -> decrypt_data(credential.data)
        end

      connection ->
        decrypt_data(connection.credentials)
    end
  end

  def put(channel, attrs) do
    current = get(channel) || %{}
    clean = clean_attrs(attrs)
    data = encrypt_data(Map.merge(current, clean))

    connection =
      case Repo.get_by(BotChannelConnection, channel: channel) do
        nil ->
          %BotChannelConnection{
            channel: channel,
            name: "#{String.upcase(channel)} default",
            external_id: clean["group_id"] || if(channel == "echo", do: "sandbox"),
            public_id: "conn_#{channel}",
            status: "active",
            config: %{}
          }

        connection ->
          connection
      end

    result =
      connection
      |> BotChannelConnection.changeset(%{
        credentials: data,
        external_id: clean["group_id"] || connection.external_id
      })
      |> Repo.insert_or_update()

    case Repo.get_by(BotChannelCredential, channel: channel) do
      nil -> %BotChannelCredential{}
      credential -> credential
    end
    |> BotChannelCredential.changeset(%{channel: channel, data: data})
    |> Repo.insert_or_update()

    result
  end

  def put_connection(%BotChannelConnection{} = connection, attrs) do
    current = for_connection(connection) || %{}
    clean = clean_attrs(attrs)

    connection
    |> BotChannelConnection.changeset(%{
      credentials: encrypt_data(Map.merge(current, clean)),
      external_id: clean["group_id"] || connection.external_id
    })
    |> Repo.update()
  end

  def for_connection(%BotChannelConnection{} = connection) do
    case decrypt_data(connection.credentials) do
      empty when empty == %{} -> env_credentials(connection.channel) || %{}
      data -> data
    end
  end

  def configured?(channel), do: !!get(channel)

  defp clean_attrs(attrs) do
    attrs
    |> Enum.reject(fn {key, value} -> to_string(key) == "name" or value in [nil, ""] end)
    |> Map.new(fn {key, value} -> {to_string(key), value} end)
  end

  defp env_credentials("vk") do
    token = System.get_env("VK_GROUP_ACCESS_TOKEN")
    confirmation = System.get_env("VK_CONFIRMATION_CODE")
    group_id = System.get_env("VK_GROUP_ID")

    if token || confirmation || group_id do
      %{
        "group_access_token" => token,
        "confirmation_code" => confirmation,
        "group_id" => group_id
      }
    end
  end

  defp env_credentials("telegram") do
    if token = System.get_env("TELEGRAM_BOT_TOKEN") do
      %{"bot_token" => token}
    end
  end

  defp env_credentials(_), do: nil

  defp encrypt_data(attrs) do
    attrs
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new(fn {key, value} -> {to_string(key), encrypt(to_string(value))} end)
  end

  defp decrypt_data(data), do: Map.new(data || %{}, fn {key, value} -> {key, decrypt(value)} end)

  defp encrypt(value) do
    iv = :crypto.strong_rand_bytes(12)
    {cipher, tag} = :crypto.crypto_one_time_aead(:aes_256_gcm, key(), iv, value, @aad, true)
    Base.url_encode64(iv <> tag <> cipher, padding: false)
  end

  defp decrypt(value) do
    decoded = Base.url_decode64!(value, padding: false)
    <<iv::binary-12, tag::binary-16, cipher::binary>> = decoded
    :crypto.crypto_one_time_aead(:aes_256_gcm, key(), iv, cipher, @aad, tag, false)
  end

  defp key do
    secret = BotMachineWeb.Endpoint.config(:secret_key_base) || raise "missing secret_key_base"
    :crypto.hash(:sha256, secret)
  end
end
