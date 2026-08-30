# Conformance corpus

`conformance/fixtures.json` is consumed by both ExUnit and Vitest. Each case
uses the public profile and schema JSON formats and records the stable backend
and browser diagnostic codes that must be present. The browser can report a
smaller advisory set, but it cannot disagree with an authoritative backend
error it claims to model.

`pnpm check:conformance` also proves that:

- source contract fields survive generation;
- packaged backend JSON and generated TypeScript are current;
- every enabled MJML element has generated metadata;
- structural elements have nesting rules;
- fixtures and implementation code use only registered diagnostics.

Add a fixture when changing grammar, schema contexts, or a security boundary.
Unit tests remain appropriate for worker framing, render budgets, lifecycle,
and UI mechanics that do not cross runtimes. Sensitive payloads and consumer
vocabulary are forbidden.
