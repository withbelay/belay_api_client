import Config

base_url = System.get_env("BELAY_API_BASE_URL", "localhost:4000")

config :belay_api_client,
  env: config_env(),
  stock_universe: ["AAPL", "TSLA"],
  token_cache_name: :belay_api_cache,
  token_cache_ttl: :timer.minutes(5),
  api_url: (if String.starts_with?(base_url, "localhost"), do: "http://#{base_url}", else: "https://#{base_url}"),
  ws_url: (if String.starts_with?(base_url, "localhost"), do: "ws://#{base_url}", else: "wss://#{base_url}"),
  partner_id: System.get_env("BELAY_API_PARTNER_ID", "belay_alpaca"),
  client_id: System.fetch_env!("BELAY_API_AUTH0_CLIENT_ID"),
  client_secret: System.fetch_env!("BELAY_API_AUTH0_CLIENT_SECRET")

import_config "#{config_env()}.exs"
