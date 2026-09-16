defmodule Letterpress.MixProject do
  use Mix.Project

  @version "0.1.3"
  @source_url "https://github.com/futhr/letterpress"

  def project do
    [
      app: :letterpress,
      name: "Letterpress",
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      description: description(),
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
    [extra_applications: [:crypto, :logger]]
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
      {:stream_data, "~> 1.1", only: [:dev, :test]},
      {:benchee, "~> 1.3", only: :dev, runtime: false},
      {:benchee_markdown, "~> 0.3", only: :dev, runtime: false}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "cmd pnpm install", "cmd pnpm build:compiler"],
      bench: ["run bench/run.exs"],
      "bench.smoke": ["run bench/run.exs --smoke"]
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

  defp description, do: "Safe, deterministic notification templates for Elixir."

  defp package do
    [
      maintainers: ["Tobias Bohwalli <hi@futhr.io>"],
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Documentation" => "https://hexdocs.pm/letterpress"
      },
      files: ~w(
          lib
          priv/compiler/worker.mjs
          priv/contract.json
          conformance
          notebooks
          bench/README.md
          bench/output/benchmarks.md
          docs/adr
          docs/guides
          docs/research
          docs/specs
          docs/README.md
          mix.exs
          README.md
          CHANGELOG.md
          CONTRIBUTING.md
          LICENSE
          RELEASING.md
          SECURITY.md
          usage-rules.md
        )
    ]
  end

  defp docs do
    [
      main: "readme-1",
      source_url: @source_url,
      source_ref: "v#{@version}",
      extras: [
        "README.md": [title: "Overview"],
        "docs/guides/quickstart.md": [title: "Quick start"],
        "docs/guides/compiler-and-runtime.md": [title: "Compiler and runtime"],
        "docs/guides/browser-editor.md": [title: "Browser editor"],
        "docs/guides/consumer-adoption.md": [title: "Consumer adoption"],
        "docs/guides/troubleshooting.md": [title: "Troubleshooting"],
        "notebooks/quick-start.livemd": [title: "Quick start Livebook"],
        "notebooks/text-and-diagnostics.livemd": [title: "Text and diagnostics Livebook"],
        "notebooks/artifacts-and-translations.livemd": [
          title: "Artifacts and translations Livebook"
        ],
        "bench/output/benchmarks.md": [title: "Benchmarks"],
        "docs/README.md": [title: "Documentation map"],
        "docs/research/R.01-platform-analysis.md": [title: "Platform analysis"],
        "docs/research/R.02-library-posture.md": [title: "Elixir library posture"],
        "docs/research/R.03-dependency-hardening.md": [title: "Dependency hardening"],
        "conformance/README.md": [title: "Conformance corpus"],
        "docs/adr/ADR.001-backend-authority.md": [title: "Backend authority"],
        "docs/adr/ADR.002-host-boundary.md": [title: "Host boundary"],
        "docs/adr/ADR.003-caller-owned-supervision.md": [
          title: "Caller-owned supervision"
        ],
        "usage-rules.md": [title: "Usage rules"],
        "docs/specs/LP.01-letterpress-contract.md": [title: "Letterpress contract"],
        "CONTRIBUTING.md": [title: "Contributing"],
        "RELEASING.md": [title: "Releasing"],
        "SECURITY.md": [title: "Security"],
        "CHANGELOG.md": [title: "Changelog"],
        LICENSE: [title: "License"]
      ],
      groups_for_extras: [
        Guides: ~r/docs\/guides/,
        Livebooks: ~r/notebooks/,
        Performance: ~r/bench\/output/,
        Research: ~r/docs\/research/,
        Contract: ["docs/specs/LP.01-letterpress-contract.md"],
        Architecture: ~r/docs\/adr/,
        Reference: [
          "docs/README.md",
          "conformance/README.md",
          "usage-rules.md",
          "CONTRIBUTING.md",
          "RELEASING.md",
          "SECURITY.md",
          "CHANGELOG.md",
          "LICENSE"
        ]
      ],
      groups_for_modules: [
        "Public API": [Letterpress, Letterpress.Artifact, Letterpress.Diagnostic],
        "Profiles and schemas": [Letterpress.Profile, Letterpress.Schema],
        Compilation: [Letterpress.Compiler, Letterpress.Compiler.Supervisor],
        Rendering: [Letterpress.Renderer],
        Contracts: [Letterpress.Contract, Letterpress.CanonicalJSON],
        Telemetry: [Letterpress.Telemetry],
        "Internal modules": [
          Letterpress.Compiler.Worker,
          Letterpress.JSON,
          Letterpress.Renderer.Filters,
          Letterpress.Renderer.ForTag
        ]
      ]
    ]
  end
end
