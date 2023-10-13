import Config

config :belay_api_client,
  api_url: System.get_env("BELAY_API_URL", "http://localhost:4000"),
  partner_id: System.get_env("BELAY_API_PARTNER_ID", "belay_alpaca"),
  client_id: System.fetch_env!("BELAYALPACA__AUTH0__CLIENT_ID"),
  client_secret: System.fetch_env!("BELAYALPACA__AUTH0__CLIENT_SECRET")

# cached_token: "your belay oauth token here"

import_config "#{config_env()}.exs"
