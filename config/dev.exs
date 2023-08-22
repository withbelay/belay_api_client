import Config

config :belay_api_client,
  token_cache_name: :belay_api_cache,
  token_cache_ttl: :timer.minutes(5),
  url: System.get_env("BELAY_API_URL") || "http://localhost:4000",
  partners: [:belay_alpaca_sandbox_partner]

config :belay_api_client, :belay_alpaca_sandbox_partner,
  client_id: System.fetch_env!("BELAY_API_PARTNER_CLIENT_ID"),
  client_secret: System.fetch_env!("BELAY_API_PARTNER_CLIENT_SECRET")
