defmodule BotMachineWeb.Admin.AgentController do
  use BotMachineWeb, :controller

  alias BotMachine.BotCore.Registry
  alias BotMachine.BotRuntime

  plug :require_json_body when action in [:validate_flow, :save_flow]

  def overview(conn, _params) do
    json(conn, %{
      counts: BotRuntime.counts(),
      actions: actions(),
      flows:
        Enum.map(BotRuntime.list_flows(), fn flow ->
          version = List.first(flow.versions || [])

          %{
            id: flow.id,
            slug: flow.slug,
            name: flow.name,
            status: flow.status,
            version_id: version && version.id,
            version: version && version.version,
            edit_url: version && ~p"/admin/bot/flows/#{version.id}/edit",
            api_url: version && ~p"/admin/api/agent/flows/#{version.id}"
          }
        end)
    })
  end

  def flow(conn, %{"version_id" => version_id}) do
    with version when not is_nil(version) <- BotRuntime.get_flow_version(version_id) do
      json(conn, flow_payload(version))
    else
      nil -> not_found(conn, "flow version not found")
    end
  end

  def validate_flow(conn, %{"version_id" => version_id, "definition" => definition}) do
    with version when not is_nil(version) <- BotRuntime.get_flow_version(version_id) do
      issues = BotRuntime.validate_flow_definition(definition)
      json(conn, %{ok: issues == [], flow: flow_meta(version), issues: issues})
    else
      nil -> not_found(conn, "flow version not found")
    end
  end

  def validate_flow(conn, _params), do: bad_request(conn, "definition is required")

  def save_flow(conn, %{"version_id" => version_id, "definition" => definition}) do
    with version when not is_nil(version) <- BotRuntime.get_flow_version(version_id),
         {:ok, saved} <- BotRuntime.save_flow_definition(version, definition) do
      json(conn, %{ok: true, flow: flow_meta(saved)})
    else
      nil ->
        not_found(conn, "flow version not found")

      {:error, issues} when is_list(issues) ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{ok: false, issues: issues})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{ok: false, error: inspect(changeset.errors)})
    end
  end

  def save_flow(conn, _params), do: bad_request(conn, "definition is required")

  defp flow_payload(version) do
    %{
      flow: flow_meta(version),
      definition: version.definition,
      viewer: BotRuntime.build_flow_viewer(version),
      actions: actions(),
      issues: BotRuntime.validate_flow_definition(version.definition)
    }
  end

  defp flow_meta(version) do
    %{
      id: version.bot_flow.id,
      slug: version.bot_flow.slug,
      name: version.bot_flow.name,
      status: version.bot_flow.status,
      version_id: version.id,
      version: version.version,
      version_status: version.status,
      edit_url: ~p"/admin/bot/flows/#{version.id}/edit",
      view_url: ~p"/admin/bot/flows/#{version.id}/view"
    }
  end

  defp actions do
    BotMachine.BotApp.registry()
    |> Registry.actions()
  end

  defp require_json_body(conn, _opts) do
    content_type = get_req_header(conn, "content-type") |> List.first() || ""

    if String.contains?(content_type, "application/json") do
      conn
    else
      conn
      |> put_status(:unsupported_media_type)
      |> json(%{error: "content-type must be application/json"})
      |> halt()
    end
  end

  defp not_found(conn, message),
    do: conn |> put_status(:not_found) |> json(%{error: message})

  defp bad_request(conn, message),
    do: conn |> put_status(:bad_request) |> json(%{error: message})
end
