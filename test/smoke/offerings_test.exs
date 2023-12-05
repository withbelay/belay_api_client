defmodule Smoke.OfferingsTest do
  use ExUnit.Case, async: false
  use AssertEventually, timeout: 1000, interval: 5

  alias BelayApiClient.PartnerSocket

  @sym "AAPL"

  setup_all _ do
    opts = Application.get_all_env(:belay_api_client)
    client_id = Keyword.fetch!(opts, :client_id)
    client_secret = Keyword.fetch!(opts, :client_secret)
    partner_id = Keyword.fetch!(opts, :partner_id)
    host = Keyword.fetch!(opts, :ws_url)

    {:ok, %{access_token: token}} = BelayApiClient.fetch_token(client_id, client_secret)

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

    test "connect to server and see that we're getting offerings", %{offerings_topic: offerings_topic} do
      assert_receive {^offerings_topic, :joined, offerings}

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

    test "there are no offerings", %{offerings_topic: offerings_topic} do
      assert_receive {^offerings_topic, :joined, []}
    end
  end
end
