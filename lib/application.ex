defmodule BelayApiClient.Application do
  use Application

  @impl true
  def start(_type, _args) do
    BelayApiOfferings.setup()

    children = children(Application.get_env(:belay_api_client, :env))
    opts = [strategy: :one_for_one, name: BelayApiClient.Supervisor]
    Supervisor.start_link(children, opts)
  end

  def children(:test) do
    [
      {Cachex, name: :belay_api_cache}
    ]
  end

  def children(_env) do
    opts = Application.get_all_env(:belay_api_client)
    client_id = Keyword.fetch!(opts, :client_id)
    client_secret = Keyword.fetch!(opts, :client_secret)
    offerings_host = Keyword.fetch!(opts, :offerings_host)
    stock_universe = Keyword.fetch!(opts, :stock_universe)

    {:commit, %{access_token: token}} = BelayApiClient.fetch_token(client_id, client_secret)

    children(:test) ++
      [
        {BelayApiOfferings, [host: offerings_host, token: token, stock_universe: stock_universe]}
      ]
  end
end
