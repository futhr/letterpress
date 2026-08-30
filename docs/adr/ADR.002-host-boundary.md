# ADR.002 - Keep product workflow outside Letterpress

## Status

Accepted on 2026-08-30.

## Decision

Letterpress is a language/compiler/runtime/editor library. It does not own
tenant resources, authorization, publication workflows, localization policy,
provider delivery, AI orchestration, or legacy data access.

## Consequences

- The package is reusable across unrelated Elixir products.
- Legacy importers convert into the public profile contract and pass through the
  normal compiler gate.
- Consumers remain responsible for transactional publication, audit history,
  rollback, and transport-specific policy.
