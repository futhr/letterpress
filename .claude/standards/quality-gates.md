# Letterpress quality gates

`mix check` is the required completion gate. It covers warning-free Elixir
compilation, formatting, strict Credo, documentation, audits, Dialyzer, ExUnit
coverage, frontend lint and types, Vitest coverage, package exports,
conformance, boundary checks, and release smoke tests.

Run focused checks while iterating:

```bash
mix format --check-formatted
mix compile --warnings-as-errors
mix credo --strict
mix test
pnpm lint
pnpm typecheck
pnpm test
pnpm check:conformance
```

Before handoff:

```bash
git diff --check
mix check
```

Additional gates by surface:

- Notebook change: `mix test test/notebooks_test.exs`.
- Benchmark or performance claim: `mix bench.smoke` and label the output as a
  smoke run or full run.
- Contract change: regenerate the contract, run ExUnit and Vitest conformance,
  then run package-export and release-contract checks.
- Release metadata: run `pnpm check:release` and the exact-artifact smoke.

Do not weaken checks, lower coverage, add exclusions, or change fixtures only
to silence a failure.
