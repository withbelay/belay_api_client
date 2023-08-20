defmodule BelayApiClientTest do
  use ExUnit.Case, async: true

  alias BelayApiClient

  setup do
    bypass = Bypass.open(port: 1111)

    %{bypass: bypass, bypass_port: 1111}
  end

  @id UUID.uuid4()
  @partner_id "belay_alpaca_sandbox_partner"
  @investor_id "b6df1a1f-b7d5-479f-9a1f-c79bead97203"

  describe "integration" do
    @describetag :integration

    setup do
      url  = Application.get_env(:belay_api_client, :url)
      client_id = Application.get_env(:belay_api_client, :client_id)
      client_secret = Application.get_env(:belay_api_client, :client_secret)
      partner_id = Application.get_env(:belay_api_client, :partner_id)

      {:ok, _pid} =
        BelayApiClient.start_link(
          client_id: client_id,
          client_secret: client_secret,
          partner_id: partner_id,
          belay_api_url: url
        )

      :ok
    end

    test "fetch_investor_id" do
      assert {:ok, :not_found} == BelayApiClient.fetch_investor_id("some_email")
    end

    test "fetch_policies" do
      assert {:ok, []} == BelayApiClient.fetch_policies(@investor_id)
    end

    test "buy_policy" do
      assert {:ok, policy} = BelayApiClient.buy_policy(@investor_id, "AAPL", "2023-11-23", 10, 42)

      assert %{
               "expiration" => "2023-11-23",
               "investor_account_id" => "b6df1a1f-b7d5-479f-9a1f-c79bead97203",
               "partner_id" => "belay_alpaca_sandbox_partner",
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
    setup [:start_client, :expect_token_request]

    test "returns investor_id", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/api/investors", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{"investor_id" => @id}))
      end)

      assert {:ok, @id} == BelayApiClient.fetch_investor_id("some_email")
    end

    test "returns not found on 404", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/api/investors", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(404, "")
      end)

      assert {:ok, :not_found} == BelayApiClient.fetch_investor_id("some_email")
    end

    test "returns unexpected and logs on 500", %{bypass: bypass} do
      expected_body = %{"error" => "unexpected", "error_detail" => "Something unexpected happened"}

      Bypass.expect_once(bypass, "POST", "/api/investors", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(500, Jason.encode!(expected_body))
      end)

      assert {:error, %{"error" => "unexpected", "error_detail" => "Something unexpected happened", "status" => 500}} ==
               BelayApiClient.fetch_investor_id("some_email")
    end

    test "returns unexpected and logs on other statuses", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/api/investors", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(418, Jason.encode!("I'm a teapot"))
      end)

      assert {:error, %{status: 418}} == BelayApiClient.fetch_investor_id("some_email")
    end

    test "returns unexpected if client can't be created", %{bypass: bypass} do
      Cachex.del(:investor_web_cache, :belay_token)

      expected_body = %{"error" => "unexpected", "error_detail" => "We can't process your request"}

      Bypass.expect_once(bypass, "POST", "/api/oauth/token", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(500, Jason.encode!(expected_body))
      end)

      assert {
               :error_fetching_token,
               %{"error" => "unexpected", "error_detail" => "We can't process your request", "status" => 500}
             } == BelayApiClient.fetch_investor_id("some_email")
    end
  end

  describe "fetch_policies" do
    @other_investor_id UUID.uuid4()

    setup [:start_client, :expect_token_request]

    test "returns policies for the given investor id", %{bypass: bypass} do
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

      resp = BelayApiClient.fetch_policies(@investor_id)

      assert {:ok, [policy_a]} == resp
      refute {:ok, [policy_b]} == resp
      refute {:ok, [policy_a, policy_b]} == resp
    end

    test "returns unexpected and logs on other statuses", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/api/policies", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(500, Jason.encode!(%{"error" => "unexpected", "error_detail" => "Sucks to be you"}))
      end)

      assert {
               :error,
               %{"error" => "unexpected", "error_detail" => "Sucks to be you", "status" => 500}
             } == BelayApiClient.fetch_policies(@investor_id)
    end
  end

  describe "fetch_oauth_token" do
    setup :start_client

    test "returns access_token and expires_in", %{bypass: bypass, state: state} do
      expected_body = %{"access_token" => "cool_token", "expires_in" => 3600}

      Bypass.expect_once(bypass, "POST", "/api/oauth/token", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(expected_body))
      end)

      assert {:commit, %{access_token: "cool_token", expires_in: 3600}} ==
               BelayApiClient.fetch_oauth_token(state)
    end

    test "returns unprocessable and logs on 422", %{bypass: bypass, state: state} do
      expected_body = %{"error" => "unprocessable", "error_detail" => "We can't process your request"}

      Bypass.expect_once(bypass, "POST", "/api/oauth/token", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(422, Jason.encode!(expected_body))
      end)

      assert {
               :error,
               %{"error" => "unprocessable", "error_detail" => "We can't process your request", "status" => 422}
             } == BelayApiClient.fetch_oauth_token(state)
    end

    test "returns unexpected and logs on 500", %{bypass: bypass, state: state} do
      expected_body = %{"error" => "unexpected", "error_detail" => "Something unexpected happened"}

      Bypass.expect_once(bypass, "POST", "/api/oauth/token", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(500, Jason.encode!(expected_body))
      end)

      assert {
               :error,
               %{"error" => "unexpected", "error_detail" => "Something unexpected happened", "status" => 500}
             } == BelayApiClient.fetch_oauth_token(state)
    end

    test "returns unexpected and logs on other statuses", %{bypass: bypass, state: state} do
      Bypass.expect_once(bypass, "POST", "/api/oauth/token", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(418, Jason.encode!("No coffee, just tea"))
      end)

      assert {:error, %{status: 418}} == BelayApiClient.fetch_oauth_token(state)
    end
  end

  describe "buy_policy" do
    setup [:start_client, :expect_token_request]

    test "returns policy request", %{bypass: bypass} do
      expected_body = %{"test" => "body"}

      Bypass.expect_once(bypass, "POST", "/api/policies", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(expected_body))
      end)

      assert {:ok, expected_body} ==
               BelayApiClient.buy_policy(@investor_id, "AAPL", "2023-11-23", 10, 42)
    end
  end

  defp start_client(context) do
    cache_name = :"#{__MODULE__}_#{context.test}_#{context.line}"

    {:ok, pid} =
      BelayApiClient.start_link(
        client_id: "client_id",
        client_secret: "client_secret",
        belay_api_url: "http://localhost:#{context.bypass_port}",
        partner_id: @partner_id,
        token_cache_name: cache_name
      )

    state = :sys.get_state(pid)

    assert %BelayApiClient.State{
             client_id: "client_id",
             client_secret: "client_secret",
             partner_id: @partner_id,
             token_cache_name: cache_name,
             token_cache_ttl: 300_000,
             url: "http://localhost:#{context.bypass_port}"
           } == state

    %{state: state, pid: pid, cache_name: cache_name}
  end

  defp expect_token_request(context) do
    Bypass.expect_once(context.bypass, "POST", "/api/oauth/token", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, Jason.encode!(%{"access_token" => "cool_token", "expires_in" => 3600}))
    end)
  end
end
