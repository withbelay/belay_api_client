defmodule BelayApiClientTest do
  use ExUnit.Case, async: false

  alias BelayApiClient

  setup_all do
    token_cache_name = Application.get_env(:belay_api_client, :token_cache_name, :belay_api_cache)
    token_cache_ttl = Application.get_env(:belay_api_client, :token_cache_ttl, 5)
    {:ok, _pid} = Cachex.start_link(token_cache_name, ttl: token_cache_ttl)

    :ok
  end

  setup do
    bypass = Bypass.open(port: 1111)

    Application.put_env(:belay_api_client, :url, "http://localhost:1111")

    %{bypass: bypass, bypass_port: 1111}
  end

  @id UUID.uuid4()
  @client_id UUID.uuid4()
  @client_secret UUID.uuid4()
  @partner_id "belay_alpaca_sandbox_partner"
  @investor_id "b6df1a1f-b7d5-479f-9a1f-c79bead97203"

  describe "integration" do
    @describetag :integration

    setup do
      partner_id = :belay_alpaca_sandbox_partner
      opts = Application.get_env(:belay_api_client, partner_id)
      client_id = Keyword.fetch!(opts, :client_id)
      client_secret = Keyword.fetch!(opts, :client_secret)

      Application.put_env(:belay_api_client, :url, "http://localhost:4000")

      {:ok, client} = BelayApiClient.client(client_id, client_secret)

      %{client: client}
    end

    test "fetch_investor_id", %{client: client} do
      assert {:ok, :not_found} == BelayApiClient.fetch_investor_id(client, @partner_id, "some_email")
    end

    test "fetch_policies", %{client: client} do
      assert {:ok, []} == BelayApiClient.fetch_policies(client, @investor_id)
    end

    test "buy_policy", %{client: client} do
      assert {:ok, policy} = BelayApiClient.buy_policy(client, @investor_id, "AAPL", "2023-11-23", 10, 42)

      assert %{
               "expiration" => "2023-11-23",
               "investor_account_id" => "b6df1a1f-b7d5-479f-9a1f-c79bead97203",
               "partner_investor_id" => "b6df1a1f-b7d5-479f-9a1f-c79bead97203",
               #               "policy_id" => "bdc5de70-baaf-4600-837c-f6b2963b8ba2",
               "qty" => 10.0,
               "status" => "pending",
               "strike" => 0.42,
               "sym" => "AAPL"
             } = policy

      #      assert {:ok, ^policy} = BelayApiClient.buy_policy(@investor_id, "AAPL", "2023-11-23", 10, 42)
    end
  end

  describe "fetch_investor_id" do
    setup :create_client

    test "returns investor_id", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "POST", "/api/investors", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{"investor_id" => @id}))
      end)

      assert {:ok, @id} == BelayApiClient.fetch_investor_id(client, @partner_id, "some_email")
    end

    test "returns not found on 404", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "POST", "/api/investors", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(404, "")
      end)

      assert {:ok, :not_found} == BelayApiClient.fetch_investor_id(client, @partner_id, "some_email")
    end

    test "returns unexpected on 500", %{bypass: bypass, client: client} do
      expected_body = %{"error" => "unexpected", "error_detail" => "Something unexpected happened"}

      Bypass.expect_once(bypass, "POST", "/api/investors", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(500, Jason.encode!(expected_body))
      end)

      assert {:error, %{"error" => "unexpected", "error_detail" => "Something unexpected happened", "status" => 500}} ==
               BelayApiClient.fetch_investor_id(client, @partner_id, "some_email")
    end

    test "returns unexpected and logs on other statuses", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "POST", "/api/investors", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(418, Jason.encode!("I'm a teapot"))
      end)

      assert {:error, %{status: 418}} == BelayApiClient.fetch_investor_id(client, @partner_id, "some_email")
    end
  end

  describe "fetch_policies" do
    @other_investor_id UUID.uuid4()

    setup :create_client

    test "returns policies for the given investor id", %{bypass: bypass, client: client} do
      policy_a = %{
        "expiration" => "2023-01-01",
        "investor_account_id" => @investor_id,
        "partner_id" => "belay_alpaca_sandbox_partner",
        "partner_investor_id" => @investor_id,
        "policy_id" => "f3e7a7b0-002e-4df2-944e-93581ad2eea8",
        "qty" => 100.0,
        "status" => "expired",
        "strike" => 0.42,
        "sym" => "AAPL",
        "total_cost" => 42.0
      }

      policy_b = %{
        "expiration" => "2024-01-01",
        "investor_account_id" => @other_investor_id,
        "partner_id" => "belay_alpaca_sandbox_partner",
        "partner_investor_id" => @other_investor_id,
        "policy_id" => "ecfe75fc-ab09-4030-8fef-906f71632961",
        "qty" => 100.0,
        "status" => "expired",
        "strike" => 0.42,
        "sym" => "FB",
        "total_cost" => 42.0
      }

      expected_body = [
        policy_a,
        policy_b
      ]

      Bypass.expect_once(bypass, "GET", "/api/policies", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(expected_body))
      end)

      resp = BelayApiClient.fetch_policies(client, @investor_id)

      assert {:ok, [policy_a]} == resp
      refute {:ok, [policy_b]} == resp
      refute {:ok, [policy_a, policy_b]} == resp
    end

    test "returns unexpected and logs on other statuses", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "GET", "/api/policies", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(500, Jason.encode!(%{"error" => "unexpected", "error_detail" => "Sucks to be you"}))
      end)

      assert {
               :error,
               %{"error" => "unexpected", "error_detail" => "Sucks to be you", "status" => 500}
             } == BelayApiClient.fetch_policies(client, @investor_id)
    end
  end

  describe "fetch_oauth_token" do
    test "returns access_token and expires_in", %{bypass: bypass} do
      expected_body = %{"access_token" => "cool_token", "expires_in" => 3600}

      Bypass.expect_once(bypass, "POST", "/api/oauth/token", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(expected_body))
      end)

      assert {:commit, %{access_token: "cool_token", expires_in: 3600}} ==
               BelayApiClient.fetch_token(@client_id, @client_secret)
    end

    test "returns unprocessable and logs on 422", %{bypass: bypass} do
      expected_body = %{"error" => "unprocessable", "error_detail" => "We can't process your request"}

      Bypass.expect_once(bypass, "POST", "/api/oauth/token", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(422, Jason.encode!(expected_body))
      end)

      assert {
               :error,
               %{"error" => "unprocessable", "error_detail" => "We can't process your request", "status" => 422}
             } == BelayApiClient.fetch_token(@client_id, @client_secret)
    end

    test "returns unexpected and logs on 500", %{bypass: bypass} do
      expected_body = %{"error" => "unexpected", "error_detail" => "Something unexpected happened"}

      Bypass.expect_once(bypass, "POST", "/api/oauth/token", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(500, Jason.encode!(expected_body))
      end)

      assert {
               :error,
               %{"error" => "unexpected", "error_detail" => "Something unexpected happened", "status" => 500}
             } == BelayApiClient.fetch_token(@client_id, @client_secret)
    end

    test "returns unexpected and logs on other statuses", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/api/oauth/token", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(418, Jason.encode!("No coffee, just tea"))
      end)

      assert {:error, %{status: 418}} == BelayApiClient.fetch_token(@client_id, @client_secret)
    end
  end

  describe "buy_policy" do
    setup :create_client

    test "returns policy request", %{bypass: bypass, client: client} do
      expected_body = %{"test" => "body"}

      Bypass.expect_once(bypass, "POST", "/api/policies", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(expected_body))
      end)

      assert {:ok, expected_body} ==
               BelayApiClient.buy_policy(client, @investor_id, "AAPL", "2023-11-23", 10, 42)
    end
  end

  defp create_client(context) do
    expect_token_request(context)

    {:ok, client} = BelayApiClient.client(UUID.uuid4(), UUID.uuid4())

    %{client: client}
  end

  defp expect_token_request(context) do
    Bypass.expect_once(context.bypass, "POST", "/api/oauth/token", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, Jason.encode!(%{"access_token" => "cool_token", "expires_in" => 3600}))
    end)
  end
end
