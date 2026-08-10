defmodule BotMachine.BotRuntime.Credentials do
  alias BotMachine.BotRuntime.BotChannelCredential
  alias BotMachine.Repo

  @aad "bot_machine:channel_credentials:v1"

  def get(channel) do
    case Repo.get_by(BotChannelCredential, channel: channel) do
      nil -> env_credentials(channel)
      credential -> decrypt_data(credential.data)
    end
  end

  def put(channel, attrs) do
    current = get(channel) || %{}

    clean =
      attrs
      |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
      |> Map.new(fn {key, value} -> {to_string(key), value} end)

    data = encrypt_data(Map.merge(current, clean))

    case Repo.get_by(BotChannelCredential, channel: channel) do
      nil -> %BotChannelCredential{}
      credential -> credential
    end
    |> BotChannelCredential.changeset(%{channel: channel, data: data})
    |> Repo.insert_or_update()
  end

  def configured?(channel), do: !!get(channel)

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
