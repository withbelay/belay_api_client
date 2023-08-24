defmodule BelayApiClient.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [{Cachex, name: :belay_api_cache}]
    opts = [strategy: :one_for_one, name: BelayApiClient.Supervisor]

    Supervisor.start_link(children, opts)
  end
end
