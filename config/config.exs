import Config

config :belay_api_client,
  url: System.get_env("BELAY_API_URL") || "http://localhost:4000",
  client_id: System.fetch_env!("BELAY_API_PARTNER_CLIENT_ID"),
  client_secret: System.fetch_env!("BELAY_API_PARTNER_CLIENT_SECRET"),
  partner_id: System.fetch_env!("BELAY_API_PARTNER_ID")
