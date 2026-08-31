# Conformance corpus

This directory is a test boundary shared by the Elixir backend and browser
language package. It is at the repository root because neither runtime owns the
fixtures.

`fixtures.json` contains portable source, schema, profile, and expected
diagnostic cases. ExUnit runs each case through the authoritative backend.
Vitest runs the same case through advisory browser diagnostics. Browser checks
may implement a smaller diagnostic set, but any backend rule they model must
agree on the stable code.

`pnpm check:conformance` also verifies that:

- source contract fields survive generation;
- `generated/letterpress-v1.json`, `priv/contract.json`, and generated
  TypeScript are current;
- enabled MJML elements have metadata and structural nesting rules;
- fixtures and implementation code use registered diagnostic codes.

Add a fixture when grammar, schema contexts, diagnostic codes, or another
cross-runtime rule changes. Keep worker protocol, render budget, artifact, and
Svelte lifecycle cases in their owning unit-test suites.

The corpus is release evidence, not a runtime API or an Elixir module. It must
not contain secret values, private consumer names, or host-product vocabulary.
