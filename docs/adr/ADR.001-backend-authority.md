# ADR.001 - Keep compilation and rendering authoritative on the backend

## Status

Accepted on 2026-08-30.

## Context

Letterpress has three implementations in one repository: the Elixir package,
the bundled Node/MJML compiler worker, and browser language/editor packages.
Without a single authority, the browser could approve source that compiles
differently, or delivery could depend on whichever compiler happens to be
available at send time.

The platform review in
[`R.01`](../research/R.01-platform-analysis.md) found two common alternatives:
hosted systems render provider-owned source during workflow delivery, while
code-first builders emit HTML from a Node build. Neither provides the required
Elixir-owned, portable, versioned runtime contract.

## Alternatives considered

1. Make browser parsing and preview authoritative. Rejected because browser
   state is client-controlled and cannot be the publication gate.
2. Compile MJML during every delivery. Rejected because published messages
   would depend on Node, MJML, worker health, and compiler drift.
3. Use provider-side template IDs. Rejected because provider availability and
   active-version state would become part of rendering semantics.
4. Replace the official MJML compiler with another implementation. Deferred to
   a new profile because compiler identity and output are artifact semantics.

## Decision

The Elixir package owns validation, compilation, artifacts, and delivery-time
rendering. Browser packages project the same generated contract for editing but
cannot approve content or produce a delivery artifact.

MJML compilation runs before publication through a supervised bundled Node
worker. Delivery renders the persisted artifact in bounded pure-BEAM code.

The normative rules are in `LP.01` sections 5-8 and 11. This ADR explains why
those rules exist; it does not define a second contract.

## Consequences

- Preview, publication, and delivery can share one artifact path.
- A compiler outage cannot stop delivery of already published templates.
- Delivery-only nodes may run without Node.
- Browser diagnostics remain fast but are advisory until confirmed by the
  backend.
- Hosts must persist artifacts and explicitly backfill legacy content.

## Revisit when

- the pinned official compiler cannot meet isolation or determinism gates;
- browser metadata can no longer be generated from the backend contract; or
- a reference consumer demonstrates that an artifact cannot capture the data
  required for offline delivery rendering.
