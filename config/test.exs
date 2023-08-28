import Config

config :belay_api_client,
  stock_universe: ["AAPL", "TSLA"],
  ws_url: System.get_env("BELAY_API_WS_URL", "ws://localhost:4000")
