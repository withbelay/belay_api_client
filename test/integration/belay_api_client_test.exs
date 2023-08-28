defmodule Integration.BelayApiClientTest do
  use ExUnit.Case, async: false

  @moduletag :integration

  @partner_id Application.compile_env!(:belay_api_client, :partner_id)
  @investor_id "b6df1a1f-b7d5-479f-9a1f-c79bead97203"

  describe "integration" do
    test "fetch_token" do
      {client_id, client_secret} = get_real_ids()

      {:commit, %{access_token: _}} = BelayApiClient.fetch_token(client_id, client_secret)
    end

    test "fetch_cached_token" do
      {client_id, client_secret} = get_real_ids()

      BelayApiClient.fetch_cached_token(client_id, client_secret)
    end

    test "fetch_investor_id" do
      client = create_real_client()

      assert {:error, %{error: "not_found", status: 404, error_detail: "Investor not found"}} ==
               BelayApiClient.fetch_investor_id(client, @partner_id, "some_email")
    end

    test "fetch_policies" do
      client = create_real_client()
      assert {:ok, []} == BelayApiClient.fetch_policies(client, @investor_id)
    end

    test "buy_policy" do
      client = create_real_client()
      assert {:ok, policy} = BelayApiClient.buy_policy(client, @investor_id, "AAPL", "2023-11-23", 10, 42)

      assert %{
               "expiration" => "2023-11-23",
               "investor_account_id" => "b6df1a1f-b7d5-479f-9a1f-c79bead97203",
               "partner_investor_id" => "b6df1a1f-b7d5-479f-9a1f-c79bead97203",
               #               "policy_id" => "bdc5de70-baaf-4600-837c-f6b2963b8ba2",
               "qty" => "10",
               "status" => "pending",
               "strike" => %{"amount" => 42, "currency" => "USD"},
               "sym" => "AAPL"
             } = policy

      #      assert {:ok, ^policy} = BelayApiClient.buy_policy(@investor_id, "AAPL", "2023-11-23", 10, 42)
    end
  end

  defp get_real_ids() do
    opts = Application.get_all_env(:belay_api_client)
    client_id = Keyword.fetch!(opts, :client_id)
    client_secret = Keyword.fetch!(opts, :client_secret)

    {client_id, client_secret}
  end

  defp create_real_client() do
    {client_id, client_secret} = get_real_ids()

    Application.put_env(:belay_api_client, :api_url, "http://localhost:4000")

    {:ok, client} = BelayApiClient.client(client_id, client_secret)
    client
  end
end
