defmodule Smoke.OfferingsTest do
  use ExUnit.Case, async: false
  use AssertEventually, timeout: 1000, interval: 5

  alias BelayApiClient.PartnerSocket

  @sym "AAPL"

  setup_all _ do
    opts = Application.get_all_env(:belay_api_client)
    client_id = Keyword.fetch!(opts, :client_id)
    client_secret = Keyword.fetch!(opts, :client_secret)
    host = Keyword.fetch!(opts, :ws_url)

    {:ok, %{access_token: token}} = BelayApiClient.fetch_token(client_id, client_secret)

    %{token: token, host: host}
  end

  setup %{token: token, host: host} do
    start_supervised!({PartnerSocket, test_pid: self(), host: host, token: token, stock_universe: [@sym]})

    :ok
  end

  describe "when during market hours" do
    @describetag :smoke_open_hours

    test "connect to server and see that we're getting offerings" do
      expected_topic = "offerings:#{@sym}"

      assert_receive {^expected_topic, :joined, offerings}

      assert %{
               "expiration" => expiration,
               "price" => _,
               "strike" => _,
               "sym" => "AAPL"
             } = hd(offerings)

      assert {:ok, _exp} = Date.from_iso8601(expiration)
    end
  end

  describe "when off market hours" do
    @describetag :smoke_closed_hours

    test "there are no offerings" do
      expected_topic = "offerings:#{@sym}"
      assert_receive {^expected_topic, :joined, []}
    end
  end
end
