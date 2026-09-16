# Change Log

All notable changes to this project will be documented in this file.
See [Conventional Commits](Https://conventionalcommits.org) for commit guidelines.

<!-- changelog -->

## [v0.1.2](https://github.com/futhr/letterpress/compare/v0.1.1...v0.1.2) (2026-09-16)




### Bug Fixes:

* language: support peers without optional brace closing by Tobias Bohwalli

* compiler: restart workers after malformed response envelopes by Tobias Bohwalli

* liquid: recognize scoped loop metadata across runtimes by Tobias Bohwalli

* translation: enforce complete localized channel limits by Tobias Bohwalli

* compiler: include queue time in request deadlines by Tobias Bohwalli

* renderer: enforce budgets across validation and defaults by Tobias Bohwalli

* artifact: validate delivery syntax before accepting channels by Tobias Bohwalli

* compiler: preserve numeric values and literal replacements by Tobias Bohwalli

* schema: reject invalid identifiers and conflicting fields by Tobias Bohwalli

* artifact: reject ambiguous JSON and verify schema identity by Tobias Bohwalli

### Performance Improvements:

* compiler: reuse native schema objects for variable lookup by Tobias Bohwalli

## [v0.1.1](https://github.com/futhr/letterpress/compare/v0.1.0...v0.1.1) (2026-09-07)




### Bug Fixes:

* release: verify package identities and complete checksums by Tobias Bohwalli

* translation: extract and safely replace email attributes by Tobias Bohwalli

* compiler: reject unevaluated compile-phase expressions by Tobias Bohwalli

* check: always run the complete quality gate by Tobias Bohwalli

* api: validate option lists and email channel encodings by Tobias Bohwalli

* compiler: validate variables used by filter arguments by Tobias Bohwalli

* translation: distinguish siblings and validate replacements by Tobias Bohwalli

* language: complete MJML values and closing tags in context by Tobias Bohwalli

* json: reject improper lists without raising by Tobias Bohwalli

* renderer: preserve zero limits and nested loop bindings by Tobias Bohwalli

* artifact: validate encoding inputs before canonical hashing by Tobias Bohwalli

* editor: handle asynchronous command failures by Tobias Bohwalli

* ci: enforce npm audits and produce frontend coverage by Tobias Bohwalli

* api: reject invalid source encoding before worker requests by Tobias Bohwalli

* compiler: forbid unchecked MJML output attributes by Tobias Bohwalli

* compiler: require complete safe URL attributes by Tobias Bohwalli

* compiler: validate and escape compile-phase values by Tobias Bohwalli

* json: reject invalid UTF-8 at normalization boundary by Tobias Bohwalli

* artifact: validate variable shapes before reading fields by Tobias Bohwalli

* renderer: reject obfuscated URLs and widened schemes by Tobias Bohwalli

* renderer: validate complete subject channels by Tobias Bohwalli

* editor: discard formatting for changed documents by Tobias Bohwalli

## [v0.1.0](https://github.com/futhr/letterpress/compare/v0.1.0...v0.1.0) (2026-09-01)




### Features:

* editor: support preprocessed authoring sources by futhr

* translation: localize email channels atomically by futhr

* profile: add bounded HTML fragments by futhr

* context: support compatible email sinks by futhr

* schema: support predicate variable names by futhr

* runtime: add caller-owned compiler pools by futhr

* compile complete email artifacts by futhr

* svelte: add paired editor themes by futhr

* provide complete Svelte editor affordances by futhr

* expose nested collection dependencies by futhr

* describe structured template dependencies by futhr

* add schema-neutral variable discovery by futhr

* enforce cross-runtime template conformance by futhr

* add shared browser editor packages by futhr

* add deterministic compiler and safe runtime by futhr

### Bug Fixes:

* release: configure shared version management by futhr

* ci: install pnpm before enabling cache by futhr

* compiler: verify sentinel output contexts by futhr

* release: preserve local artifacts in smoke installs by futhr

* compiler: translate text profile documents by futhr

* make editor theming safe across package boundaries by futhr

* diagnose legacy template syntax precisely by futhr

* normalize compiler runtime settings by futhr

* discover liquid control-flow dependencies by futhr

* support linked Svelte consumers by futhr

* validate mixed template markup accurately by futhr

### Performance Improvements:

* bench: add compiler and renderer benchmarks by futhr
