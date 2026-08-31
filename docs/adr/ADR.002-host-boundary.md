# ADR.002 - Keep product workflow outside Letterpress

## Status

Accepted on 2026-08-30.

## Context

Notification products often combine template storage, tenants, brands,
preferences, publication, routing, providers, analytics, and delivery. Those
features are useful, but they require host data models and operational policy.
Putting them in Letterpress would couple the language contract to one product
shape.

[`R.01`](../research/R.01-platform-analysis.md) compares hosted platforms,
provider templates, code-first builders, and Elixir mail libraries. The common
hosted model is intentionally broader than this package. Letterpress instead
needs to be reusable inside unrelated Elixir systems and compatible with
Swoosh, Bamboo, direct provider APIs, or other consumer-owned delivery paths.

## Alternatives considered

1. Build a complete notification platform. Rejected because persistence,
   tenancy, workflow, provider, and preference semantics are product policy.
2. Add provider adapters to the core package. Rejected because rendered
   channels are already a stable handoff and adapters expand runtime
   dependencies.
3. Own localization fallback and translation providers. Rejected because
   locale availability, fallback order, review, and vendor calls are host
   policy; Letterpress owns only safe unit extraction and application.
4. Import legacy stores directly. Rejected because an importer should convert
   host data into source/schema inputs and pass the normal compiler gate.

## Decision

Letterpress is a language/compiler/runtime/editor library. It does not own
tenant resources, authorization, publication workflows, localization policy,
provider delivery, AI orchestration, or legacy data access.

The normative ownership list is in `LP.01` sections 2, 10, and 16. This ADR
records the rejected product boundaries.

## Consequences

- The package is reusable across unrelated Elixir products.
- Legacy importers convert into the public profile contract and pass through the
  normal compiler gate.
- Consumers remain responsible for transactional publication, audit history,
  rollback, and transport-specific policy.

## Revisit when

- two unrelated consumers require the same dependency-free conversion at the
  rendered-channel boundary; or
- a required safety property cannot be enforced without moving a narrowly
  defined policy into the versioned profile contract.

Convenience or hosted-platform parity alone does not reopen the boundary.
