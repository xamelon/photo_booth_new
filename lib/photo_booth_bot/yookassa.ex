defmodule PhotoBoothBot.YooKassa do
  @api_url "https://api.yookassa.ru/v3"

  def configured?, do: shop_id() not in [nil, ""] and secret_key() not in [nil, ""]

  def create_payment(params) do
    call("/payments",
      method: "POST",
      headers: [{"Idempotence-Key", Ecto.UUID.generate()}],
      json: %{
        amount: %{"value" => params.amount_value, "currency" => "RUB"},
        capture: true,
        confirmation: %{"type" => "redirect", "return_url" => return_url()},
        description: params.description,
        metadata: params.metadata,
        receipt: receipt(params)
      }
    )
  end

  def get_payment(payment_id), do: call("/payments/#{payment_id}", method: "GET")

  defp call(path, opts) do
    if configured?() do
      opts =
        Keyword.update(opts, :headers, auth_header(), &[auth_header() | &1])

      case Req.request(Keyword.put(opts, :url, @api_url <> path)) do
        {:ok, %{status: status, body: body}} when status in 200..299 ->
          {:ok, body}

        {:ok, %{status: status, body: body}} ->
          {:error, "YooKassa HTTP #{status}: #{description(body)}"}

        {:error, reason} ->
          {:error, Exception.message(reason)}
      end
    else
      {:error, "YooKassa is not configured"}
    end
  end

  defp receipt(params) do
    %{
      customer: %{email: params.email},
      items: [
        %{
          description: "Пополнение баланса: #{params.package_label}",
          quantity: "1.00",
          amount: %{"value" => params.amount_value, "currency" => "RUB"},
          vat_code: 1,
          payment_mode: "full_payment",
          payment_subject: "service"
        }
      ]
    }
  end

  defp description(%{"description" => text}) when is_binary(text), do: text
  defp description(body), do: inspect(body)

  defp auth_header do
    token = Base.encode64("#{shop_id()}:#{secret_key()}")
    {"authorization", "Basic #{token}"}
  end

  defp shop_id, do: System.get_env("YOOKASSA_SHOP_ID")
  defp secret_key, do: System.get_env("YOOKASSA_SECRET_KEY")

  defp return_url do
    System.get_env("YOOKASSA_RETURN_URL") || System.get_env("PUBLIC_URL") ||
      BotMachineWeb.Endpoint.url()
  end
end
