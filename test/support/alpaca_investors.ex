defmodule AlpacaInvestors do
  @moduledoc """
  Used for smoke tests that need alpaca investor ids that are new and unused. A unused alpaca investor means:
  - it has a starting amount of cash
  - it hasn't purchased anything
  - it is active and ready to be used in any alpaca API call
  """
  use Agent

  alias Alpaca

  def start_link(num_investor_accounts: num_of_investor_accounts) do
    {:ok, investors} = Alpaca.get_active_smoke_accounts(num_of_investor_accounts)
    investor_ids = Enum.map(investors, &Map.fetch!(&1, "id"))

    Agent.start_link(fn -> investor_ids end, name: __MODULE__)
  end

  def fetch_investor do
    Agent.get_and_update(__MODULE__, fn investor_ids ->
      [investor_id | investor_ids] = investor_ids

      Task.start_link(fn -> Alpaca.create_funded_user() end)

      {investor_id, investor_ids}
    end)
  end
end
