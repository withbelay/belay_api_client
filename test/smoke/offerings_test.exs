defmodule Smoke.OfferingsTest do
  use ExUnit.Case, async: false
  use AssertEventually, timeout: 1000, interval: 5

  alias BelayApiClient.PartnerSocket

  @sym "AAPL"

  describe "when during market hours" do
    @describetag :smoke_open_hours

    test "connect to server and see that we're getting offerings" do
      opts = Application.get_all_env(:belay_api_client)
      client_id = Keyword.fetch!(opts, :client_id)
      client_secret = Keyword.fetch!(opts, :client_secret)
      host = Keyword.fetch!(opts, :ws_url)

      {:commit, %{access_token: token}} = BelayApiClient.fetch_token(client_id, client_secret)

      start_supervised!({PartnerSocket, test_pid: self(), host: host, token: token, stock_universe: [@sym]})

      expected_topic = "offerings:#{@sym}"

      assert_receive {^expected_topic, :joined, offerings}

      assert %{
               "expiration" => expiration,
               "price" => %{"amount" => _price, "currency" => "USD"},
               "strike" => %{"amount" => _strike, "currency" => "USD"},
               "sym" => "AAPL"
             } = hd(offerings)

      assert {:ok, _exp} = Date.from_iso8601(expiration)
    end
  end

  describe "when off market hours" do
    @describetag :smoke_closed_hours

    test "there are no offerings" do
    end
  end
end
