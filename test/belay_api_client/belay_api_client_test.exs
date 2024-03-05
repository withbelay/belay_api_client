defmodule BelayApiClientTest do
  use ExUnit.Case, async: false

  setup do
    bypass = Bypass.open(port: 1111)

    prior_api_url = Application.fetch_env!(:belay_api_client, :api_url)
    Application.put_env(:belay_api_client, :api_url, "http://localhost:1111")

    on_exit(fn ->
      Application.put_env(:belay_api_client, :api_url, prior_api_url)
    end)

    %{bypass: bypass, bypass_port: 1111}
  end

  @id UUID.uuid4()
  @client_id UUID.uuid4()
  @client_secret UUID.uuid4()
  @partner_id Application.compile_env!(:belay_api_client, :partner_id)
  @investor_id "b6df1a1f-b7d5-479f-9a1f-c79bead97203"

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

      assert {:error, %{status: 404}} == BelayApiClient.fetch_investor_id(client, @partner_id, "some_email")
    end

    test "returns unexpected on 500", %{bypass: bypass, client: client} do
      expected_body = %{"error" => "unexpected", "error_detail" => "Something unexpected happened"}

      Bypass.expect_once(bypass, "POST", "/api/investors", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(500, Jason.encode!(expected_body))
      end)

      assert {:error, %{error: "unexpected", error_detail: "Something unexpected happened", status: 500}} ==
               BelayApiClient.fetch_investor_id(client, @partner_id, "some_email")
    end

    test "returns unexpected on other statuses", %{bypass: bypass, client: client} do
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

    test "returns unexpected on other statuses", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "GET", "/api/policies", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(500, Jason.encode!(%{"error" => "unexpected", "error_detail" => "Sucks to be you"}))
      end)

      assert {
               :error,
               %{error: "unexpected", error_detail: "Sucks to be you", status: 500}
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

      assert {:ok, %{access_token: "cool_token", expires_in: 3600}} ==
               BelayApiClient.fetch_token(@client_id, @client_secret)
    end

    test "returns unprocessable on 422", %{bypass: bypass} do
      expected_body = %{"error" => "unprocessable", "error_detail" => "We can't process your request"}

      Bypass.expect_once(bypass, "POST", "/api/oauth/token", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(422, Jason.encode!(expected_body))
      end)

      assert {
               :error,
               %{error: "unprocessable", error_detail: "We can't process your request", status: 422}
             } == BelayApiClient.fetch_token(@client_id, @client_secret)
    end

    test "returns unexpected on 500", %{bypass: bypass} do
      expected_body = %{"error" => "unexpected", "error_detail" => "Something unexpected happened"}

      Bypass.expect_once(bypass, "POST", "/api/oauth/token", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(500, Jason.encode!(expected_body))
      end)

      assert {
               :error,
               %{error: "unexpected", error_detail: "Something unexpected happened", status: 500}
             } == BelayApiClient.fetch_token(@client_id, @client_secret)
    end

    test "returns unexpected on other statuses", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/api/oauth/token", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(418, Jason.encode!("No coffee, just tea"))
      end)

      assert {:error, %{status: 418}} == BelayApiClient.fetch_token(@client_id, @client_secret)
    end
  end

  describe "fetch_investor_token" do
    setup :create_client

    test "returns token", %{bypass: bypass, client: client} do
      expected_body = %{"token" => "1234"}

      Bypass.expect_once(bypass, "GET", "/api/investors/#{@investor_id}/token", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(expected_body))
      end)

      assert {:ok, %{token: "1234"}} == BelayApiClient.fetch_investor_token(client, @investor_id)
    end

    test "returns forbidden on 403", %{bypass: bypass, client: client} do
      expected_body = %{"error" => "unprocessable", "error_detail" => "We can't process your request"}

      Bypass.expect_once(bypass, "GET", "/api/investors/#{@investor_id}/token", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(403, Jason.encode!(expected_body))
      end)

      assert {
               :error,
               %{error: "unprocessable", error_detail: "We can't process your request", status: 403}
             } == BelayApiClient.fetch_investor_token(client, @investor_id)
    end

    test "returns not found on 404", %{bypass: bypass, client: client} do
      expected_body = %{"error" => "invalid_id", "error_detail" => "Investor ID supplied is invalid"}

      Bypass.expect_once(bypass, "GET", "/api/investors/#{@investor_id}/token", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(404, Jason.encode!(expected_body))
      end)

      assert {:error, %{error: "invalid_id", status: 404, error_detail: "Investor ID supplied is invalid"}} ==
               BelayApiClient.fetch_investor_token(client, @investor_id)
    end

    test "returns unexpected on other statuses", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "GET", "/api/investors/#{@investor_id}/token", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(418, Jason.encode!("No coffee, just tea"))
      end)

      assert {:error, %{status: 418}} == BelayApiClient.fetch_investor_token(client, @investor_id)
    end
  end

  describe "fetch_investor_holdings" do
    setup :create_client

    test "returns holdings", %{bypass: bypass, client: client} do
      expected_body = %{
        "holdings" => %{
          "qty" => 1.0,
          "sym" => "AAPL",
          "market_value" => 1.0,
          "unrealized_pl" => 1.0,
          "unrealized_plpc" => 0.5
        }
      }

      Bypass.expect_once(bypass, "GET", "/api/investors/#{@investor_id}/holdings", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(expected_body))
      end)

      assert {:ok,
              %{"market_value" => 1.0, "qty" => 1.0, "sym" => "AAPL", "unrealized_pl" => 1.0, "unrealized_plpc" => 0.5}} ==
               BelayApiClient.fetch_investor_holdings(client, @investor_id)
    end

    test "returns forbidden on 403", %{bypass: bypass, client: client} do
      expected_body = %{"error" => "unprocessable", "error_detail" => "We can't process your request"}

      Bypass.expect_once(bypass, "GET", "/api/investors/#{@investor_id}/holdings", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(403, Jason.encode!(expected_body))
      end)

      assert {
               :error,
               %{error: "unprocessable", error_detail: "We can't process your request", status: 403}
             } == BelayApiClient.fetch_investor_holdings(client, @investor_id)
    end

    test "returns not found on 404", %{bypass: bypass, client: client} do
      expected_body = %{"error" => "invalid_id", "error_detail" => "Investor ID supplied is invalid"}

      Bypass.expect_once(bypass, "GET", "/api/investors/#{@investor_id}/holdings", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(404, Jason.encode!(expected_body))
      end)

      assert {:error, %{error: "invalid_id", status: 404, error_detail: "Investor ID supplied is invalid"}} ==
               BelayApiClient.fetch_investor_holdings(client, @investor_id)
    end

    test "returns unexpected on other statuses", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "GET", "/api/investors/#{@investor_id}/holdings", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(418, Jason.encode!("No coffee, just tea"))
      end)

      assert {:error, %{status: 418}} == BelayApiClient.fetch_investor_holdings(client, @investor_id)
    end
  end

  describe "fetch_market_clock" do
    setup :create_client

    test "returns market clock", %{bypass: bypass, client: client} do
      expected_body = %{"is_open" => true, "opens_in" => 0}

      Bypass.expect_once(bypass, "GET", "/api/market/clock", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(expected_body))
      end)

      assert {:ok, %{is_open: true, opens_in: 0}} == BelayApiClient.fetch_market_clock(client)
    end
  end

  describe "fetch_market_stock_universe" do
    setup :create_client

    test "returns market stock universe", %{bypass: bypass, client: client} do
      expected_stock_universe = ["AAPL", "TSLA", "MSFT"]
      expected_body = %{"stock_universe" => expected_stock_universe}

      Bypass.expect_once(bypass, "GET", "/api/market/stock_universe", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(expected_body))
      end)

      assert BelayApiClient.fetch_market_stock_universe(client) == {:ok, expected_stock_universe}
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
               BelayApiClient.buy_policy(client, @investor_id, "AAPL", "2023-11-23", 10, 42, 100)
    end

    test "returns policy request when provided discount code", %{bypass: bypass, client: client} do
      expected_body = %{"test" => "body"}

      Bypass.expect_once(bypass, "POST", "/api/policies", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(expected_body))
      end)

      assert {:ok, expected_body} ==
               BelayApiClient.buy_policy(client, @investor_id, "AAPL", "2023-11-23", 10, 42, 100, "cool_code")
    end
  end

  describe "apply_discount_code" do
    setup :create_client

    test "returns discount", %{bypass: bypass, client: client} do
      code = "my_cool_discount"
      expected_body = %{valid: true, discount_info: %{"code" => code}, discounted_price: 42.0}

      Bypass.expect_once(bypass, "POST", "/api/discount/apply/#{code}", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(expected_body))
      end)

      assert {:ok, expected_body} == BelayApiClient.apply_discount_code(client, @investor_id, code, 50.0)
    end

    test "returns discount when investor id is nil", %{bypass: bypass, client: client} do
      code = "my_cool_discount"
      expected_body = %{valid: true, discount_info: %{"code" => code}, discounted_price: 42.0}

      Bypass.expect_once(bypass, "POST", "/api/discount/apply/#{code}", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(expected_body))
      end)

      assert {:ok, expected_body} == BelayApiClient.apply_discount_code(client, nil, code, 50.0)
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
