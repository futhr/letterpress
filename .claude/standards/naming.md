# Letterpress naming standard

Use these terms consistently in code, specs, docs, tests, and package copy.
`LP.01` is normative when this summary and the contract differ.

| Term | Meaning |
|---|---|
| Source | User-authored MJML/Liquid or text/Liquid input. |
| Profile | Immutable language identifier such as `email/mjml-liquid@1`. |
| Schema | Typed variable and output-context contract supplied at authoring. |
| Compile phase | Authoring-time substitution and MJML compilation. |
| Delivery phase | Bounded Liquid rendering from a persisted artifact. |
| Artifact | Canonical, immutable, content-addressed compilation result. |
| Diagnostic | Versioned, LSP-shaped expected-failure report. |
| Backend | The authoritative Elixir compiler/runtime contract. |
| Browser projection | Advisory language/editor behavior generated from the backend contract. |
| Consumer | Host application that owns records, workflow, policy, and delivery. |
| Conformance corpus | Portable fixtures executed by backend and browser implementations. |

Avoid these substitutions:

- Do not call Letterpress a notification platform, provider, CMS, or workflow
  engine.
- Do not call source an artifact or treat an artifact as editable source.
- Do not describe browser diagnostics as authoritative validation.
- Do not use "template rendering" when the distinction between compile phase
  and delivery phase matters.
- Do not name private consumers, tenant models, providers, or host routes.

## JavaScript and TypeScript functions

Prefer `const`-bound arrow functions and concise expression bodies for a single
returned expression. Keep explicit types on module boundaries. Use ordinary
functions when their semantics are needed, such as generators or dynamic
`this`; initialize arrow functions before invoking them.

Compiler passes consume readonly inputs and return diagnostics, translation
units, or replacement plans. A helper must not append to a caller-owned
collection. Local arrays, maps, and loop cursors may be mutable while building
a result; avoid repeated accumulator copies. Readonly types constrain writes
through typed references and do not imply runtime deep freezing.

Biome checks arrow function expressions, concise arrow returns, constant
bindings, optional chaining, object spread, parameter reassignment, and
accumulating spread. Its built-in arrow rule does not cover function
declarations; review those against the preference above.
