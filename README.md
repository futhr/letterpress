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

## Packages

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

`mix check` runs the Elixir and browser gates, shared conformance corpus,
package-export validation, release-contract tests, and exact contract checks.
The release harness builds one Hex tarball and both npm tarballs once, records
their hashes, and installs those exact bytes in throwaway consumers before a
publish job can use them.

Start with the [quick-start guide](docs/guides/quickstart.md). The
[compiler/runtime guide](docs/guides/compiler-and-runtime.md) explains the
authoring-versus-delivery split, and the
[browser editor guide](docs/guides/browser-editor.md) covers CodeMirror and
Svelte integration.

## License

MIT. See [LICENSE](LICENSE).
