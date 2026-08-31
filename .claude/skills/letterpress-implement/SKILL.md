---
name: letterpress-implement
description: Apply when implementing a bounded Letterpress change to compilation, rendering, artifacts, schemas, diagnostics, translation, generated browser metadata, CodeMirror services, or the Svelte editor. Follow LP.01, preserve authoring/delivery and host boundaries, and prove affected runtimes.
---

# Letterpress implement

Before editing, read `CLAUDE.md`, the applicable `LP.01` sections, owning code,
tests, and any linked research or ADR. Compare equivalent repository ergonomics
with the sibling Hex libraries named in `CLAUDE.md` when the change concerns
docs, gates, notebooks, benchmarks, or release structure.

Write the smallest failing proof for the requested behavior. A harness,
dependency, syntax, or worker-start failure is not a valid red test.

Keep the public facade thin. Preserve tagged diagnostic errors, deterministic
canonical bytes, bounded rendering, compiler isolation, and host ownership.
Update the normative contract in the same change when public behavior changes.
Update generated metadata rather than hand-editing derived files.

Make the smallest change that turns the same proof green. Then run the relevant
cross-runtime proof and `mix check`. Record focused and final gate results from
the final working tree.
