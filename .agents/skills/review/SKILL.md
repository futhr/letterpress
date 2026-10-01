---
name: review
description: Review a proposed change or final delivery for contract alignment, context safety, determinism, backend/browser agreement, host boundaries, and test integrity. Use for requested reviews and for relevant changed mechanisms before handoff; scale checks to the affected surface.
user-invocable: false
---

# Change review

Input: requested review scope or final diff, owning code, tests, and applicable
[LP.01 rules](../../../docs/specs/LP.01-letterpress-contract.md). Output: findings
with severity, file/line evidence, impact, and actual verification in chat.
State residual uncertainty when evidence is incomplete.

Inspect the implementation behind each affected contract claim:

- Context safety: outputs cannot enter weaker HTML, attribute, URL, subject,
  CSS, or color contexts. Raw output and unsafe schemes fail closed; sentinel
  loss, unexpected duplication, and relocation are handled by the modeled
  compiler transformation.
- Determinism: artifact bytes and hashes exclude timestamps, host paths,
  process/random identifiers, and map-order leaks.
- Delivery isolation: Node, MJML, file access, network, plugins, and loaders
  stay outside rendering. Worker framing/deadlines and render cleanup remain
  bounded, with atomic channel results.
- Expected errors: authored invalid input returns diagnostics without secret
  values, full source, host paths, or exception dumps.
- Cross-runtime agreement: generated metadata, UTF-16 ranges, browser rules,
  package exports, and shared fixtures match the backend where modeled.
  Browser validation does not become publication authority.
- Host ownership: no consumer persistence, tenancy, providers, queues, workflow,
  or private product vocabulary enters the library.
- Evidence: assertions exercise behavior; Livebook saved outputs and benchmark
  claims match their checks. Test exclusions, skipped cases, weak assertions,
  coverage padding, and relaxed budgets cannot substitute for a proof.

For guidance-only changes, inspect skill triggers, workflow ownership, commands,
references, and discovery behavior rather than inferring application safety
from prose. Follow [AGENTS.md](../../../AGENTS.md) for relevant checks. Run focused
checks needed to validate a finding; preserve a review-only request's scope and
do not mutate application code without authorization.
