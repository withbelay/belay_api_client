defmodule Smoke.PolicyUpdatesTest do
  use ExUnit.Case, async: false
  use AssertEventually, timeout: 1000, interval: 5
  @moduletag :smoke

  alias BelayApiClient.PartnerSocket

  @investor_id "b6df1a1f-b7d5-479f-9a1f-c79bead97203"

  setup _ do
    opts = Application.get_all_env(:belay_api_client)
    client_id = Keyword.fetch!(opts, :client_id)
    client_secret = Keyword.fetch!(opts, :client_secret)

    host = "ws://localhost:4000"
    {:commit, %{access_token: token}} = BelayApiClient.fetch_token(client_id, client_secret)

    pid = start_supervised!({PartnerSocket, test_pid: self(), host: host, token: token, stock_universe: ["AAPL"]})

    assert_receive {"policy_updates", :joined, _}

    %{token: token, host: host, pid: pid, client_id: client_id, client_secret: client_secret}
  end

  test "foo", acc do
    {:ok, client} = BelayApiClient.client(acc.client_id, acc.client_secret)

    assert {:ok, %{"policy_id" => policy_id}} = BelayApiClient.buy_policy(client, @investor_id, "AAPL", "2023-11-23", 10, 42)

    assert_receive {"policy_updates", "policy_update:requested", %{"policy_id" => ^policy_id}}
  end
end
