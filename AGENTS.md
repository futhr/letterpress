# Letterpress agent guide

Letterpress is an OSS template compiler and runtime for Elixir notification
systems. One repository owns the Hex package (`:letterpress`) and the
`@letterpress/language` and `@letterpress/svelte` npm packages. The backend is
authoritative; browser packages provide an editor projection of the same
versioned contract.

## Working agreement

- Read `docs/specs/LP.01-letterpress-contract.md` before changing public
  behavior. Treat profiles, artifact JSON, diagnostics, and generated editor
  metadata as public APIs.
- Keep host-product behavior out of this repository. Tenancy, persistence,
  publication workflows, providers, localization policy, AI orchestration, and
  legacy imports belong to consumers.
- Compile notification source once and render the immutable artifact many
  times. Never make Node or MJML availability a delivery-time dependency.
- The Elixir runtime is authoritative. Frontend parsing, completion, and lint
  are advisory and must carry the same contract version as the backend.
- Expected input failures return tagged errors with diagnostics. Do not raise
  for invalid user-authored templates.
- Preserve determinism: identical source, schema, profile, options, and pinned
  tool versions must produce byte-identical canonical artifacts.
- Do not commit, push, tag, publish, or create remote state unless the user
  explicitly requests it.

## Toolchain and gates

The supported floor is Elixir 1.18/OTP 27 and Node 22. Development targets the
latest pinned Elixir/OTP and Node LTS pairs in CI. Use pnpm for all JavaScript
work.

```bash
mix setup
mix check
```

`mix check` is the repository completion gate. It must cover warning-free
compilation, formatting, strict Credo, documentation coverage, dependency
audit, Dialyzer, ExUnit coverage, frontend formatting/lint/type checks, Vitest
coverage, package export checks, conformance fixtures, boundary checks, and a
dry-run release smoke. Use narrower commands while iterating.

## Architecture boundaries

- `Letterpress.Compiler` and its supervised worker own source analysis and
  MJML compilation.
- `Letterpress.Renderer` owns bounded pure-BEAM Liquid rendering from a compiled
  artifact.
- `Letterpress.Artifact`, `Diagnostic`, `Schema`, and `Profile` own the stable
  serialized contract.
- `Letterpress.Conformance` owns portable fixtures shared by Elixir and npm.
- `npm/language` owns CodeMirror language services generated from backend
  metadata.
- `npm/svelte` owns an unstyled Svelte 5 editor shell. It must not know a host
  route, resource, tenant, brand, provider, or persistence model.

The compiler worker may load only the checked-in bundle under `priv/`. File
includes, arbitrary plugins, network access, and host module loading are not
part of the contract.

## Commit convention

Use Conventional Commit subjects with a narrow scope, for example:

```text
feat(compiler): emit deterministic MJML artifacts
fix(renderer): reject an unsafe dynamic URL
test(conformance): cover nested Liquid branches
docs(contract): define diagnostic position encoding
```

Never add AI attribution or co-authors.
