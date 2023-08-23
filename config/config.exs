import Config

config :belay_api_client,
  env: config_env(),
  stock_universe: ["AAPL", "TSLA"],
  token_cache_name: :belay_api_cache,
  token_cache_ttl: :timer.minutes(5),
  api_url: System.get_env("BELAY_API_URL") || "http://localhost:4000",
  offerings_host: System.get_env("BELAY_API_OFFERINGS") || "ws://localhost:4000",
  partner_id: System.get_env("BELAY_API_PARTNER_ID") || "belay_alpaca",
  client_id: System.get_env("BELAY_API_CLIENT_ID") || System.fetch_env!("BELAY_ALPACA__AUTH0__CLIENT_ID"),
  client_secret: System.fetch_env!("BELAY_API_CLIENT_SECRET") || System.fetch_env!("BELAY_ALPACA__AUTH0__CLIENT_SECRET")

config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"
