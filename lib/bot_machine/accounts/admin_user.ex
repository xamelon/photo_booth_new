defmodule BotMachine.Accounts.AdminUser do
  use Ecto.Schema
  import Ecto.Changeset

  schema "admin_users" do
    field :email, :string
    field :hashed_password, :string
    field :role, :string, default: "admin"
    timestamps(type: :utc_datetime)
  end

  def changeset(user, attrs),
    do:
      cast(user, attrs, [:email, :hashed_password, :role])
      |> validate_required([:email, :role])
      |> unique_constraint(:email)
end
