# Letterpress repository contract

Read this file before editing. It owns repository-wide agent policy. The
linked specs define public behavior; supporting standards and skills provide
the details needed for the active task.

## Working scope and discovery

- Preserve unrelated changes and existing local client settings.
- Report findings, decisions, sources, actual checks, and material limitations
  in chat. Distinguish executed tests and reviewed code from planned work or
  declarations in documentation.
- Canonical skills live in tracked `.agents/skills/<name>/SKILL.md`. Select and
  apply matching skills automatically from their descriptions as the task,
  changed mechanism, or delivery stage requires. The user does not invoke
  skills or choose slash commands. Keep implicit invocation enabled.
- Use native discovery where supported. Clients without it must inspect skill
  names and descriptions, then read and apply matching `SKILL.md` files.
  Load supporting material only when relevant; resolve links relative to the
  file containing them.
- For Claude Code, ensure each canonical skill has an ignored individual
  directory symlink at `.claude/skills/<name>` pointing to
  `../../.agents/skills/<name>`. Create absent links and repair repository-owned
  dangling links, including after a skill rename. Remove obsolete
  repository-owned links rather than retaining aliases. Preserve unrelated
  local entries and report collisions rather than overwriting them. Keep all
  `.claude/` directories ignored and `.agents/` tracked. Client settings stay
  local; do not add agent hooks or setup helpers that require extra dependencies.

## What this library is

Letterpress is the language boundary for notification templates in Elixir
systems. It compiles restricted MJML and Liquid source into a versioned,
immutable artifact during authoring, then renders that artifact in bounded
pure-BEAM code during delivery. The Hex package is authoritative. The npm
packages expose an advisory browser projection of the same generated contract.

Letterpress is not a notification platform. Consumers own template records,
tenancy, authorization, publication, localization policy, providers, queues,
retries, preferences, and delivery telemetry.

## Hard rules

1. Read [LP.01](docs/specs/LP.01-letterpress-contract.md) in full before changing a
   profile, schema, artifact, diagnostic, render rule, translation rule,
   generated contract, or browser package behavior.
2. Compile once and render many times. Node and MJML may be authoring-time
   dependencies; they must never become delivery-time dependencies.
3. Preserve determinism. Identical source, schema, profile, options, and pinned
   tools must produce byte-identical canonical artifacts.
4. Invalid user-authored source, schema, values, and artifacts return tagged
   errors with diagnostics. Do not raise for expected input failures.
5. The Elixir backend is authoritative. Browser parsing, completion, lint, and
   formatting are advisory and carry the same generated contract version.
6. The compiler worker loads only the checked-in bundle under `priv/compiler`.
   File includes, arbitrary plugins, network access, shell access, dynamic
   imports, and host module loading are outside the contract.
7. Keep host-product behavior out of the repository. Do not add persistence,
   tenant models, publication workflows, provider clients, localization
   policy, AI orchestration, or legacy data access.
8. Every public Elixir function has `@doc` and `@spec`; every public module has
   `@moduledoc`. Public TypeScript exports need explicit types and package tests.
9. Do not add a runtime dependency without an explicit boundary and release
   justification. Keep compiler-only JavaScript out of the delivery runtime.
10. Before changing repository guidance, README structure, Livebooks,
    benchmarks, release metadata, or quality configuration, compare the same
    surface in `../ex_booking`, `../exk_passwd`, `../sigil_guard`, and
    `../ex_maude`. Those repositories are the house baseline, not a reason to
    copy domain-specific rules into Letterpress.
11. Keep Letterpress a library application. The host owns compiler supervision;
    runtime policy belongs in child-spec or call options, not global
    `:letterpress` application configuration.
12. Do not commit, push, tag, publish, or create remote state unless the user
    explicitly asks.

## Architecture

```text
authoring
  source + typed schema + profile
    -> Elixir API
    -> caller-owned supervised bundled Node/MJML compiler
    -> canonical immutable artifact

delivery
  persisted artifact + values
    -> bounded pure-BEAM Liquid renderer
    -> subject / HTML / text atomically

browser
  generated contract
    -> @letterpress/language
    -> @letterpress/svelte
    -> advisory editing only
```

- `lib/letterpress.ex` is the public facade.
- `Letterpress.Compiler` and `Letterpress.Compiler.Worker` own authoring-time
  analysis and compilation.
- `Letterpress.Renderer` owns delivery-time rendering and budgets.
- `Letterpress.Artifact`, `Diagnostic`, `Schema`, and `Profile` own serialized
  public contracts.
- `contract/` is the hand-reviewed source contract. `generated/`,
  `priv/contract.json`, and generated TypeScript are derived from it.
- `conformance/` is a shared executable fixture corpus consumed by ExUnit,
  Vitest, and contract checks. It is not an Elixir runtime namespace.
- `npm/language` owns framework-neutral CodeMirror language services.
- `npm/svelte` owns the unstyled Svelte 5 editor shell.

## Documentation system

- `docs/research/` records external evidence, alternatives, and bounded
  conclusions. Research explains why a direction is credible; it does not
  define public behavior.
- `docs/specs/` is normative. `LP.01` defines the versioned public contract.
- `docs/adr/` records durable architecture choices and rejected alternatives.
  An ADR must add rationale beyond the spec and link the relevant research and
  normative sections. It must not become a second copy of the contract.
- `docs/guides/` teaches implemented public behavior without inventing new
  guarantees.
- `notebooks/` contains runnable Livebook tutorials included in HexDocs.
  Notebook code and saved outputs are checked by ExUnit.
- `bench/` contains Benchee scenarios and checked-in result summaries. Results
  are evidence for the recorded machine and run mode, never universal claims.
- Use [the naming standard](.agents/standards/naming.md) when choosing domain
  terminology or changing JavaScript/TypeScript functions and compiler passes.

The separation is about authority, not document size: research is evidence,
ADRs explain decisions, specs define behavior, guides teach usage, and the
conformance corpus executes claims across runtimes.

Project documents have no fixed token, word, page, line, or diff-size budget.
Split only at an ownership or lifecycle boundary.

## Cross-platform discipline

The Hex and npm packages ship one contract version and one source tag. A public
change is incomplete until these surfaces agree where applicable:

- Elixir analysis, compilation, artifact decoding, and rendering;
- compiler worker diagnostics and source positions;
- generated JSON and TypeScript contract metadata;
- CodeMirror parsing, completion, formatting, and local diagnostics;
- Svelte component types and lifecycle behavior;
- shared conformance fixtures, package exports, and exact-artifact smoke tests;
- HexDocs, npm READMEs, Livebooks, and consumer examples.

## Quality gates

The supported floor is Elixir 1.18/OTP 27 and Node 22. Use the pinned local
toolchain in [`.tool-versions`](.tool-versions), the runtime matrix in
[CI](.github/workflows/ci.yml), and pnpm for JavaScript work.

For application code, public documentation, contract, package, release, or
quality-configuration changes, run focused checks while iterating, then run
the full gate from the final working tree before claiming completion:

```sh
git diff --check
mix check
```

[`.check.exs`](.check.exs) owns the configured commands: warning-free Elixir
compilation, formatting, strict Credo, Doctor, documentation warnings, dependency
checks and audits, Dialyzer, ExUnit coverage, frontend lint/types/tests, package
exports, conformance, host-boundary checks, and release-contract tests. Read it
before running the gate: it includes a frozen-lockfile pnpm install. Report
failed, skipped, or unavailable lanes; do not describe a partial run as passing.

Additional checks depend on the changed surface:

- Notebook: `mix test test/notebooks_test.exs` checks code and saved output.
- Contract: regenerate with `pnpm build:compiler`, run the affected ExUnit and
  Vitest conformance cases, then package-export and release-contract checks.
- Release metadata: `pnpm check:release` plus the exact-artifact smoke described
  in [RELEASING.md](RELEASING.md).
- Benchmark code or measured performance prose: run `mix bench.smoke` and label
  the result as smoke or full. It rewrites machine-specific output and is
  outside the deterministic completion gate.

For changes confined to agent instructions, skills, or discovery links, review
the workflows against owning code and current official client documentation.
Check YAML metadata, names, local references, tracking/ignore boundaries, links,
and `git diff --check` using existing tools. Do not install dependencies or run
unrelated application suites for that surface.

Strict Credo means enabled checks are fixed in code. Do not add exclusions,
inline disables, weaker thresholds, coverage padding, or changed fixture
expectations to silence a failure. Text searches locate code and stale
references; they do not prove behavior, security, or cross-runtime correctness.

## Commit rules

Use Conventional Commits with a narrow scope, such as:

```text
feat(compiler): emit deterministic MJML artifacts
fix(renderer): reject an unsafe dynamic URL
test(conformance): cover nested Liquid branches
docs(contract): define diagnostic position encoding
```

Never add AI attribution, generated-by comments, or co-author trailers.
