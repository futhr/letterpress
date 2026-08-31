---
name: letterpress-diagnosis-loop
description: Apply when a Letterpress compiler, renderer, artifact, source-map, conformance, browser, package, notebook, or determinism check fails. Reduce the input, identify the violated contract invariant, and fix the owning layer.
---

# Letterpress diagnosis loop

Record the profile, source hash, schema hash, options, tool versions,
diagnostic codes, artifact hash, and failing runtime without logging source or
values that may be sensitive.

Reduce to the smallest source/schema/value tuple that keeps the failure. Test
one causal boundary at a time: normalization, mixed-language parsing, context
classification, sentinel handling, MJML compilation, artifact canonicalization,
Solid parsing, render budget, generated contract, or editor projection.

Fix the semantic owner. Do not patch a browser fixture around a backend error,
reorder output after hashing, weaken a budget, or retry a deterministic input
failure. Retain the minimized regression and a shared conformance fixture when
the invariant crosses runtimes.

After three materially different failed fixes for one symptom, stop patching
and reopen the contract assumption or layer boundary. Close with fresh focused
output and the final completion gate.
