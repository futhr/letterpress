---
name: write-docs
description: Write or revise README, HexDocs, guides, specs, ADRs, Livebooks, benchmark notes, public API comments, release text, or agent guidance. Keep technical claims tied to their owning evidence and remove filler while preserving exact APIs and contract terms. Use when prose changes, not for code-only edits.
user-invocable: false
---

# Technical prose

Input: requested text change, its audience and owning source of truth, and
available implementation/test evidence. Output: the requested prose and a chat
summary of material edits and actual verification.

Use the document ownership in [AGENTS.md](../../../AGENTS.md) and the
[naming standard](../../standards/naming.md) when terminology matters. Identify
the exact surface: Elixir backend, compiler worker, artifact, renderer,
CodeMirror package, Svelte package, or shared fixture. Separate normative
requirements from examples, implementation state, external evidence, and
inference.

Check examples against current public functions, option types, package versions,
and existing runnable tests. Distinguish focused tests from the full gate,
package inspection from an installed consumer, and smoke benchmarks from
measured performance results. Do not upgrade a planned check into a completion
claim.

Security text must name the enforced boundary. Node permission flags are defense
in depth, not a sandbox. Browser diagnostics are advisory. Artifact hashes
detect corruption rather than authenticate the producer; pure-BEAM delivery
depends on a valid artifact from a trusted path.

Edit for concrete meaning: remove copied vendor copy, generic praise, filler,
forced contrasts/triads, hedge stacks, decorative emphasis, and comments that
repeat code. Preserve identifiers, profile names, APIs, commands, code blocks,
diagnostic codes, versions, dates, measurements, and attributed quotes exactly
unless the requested correction changes them.

Reread the result against its evidence and the requested audience. Run checks
appropriate to the changed surface under AGENTS.md; report what ran and what
remains unverified.
