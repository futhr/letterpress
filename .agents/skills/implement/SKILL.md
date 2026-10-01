---
name: implement
description: Implement changes to compilation, rendering, schemas, artifacts, diagnostics, translation, generated contracts, CodeMirror services, or the Svelte editor. Trace affected backend and browser behavior and produce focused regression evidence. Use diagnose first when the cause of a failure is unknown.
user-invocable: false
---

# Implementation

Input: requested behavior, the changed semantic boundary, owning code, and
existing tests. Output: the implementation, affected contract/docs/fixtures,
and actual validation results in chat.

1. Locate the owner using [AGENTS.md](../../../AGENTS.md) and
   [LP.01](../../../docs/specs/LP.01-letterpress-contract.md). Read the relevant
   implementation and tests. Load linked ADRs or research only when the choice
   they explain is involved.
2. For a behavior change, write a focused regression that fails because of the
   requested behavior. A dependency, syntax, harness, or worker-start failure
   does not establish the regression. Make the change in the owning layer;
   keep the public facade thin.
3. Trace contract changes from [the source contract](../../../contract/letterpress-v1.json)
   through the compiler, Elixir API, generated metadata, language services,
   Svelte types, shared fixtures, exports, and affected user documentation.
   Touch only applicable surfaces. Use `pnpm build:compiler` to regenerate the
   bundle and metadata rather than editing derived files.
4. Prove the backend behavior first, then check the advisory browser behavior
   for rules it models. Verify diagnostic codes and UTF-16 ranges, contract
   versions, canonical ordering, and artifact hashes where changed.
5. Add a shared [conformance fixture](../../../conformance/README.md) for
   grammar, schema-context, or cross-runtime diagnostic changes. Keep worker
   framing, render isolation/budgets, and editor lifecycle regressions in their
   owning unit suites.
6. Rerun the regression and the affected existing tests. For shared-contract or
   package changes, also run `pnpm check:conformance`, `pnpm check:exports`,
   `pnpm test:release`, and `pnpm check:release` as applicable. Follow the
   completion gate in AGENTS.md and report unavailable lanes explicitly.
