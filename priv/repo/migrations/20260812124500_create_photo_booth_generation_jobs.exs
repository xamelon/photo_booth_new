defmodule BotMachine.Repo.Migrations.CreatePhotoBoothGenerationJobs do
  use Ecto.Migration

  def change do
    create table(:photo_booth_generation_jobs) do
      add :bot_channel_connection_id,
          references(:bot_channel_connections, on_delete: :delete_all), null: false

      add :channel, :text, null: false
      add :external_id, :text, null: false
      add :status, :text, null: false, default: "pending"
      add :mode, :text, null: false
      add :title, :text, null: false
      add :photo_url, :text, null: false
      add :prompt, :text, null: false
      add :fal_endpoint, :text
      add :fal_request_id, :text
      add :fal_status_url, :text
      add :fal_response_url, :text
      add :result_url, :text
      add :attempts, :integer, null: false, default: 0
      add :next_poll_at, :utc_datetime
      add :last_error, :text
      timestamps(type: :utc_datetime)
    end

    create index(:photo_booth_generation_jobs, [:status, :next_poll_at])
    create index(:photo_booth_generation_jobs, [:bot_channel_connection_id, :external_id])
  end
end
