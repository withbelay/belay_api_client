defmodule BelayApiClient.MixProject do
  use Mix.Project

  def project do
    [
      app: :belay_api_client,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      aliases: aliases(),
      preferred_cli_env: preferred_cli_envs(),
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {BelayApiClient.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:alpaca_investors,
       github: "/withbelay/alpaca-investors", ref: "42f8b65109a883910440700efd0afae31bb8b7e1", only: :test},
      {:assert_eventually, "~> 1.0.0", only: :test},
      {:bypass, "~> 2.1", only: :test},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.0", only: [:dev, :test], runtime: false},
      {:elixir_uuid, "~> 1.2"},
      {:esbuild, "~> 0.7.1", runtime: Mix.env() == :dev},
      {:opentelemetry_tesla, "~> 2.4.0"},
      {:slipstream, "~> 1.1"},
      {:tesla, "~> 1.7"}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get"],
      "test.int": ["test --include integration"],
      "test.smoke": ["test --include smoke"],
      "test.all": ["test --include smoke --include integration"]
    ]
  end

  defp preferred_cli_envs() do
    [
      "coveralls.github": :test,
      coveralls: :test,
      dialyzer: :test,
      test: :test,
      "test.all": :test,
      "test.int": :test,
      "test.smoke": :test
    ]
  end
end
