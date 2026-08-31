---
name: letterpress-review
description: Apply when reviewing Letterpress code, docs, contracts, packages, security boundaries, coverage, or release readiness. Find correctness, determinism, context-safety, cross-runtime, test-integrity, and host-boundary defects using repository evidence.
---

# Letterpress review

Review in this order:

1. Contract alignment: public behavior matches `LP.01` and versioning rules.
2. Context safety: variables cannot move into weaker HTML, attribute, URL,
   subject, CSS, or color contexts; raw output and unsafe schemes fail closed.
3. Determinism: canonical bytes contain no time, path, process, random, or map
   ordering leaks.
4. Compile/render split: Node, MJML, files, network, and plugins stay out of
   delivery rendering.
5. Expected failures: invalid authored input returns diagnostics without secret
   values, source dumps, or host paths.
6. Cross-runtime behavior: generated contracts, browser diagnostics, packages,
   and conformance fixtures agree with the backend.
7. Host boundary: no tenancy, persistence, provider, workflow, or consumer
   vocabulary enters the library.
8. Proof quality: assertions test behavior; no skipped tests, coverage padding,
   weakened budgets, broad excludes, stale Livebook outputs, or invented
   benchmark claims.

Report findings by severity with file and line evidence. Run focused checks
needed to validate a finding; do not mutate code during a review-only request.
