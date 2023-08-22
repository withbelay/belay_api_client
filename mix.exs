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
      deps: deps(),
      test_coverage: [tool: ExCoveralls]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:bypass, "~> 2.1", only: :test},
      {:cachex, "~> 3.5"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:decimal, "~> 2.0"},
      {:dialyxir, "~> 1.0", only: [:dev, :test], runtime: false},
      {:esbuild, "~> 0.7.1", runtime: Mix.env() == :dev},
      {:elixir_uuid, "~> 1.2"},
      {:excoveralls, "~> 0.16", only: [:test, :dev]},
      {:finch, "~> 0.8"},
      {:gettext, "~> 0.18"},
      {:jason, "~> 1.4"},
      {:mix_test_watch, "~> 1.0", only: [:dev, :test], runtime: false},
      {:money, "~> 1.9"},
      {:telemetry_metrics, "~> 0.6"},
      {:telemetry_poller, "~> 1.0"},
      {:tesla, "~> 1.4"}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get"],
      "test.int": ["test --include integration"],
      "test.ext": ["test --include external"],
      "test.all": ["test --include external --include integration"]
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
      "test.ext": :test
    ]
  end
end
