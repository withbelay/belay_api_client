defmodule Smoke.PolicyUpdatesTest do
  use ExUnit.Case, async: false
  use AssertEventually, timeout: 1000, interval: 5

  alias BelayApiClient.PartnerSocket

  require Logger

  @sym "AAPL"
  @num_of_test_cases 2

  setup_all _ do
    opts = Application.get_all_env(:belay_api_client)
    client_id = Keyword.fetch!(opts, :client_id)
    client_secret = Keyword.fetch!(opts, :client_secret)
    host = Keyword.fetch!(opts, :ws_url)

    {:ok, %{access_token: token}} = BelayApiClient.fetch_token(client_id, client_secret)

    start_supervised!({AlpacaInvestors, num_investor_accounts: @num_of_test_cases})

    %{token: token, host: host}
  end

  setup %{token: token, host: host} do
    start_supervised!({PartnerSocket, test_pid: self(), host: host, token: token, stock_universe: [@sym]})

    assert_receive {"policy_updates", :joined, _}

    :ok
  end

  describe "when during market hours" do
    @describetag :smoke_open_hours

    test "buy policy and ensure activation", %{token: token} do
      {:ok, client} = BelayApiClient.client(token)

      # Fetch a investor that hasn't purchased a policy
      investor_id = AlpacaInvestors.fetch_investor()

      on_exit(fn ->
        # To ensure on next run we always use a fresh smoke test investor, close the one used
        {:ok, _} = Alpaca.create_order(@sym, "-1", investor_id)
        {:ok, _} = Alpaca.close_account(investor_id)
      end)

      # Buy 1 share of the stock we are about to get a policy on
      {:ok, _} = Alpaca.create_order(@sym, "1", investor_id)

      # Fetch first offering
      assert_receive {"offerings:#{@sym}", :joined, [offering | _]}

      # Translate data types
      expiration = offering["expiration"]
      qty = 1.0
      # FIXME: This shouldn't be necessary, we shouldn't be returning the money map
      strike = Float.to_string(offering["strike"]["amount"] / 100)
      purchase_limit_price = Float.to_string(offering["price"]["amount"] * 1.1 / 100)

      assert {:ok, %{"policy_id" => policy_id}} =
               BelayApiClient.buy_policy(client, investor_id, @sym, expiration, qty, strike, purchase_limit_price)

      assert_receive {"policy_updates", "policy_update:requested", %{"policy_id" => ^policy_id}}

      assert_receive {"policy_updates", "policy_update:activated", %{"policy_id" => ^policy_id}}

      # Fetch the policies owned for investor_id and make sure we see the new policy there
      assert {:ok, received_policies} = BelayApiClient.fetch_policies(client, investor_id)

      assert Enum.any?(received_policies, fn %{"policy_id" => received_policy_id} -> received_policy_id == policy_id end)

      # FIXME: We need to write a test that sells the stock, and makes sure qty changed gets invoked or doesn't depending on the market
      # {:ok, _} = Alpaca.create_order(@sym, "-0.5", investor_id)
      # if sym price > policy_strike, assert policy qty is the same
      # if sym price < policy_strike, assert policy qty is policy qty - qty sold
      # assert_receive {"policy_updates", "policy_update:qty_changed", %{"policy_id" => ^policy_id}}
    end

    test "check a policy purchase call respects a purchase limit price being surpassed", %{token: token} do
      {:ok, client} = BelayApiClient.client(token)

      # Fetch a investor that hasn't purchased a policy
      investor_id = AlpacaInvestors.fetch_investor()

      on_exit(fn ->
        # To ensure on next run we always use a fresh smoke test investor, close the one used
        {:ok, _} = Alpaca.create_order(@sym, "-1", investor_id)
        {:ok, _} = Alpaca.close_account(investor_id)
      end)

      # Buy 1 share of the stock we are about to get a policy on
      {:ok, _} = Alpaca.create_order(@sym, "1", investor_id)

      # Fetch first offering
      assert_receive {"offerings:#{@sym}", :joined, [offering | _]}

      # Translate data types
      expiration = offering["expiration"]
      qty = 1.0
      # FIXME: This shouldn't be necessary, we shouldn't be returning the money map
      strike = Float.to_string(offering["strike"]["amount"] / 100)

      # Normally purchase_limit_price would be near the price of the offering, but, here we want to set it to something that will force
      # a policy failure due to the purchase_limit_price being exceeded
      purchase_limit_price = Float.to_string(0.01)

      assert {:ok, %{"policy_id" => policy_id}} =
               BelayApiClient.buy_policy(client, investor_id, @sym, expiration, qty, strike, purchase_limit_price)

      assert_receive {"policy_updates", "policy_update:requested", %{"policy_id" => ^policy_id}}

      # FIXME: We need to add a assert_receive on a policy failed update, our code in belay-api currently does not emit it
      # assert_receive {"policy_updates", "policy_update:failed", %{"policy_id" => ^policy_id}}
      refute_receive {"policy_updates", "policy_update:activated", %{"policy_id" => ^policy_id}}

      # Fetch the policies owned for investor_id and make sure we don't see the new policy there
      assert {:ok, received_policies} = BelayApiClient.fetch_policies(client, investor_id)

      refute Enum.any?(received_policies, fn %{"policy_id" => received_policy_id} -> received_policy_id == policy_id end)
    end
  end
end
