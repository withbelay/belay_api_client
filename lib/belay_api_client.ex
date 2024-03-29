defmodule BelayApiClient do
  @moduledoc """
  Provides a simplified interface to BelayApi
  """
  alias Decimal
  alias Tesla.Client

  require Logger

  @doc """
  Create a Tesla client for calls against BelayApi for the given client_id and client_secret

  Used for most calls with this interface
  """
  @spec client(String.t(), String.t()) :: {:ok, Tesla.Client.t()} | {:error, any()}
  def client(client_id, client_secret) do
    with {:ok, %{access_token: access_token}} <- fetch_token(client_id, client_secret) do
      client(access_token)
    end
  end

  @spec client(String.t()) :: {:ok, Tesla.Client.t()}
  def client(access_token) do
    base_middlewares = Tesla.Client.middleware(public_client())

    auth_middleware =
      [
        Tesla.Middleware.OpenTelemetry,
        Tesla.Middleware.UniqueRequestId,
        {Tesla.Middleware.Headers, [{"Authorization", "Bearer #{access_token}"}]}
      ]

    {:ok, Tesla.client(base_middlewares ++ auth_middleware)}
  end

  @spec public_client() :: Tesla.Client.t()
  def public_client do
    url = Application.fetch_env!(:belay_api_client, :api_url)

    middleware =
      [
        {Tesla.Middleware.BaseUrl, url},
        {Tesla.Middleware.Logger, log_level: &log_level/1, debug: false, filter_headers: ~w[Authorization]},
        Tesla.Middleware.JSON
      ]

    Tesla.client(middleware)
  end

  def log_level(env) when env.status >= 500, do: :error
  def log_level(_), do: :debug

  @doc """
  Fetch an auth token from BelayApi for the given client_id and client_secret.
  """
  def fetch_token(client_id, client_secret) do
    case Tesla.post(public_client(), "/api/oauth/token", %{client_id: client_id, client_secret: client_secret}) do
      {:ok, %Tesla.Env{status: 200, body: %{"access_token" => access_token, "expires_in" => expires_in}}} ->
        {:ok, %{access_token: access_token, expires_in: expires_in}}

      bad_response ->
        parse_error(bad_response)
    end
  end

  @doc """
  Fetch an investor token from BelayApi for the given client_id and client_secret.
  """
  def fetch_investor_token(client, investor_id) do
    case Tesla.get(client, "/api/investors/#{investor_id}/token") do
      {:ok, %Tesla.Env{status: 200, body: %{"token" => token}}} -> {:ok, %{token: token}}
      bad_response -> parse_error(bad_response)
    end
  end

  @doc """
  Fetch the investor_id for the given email address
  """
  def fetch_investor_id(%Client{} = client, partner_id, email) do
    case Tesla.post(client, "/api/investors", %{email: email, partner_id: partner_id}) do
      {:ok, %Tesla.Env{status: 200, body: %{"investor_id" => investor_id}}} -> {:ok, investor_id}
      response -> parse_error(response)
    end
  end

  @doc """
  Fetch the investor_id for the given email address
  """
  def fetch_investor_holdings(%Client{} = client, investor_id) do
    case Tesla.get(client, "/api/investors/#{investor_id}/holdings") do
      {:ok, %Tesla.Env{status: 200, body: %{"holdings" => holdings}}} -> {:ok, holdings}
      response -> parse_error(response)
    end
  end

  @doc """
  Fetch the market clock
  """
  def fetch_market_clock do
    case Tesla.get(public_client(), "/api/market/clock") do
      {:ok, %Tesla.Env{status: 200, body: %{"is_open" => is_open, "opens_in" => opens_in}}} ->
        {:ok, %{is_open: is_open, opens_in: opens_in}}

      response ->
        parse_error(response)
    end
  end

  @doc """
  Fetch the market stock universe
  """
  def fetch_market_stock_universe do
    case Tesla.get(public_client(), "/api/market/stock_universe") do
      {:ok, %Tesla.Env{status: 200, body: %{"stock_universe" => stock_universe}}} ->
        {:ok, stock_universe}

      response ->
        parse_error(response)
    end
  end

  @doc """
  Fetch all partner policies
  """
  def fetch_policies(%Client{} = client) do
    case Tesla.get(client, "/api/policies") do
      {:ok, %Tesla.Env{status: 200, body: policies}} ->
        {:ok, policies}

      response ->
        parse_error(response)
    end
  end

  @doc """
  Fetch policies for the given investor
  """
  def fetch_policies(%Client{} = client, investor_id) do
    with {:ok, partner_policies} <- fetch_policies(client) do
      policies = Enum.filter(partner_policies, fn policy -> policy["investor_account_id"] == investor_id end)

      {:ok, policies}
    end
  end

  @doc """
  Buy a policy for the given investor
  """
  def buy_policy(
        %Client{} = client,
        investor_id,
        sym,
        expiration,
        qty,
        strike,
        purchase_limit_price,
        discount_code \\ nil
      ) do
    policy = %{
      "sym" => sym,
      "expiration" => expiration,
      "investor_account_id" => investor_id,
      "qty" => qty,
      "strike" => strike,
      "partner_investor_id" => investor_id,
      "purchase_limit_price" => purchase_limit_price
    }

    policy =
      if discount_code do
        Map.put(policy, "discount_code", discount_code)
      else
        policy
      end

    case Tesla.post(client, "/api/policies", policy) do
      {:ok, %Tesla.Env{status: 200, body: policy_request}} -> {:ok, policy_request}
      response -> parse_error(response)
    end
  end

  @doc """
  Apply a discount code for an investor's purchase
  """
  def apply_discount_code(%Client{} = client, nil, discount_code, price) do
    client
    |> Tesla.post("/api/discount/apply/#{discount_code}", %{price: price})
    |> parse_discount_code_response()
  end

  def apply_discount_code(%Client{} = client, investor_id, discount_code, price) do
    client
    |> Tesla.post("/api/discount/apply/#{discount_code}", %{investor_id: investor_id, price: price})
    |> parse_discount_code_response()
  end

  defp parse_discount_code_response(discount_result) do
    case discount_result do
      {:ok,
       %Tesla.Env{
         status: 200,
         body: %{"valid" => valid, "discount_info" => discount_info, "discounted_price" => discounted_price}
       }} ->
        {:ok, %{valid: valid, discount_info: discount_info, discounted_price: discounted_price}}

      response ->
        parse_error(response)
    end
  end

  defp parse_error({:ok, %Tesla.Env{status: status, body: body}})
       when is_map_key(body, "error") and is_map_key(body, "error_detail") do
    {:error, %{status: status, error: body["error"], error_detail: body["error_detail"]}}
  end

  defp parse_error({:ok, %Tesla.Env{status: status, body: body}}) when is_map_key(body, "error"),
    do: {:error, %{status: status, error: body["error"]}}

  defp parse_error({_, %Tesla.Env{status: status}}), do: {:error, %{status: status}}

  defp parse_error(_reason) do
    {:error, :unknown}
  end
end
