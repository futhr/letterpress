---
name: letterpress-cross-runtime-proof
description: Apply when Letterpress changes a profile, schema, diagnostic, artifact, Liquid rule, MJML rule, generated contract, CodeMirror service, Svelte API, conformance fixture, or package surface. Prove the authoritative backend and advisory browser packages remain version-aligned.
---

# Letterpress cross-runtime proof

Trace the change from `LP.01` and `contract/letterpress-v1.json` through the
compiler worker, Elixir API, generated JSON, generated TypeScript, language
services, Svelte types, shared fixtures, package exports, and user docs.

Prove backend behavior first. Browser behavior may report a smaller advisory
set, but it must not contradict an authoritative error it models. Preserve
diagnostic codes, UTF-16 ranges, contract versions, canonical ordering, and
artifact hashes.

Add a root `conformance/` fixture for grammar, schema-context, or cross-runtime
diagnostic changes. Use unit tests for worker framing, render isolation,
budgets, and component lifecycle that do not cross runtimes.

Run the focused Elixir and Vitest tests, `pnpm check:conformance`, package export
checks, and `mix check`. Report any unavailable runtime or consumer lane.
