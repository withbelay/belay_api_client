defmodule BelayApiClient do
  @moduledoc """
  Provides a simplified interface to BelayApi
  """
  alias Decimal
  alias Tesla.Client

  @doc """
  Create a Tesla client for calls against BelayApi for the given client_id and client_secret

  Used for most calls with this interface
  """
  @spec client(String.t(), String.t()) :: Tesla.Client.t()
  def client(client_id, client_secret) do
    url = Application.fetch_env!(:belay_api_client, :url)

    with {:ok, %{access_token: access_token}} <- fetch_cached_token(client_id, client_secret) do
      middleware =
        [{Tesla.Middleware.BaseUrl, url}, Tesla.Middleware.JSON] ++
          [{Tesla.Middleware.Headers, [{"Authorization", "Bearer #{access_token}"}]}]

      {:ok, Tesla.client(middleware)}
    end
  end

  @doc """
  Fetch an auth token from BelayApi for the given client_id and client_secret.

  Caches the token in the configured Cachex cache.
  """
  def fetch_cached_token(client_id, client_secret) do
    token_cache_name = Application.get_env(:belay_api_client, :token_cache_name, :belay_api_cache)
    token_id = :"#{__MODULE__}.#{client_id}"

    case Cachex.fetch(token_cache_name, token_id, fn -> fetch_token(client_id, client_secret) end) do
      {:ok, token_map} ->
        {:ok, token_map}

      {:commit, %{expires_in: expires_in} = token_map} ->
        Cachex.expire(token_cache_name, token_id, expires_in)
        {:ok, token_map}

      {_, response} ->
        {:error_fetching_token, response}
    end
  end

  @doc """
  Fetch an auth token from BelayApi for the given client_id and client_secret.
  """
  def fetch_token(client_id, client_secret) do
    url = Application.fetch_env!(:belay_api_client, :url)
    client = Tesla.client([{Tesla.Middleware.BaseUrl, url}, Tesla.Middleware.JSON])

    case(Tesla.post(client, "/api/oauth/token", %{client_id: client_id, client_secret: client_secret})) do
      {:ok, %Tesla.Env{status: 200, body: %{"access_token" => access_token, "expires_in" => expires_in}}} ->
        {:commit, %{access_token: access_token, expires_in: expires_in}}

      bad_response ->
        parse_error(bad_response)
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
  Fetch policies for the given investor
  """
  def fetch_policies(%Client{} = client, investor_id) do
    case Tesla.get(client, "/api/policies") do
      {:ok, %Tesla.Env{status: 200, body: policies}} ->
        policies = Enum.filter(policies, fn policy -> policy["investor_account_id"] == investor_id end)

        {:ok, policies}

      response ->
        parse_error(response)
    end
  end

  @doc """
  Buy a policy for the given investor
  """
  def buy_policy(%Client{} = client, investor_id, sym, expiration, qty, strike) do
    policy = %{
      "sym" => sym,
      "expiration" => expiration,
      "investor_account_id" => investor_id,
      "qty" => qty,
      "strike" => strike,
      "partner_investor_id" => investor_id,
      "purchase_limit_price" => strike
    }

    case Tesla.post(client, "/api/policies", policy) do
      {:ok, %Tesla.Env{status: 200, body: policy_request}} -> {:ok, policy_request}
      response -> parse_error(response)
    end
  end

  defp parse_error({:ok, %Tesla.Env{status: 404}}), do: {:ok, :not_found}

  defp parse_error({:ok, %Tesla.Env{status: status, body: body}})
       when is_map_key(body, "error") and is_map_key(body, "error_detail"),
       do: {:error, %{"status" => status, "error" => body["error"], "error_detail" => body["error_detail"]}}

  defp parse_error({:ok, %Tesla.Env{status: status, body: body}}) when is_map_key(body, "error"),
    do: {:error, %{"status" => status, "error" => body["error"]}}

  defp parse_error({_, %Tesla.Env{status: status}}), do: {:error, %{status: status}}
  defp parse_error(_), do: {:error, :unknown}
end
