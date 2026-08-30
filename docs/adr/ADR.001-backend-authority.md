# ADR.001 - Keep compilation and rendering authoritative on the backend

## Status

Accepted on 2026-08-30.

## Decision

The Elixir package owns validation, compilation, artifacts, and delivery-time
rendering. Browser packages project the same generated contract for editing but
cannot approve content or produce a delivery artifact.

MJML compilation runs before publication through a supervised bundled Node
worker. Delivery renders the persisted artifact in bounded pure-BEAM code.

## Consequences

- Preview, publication, and delivery can share one artifact path.
- A compiler outage cannot stop delivery of already published templates.
- Delivery-only nodes may run without Node.
- Browser diagnostics remain fast but are advisory until confirmed by the
  backend.
- Hosts must persist artifacts and explicitly backfill legacy content.
