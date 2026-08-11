defmodule Mix.Tasks.BotMachine.Materialize do
  use Mix.Task

  @shortdoc "Turns the deletable example app into a real bot app"

  @moduledoc """
  Materializes this template checkout into a real bot project without renaming the
  generic BotMachine engine.

      mix bot_machine.materialize
      mix bot_machine.materialize PizzaBot pizza_bot ghcr.io/acme/pizza-bot

  The task replaces:

    * `lib/bot_machine_example_app` with your app logic folder
    * `lib/bot_machine_example_app_web` with your app admin UI folder
    * `BotMachineExampleApp` with your app module
    * GHCR and compose placeholders with your image/volume names
  """

  @impl true
  def run(args) do
    Mix.shell().info("Materializing BotMachine template")

    {app_module, app_dir, image_name} = input(args)
    app_web_module = app_module <> "Web"
    app_dir_web = app_dir <> "_web"

    validate!(app_module, app_dir, image_name)
    ensure_example_exists!()

    rename_example(app_dir, app_dir_web)
    replace_all(app_module, app_web_module, app_dir, app_dir_web, image_name)
    configure_bot_app(app_module)
    maybe_copy_workflow()
    maybe_copy_env()
    write_next_steps(app_module, app_dir, app_dir_web, image_name)

    Mix.shell().info("\nDone: #{app_module} lives in lib/#{app_dir} and lib/#{app_dir_web}")
    Mix.shell().info("Next: mix format && mix test")
  end

  defp input([app_module, app_dir, image_name]), do: {app_module, app_dir, image_name}

  defp input([]) do
    app_module = prompt("App module", "PizzaBot")
    app_dir = prompt("App dir", Macro.underscore(app_module))
    image_name = prompt("GHCR image", "ghcr.io/YOUR_ORG/#{String.replace(app_dir, "_", "-")}")
    {app_module, app_dir, image_name}
  end

  defp input(_args) do
    Mix.raise("usage: mix bot_machine.materialize APP_MODULE APP_DIR IMAGE_NAME")
  end

  defp prompt(label, default) do
    case Mix.shell().prompt("#{label} [#{default}]:") |> String.trim() do
      "" -> default
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
    unless File.dir?("lib/bot_machine_example_app") and
             File.dir?("lib/bot_machine_example_app_web") do
      Mix.raise("example app folders not found; this project may already be materialized")
    end
  end

  defp rename_example(app_dir, app_dir_web) do
    File.rename!("lib/bot_machine_example_app", "lib/#{app_dir}")
    File.rename!("lib/bot_machine_example_app_web", "lib/#{app_dir_web}")
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
      "BotMachineExampleApp" => app_module,
      "BotMachineExampleAppWeb" => app_web_module,
      "BotMachineWeb.Admin.ExampleAppController" => "BotMachineWeb.Admin.AppController",
      "BotMachineWeb.Admin.ExampleAppHTML" => "BotMachineWeb.Admin.AppHTML",
      "ExampleAppController" => "AppController",
      "ExampleAppHTML" => "AppHTML",
      "example_app_html/*" => "app_html/*",
      "bot_machine_example_app_web" => app_dir_web,
      "bot_machine_example_app" => app_dir,
      "ghcr.io/YOUR_ORG/YOUR_APP" => image_name,
      "bot_machine_data" => "#{app_dir}_data",
      "bot_machine_storage" => "#{app_dir}_storage"
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

  defp write_next_steps(app_module, app_dir, app_dir_web, image_name) do
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
end
