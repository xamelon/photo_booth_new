defmodule BotMachine.BotRuntime.Media do
  @public_prefix "/uploads/bot"
  @max_bytes 5 * 1024 * 1024
  @allowed %{
    "image/jpeg" => ".jpg",
    "image/png" => ".png",
    "image/webp" => ".webp",
    "image/gif" => ".gif"
  }

  def upload_dir do
    System.get_env("STORAGE_DIR", "storage/uploads")
    |> Path.expand()
    |> Path.join("bot")
  end

  def path(filename) do
    safe = sanitize_filename(filename)

    if safe == "" or safe != filename do
      {:error, "invalid filename"}
    else
      {:ok, Path.join(upload_dir(), safe)}
    end
  end

  def save_preview(ref, bytes, content_type) when is_binary(ref) and is_binary(bytes) do
    with :ok <- validate_size(bytes),
         {:ok, ext} <- extension(content_type),
         {:ok, filename} <- filename_for_ref(ref, ext) do
      File.mkdir_p!(upload_dir())
      path = Path.join(upload_dir(), filename)
      File.write!(path, bytes)
      {:ok, %{url: "#{@public_prefix}/#{filename}", filename: filename, path: path}}
    end
  end

  defp validate_size(bytes) when byte_size(bytes) in 1..@max_bytes, do: :ok
  defp validate_size(_), do: {:error, "image must be between 1 byte and 5 MB"}

  defp extension(content_type) do
    case @allowed[String.downcase(to_string(content_type))] do
      nil -> {:error, "only JPEG, PNG, WebP and GIF images are allowed"}
      ext -> {:ok, ext}
    end
  end

  defp filename_for_ref(ref, ext) do
    safe = ref |> String.trim() |> sanitize_filename()
    if safe == "", do: {:error, "invalid media ref"}, else: {:ok, safe <> ext}
  end

  defp sanitize_filename(value), do: String.replace(value, ~r/[^a-zA-Z0-9._-]/, "")
end
