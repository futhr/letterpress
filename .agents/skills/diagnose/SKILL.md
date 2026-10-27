---
name: diagnose
description: Diagnose a failing compiler, renderer, artifact, source map, determinism, conformance, browser, package, or notebook check. Reduce the input, identify the causal boundary, and retain a regression for the fix. Use for unexplained failures rather than ordinary feature implementation.
user-invocable: false
---

# Failure diagnosis

Input: observed failure, failing command/runtime, and available source/schema/
value tuple. Output: a reproduced cause, a minimized regression and owning-layer
fix when authorized, or a specific blocker with actual evidence in chat.

Separate missing tools/dependencies and harness failures from a violated
[LP.01 invariant](../../../docs/specs/LP.01-letterpress-contract.md). Capture
relevant profile, source/schema hashes, options, tool versions, diagnostic codes,
and artifact hash without logging sensitive source or values.

Reduce the tuple while preserving the failure. Test the suspected causal
boundary: normalization, mixed-language parsing, context classification,
sentinel handling, MJML output, artifact canonicalization, Solid parsing,
render isolation/budgets, generated metadata, or editor projection. Use the
owning unit suite or shared [conformance corpus](../../../conformance/README.md)
to make the hypothesis executable.

Fix the semantic owner. Do not work around backend errors in browser fixtures,
reorder bytes after hashing, or retry deterministic input failures. If a fix
does not explain the observation, revisit the hypothesis before accumulating
patches. Remove only the exploratory edits motivated by a rejected hypothesis,
preserving unrelated work and independently useful diagnostics; retain the
counter-evidence in task notes. Preserve the reduced regression; use a shared
fixture only when the invariant crosses runtimes.

For worker timing failures retain the absolute submission deadline, active/queued
request identity, response ID and caller/port lifetime. Late, malformed or
mismatched responses cannot complete expired work; inspect timer and queued
payload cleanup in [compiler tests](../../../test/letterpress/compiler_test.exs).
For render failures, separate artifact verification, defaults/input budgets,
Liquid execution and result cleanup; no partial channel or late message can
stand in for the atomic result. A missing Node/dependency is an unavailable
prerequisite, not a behavioral red case.

Rerun the original failing command and focused regression after the fix, then
follow the validation requirements in [AGENTS.md](../../../AGENTS.md). Report
which observations support the cause and which checks remain unavailable.
