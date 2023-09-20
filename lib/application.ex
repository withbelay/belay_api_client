defmodule BelayApiClient.Application do
  use Application

  @impl true
  def start(_type, _args) do
    opts = [strategy: :one_for_one, name: BelayApiClient.Supervisor]

    Supervisor.start_link([], opts)
  end
end
