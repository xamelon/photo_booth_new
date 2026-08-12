defmodule Mix.Tasks.BotMachine.Materialize do
  use Mix.Task

  @shortdoc "Turns the deletable example app into a real bot app"

  @moduledoc """
  Materializes this template checkout into a real bot project without renaming the
  generic BotMachine engine.

      mix bot_machine.materialize
      mix bot_machine.materialize PizzaBot pizza_bot ghcr.io/acme/pizza-bot
      mix bot_machine.materialize PizzaBot pizza_bot ghcr.io/acme/pizza-bot git@github.com:acme/pizza-bot.git

  The task replaces:

    * `lib/photo_booth_bot` with your app logic folder
    * `lib/photo_booth_bot_web` with your app admin UI folder
    * `PhotoBoothBot` with your app module
    * GHCR and compose placeholders with your image/volume names
  """

  @impl true
  def run(args) do
    Mix.shell().info("Materializing BotMachine template")

    {app_module, app_dir, image_name, origin_url} = input(args)
    app_web_module = app_module <> "Web"
    app_dir_web = app_dir <> "_web"

    validate!(app_module, app_dir, image_name)
    ensure_example_exists!()

    rename_example(app_dir, app_dir_web)
    replace_all(app_module, app_web_module, app_dir, app_dir_web, image_name)
    configure_bot_app(app_module)
    maybe_copy_workflow()
    maybe_copy_env()
    maybe_setup_git(origin_url)
    write_next_steps(app_module, app_dir, app_dir_web, image_name, origin_url)

    Mix.shell().info("\nDone: #{app_module} lives in lib/#{app_dir} and lib/#{app_dir_web}")
    Mix.shell().info("Next: mix format && mix test")
  end

  defp input([app_module, app_dir, image_name]), do: {app_module, app_dir, image_name, nil}

  defp input([app_module, app_dir, image_name, origin_url]),
    do: {app_module, app_dir, image_name, origin_url}

  defp input([]) do
    app_module = prompt("App module", "PizzaBot")
    app_dir = prompt("App dir", Macro.underscore(app_module))
    image_name = prompt("GHCR image", "ghcr.io/YOUR_ORG/#{String.replace(app_dir, "_", "-")}")
    origin_url = prompt_optional("New bot git origin URL, blank to skip")
    {app_module, app_dir, image_name, origin_url}
  end

  defp input(_args) do
    Mix.raise("usage: mix bot_machine.materialize APP_MODULE APP_DIR IMAGE_NAME [NEW_ORIGIN_URL]")
  end

  defp prompt(label, default) do
    case Mix.shell().prompt("#{label} [#{default}]:") |> String.trim() do
      "" -> default
      value -> value
    end
  end

  defp prompt_optional(label) do
    case Mix.shell().prompt("#{label}:") |> String.trim() do
      "" -> nil
      value -> value
    end
  end

  defp validate!(app_module, app_dir, image_name) do
    unless Regex.match?(~r/^[A-Z][A-Za-z0-9]*$/, app_module),
      do: Mix.raise("APP_MODULE must be an Elixir module alias, e.g. PizzaBot")

    unless Regex.match?(~r/^[a-z][a-z0-9_]*$/, app_dir),
      do: Mix.raise("APP_DIR must be snake_case, e.g. pizza_bot")

    unless String.starts_with?(image_name, "ghcr.io/"),
      do: Mix.raise("IMAGE_NAME should look like ghcr.io/ORG/APP")
  end

  defp ensure_example_exists! do
    unless File.dir?("lib/photo_booth_bot") and
             File.dir?("lib/photo_booth_bot_web") do
      Mix.raise("example app folders not found; this project may already be materialized")
    end
  end

  defp rename_example(app_dir, app_dir_web) do
    File.rename!("lib/photo_booth_bot", "lib/#{app_dir}")
    File.rename!("lib/photo_booth_bot_web", "lib/#{app_dir_web}")
    File.rename!("lib/#{app_dir}/example_app.ex", "lib/#{app_dir}/app.ex")

    File.rename!(
      "lib/#{app_dir_web}/controllers/admin/example_app_controller.ex",
      "lib/#{app_dir_web}/controllers/admin/app_controller.ex"
    )

    File.rename!(
      "lib/#{app_dir_web}/controllers/admin/example_app_html.ex",
      "lib/#{app_dir_web}/controllers/admin/app_html.ex"
    )

    File.rename!(
      "lib/#{app_dir_web}/controllers/admin/example_app_html",
      "lib/#{app_dir_web}/controllers/admin/app_html"
    )
  end

  defp replace_all(app_module, app_web_module, app_dir, app_dir_web, image_name) do
    replacements = %{
      "PhotoBoothBot" => app_module,
      "PhotoBoothBotWeb" => app_web_module,
      "BotMachineWeb.Admin.AppController" => "BotMachineWeb.Admin.AppController",
      "BotMachineWeb.Admin.AppHTML" => "BotMachineWeb.Admin.AppHTML",
      "AppController" => "AppController",
      "AppHTML" => "AppHTML",
      "app_html/*" => "app_html/*",
      "photo_booth_bot_web" => app_dir_web,
      "photo_booth_bot" => app_dir,
      "ghcr.io/xamelon/photo-booth-new" => image_name,
      "photo_booth_bot_data" => "#{app_dir}_data",
      "photo_booth_bot_storage" => "#{app_dir}_storage"
    }

    files()
    |> Enum.each(fn path ->
      text = File.read!(path)

      next =
        Enum.reduce(replacements, text, fn {from, to}, acc -> String.replace(acc, from, to) end)

      if next != text, do: File.write!(path, next)
    end)
  end

  defp files do
    roots = ["lib", "priv", "test", "deploy", ".github", "AGENTS.md"]

    roots
    |> Enum.flat_map(fn root ->
      cond do
        File.regular?(root) -> [root]
        File.dir?(root) -> Path.wildcard(Path.join(root, "**/*"))
        true -> []
      end
    end)
    |> Enum.filter(&File.regular?/1)
    |> Enum.filter(fn path ->
      Path.extname(path) in [".ex", ".exs", ".heex", ".md", ".yml", ".yaml", ".example"] or
        Path.basename(path) == "AGENTS.md"
    end)
  end

  defp configure_bot_app(app_module) do
    path = "config/config.exs"
    text = File.read!(path)

    old =
      "config :bot_machine,\n  ecto_repos: [BotMachine.Repo],\n  generators: [timestamp_type: :utc_datetime]"

    new =
      "config :bot_machine,\n  ecto_repos: [BotMachine.Repo],\n  generators: [timestamp_type: :utc_datetime],\n  bot_app: #{app_module}"

    if String.contains?(text, old) do
      File.write!(path, String.replace(text, old, new))
    else
      Mix.shell().info(
        "config/config.exs already customized; ensure :bot_app points to #{app_module}"
      )
    end
  end

  defp maybe_copy_workflow do
    source = ".github/workflows/docker-image.yml.example"
    target = ".github/workflows/docker-image.yml"

    if File.exists?(source) and !File.exists?(target) and
         Mix.shell().yes?("Create GitHub Actions workflow?") do
      File.mkdir_p!(Path.dirname(target))
      File.cp!(source, target)
    end
  end

  defp maybe_copy_env do
    source = "deploy/docker/.env.image.example"
    target = "deploy/docker/.env"

    if File.exists?(source) and !File.exists?(target) and
         Mix.shell().yes?("Create deploy/docker/.env from image example?") do
      File.cp!(source, target)
    end
  end

  defp maybe_setup_git(nil), do: :ok

  defp maybe_setup_git(origin_url) do
    if File.dir?(".git") do
      remotes = git_lines(["remote"])

      if "origin" in remotes and "template" not in remotes do
        git!(["remote", "rename", "origin", "template"])
        Mix.shell().info("Renamed git remote origin -> template")
      end

      remotes = git_lines(["remote"])

      cond do
        "origin" in remotes ->
          git!(["remote", "set-url", "origin", origin_url])
          Mix.shell().info("Updated git remote origin -> #{origin_url}")

        true ->
          git!(["remote", "add", "origin", origin_url])
          Mix.shell().info("Added git remote origin -> #{origin_url}")
      end
    else
      Mix.shell().info("No .git directory found; skipped git remote setup")
    end
  end

  defp git_lines(args) do
    case System.cmd("git", args, stderr_to_stdout: true) do
      {out, 0} -> out |> String.split("\n", trim: true)
      _ -> []
    end
  end

  defp git!(args) do
    case System.cmd("git", args, stderr_to_stdout: true) do
      {_out, 0} -> :ok
      {out, _} -> Mix.raise("git #{Enum.join(args, " ")} failed:\n#{out}")
    end
  end

  defp write_next_steps(app_module, app_dir, app_dir_web, image_name, origin_url) do
    File.write!("NEXT_STEPS.md", """
    # Next steps

    Materialized app:

    - Module: `#{app_module}`
    - App logic: `lib/#{app_dir}`
    - App admin UI: `lib/#{app_dir_web}`
    - Image: `#{image_name}`

    Run:

    ```bash
    mix format
    mix test
    ```

    Git remotes:

    #{git_next_steps(origin_url)}

    Commit prefixes for future backports:

    - `core:` generic template changes that may be cherry-picked back to the template
    - `app:` project-specific bot/business changes, never backport
    - `ops:` deploy/env/CI for this concrete project
    - `docs:` documentation-only changes
    - `mixed:` only when explicitly requested, do not backport directly

    Keep `core:` and `app:` changes in separate commits. Backport only `core:` commits to the template.

    Edit your real bot flow/actions in:

    ```text
    lib/#{app_dir}/app.ex
    ```

    Deploy from GHCR with:

    ```bash
    cd deploy/docker
    docker compose -f docker-compose.image.yml pull
    docker compose -f docker-compose.image.yml run --rm app /app/bin/bot_machine eval "BotMachine.Release.migrate()"
    docker compose -f docker-compose.image.yml up -d app
    ```
    """)
  end

  defp git_next_steps(nil) do
    """
    If you cloned from the template, keep it as upstream:

    ```bash
    git remote rename origin template
    git remote add origin <new-bot-repo-url>
    git push -u origin main
    ```
    """
  end

  defp git_next_steps(origin_url) do
    """
    This task configured:

    ```text
    template = original template remote
    origin   = #{origin_url}
    ```

    Push when ready:

    ```bash
    git push -u origin main
    ```
    """
  end
end
