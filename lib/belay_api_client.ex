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
  @spec client(String.t(), String.t()) :: Tesla.Client.t()
  def client(client_id, client_secret) do
    with {:ok, %{access_token: access_token}} <- fetch_token(client_id, client_secret) do
      client(access_token)
    end
  end

  @spec client(String.t()) :: Tesla.Client.t()
  def client(access_token) do
    url = Application.fetch_env!(:belay_api_client, :api_url)

    middleware =
      [{Tesla.Middleware.BaseUrl, url}, Tesla.Middleware.JSON] ++
        [{Tesla.Middleware.Headers, [{"Authorization", "Bearer #{access_token}"}]}]

    {:ok, Tesla.client(middleware)}
  end

  @doc """
  Fetch an auth token from BelayApi for the given client_id and client_secret.
  """
  def fetch_token(client_id, client_secret) do
    url = Application.fetch_env!(:belay_api_client, :api_url)
    client = Tesla.client([{Tesla.Middleware.BaseUrl, url}, Tesla.Middleware.JSON])

    case Tesla.post(client, "/api/oauth/token", %{client_id: client_id, client_secret: client_secret}) do
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
  def fetch_market_clock(%Client{} = client) do
    case Tesla.get(client, "/api/market/clock") do
      {:ok, %Tesla.Env{status: 200, body: %{"is_open" => is_open, "opens_in" => opens_in}}} ->
        {:ok, %{is_open: is_open, opens_in: opens_in}}

      response ->
        parse_error(response)
    end
  end

  @doc """
  Fetch the market stock universe
  """
  def fetch_market_stock_universe(%Client{} = client) do
    case Tesla.get(client, "/api/market/stock_universe") do
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
  def buy_policy(%Client{} = client, investor_id, sym, expiration, qty, strike, purchase_limit_price) do
    policy = %{
      "sym" => sym,
      "expiration" => expiration,
      "investor_account_id" => investor_id,
      "qty" => qty,
      "strike" => strike,
      "partner_investor_id" => investor_id,
      "purchase_limit_price" => purchase_limit_price
    }

    case Tesla.post(client, "/api/policies", policy) do
      {:ok, %Tesla.Env{status: 200, body: policy_request}} -> {:ok, policy_request}
      response -> parse_error(response)
    end
  end

  defp parse_error({:ok, %Tesla.Env{status: status, body: body}})
       when is_map_key(body, "error") and is_map_key(body, "error_detail"),
       do: {:error, %{status: status, error: body["error"], error_detail: body["error_detail"]}}

  defp parse_error({:ok, %Tesla.Env{status: status, body: body}}) when is_map_key(body, "error"),
    do: {:error, %{status: status, error: body["error"]}}

  defp parse_error({_, %Tesla.Env{status: status}}), do: {:error, %{status: status}}
  defp parse_error(reason) do
    Logger.error("[BelayApiClient] Unexpected result", reason: reason)

    {:error, :unknown}
  end
end
