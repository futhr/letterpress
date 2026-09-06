# R.03 - Dependency hardening

Status: adopted with a deferred toolchain migration
Last reviewed: 2026-09-06

## Question

Which dependency updates improve Letterpress without changing its authoring
and delivery boundary or introducing an unsupported development toolchain?

## Evidence

- [Mint's changelog](https://github.com/elixir-mint/mint/blob/main/CHANGELOG.md)
  identifies 1.10.0 as the fix for CVE-2026-82728 and CVE-2026-82729. Letterpress
  receives Mint through development tooling; it is not a delivery dependency.
- [ExDoc's changelog](https://github.com/elixir-lang/ex_doc/blob/main/CHANGELOG.md)
  records documentation fixes in 0.40.4. The locked Dialyxir version also moves
  to 1.4.8; registry metadata confirmed that release, but the upstream changelog
  available during review did not describe its exact changes.
- [Solid's API](https://hexdocs.pm/solid/Solid.html) documents strict parsing,
  custom filters, and custom tags. Custom filters still fall back to standard
  filters, so Letterpress must enforce its own allow-list before rendering.
- [Jason's API](https://hexdocs.pm/jason/Jason.html) documents encoding failures
  and the risks of creating atoms from decoded input. JSON boundaries must
  reject invalid UTF-8 and retain string keys.
- [NimbleOptions](https://hexdocs.pm/nimble_options/NimbleOptions.html) validates
  keyword options against a schema. Letterpress checks the keyword-list shape
  before handing arbitrary public inputs to that validator.
- The installed CodeMirror changelogs for state 6.7.4, view 6.43.11, and search
  6.7.2 include range mapping, browser input, scrolling, and search-dialog fixes.
  Exact package changelogs were used where upstream default branches lagged
  registry releases. The [CodeMirror release log](https://codemirror.net/docs/changelog/)
  provides the upstream history.
- [Vitest's migration guide](https://vitest.dev/guide/migration/) documents the
  Node/Vite requirements and changed mock defaults in version 5. Letterpress's
  pinned Node 24 and Vite 8 toolchain meets those requirements; the compiler,
  language, and Svelte suites passed with Vitest and coverage-v8 5.0.0.
- The installed Svelte checker 4.7.6 rejects a standalone TypeScript 7 compiler.
  Its experimental migration requires TypeScript 6 alongside an aliased
  TypeScript 7 installation. See the
  [language-tools releases](https://github.com/sveltejs/language-tools/releases).

## Decision

Adopt the Mint security release, the available Hex tooling updates, compatible
npm updates, Vitest 5, and MJML 5 type declarations. Keep Node declarations on
the development runtime's major version. Regenerate the compiler bundle from
the lockfile and validate the browser packages and exact release artifacts.

Defer TypeScript 7 until the Svelte checker supports the intended toolchain
without an experimental dual-compiler setup. TypeScript 6.0.3 remains locked
and passes the complete typecheck. No delivery runtime dependency is added.

The repository quality gate owns dependency audits, generated contract checks,
and regression coverage. A clean audit reports known advisories at the time
of execution; it does not establish that dependencies have no vulnerabilities.
