defmodule BotMachine.BotRuntime.Channels.VKPhotoUpload do
  alias BotMachine.BotRuntime.{Credentials, Media}
  alias BotMachine.BotRuntime.Channels.VK

  @allowed %{
    "image/jpeg" => ".jpg",
    "image/png" => ".png",
    "image/webp" => ".webp",
    "image/gif" => ".gif"
  }

  def upload(%Plug.Upload{} = upload) do
    with {:ok, bytes} <- File.read(upload.path),
         :ok <- validate(bytes, upload.content_type),
         {:ok, ref} <- upload_to_vk(bytes, upload.content_type),
         {:ok, preview} <- Media.save_preview(ref, bytes, upload.content_type) do
      {:ok, %{"type" => "photo", "ref" => ref, "url" => preview.url}}
    end
  end

  def upload(_), do: {:error, "image file is required"}

  defp validate(bytes, content_type) do
    cond do
      byte_size(bytes) == 0 ->
        {:error, "empty image"}

      byte_size(bytes) > 5 * 1024 * 1024 ->
        {:error, "image is larger than 5 MB"}

      !Map.has_key?(@allowed, content_type) ->
        {:error, "only JPEG, PNG, WebP and GIF images are allowed"}

      true ->
        :ok
    end
  end

  defp upload_to_vk(bytes, content_type) do
    creds = Credentials.get("vk") || %{}
    token = creds["group_access_token"]
    group_id = parse_int(creds["group_id"])

    cond do
      !token ->
        {:error, "VK credentials are not configured"}

      !group_id ->
        {:error, "VK group_id is not configured"}

      true ->
        with {:ok, upload_url} <-
               VK.get_message_photo_upload_url(%{"group_id" => group_id}, token),
             {:ok, uploaded} <-
               VK.upload_photo(
                 upload_url,
                 {"photo#{@allowed[content_type]}", bytes, content_type}
               ),
             {:ok, ref} <- VK.save_message_photo(uploaded, token) do
          {:ok, ref}
        end
    end
  end

  defp parse_int(value) when is_integer(value), do: value

  defp parse_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> nil
    end
  end

  defp parse_int(_), do: nil
end
