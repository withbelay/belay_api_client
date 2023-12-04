import Config

config :belay_api_client,
  stock_universe: ["AAPL", "TSLA"],
  ws_url: System.get_env("BELAY_API_WS_URL", "ws://localhost:4000")

config :alpaca_investors, AlpacaInvestors,
  base_url: System.get_env("ALPACA_BASE_URL", "https://broker-api.sandbox.alpaca.markets"),
  key: System.fetch_env!("BELAYALPACA__ALPACA__KEY"),
  secret: System.fetch_env!("BELAYALPACA__ALPACA__SECRET")
