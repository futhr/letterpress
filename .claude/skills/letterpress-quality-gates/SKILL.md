---
name: letterpress-quality-gates
description: Apply before claiming a Letterpress task complete or release-ready. Run the authoritative Elixir, frontend, conformance, package, documentation, and release gates, and report failed, skipped, blocked, or unavailable lanes.
---

# Letterpress quality gates

Read `.claude/standards/quality-gates.md`, run focused checks while iterating,
then run from the final working tree:

```bash
git diff --check
mix check
```

`mix check` must include strict Credo, documentation warnings as errors,
audits, Dialyzer, ExUnit coverage, frontend lint/types/tests, package exports,
shared conformance, host-boundary checks, and release smoke tests.

Run `mix bench.smoke` only when benchmark code or performance prose changed.
Benchmark output is machine-specific and is not a deterministic completion
gate.

If any required lane fails, the task is not complete. Do not weaken a check,
coverage threshold, budget, conformance expectation, or package smoke.
