# Letterpress

**Compile MJML and Liquid once. Render safely in pure BEAM.**

[![Hex.pm](https://img.shields.io/hexpm/v/letterpress.svg)](https://hex.pm/packages/letterpress)
[![Docs](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/letterpress)
[![CI](https://github.com/futhr/letterpress/actions/workflows/ci.yml/badge.svg)](https://github.com/futhr/letterpress/actions/workflows/ci.yml)
[![Coverage](https://codecov.io/gh/futhr/letterpress/branch/main/graph/badge.svg)](https://codecov.io/gh/futhr/letterpress)
[![License](https://img.shields.io/github/license/futhr/letterpress.svg)](LICENSE)

[Installation](#installation) ·
[Quick start](#quick-start) ·
[Packages](#packages) ·
[Livebooks](#livebooks) ·
[Benchmarks](#benchmarks) ·
[Development](#development)

---

Letterpress is the language boundary for notification templates in Elixir. It
compiles restricted MJML and Liquid source into immutable artifacts during
authoring, then renders those artifacts in bounded pure-BEAM code during
delivery. Its CodeMirror 6 language package and Svelte 5 editor use the
generated backend contract for profile metadata, completion vocabulary, and
advisory diagnostic codes. Browser feedback never authorizes publication.

---

## Installation

Add Letterpress to your dependencies:

```elixir
def deps do
  [
    {:letterpress, "~> 0.1"}
  ]
end
```

Node 22 or newer is required on every authoring node because all profiles use
the bundled compiler worker for analysis, compilation, formatting, and
translation operations. Node 22 is the supported floor; local development and
the full CI lane use Node 24 LTS, while the portability matrix covers both
releases. Nodes that only render verified artifacts run entirely on the BEAM.

Letterpress is a library application: it does not add processes to your OTP
tree. On authoring nodes, add the compiler pool to your own supervisor:

```elixir
children = [
  {Letterpress.Compiler.Supervisor, pool_size: 2}
]

Supervisor.start_link(children, strategy: :one_for_one)
```

Delivery-only nodes omit this child and do not need Node.

---

## Quick start

Define a typed variable schema, compile the source during authoring, and store
the complete artifact:

```elixir
schema = %{
  "version" => 1,
  "variables" => %{
    "name" => %{"type" => "string", "context" => "text"},
    "action_url" => %{"type" => "url", "context" => "url"}
  }
}

source = """
<mjml>
  <mj-body>
    <mj-section>
      <mj-column>
        <mj-text>Hello {{ name }}</mj-text>
        <mj-button href="{{ action_url }}">Open account</mj-button>
      </mj-column>
    </mj-section>
  </mj-body>
</mjml>
"""

{:ok, artifact, diagnostics} =
  Letterpress.compile("email/mjml-liquid@1", source, schema,
    subject: "Welcome, {{ name }}",
    text: "Hello {{ name }}. Open {{ action_url }}"
  )
```

Render every channel atomically from the stored artifact at delivery time:

```elixir
{:ok, result} =
  Letterpress.render(artifact, %{
    "name" => "Taylor",
    "action_url" => "https://example.test/account"
  })
```

Email localization uses the same atomic boundary. Extract channel-aware units
with the original `:subject` and `:text`, apply provider results with
`Letterpress.localize/5`, then compile the returned three sources as one locale
artifact. A missing or structurally invalid unit rejects the complete localized
result rather than mixing locales between HTML, subject, and plain text.

See the [quick-start guide](docs/guides/quickstart.md) for the full lifecycle.

## Livebooks

[![Run in Livebook](https://livebook.dev/badge/v1/blue.svg)](https://livebook.dev/run?url=https%3A%2F%2Fraw.githubusercontent.com%2Ffuthr%2Fletterpress%2Fmain%2Fnotebooks%2Fquick-start.livemd)

- [Compile once, render many times](notebooks/quick-start.livemd) covers the
  email authoring and delivery boundary.
- [Text templates and diagnostics](notebooks/text-and-diagnostics.livemd)
  covers the text profile, discovery, and expected failures.
- [Artifacts and translations](notebooks/artifacts-and-translations.livemd)
  covers translation placeholders and canonical artifact round trips.

The notebooks are included in the HexDocs build. ExUnit evaluates their code
cells and checks saved outputs against the current package version.

---

## Packages

| Registry | Package | Responsibility |
|---|---|---|
| Hex | `letterpress` | Profiles, caller-owned compiler supervision, artifacts, safe Liquid rendering, diagnostics, telemetry, and conformance |
| npm | `@letterpress/language` | CodeMirror mixed MJML/Liquid/CSS language services |
| npm | `@letterpress/svelte` | Unstyled Svelte 5 editor and diagnostics integration |

---

## Core lifecycle

```text
source + typed schema + profile
  -> analyze
  -> compile once with the supervised official MJML worker
  -> persist immutable artifact
  -> render many times in bounded pure-BEAM Liquid
```

Consumer applications own templates as business records, publication,
tenancy, authorization, localization policy, translation providers, delivery
providers, and legacy migration. Letterpress owns only the portable language,
compiler, runtime, and editor contract.

The [public contract](docs/specs/LP.01-letterpress-contract.md) defines this
boundary and the serialized formats shared across runtimes.

The [platform analysis](docs/research/R.01-platform-analysis.md) compares this
boundary with hosted notification systems, provider templates, code-first email
builders, and Elixir mail libraries.

## Benchmarks

The Benchee suite measures pure-BEAM rendering, bounded Liquid loops, artifact
encoding/decoding, text compilation, and MJML compilation.

```bash
mix bench
mix bench.smoke
```

See the [benchmark guide](bench/README.md) and
[recorded results](bench/output/benchmarks.md). Smoke output checks that each
scenario runs; use a stable run on controlled hardware for comparisons.

---

## Development

The supported floor is Elixir 1.18/OTP 27 and Node 22. Node 24 LTS is the
pinned development version, and pnpm manages the npm workspace.

```bash
mix setup
mix check
```

`mix check` runs the Elixir and browser gates, shared conformance corpus,
package-export validation, release-contract tests, and exact contract checks.
The release harness builds one Hex tarball and both npm tarballs once, records
their hashes, and installs those exact bytes in throwaway consumers before a
publish job can use them.

The [compiler/runtime guide](docs/guides/compiler-and-runtime.md) explains the
authoring-versus-delivery split, and the
[browser editor guide](docs/guides/browser-editor.md) covers CodeMirror and
Svelte integration.

---

## License

MIT. See [LICENSE](LICENSE).
