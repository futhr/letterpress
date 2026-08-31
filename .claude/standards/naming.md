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
