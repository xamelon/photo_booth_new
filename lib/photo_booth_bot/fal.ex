defmodule PhotoBoothBot.Fal do
  @queue_url "https://queue.fal.run"

  def configured?, do: !!key()

  def submit(%{endpoint: endpoint, photo_url: photo_url, prompt: prompt}) do
    Req.post(url(endpoint), headers: headers(), json: input(photo_url, prompt))
    |> case do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok,
         %{
           request_id: body["request_id"],
           status_url: body["status_url"],
           response_url: body["response_url"]
         }}

      {:ok, response} ->
        {:error, "fal submit failed: HTTP #{response.status}"}

      {:error, reason} ->
        {:error, Exception.message(reason)}
    end
  end

  def poll(status_url, response_url) do
    Req.get!(status_url, headers: headers())
    |> case do
      %{status: status} when status in [202, 204] ->
        :pending

      %{status: status, body: body} when status in 200..299 ->
        if completed?(body) do
          fetch_result(body["response_url"] || response_url)
        else
          :pending
        end

      %{status: status} ->
        {:error, "fal poll failed: HTTP #{status}"}
    end
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp fetch_result(nil), do: {:error, "fal response_url missing"}

  defp fetch_result(response_url) do
    Req.get!(response_url, headers: headers())
    |> case do
      %{status: status, body: body} when status in 200..299 ->
        case image_url(body) do
          nil -> {:error, "fal result image url missing"}
          url -> {:completed, url}
        end

      %{status: status} ->
        {:error, "fal result failed: HTTP #{status}"}
    end
  end

  defp completed?(%{"status" => status}) when status in ["COMPLETED", "completed"], do: true
  defp completed?(%{"completed" => true}), do: true
  defp completed?(_), do: false

  defp image_url(%{"images" => [%{"url" => url} | _]}) when is_binary(url), do: url
  defp image_url(%{"image" => %{"url" => url}}) when is_binary(url), do: url
  defp image_url(%{"url" => url}) when is_binary(url), do: url
  defp image_url(_), do: nil

  defp input(photo_url, prompt) do
    %{
      "prompt" => prompt,
      "image_urls" => [photo_url],
      "image_size" => System.get_env("FAL_IMAGE_SIZE") || "portrait_4_3",
      "num_images" => 1,
      "output_format" => "jpeg",
      "enable_safety_checker" => true
    }
  end

  defp url(endpoint), do: @queue_url <> "/" <> String.trim_leading(endpoint, "/")
  defp headers, do: [{"authorization", "Key " <> key!()}]
  defp key, do: System.get_env("FAL_KEY")
  defp key!, do: key() || raise("FAL_KEY is not configured")
end
