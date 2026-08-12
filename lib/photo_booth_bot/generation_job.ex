defmodule PhotoBoothBot.GenerationJob do
  use Ecto.Schema
  import Ecto.Changeset

  schema "photo_booth_generation_jobs" do
    belongs_to :bot_channel_connection, BotMachine.BotRuntime.BotChannelConnection
    field :channel, :string
    field :external_id, :string
    field :status, :string, default: "pending"
    field :mode, :string
    field :title, :string
    field :photo_url, :string
    field :prompt, :string
    field :fal_endpoint, :string
    field :fal_request_id, :string
    field :fal_status_url, :string
    field :fal_response_url, :string
    field :result_url, :string
    field :attempts, :integer, default: 0
    field :next_poll_at, :utc_datetime
    field :last_error, :string
    timestamps(type: :utc_datetime)
  end

  def changeset(job, attrs) do
    job
    |> cast(attrs, [
      :bot_channel_connection_id,
      :channel,
      :external_id,
      :status,
      :mode,
      :title,
      :photo_url,
      :prompt,
      :fal_endpoint,
      :fal_request_id,
      :fal_status_url,
      :fal_response_url,
      :result_url,
      :attempts,
      :next_poll_at,
      :last_error
    ])
    |> validate_required([
      :bot_channel_connection_id,
      :channel,
      :external_id,
      :status,
      :mode,
      :title,
      :photo_url,
      :prompt
    ])
  end
end
