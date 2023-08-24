defmodule BelayApiOfferingsTest do
  use ExUnit.Case, async: true
  use AssertEventually, timeout: 1000, interval: 5

  @tag integration: true
  test "connect to server and see that we're getting offerings" do
    assert :disconnected == BelayApiOfferings.status()

    opts = Application.get_all_env(:belay_api_client)
    client_id = Keyword.fetch!(opts, :client_id)
    client_secret = Keyword.fetch!(opts, :client_secret)

    host = "ws://localhost:4000"
    {:ok, %{access_token: token}} = BelayApiClient.fetch_cached_token(client_id, client_secret)

    BelayApiOfferings.start_link(host: host, token: token, stock_universe: ["AAPL"])

    assert_eventually(BelayApiOfferings.status() == :joined)

    offerings = BelayApiOfferings.fetch_offerings("AAPL")

    BelayApiOfferings.status()
    |> IO.inspect(option: :pretty, label: "; #{__ENV__.file}:#{__ENV__.line}")

    %{
      "expiration" => expiration,
      "price" => %{"amount" => _price, "currency" => "USD"},
      "strike" => %{"amount" => _strike, "currency" => "USD"},
      "sym" => "AAPL"
    } = hd(offerings)

    assert {:ok, _exp} = Date.from_iso8601(expiration)
  end
end
