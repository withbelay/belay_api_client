defmodule Smoke.PolicyUpdatesTest do
  use ExUnit.Case, async: false
  use AssertEventually, timeout: 1000, interval: 5

  alias BelayApiClient.PartnerSocket
  alias AlpacaInvestors.AlpacaClient

  require Logger

  @sym "AAPL"
  @num_of_test_cases 2

  setup_all _ do
    opts = Application.get_all_env(:belay_api_client)
    client_id = Keyword.fetch!(opts, :client_id)
    client_secret = Keyword.fetch!(opts, :client_secret)
    partner_id = Keyword.fetch!(opts, :partner_id)
    host = Keyword.fetch!(opts, :ws_url)

    {:ok, %{access_token: token}} = BelayApiClient.fetch_token(client_id, client_secret)

    start_supervised!({AlpacaInvestors, num_investor_accounts: @num_of_test_cases})

    %{token: token, host: host, partner_id: partner_id}
  end

  setup %{token: token, host: host, partner_id: partner_id} do
    policy_updates_topic = "partner:policy_updates:#{partner_id}"
    offerings_topic = "offerings:#{partner_id}:#{@sym}"

    start_supervised!({PartnerSocket, test_pid: self(), host: host, token: token, stock_universe: [@sym], partner_id: partner_id})
    assert_receive {^policy_updates_topic, :joined, _}

    %{policy_updates_topic: policy_updates_topic, offerings_topic: offerings_topic}
  end

  describe "when during market hours" do
    @describetag :smoke_open_hours

    test "buy policy and ensure activation", %{token: token, policy_updates_topic: policy_updates_topic, offerings_topic: offerings_topic} do
      {:ok, client} = BelayApiClient.client(token)

      # Fetch a investor that hasn't purchased a policy
      investor_id = AlpacaInvestors.fetch_investor()

      # Buy 1 share of the stock we are about to get a policy on
      {:ok, _} = AlpacaClient.create_buy_order(@sym, "1", investor_id)

      # Fetch first offering
      assert_receive {^offerings_topic, :joined, [offering | _]}

      # Translate data types
      expiration = offering["expiration"]
      qty = 1.0
      strike = offering["strike"]
      purchase_limit_price = offering["price"] |> String.to_float() |> Kernel.*(1.1) |> Float.to_string()

      assert {:ok, %{"policy_id" => policy_id}} =
               BelayApiClient.buy_policy(client, investor_id, @sym, expiration, qty, strike, purchase_limit_price)

      assert_receive {^policy_updates_topic, "policy_update:requested", %{"policy_id" => ^policy_id}}

      assert_receive {^policy_updates_topic, "policy_update:activated", %{"policy_id" => ^policy_id}}

      # Fetch the policies owned for investor_id and make sure we see the new policy there
      assert {:ok, received_policies} = BelayApiClient.fetch_policies(client, investor_id)

      assert Enum.any?(received_policies, fn %{"policy_id" => received_policy_id} -> received_policy_id == policy_id end)

      # FIXME: We need to write a test that sells the stock, and makes sure qty changed gets invoked or doesn't depending on the market
      # {:ok, _} = AlpacaClient.create_order(@sym, "-0.5", investor_id)
      # if sym price > policy_strike, assert policy qty is the same
      # if sym price < policy_strike, assert policy qty is policy qty - qty sold
      # assert_receive {"policy_updates", "policy_update:qty_changed", %{"policy_id" => ^policy_id}}
    end

    test "check a policy purchase call respects a purchase limit price being surpassed", %{token: token, policy_updates_topic: policy_updates_topic, offerings_topic: offerings_topic} do
      {:ok, client} = BelayApiClient.client(token)

      # Fetch a investor that hasn't purchased a policy
      investor_id = AlpacaInvestors.fetch_investor()

      # Buy 1 share of the stock we are about to get a policy on
      {:ok, _} = AlpacaClient.create_buy_order(@sym, "1", investor_id)

      # Fetch first offering
      assert_receive {^offerings_topic, :joined, [offering | _]}

      # Translate data types
      expiration = offering["expiration"]
      qty = 1.0
      strike = offering["strike"]

      # Normally purchase_limit_price would be near the price of the offering, but, here we want to set it to something that will force
      # a policy failure due to the purchase_limit_price being exceeded
      purchase_limit_price = Float.to_string(0.01)

      assert {:ok, %{"policy_id" => policy_id}} =
               BelayApiClient.buy_policy(client, investor_id, @sym, expiration, qty, strike, purchase_limit_price)

      assert_receive {^policy_updates_topic, "policy_update:requested", %{"policy_id" => ^policy_id}}

      # FIXME: We need to add a assert_receive on a policy failed update, our code in belay-api currently does not emit it
      # assert_receive {"policy_updates", "policy_update:failed", %{"policy_id" => ^policy_id}}
      refute_receive {^policy_updates_topic, "policy_update:activated", %{"policy_id" => ^policy_id}}

      # Fetch the policies owned for investor_id and make sure we don't see the new policy there
      assert {:ok, received_policies} = BelayApiClient.fetch_policies(client, investor_id)

      refute Enum.any?(received_policies, fn %{"policy_id" => received_policy_id} -> received_policy_id == policy_id end)
    end
  end
end
