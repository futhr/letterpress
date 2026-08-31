# ADR.003 - Caller-owned compiler supervision

## Status

Accepted on 2026-08-31.

## Context

Letterpress compilation benefits from a supervised pool because each worker
owns a persistent framed connection to the bundled Node compiler. The first
implementation started a fixed pool from `Letterpress.Application` and read
capacity and resource settings from the `:letterpress` application
environment.

That made compiler placement, instance count, and runtime policy global. It
also started processes for delivery-only consumers even though artifact
rendering has no compiler dependency.

The evidence and alternatives are recorded in
[R.02](../research/R.02-library-posture.md). The required protocol and failure
behavior are defined in
[LP.01 section 6](../specs/LP.01-letterpress-contract.md#6-supervised-compiler-worker).

## Decision

Letterpress has no automatic application callback.

`Letterpress.Compiler.Supervisor` returns a child specification configured with
a registered pool name, worker count, and maximum frame size. The host places
that child beneath its own supervisor. Public authoring calls select a pool and
deadline through call options. Named pools may run independently in the same
BEAM instance.

Rendering requires no supervised Letterpress process. Its timeout, heap,
output, subject, and URL-scheme limits are call options with conservative
defaults.

## Consequences

- Authoring hosts must add the compiler child before calling compile, analyze,
  discover, format, or translation operations.
- Delivery-only hosts omit the child and do not need Node.
- Consumers decide process placement, restart domains, capacity, and whether a
  node performs authoring work.
- Multiple pools can serve different host workloads without sharing global
  configuration.
- README, HexDocs, Livebooks, benchmarks, tests, and release smokes must start
  a compiler pool explicitly when they compile templates.
