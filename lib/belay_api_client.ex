defmodule BelayApiClient do
  @moduledoc """
  Provides a simplified interface to BelayApi
  """
  use Agent

  alias Decimal

  require Logger

  defmodule State do
    defstruct ~w(client_id client_secret token_cache_name token_cache_ttl url)a
  end

  def start_link(opts) do
    params = %State{
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
  def fetch_investor_id(partner_id, email) do
    with {:ok, client} <- client() do
      client
      |> Tesla.post("/api/investors", %{email: email, partner_id: partner_id})
      |> parse_investor_response()
    end
  end

  @doc """
  Fetch policies for the given investor
  """
  def fetch_policies(investor_id) do
    with {:ok, client} <- client() do
      client
      |> Tesla.get("/api/policies")
      |> parse_policies_response(investor_id)
    end
  end

  def buy_policy(investor_id, offering, qty, price) do
    policy = %{
      sym: offering["sym"],
      expiration: offering["expiration"],
      investor_account_id: investor_id,
      qty: qty,
      strike: offering["strike"] |> Float.to_string(),
      # For now, we're only supporting Alpaca which doesn't have a concept of a partner investor ID
      partner_investor_id: investor_id,
      purchase_limit_price: price |> Decimal.to_string()
    }

    with {:ok, client} <- client() do
      client
      |> Tesla.post("/api/policies", policy)
      |> parse_buy_policy_response()
    end
  end

  defp get_state(), do: Agent.get(__MODULE__, fn state -> state end)

  defp client() do
    with %State{url: url} = state <- get_state(),
         {:ok, %{access_token: access_token}} <- fetch_cached_token(state) do
      middleware =
        [{Tesla.Middleware.BaseUrl, url}, Tesla.Middleware.JSON] ++
          [{Tesla.Middleware.Headers, [{"Authorization", "Bearer #{access_token}"}]}]

      {:ok, Tesla.client(middleware)}
    end
  end

  defp fetch_cached_token(%State{} = state) do
    case Cachex.fetch(state.token_cache_name, :belay_api_token, fn -> fetch_oauth_token(state) end) do
      {:ok, token_map} ->
        {:ok, token_map}

      {:commit, %{expires_in: expires_in} = token_map} ->
        Cachex.expire(state.token_cache_name, :belay_api_token, expires_in)
        {:ok, token_map}

      {:ignore, {:error, reason}} ->
        {:error, reason}
    end
  end

  #  Fetch an oauth token from Belay. For internal use only, public so it can be tested.
  @doc false
  def fetch_oauth_token(%State{} = state) do
    %{client_id: client_id, client_secret: client_secret, url: url} = state

    [{Tesla.Middleware.BaseUrl, url}, Tesla.Middleware.JSON]
    |> Tesla.client()
    |> Tesla.post("/api/oauth/token", %{
      client_id: client_id,
      client_secret: client_secret
    })
    |> parse_oauth_response()
  end

  defp parse_investor_response(resp) do
    case resp do
      {:ok, %Tesla.Env{status: 200, body: %{"investor_id" => investor_id}}} ->
        {:ok, investor_id}

      {:ok, %Tesla.Env{status: 404}} ->
        {:error, :not_found}

      {:ok, %Tesla.Env{status: 500, body: %{"error" => error, "error_detail" => error_detail}}} ->
        Logger.critical("[BelayApiClient] 500 from Belay on /investors: #{error} - #{error_detail}")
        {:error, :unexpected}

      {:ok, %Tesla.Env{status: status}} ->
        Logger.critical("[BelayApiClient] #{status} from Belay on /investors")
        {:error, :unexpected}

      {:error, :econnrefused} ->
        Logger.critical("[BelayApiClient] Can't reach the Belay API! Is it running?")
        {:error, :unexpected}

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end

  defp parse_policies_response(resp, investor_id) do
    case resp do
      {:ok, %Tesla.Env{status: 200, body: policies}} ->
        policies = Enum.filter(policies, fn policy -> policy["investor_account_id"] == investor_id end)

        {:ok, policies}

      {:ok, %Tesla.Env{status: status}} ->
        Logger.critical("[BelayApiClient] #{status} from Belay on /policies")
        {:error, :unexpected}

      {:error, :econnrefused} ->
        Logger.critical("[BelayApiClient] Can't reach the Belay API! Is it running?")
        {:error, :unexpected}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_buy_policy_response(resp) do
    case resp do
      {:ok, %Tesla.Env{status: 200, body: policy_request}} ->
        {:ok, policy_request}

      {:ok, %Tesla.Env{status: 422, body: %{"error" => error, "error_detail" => error_detail}}} ->
        Logger.critical("[BelayApiClient] 422 from Belay on /policies: #{error} - #{error_detail}")
        {:error, :unexpected}

      {:ok, %Tesla.Env{status: status}} ->
        Logger.critical("[BelayApiClient] #{status} from Belay on /policies")
        {:error, :unexpected}

      {:error, :econnrefused} ->
        Logger.critical("[BelayApiClient] Can't reach the Belay API! Is it running?")
        {:error, :unexpected}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_oauth_response(resp) do
    case resp do
      {:ok,
       %Tesla.Env{
         status: 200,
         body: %{"access_token" => access_token, "expires_in" => expires_in}
       }} ->
        {:commit, %{access_token: access_token, expires_in: expires_in}}

      {:ok, %Tesla.Env{status: 422, body: %{"error" => error, "error_detail" => error_detail}}} ->
        Logger.critical("[BelayApiClient] 422 from Belay on /oauth/token: #{error} - #{error_detail}")

        {:ignore, {:error, :unprocessable}}

      {:ok, %Tesla.Env{status: 500, body: %{"error" => error, "error_detail" => error_detail}}} ->
        Logger.critical("[BelayApiClient] 500 from Belay on /oauth/token: #{error} - #{error_detail}")

        {:ignore, {:error, :unexpected}}

      {:ok, %Tesla.Env{status: status}} ->
        Logger.critical("[BelayApiClient] #{status} from Belay on /oauth/token")
        {:ignore, {:error, :unexpected}}

      {:error, :econnrefused} ->
        Logger.critical("[BelayApiClient] Can't reach the Belay API! Is it running?")
        {:ignore, {:error, :unexpected}}
    end
  end
end
