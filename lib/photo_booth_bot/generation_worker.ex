defmodule PhotoBoothBot.GenerationWorker do
  use GenServer
  import Ecto.Query

  alias BotMachine.BotRuntime
  alias BotMachine.Repo
  alias PhotoBoothBot.{Fal, GenerationJob}

  @tick_ms 2_000
  @poll_delay_seconds 5
  @fail_after_attempts 120

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    schedule(0)
    {:ok, %{}}
  end

  @impl true
  def handle_info(:tick, state) do
    process_due_job()
    schedule(@tick_ms)
    {:noreply, state}
  end

  def process_due_job do
    case due_job() do
      nil -> :ok
      job -> process_job(job)
    end
  end

  defp due_job do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.one(
      from j in GenerationJob,
        where:
          j.status in ["pending", "submitted"] and
            (is_nil(j.next_poll_at) or j.next_poll_at <= ^now),
        order_by: [asc: j.inserted_at],
        limit: 1
    )
  end

  defp process_job(%GenerationJob{status: "pending"} = job) do
    if Fal.configured?() do
      submit(job)
    else
      fail(job, "FAL_KEY is not configured")
    end
  end

  defp process_job(%GenerationJob{status: "submitted"} = job) do
    if job.attempts >= @fail_after_attempts do
      fail(job, "fal generation timed out")
    else
      case Fal.poll(job.fal_status_url, job.fal_response_url) do
        :pending ->
          update_job(job, %{attempts: job.attempts + 1, next_poll_at: poll_at()})

        {:completed, result_url} ->
          job = update_job(job, %{status: "completed", result_url: result_url, last_error: nil})
          enqueue_event(job, "photo_generation.completed", %{"image_url" => result_url})

        {:error, reason} ->
          fail(job, reason)
      end
    end
  end

  defp submit(job) do
    endpoint =
      job.fal_endpoint || System.get_env("FAL_IMAGE_MODEL") || "fal-ai/nano-banana-pro/edit"

    case Fal.submit(%{endpoint: endpoint, photo_url: job.photo_url, prompt: job.prompt}) do
      {:ok, result} ->
        update_job(job, %{
          status: "submitted",
          fal_endpoint: endpoint,
          fal_request_id: result.request_id,
          fal_status_url: result.status_url,
          fal_response_url: result.response_url,
          attempts: job.attempts + 1,
          next_poll_at: poll_at(),
          last_error: nil
        })

      {:error, reason} ->
        fail(job, reason)
    end
  end

  defp fail(job, reason) do
    job =
      update_job(job, %{
        status: "failed",
        attempts: job.attempts + 1,
        last_error: to_string(reason)
      })

    enqueue_event(job, "photo_generation.failed", %{"error" => to_string(reason)})
  end

  defp enqueue_event(job, event_type, extra) do
    payload =
      Map.merge(extra, %{
        "kind" => "domain_event",
        "event" => event_type,
        "payload" => Map.merge(extra, %{"generation_job_id" => job.id}),
        "generation_job_id" => job.id,
        "bot_channel_connection_id" => job.bot_channel_connection_id,
        "channel" => job.channel,
        "external_id" => job.external_id,
        "text" => ""
      })

    BotRuntime.enqueue_inbox(payload, "photo-generation:#{job.id}:#{event_type}")
  end

  defp update_job(job, attrs) do
    job
    |> GenerationJob.changeset(attrs)
    |> Repo.update!()
  end

  defp poll_at do
    DateTime.utc_now()
    |> DateTime.add(@poll_delay_seconds, :second)
    |> DateTime.truncate(:second)
  end

  defp schedule(ms), do: Process.send_after(self(), :tick, ms)
end
