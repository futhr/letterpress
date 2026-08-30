# Letterpress

Safe, deterministic notification templates for Elixir.

Letterpress compiles profile-based MJML and Liquid source into an immutable,
portable artifact, then renders that artifact in pure BEAM code at delivery
time. Its generated CodeMirror and Svelte 5 packages expose the same grammar,
diagnostics, schema, and completions in browser editors without making the
browser authoritative.

The project is pre-release. The public contract is specified in
[`docs/specs/LP.01-letterpress-contract.md`](docs/specs/LP.01-letterpress-contract.md).
No package has been published and no compatibility history is implied yet.

## Intended packages

| Registry | Package | Responsibility |
|---|---|---|
| Hex | `letterpress` | Profiles, compiler supervision, artifacts, safe Liquid rendering, diagnostics, telemetry, and conformance |
| npm | `@letterpress/language` | CodeMirror mixed MJML/Liquid/CSS language services |
| npm | `@letterpress/svelte` | Unstyled Svelte 5 editor and diagnostics integration |

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

## Development

The supported floor is Elixir 1.18/OTP 27 and Node 22. pnpm manages the npm
workspace.

```bash
mix setup
mix check
```

The release harness will build exact Hex and npm artifacts and install them in
throwaway consumers, but this repository must not be tagged or published until
the initial contract and adoption gates are complete.

## License

MIT. See [LICENSE](LICENSE).
