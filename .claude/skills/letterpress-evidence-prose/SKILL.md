---
name: letterpress-evidence-prose
description: Apply when writing Letterpress README, HexDocs, npm docs, specs, ADRs, research, Livebooks, benchmark notes, moduledocs, comments, or release text. Keep contract, security, compatibility, performance, and completion claims scoped to executable evidence.
---

# Letterpress evidence prose

Name the exact surface: Elixir backend, compiler worker, artifact, renderer,
CodeMirror package, Svelte package, or shared fixture. Separate normative
contract language from research, examples, implementation state, and inference.

Keep examples runnable against the current public API and package version.
Distinguish a focused test from `mix check`, local package inspection from an
installed consumer, and a smoke benchmark from a stable measurement.

Security prose must identify the enforced boundary. Node permission flags are
defense in depth, not a sandbox. Browser validation is advisory. Rendering is
pure BEAM only after a valid artifact exists.

Remove generic claims, copied vendor language, filler, and comments that repeat
code. Run the `unslop` pass before handoff.
