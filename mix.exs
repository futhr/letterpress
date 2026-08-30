defmodule Letterpress.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/futhr/letterpress"

  def project do
    [
      app: :letterpress,
      name: "Letterpress",
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      description: "Safe, deterministic notification templates for Elixir.",
      source_url: @source_url,
      homepage_url: @source_url,
      package: package(),
      docs: docs(),
      test_coverage: [tool: ExCoveralls],
      dialyzer: dialyzer(),
      deps: deps(),
      aliases: aliases()
    ]
  end

  def application do
    [mod: {Letterpress.Application, []}, extra_applications: [:crypto, :logger]]
  end

  def cli do
    [
      preferred_envs: [
        check: :dev,
        coveralls: :test,
        "coveralls.lcov": :test,
        "coveralls.html": :test
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:jason, "~> 1.4"},
      {:nimble_options, "~> 1.1"},
      {:solid, "~> 1.3"},
      {:telemetry, "~> 1.3"},
      {:git_ops, "~> 2.6", only: :dev, runtime: false},
      {:ex_check, "~> 0.16", only: :dev, runtime: false},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:doctor, "~> 0.22", only: :dev, runtime: false},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: :test, runtime: false},
      {:stream_data, "~> 1.1", only: [:dev, :test]}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "cmd pnpm install", "cmd pnpm build:compiler"]
    ]
  end

  defp dialyzer do
    [
      flags: [:error_handling, :extra_return, :missing_return, :unmatched_returns, :unknown],
      plt_add_apps: [:mix],
      plt_core_path: "priv/plts/core",
      plt_local_path: "priv/plts/local"
    ]
  end

  defp package do
    [
      maintainers: ["Tobias Bohwalli <hi@futhr.io>"],
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files:
        ~w(lib priv/compiler/worker.mjs priv/contract.json mix.exs README.md LICENSE usage-rules.md)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_url: @source_url,
      source_ref: "v#{@version}",
      extras: [
        "README.md": [title: "Overview"],
        "usage-rules.md": [title: "Usage rules"],
        "docs/specs/LP.01-letterpress-contract.md": [title: "LP.01 contract"]
      ],
      groups_for_extras: [
        Contract: ["docs/specs/LP.01-letterpress-contract.md"],
        Reference: ["usage-rules.md"]
      ],
      groups_for_modules: [
        "Public API": [Letterpress, Letterpress.Artifact, Letterpress.Diagnostic],
        "Profiles and schemas": [Letterpress.Profile, Letterpress.Schema],
        Compilation: [Letterpress.Compiler, Letterpress.Compiler.Worker],
        Rendering: [Letterpress.Renderer],
        Contracts: [Letterpress.Contract, Letterpress.CanonicalJSON],
        Telemetry: [Letterpress.Telemetry]
      ]
    ]
  end
end
