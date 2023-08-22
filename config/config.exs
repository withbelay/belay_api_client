import Config

config :belay_api_client,
  token_cache_name: :belay_api_cache,
  token_cache_ttl: :timer.minutes(5),
  url: System.get_env("BELAY_API_URL") || "http://localhost:4000"

import_config "#{config_env()}.exs"
