defmodule BotMachine.Accounts do
  alias BotMachine.Accounts.AdminUser
  alias BotMachine.Repo

  def get_admin_user(id), do: Repo.get(AdminUser, id)

  def get_admin_user_by_email(email),
    do: Repo.get_by(AdminUser, email: String.downcase(String.trim(email)))

  def authenticate_admin(email, password) do
    user = get_admin_user_by_email(email)

    cond do
      user && Bcrypt.verify_pass(password, user.hashed_password) ->
        {:ok, user}

      user ->
        {:error, :invalid_credentials}

      true ->
        Bcrypt.no_user_verify()
        {:error, :invalid_credentials}
    end
  end

  def create_admin(attrs) do
    email = attrs[:email] || attrs["email"]
    password = attrs[:password] || attrs["password"]

    attrs =
      attrs
      |> Map.put(:email, String.downcase(String.trim(email)))
      |> Map.put(:hashed_password, Bcrypt.hash_pwd_salt(password))

    %AdminUser{}
    |> AdminUser.changeset(attrs)
    |> Repo.insert()
  end
end
