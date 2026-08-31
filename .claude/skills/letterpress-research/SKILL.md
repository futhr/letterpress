---
name: letterpress-research
description: Apply when a Letterpress decision depends on external template languages, email compilers, notification platforms, editor tooling, Elixir packages, security guidance, or compatibility facts. Use current primary sources and record a bounded decision under docs/research.
---

# Letterpress research

Write research under `docs/research/`. Do not change runtime behavior from this
skill alone.

Inventory related research, `LP.01`, ADRs, code, tests, npm packages, and
consumer-facing docs. Compare external systems by semantic ownership rather
than feature count: authoring language, schema, compile/render boundary,
artifact portability, delivery dependencies, editor authority, localization,
workflow ownership, and failure timing.

Prefer official specifications, product documentation, source repositories,
and Hex/npm package documentation. Record access dates and versions where they
matter. Distinguish documented behavior from inference and note material
exclusions.

End with an adopted, rejected, bounded-validation, or deferred conclusion. Say
which Letterpress layer owns any follow-up. Research explains a decision; only
`docs/specs/` defines public behavior.
