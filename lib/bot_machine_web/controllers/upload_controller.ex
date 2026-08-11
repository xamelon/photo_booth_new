defmodule BotMachineWeb.UploadController do
  use BotMachineWeb, :controller

  alias BotMachine.BotRuntime.Media

  def bot(conn, %{"filename" => filename}) do
    with {:ok, path} <- Media.path(filename),
         true <- File.exists?(path) do
      send_download(conn, {:file, path}, filename: filename, disposition: :inline)
    else
      _ -> send_resp(conn, 404, "not found")
    end
  end
end
