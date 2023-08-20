defmodule BelayApiClient do
  @moduledoc """
  Provides a simplified interface to BelayApi
  """
  use Agent

  alias Decimal

  require Logger

  # partner_id is part of the token.  Once that's being extracted in investor controller, it can be removed
  defmodule State do
    defstruct ~w(client_id client_secret partner_id token_cache_name token_cache_ttl url)a
  end

  def start_link(opts) do
    params = %State{
      partner_id: Keyword.fetch!(opts, :partner_id),
      client_id: Keyword.fetch!(opts, :client_id),
      client_secret: Keyword.fetch!(opts, :client_secret),
      token_cache_name: Keyword.get(opts, :token_cache_name, :belay_api_cache),
      token_cache_ttl: Keyword.get(opts, :token_cache_ttl, :timer.minutes(5)),
      url: Keyword.fetch!(opts, :belay_api_url)
    }

    {:ok, _pid} =
      Agent.start_link(
        fn ->
          {:ok, _pid} = Cachex.start_link(params.token_cache_name, ttl: params.token_cache_ttl)
          params
        end,
        name: __MODULE__
      )
  end

  @doc """
  Exchange an email and a secret token for a user's investor ID
  """
  def fetch_investor_id(email) do
    make_call = fn client, partner_id, email ->
      case Tesla.post(client, "/api/investors", %{email: email, partner_id: partner_id}) do
        {:ok, %Tesla.Env{status: 200, body: %{"investor_id" => investor_id}}} -> {:ok, investor_id}
        response -> parse_error(response)
      end
    end

    with {:ok, client, state} <- client() do
      make_call.(client, state.partner_id, email)
    end
  end

  @doc """
  Fetch policies for the given investor
  """
  def fetch_policies(investor_id) do
    make_call = fn client, investor_id ->
      case Tesla.get(client, "/api/policies") do
        {:ok, %Tesla.Env{status: 200, body: policies}} ->
          policies = Enum.filter(policies, fn policy -> policy["investor_account_id"] == investor_id end)

          {:ok, policies}

        response ->
          parse_error(response)
      end
    end

    with {:ok, client, _state} <- client() do
      make_call.(client, investor_id)
    end
  end

  @doc """
  Buy a policy for the given investor
  """
  def buy_policy(investor_id, sym, expiration, qty, strike) do
    make_call = fn client, policy ->
      case Tesla.post(client, "/api/policies", policy) do
        {:ok, %Tesla.Env{status: 200, body: policy_request}} -> {:ok, policy_request}
        response -> parse_error(response)
      end
    end

    policy = %{
      "sym" => sym,
      "expiration" => expiration,
      "investor_account_id" => investor_id,
      "qty" => qty,
      "strike" => strike,
      "partner_investor_id" => investor_id,
      "purchase_limit_price" => strike
    }

    with {:ok, client, _state} <- client() do
      make_call.(client, policy)
    end
  end

  defp client() do
    with %State{url: url} = state <- Agent.get(__MODULE__, fn state -> state end),
         {:ok, %{access_token: access_token}} <- fetch_cached_token(state) do
      middleware =
        [{Tesla.Middleware.BaseUrl, url}, Tesla.Middleware.JSON] ++
          [{Tesla.Middleware.Headers, [{"Authorization", "Bearer #{access_token}"}]}]

      {:ok, Tesla.client(middleware), state}
    end
  end

  defp fetch_cached_token(%State{} = state) do
    case Cachex.fetch(state.token_cache_name, :belay_api_token, fn -> fetch_oauth_token(state) end) do
      {:ok, token_map} ->
        {:ok, token_map}

      {:commit, %{expires_in: expires_in} = token_map} ->
        Cachex.expire(state.token_cache_name, :belay_api_token, expires_in)
        {:ok, token_map}

      {_, response} ->
        {:error_fetching_token, response}
    end
  end

  #  Fetch an oauth token from Belay. For internal use only, public so it can be tested.
  @doc false
  def fetch_oauth_token(%State{} = state) do
    %{client_id: client_id, client_secret: client_secret, url: url} = state

    client = Tesla.client([{Tesla.Middleware.BaseUrl, url}, Tesla.Middleware.JSON])

    case(Tesla.post(client, "/api/oauth/token", %{client_id: client_id, client_secret: client_secret})) do
      {:ok, %Tesla.Env{status: 200, body: %{"access_token" => access_token, "expires_in" => expires_in}}} ->
        {:commit, %{access_token: access_token, expires_in: expires_in}}

      bad_response ->
        parse_error(bad_response)
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
