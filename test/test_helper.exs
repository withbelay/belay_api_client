# Increase assert_receive timeout for all tests since smoke and integration tests may take longer
ExUnit.configure(assert_receive_timeout: :timer.minutes(1), timeout: :timer.minutes(3))

# Figure out if smoke tests are being called
is_smoke = :smoke in ExUnit.configuration()[:include]

# Figure out if market is open
client_id = Application.fetch_env!(:belay_api_client, :client_id)
client_secret = Application.fetch_env!(:belay_api_client, :client_secret)
{:ok, client} = BelayApiClient.client(client_id, client_secret)
{:ok, %{is_open: is_market_open}} = BelayApiClient.fetch_market_clock(client)

cond do
  is_smoke and is_market_open ->
    ExUnit.start(include: [smoke_open_hours: true], exclude: [integration: true, smoke_closed_hours: true])

  is_smoke ->
    ExUnit.start(include: [smoke_closed_hours: true], exclude: [integration: true, smoke_open_hours: true])

  true ->
    ExUnit.start(exclude: [integration: true, smoke_open_hours: true, smoke_closed_hours: true])
end
