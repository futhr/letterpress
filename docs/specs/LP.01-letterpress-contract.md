---
title: "LP.01 - Letterpress compiler, runtime, and editor contract"
document_id: "LP.01"
status: "Accepted for implementation"
version: 1
created: "2026-08-30"
last_updated: "2026-09-01"
---

# LP.01 - Letterpress compiler, runtime, and editor contract

## 1. Purpose

Letterpress is the reusable language boundary for notification templates in
Elixir systems. It accepts source plus a typed variable schema, compiles the
source into a deterministic immutable artifact, and renders that artifact
without a Node or MJML dependency in the delivery path. It also emits the
versioned metadata consumed by browser language tooling.

The backend is the sole authority. Browser parsing, completion, formatting,
folding, and diagnostics improve authoring but cannot approve publication or
alter delivery semantics.

## 2. Scope and ownership

### Letterpress owns

- versioned profiles and their grammar, feature allow-lists, and limits;
- parsing, analysis, formatting, and diagnostics;
- official MJML compilation through a supervised bundled Node worker;
- a restricted Liquid runtime with context-aware output handling and budgets;
- typed variable schemas and compile/delivery phases;
- deterministic canonical artifacts and source maps;
- translatable-unit extraction and safe application of translated values;
- telemetry at compile and render boundaries;
- cross-runtime conformance fixtures;
- generated browser contracts, CodeMirror language services, and an unstyled
  Svelte 5 editor shell;
- exact-artifact release and consumer-smoke tooling.

### Consumers own

- database resources, versions, publication pointers, tenancy, authorization,
  audit policy, and retention;
- locale registries, fallback policy, translation providers, and review;
- notification orchestration, queues, retries, providers, suppression, and
  delivery telemetry;
- product-specific AI prompts and actions;
- business transformations that produce template variables;
- legacy imports and migrations.

Letterpress must never import a consumer module or name a consumer product.

## 3. Profiles

Version 1 defines exactly three profiles:

| Identifier | Source | Compiled artifact |
|---|---|---|
| `email/mjml-liquid@1` | MJML 5.4 with restricted Liquid expressions | HTML Liquid template, optional text Liquid template, metadata |
| `html/liquid@1` | Allow-listed HTML fragment with restricted Liquid expressions | HTML Liquid template and metadata |
| `text/liquid@1` | Restricted Liquid plain text | Text Liquid template and metadata |

Push, JSON, voice, EEx, Mustache, Handlebars, EJS, and unrestricted HTML are
not v1 runtime profiles. Consumers may convert those formats before invoking
Letterpress. A new profile version is additive; changing the meaning of an
existing identifier is forbidden.

### Email source rules

- One `mjml` root and one `mj-body` are required. `mj-head` is optional when the
  official compiler accepts the document.
- `mj-include`, custom component registration, arbitrary plugins, and dynamic
  file loading are forbidden. `mj-html-attributes`, `mj-selector`, and
  `mj-html-attribute` are also forbidden: they can add unvalidated attributes
  to the generated HTML after the source checks.
- `mj-style` is CSS with compile-phase variables only. Delivery-phase Liquid is
  forbidden because moving control flow through generated CSS is not safe or
  source-map stable.
- Liquid outputs are allowed in text-bearing nodes and explicitly classified
  attributes. Structural Liquid control flow is allowed only where the
  compiler can preserve a valid MJML tree for every branch.
- A dynamic URL-bearing attribute must contain one complete Liquid output,
  with no surrounding text or additional outputs. Construct URLs in host code
  and pass the complete value. Static MJML URLs follow the HTML fragment URL
  policy; dynamic URLs are validated before attribute escaping against the
  schema context and configured scheme allow-list.
- Raw Liquid output is forbidden. `raw`, `include`, `render`, filesystem access,
  arbitrary filter registration, and user-defined tags are forbidden.

### HTML fragment source rules

- Output is an HTML fragment, not a document. Only the contract's embedded-HTML
  element and attribute allow-lists are accepted.
- Scriptable elements, event-handler attributes, dynamic element or attribute
  names, and unclassified URL/style sinks are forbidden.
- Static URL-bearing attributes accept relative or fragment references and the
  `http`, `https`, `mailto`, `tel`, and `cid` schemes; protocol-relative,
  obfuscated, control-bearing, and other absolute schemes are rejected.
- Liquid output is context-checked and receives its final `html_text`,
  `html_attribute`, `url`, or `css` escape filter according to the parsed sink.
- The email profile's restrictions on Liquid tags, filters, raw output, file
  access, and budgets apply unchanged.

### Text source rules

- Output is Unicode text and must not contain NUL.
- Profile limits cap source bytes, output bytes, collection sizes, loop
  iterations, nesting depth, and render time.
- Consumers apply transport-specific length/segmentation policy after render.

## 4. Variable schema

A schema is a canonical object with `version: 1` and a lexically sorted map of
variables. Every variable declares:

| Field | Contract |
|---|---|
| `name` | dotted identifier segments matching `[A-Za-z_][A-Za-z0-9_]*`; the final segment may end in `?` for predicate-style keys |
| `type` | `string`, `integer`, `number`, `boolean`, `date`, `datetime`, `url`, `email`, `phone`, `object`, or `list` |
| `phase` | `compile` or `delivery` |
| `context` | `text`, `html_text`, `html_attribute`, `url`, `color`, `css`, `subject`, or `none` |
| `required` | boolean |
| `default` | optional JSON-compatible value validated by type |
| `description` | optional human text |
| `sensitive` | boolean; sensitive values are never returned in diagnostics or telemetry |
| `items` / `properties` | nested schema for lists and objects |

Compilation rejects undeclared variables, incompatible contexts, missing
required compile values, schema cycles, unbounded nesting, and reserved names.
Rendering rejects missing required delivery values, unknown values when strict
mode is active, invalid types, unsafe URLs, CR/LF in subject values, and budget
violations.

Context declarations form a deliberately narrow compatibility lattice so one
typed value can be reused across the outputs of an atomic email artifact:

- `text` may be emitted as plain text, HTML text, an HTML attribute, or a
  subject; the compiler still injects the escape filter for each actual use.
- `url` may be emitted in a URL-bearing attribute or displayed as plain text,
  HTML text, or a subject. URL type validation remains mandatory.
- compile-phase `color` may be emitted in a color attribute or a CSS value;
  every occurrence is validated against its actual sink before MJML runs.

Other context combinations remain incompatible. In particular, a general
text declaration cannot enter a URL, color, or CSS sink, and URL declarations
cannot enter arbitrary HTML attributes.

The compiler reports discovered-but-undeclared and declared-but-unused
variables separately. It never infers a security context from a variable name.

`Letterpress.discover/3` is the schema-neutral migration and authoring seam. It
returns parsed variable output uses with their compiler-proven contexts,
control-flow dependencies with the neutral `none` context and a condition,
collection, or lookup kind, and whether an output is scoped to a named local
loop binding and collection. It still enforces profile grammar,
source budgets, allowed MJML/HTML, Liquid tags, and filters. It does not infer
types, phases, requiredness, or defaults and does not report undeclared/unused
schema diagnostics. Consumers must build and review a schema, then call
ordinary analysis or compilation before publication.

## 5. Compiler pipeline

`Letterpress.compile/4` accepts profile, source, schema, and options and returns
`{:ok, artifact, diagnostics}` or `{:error, diagnostics}`.

The email profile accepts optional `:subject` and `:text` Liquid sources. Both
are analyzed against the same schema, compiled into the same immutable
artifact, and rendered atomically with HTML. The HTML and text profiles use
their primary source as the corresponding single channel and reject those
email-only options.

For `email/mjml-liquid@1` the authoritative pipeline is:

1. normalize UTF-8 input, optional subject, and optional text alternative and
   calculate their source hashes;
2. parse the mixed MJML/Liquid document with source positions;
3. validate profile grammar, schema references, contexts, and limits;
4. resolve compile-phase values;
5. replace delivery expressions with collision-resistant sentinels carrying no
   secret or source text;
6. adapt allowed structural controls so every compiler input remains valid
   MJML without exposing file/plugin features;
7. compile in `validationLevel: strict` with the pinned official MJML compiler
   and `sanitizeStyles` enabled;
8. prove that each sentinel's compiler-emitted occurrence count and output
   contexts exactly match a modeled transformation (MJML intentionally emits
   `mj-title` into title text and the document's `aria-label` attribute);
9. restore every emitted occurrence with a normalized Liquid expression and
   the internal final filter for that occurrence's actual output context;
10. validate the HTML Liquid artifact and source map;
11. retain non-error analysis diagnostics as artifact lint metadata;
12. canonicalize and hash the artifact.

Any sentinel collision, loss, unexpected duplication outside a compiler-known
duplication site, unmodeled relocation, or unmapped compiler error fails
closed. A modeled duplication spanning multiple contexts receives a distinct
final context filter at each output location.

`html/liquid@1` validates the parsed fragment against the embedded-HTML
allow-list, resolves compile values, proves delivery sentinels remain in their
modeled output contexts, and emits HTML Liquid without invoking MJML.
`text/liquid@1` runs the same Liquid/schema analysis without HTML or MJML
compilation.

## 6. Supervised compiler worker

The Hex package contains one prebuilt Node bundle under `priv/compiler`. A
supervised Elixir pool communicates over length-prefixed JSON frames. Each
request has an opaque ID, operation, and bounded payload. The Elixir caller
enforces the deadline, and the checked-in bundle embeds the generated contract.
Each response repeats the ID and returns a result or a bounded error.

Requirements:

- Node 22 or newer is supported; the exact Node, MJML, parser, and bundle
  versions are stamped into artifacts.
- the host owns compiler supervision; pool size and maximum frame size are
  child-spec options, while the request timeout and pool selection are
  per-call options with conservative defaults;
- a crashed, malformed, oversized, or late worker response fails the request,
  restarts only that worker, and never desynchronizes later requests;
- source and variable values are excluded from logs and telemetry;
- the bundle does not use the network, shell, dynamic import, includes, or host
  file access;
- deployments that only render precompiled artifacts omit the compiler child
  and do not require Node.

Node permission mode may reduce accidental access but is not a security
sandbox. Hosts still isolate compiler workloads with normal process/container
controls when authors are untrusted.

## 7. Artifact contract

The artifact is canonical JSON and its Elixir struct projection. Required
fields are:

```json
{
  "artifact_version": 1,
  "profile": "email/mjml-liquid@1",
  "source_sha256": "hex",
  "schema_sha256": "hex",
  "options_sha256": "hex",
  "compiler": {
    "letterpress": "semver",
    "node": "semver",
    "mjml": "semver",
    "parser": "semver",
    "bundle_sha256": "hex"
  },
  "subject": "Liquid source or null",
  "html": "Liquid source or null",
  "text": "Liquid source or null",
  "variables": [],
  "translation_units": [],
  "source_map": {},
  "lint": [],
  "content_sha256": "hex"
}
```

Canonicalization uses UTF-8, lexically sorted object keys, original array order,
no insignificant whitespace, JSON native values, and SHA-256 lowercase hex.
`content_sha256` covers every artifact field except itself. Timestamps, host
paths, process IDs, random request IDs, and build-machine details are forbidden.

Consumers persist the complete artifact. They must reject unknown artifact
versions unless an explicit compatible decoder exists. Existing valid
artifacts remain renderable when the compiler is unavailable.

## 8. Safe Liquid runtime

The runtime uses Solid behind a Letterpress-owned policy layer; direct Solid
templates are not artifacts.

- Strict variables and filters are enabled.
- Only profile filters and tags are registered.
- Filesystem and include/render loaders are blank.
- Every compiler-restored output ends with the internal context filter.
- HTML text and attribute contexts use the appropriate escaping.
- URL context parses and validates the scheme before attribute escaping.
- Subject context rejects CR, LF, NUL, and configured size overflow.
- CSS and color contexts are compile-only and validated before MJML compilation.
- Source bytes, input depth, input keys, scalar size, collection size, loop
  iterations, output bytes, render duration, and process heap are bounded.
- Rendering executes in a monitored isolated BEAM process. Timeout, memory,
  invalid input, missing data, and output overflow return diagnostics rather
  than partial output.

`Letterpress.render/3` accepts only a decoded Artifact, values, and runtime
options. It returns all rendered channels atomically or an error; callers never
send one channel from a partially failed render.

## 9. Diagnostics

Diagnostics use a versioned LSP-shaped JSON contract:

```json
{
  "version": 1,
  "source_hash": "hex",
  "document_version": 12,
  "range": {
    "start": {"line": 0, "character": 0},
    "end": {"line": 0, "character": 4}
  },
  "severity": "error",
  "code": "LP_MJML_UNKNOWN_ELEMENT",
  "source": "letterpress-mjml",
  "message": "Unknown MJML element mj-foo",
  "related": [],
  "data": {}
}
```

Lines and characters are zero-based UTF-16 code units so CodeMirror/LSP
clients can consume ranges without lossy conversion. Codes and sources are
stable; prose may improve in minor releases. Severity is `error`, `warning`,
`information`, or `hint`. Diagnostics never contain variable values, full
source, credentials, host paths, or exception dumps.

Compiler diagnostics must map MJML and Liquid failures back to source whenever
the worker provides enough evidence. A document-level range is the explicit
fallback, never a fabricated line.

## 10. Translation units

Letterpress extracts stable translation units from subject, text-bearing MJML
nodes, and allow-listed human-facing attributes. IDs derive from profile,
structural source path, context, and source text hash. Units include source
range, context, source text, placeholders, and optional description.

Email extraction accepts the same optional subject and plain-text sources as
compilation. Every email unit carries its `html`, `subject`, or `text` channel,
and the channel participates in the stable ID so identical copy in two channels
cannot collide. Translation application returns all configured authoring
sources atomically; one missing or structurally invalid channel unit rejects
the whole localized result. The source-only application API remains available
for the single-channel HTML and text profiles.

The `html/liquid@1` and `text/liquid@1` profiles represent their human-facing
content as one whole-document translation unit. This keeps surrounding
whitespace, inline markup, and Liquid control flow intact for short fragments
while the structural signature prevents a translation provider from changing
markup, attributes, outputs, or tags. A document containing only whitespace
and Liquid syntax has no translation unit.

Applying translations:

- requires an exact source hash and complete placeholder preservation;
- validates translated content for its context;
- never translates tags, Liquid code, CSS, URLs, variable names, or structure;
- returns a new source document and diagnostics; it does not compile or publish;
- treats missing units as incomplete, never as success.

Consumers own supported locale lists, provider calls, review state, and the
decision to compile translated sources.

## 11. Browser contract and editor packages

The Hex build generates canonical metadata consumed by both npm packages:
profile IDs, MJML elements and attributes, value types, nesting rules, Liquid
tags/filters, schema JSON, snippets, diagnostic codes, and contract version.
Hand-maintained duplicate registries are forbidden.

`@letterpress/language` provides:

- mixed parsing for MJML, restricted Liquid, and CSS inside `mj-style`;
- correct token highlighting for markup, attributes, text, Liquid outputs,
  Liquid controls, comments, filters, strings, numbers, operators, and CSS;
- MJML/profile-aware completion, snippets, closing tags, attribute values, and
  schema-variable completion filtered by phase/context;
- structural folding, bracket/tag matching, indentation, selection ranges,
  local diagnostics, and optional server-diagnostic mapping;
- deterministic formatting through the pinned Shopify Liquid formatter plus
  Letterpress profile rules;
- framework-neutral CodeMirror 6 extensions and typed APIs.

Local diagnostics are enabled by default. A consumer whose authoring source
contains host-owned preprocessing syntax may set `clientDiagnostics: false` on
the language extension or editor component. This disables only Letterpress's
local lint pass; parsing, highlighting, completion, folding, formatting, and
mapped server diagnostics remain available. The consumer must preprocess the
authoring source deterministically before authoritative analysis or
compilation, and must associate returned diagnostics with the exact authoring
source hash or document version that produced the preprocessed input. A client
must discard diagnostics for a stale hash or version. Disabling local
diagnostics never permits publication without backend approval.

`@letterpress/svelte` provides an unstyled Svelte 5 component that creates and
destroys CodeMirror safely, supports controlled source/schema/diagnostics,
reconfigures theme and profile without recreating history, exposes save/change/
format hooks, and provides configurable line numbers, fold/lint gutters,
matching, indentation, search, completion, line wrapping, and placeholders. It
does not call a backend or decide UI layout.

The normal theming boundary is a plain `LetterpressEditorTheme` value containing
complete `light` and `dark` palettes. The package ships an accessible reference
pair and a typed constructor that deep-merges consumer overrides into that
pair. A host selects the active palette through the `colorScheme` prop; changing
the prop reconfigures CodeMirror without recreating editor state or history.

Every editor and syntax color accepts any valid CSS color, including custom
properties and `color-mix()`. This lets a host map Letterpress directly onto its
semantic design tokens without forking the component. The reference palettes
use `--letterpress-editor-*` custom properties with standalone fallbacks, so
they also serve as a complete override template. Typography is part of each
palette and has the same override boundary. Letterpress must not depend on a
host theme class, token name, brand, or mode library.

The component constructs CodeMirror theme and highlight extensions inside its
own runtime so linked local packages cannot create duplicate
`@codemirror/state` identities. Raw `Extension` values remain an advanced
escape hatch; consumers using that escape hatch must deduplicate CodeMirror
peer dependencies.

Both packages declare broad peer ranges for CodeMirror/Svelte and ship ESM,
types, source maps, export maps, provenance-ready package metadata, and no
undeclared runtime imports.

## 12. Public Elixir API

The stable v1 entry points are:

```elixir
Letterpress.profiles/0
Letterpress.discover/3
Letterpress.analyze/4
Letterpress.compile/4
Letterpress.render/3
Letterpress.extract_translation_units/4
Letterpress.apply_translations/5
Letterpress.localize/5
Letterpress.format/3
Letterpress.decode_artifact/1
Letterpress.encode_artifact/1
Letterpress.contract/0
```

Public options are validated with NimbleOptions. Expected failures return
tagged tuples. Bang variants are intentionally omitted from the authoring and
render boundary.

## 13. Telemetry

Letterpress emits start/stop/exception events for compile, discover, analyze,
render, format, source-only translation application, and atomic email
localization under `[:letterpress, operation, phase]`.
Measurements include monotonic duration and bounded sizes/counts. Metadata may
include profile, artifact version, result class, diagnostic codes, and compiler
availability. Source, output, values, tenant IDs, template IDs, locale, and
arbitrary caller metadata are excluded.

## 14. Conformance and verification

One fixture corpus is consumed by Elixir and JavaScript tests. Its portable
analysis cases cover all three profiles, representative MJML and HTML
allow-list failures, unsafe static URLs, element-specific attributes,
undeclared variables, forbidden filters, context mismatches, malformed Liquid,
and loop-local scope. A browser package may implement a smaller advisory set,
but any rule it models must agree with the backend diagnostic code.

Owning unit suites provide the rest of the current proof:

- compiler tests cover official MJML output, email channels, discovery,
  formatting, worker recovery, named pools, frame limits, and timeouts;
- sentinel tests cover loss, duplication, relocation, unsafe output positions,
  and the modeled `mj-title` duplication;
- schema, artifact, renderer, translation, diagnostic, telemetry, and JSON
  tests cover their public boundaries and failure modes;
- one StreamData property checks that map insertion order cannot change
  canonical JSON bytes;
- Vitest covers mixed parsing, completion, local and mapped diagnostics,
  formatting, Svelte lifecycle, accessibility, and paired theme behavior;
- notebook tests execute every code cell and compare saved output;
- CI compares compiler-bundle hashes across Node 22 and 24 on Linux and macOS;
- the release workflow packs one Hex tarball and two npm tarballs, then installs
  those exact files in throwaway consumers.

Future fuzz corpora, golden artifacts, or broader property coverage must be
described as planned work until the corresponding files and gates exist.

## 15. Release model

One `vX.Y.Z` source tag identifies the Hex and both npm packages. Their versions
must match. The release workflow builds artifacts once, verifies checksums and
package exports, installs those exact artifacts into throwaway Elixir and
Svelte consumers, and only then reaches a protected publish environment.

Before the first tag, `CHANGELOG.md` contains no generated project history.
GitOps creates the initial changelog from Conventional Commits in the release
commit. This specification does not authorize a tag, GitHub repository,
registry package, publish, or release.

## 16. Adoption contract

A dynamic-authoring host:

1. validates and compiles each locale before publication;
2. persists the complete artifact beside its immutable revision;
3. switches a published pointer only after every required locale compiles;
4. renders the stored artifact in delivery workers;
5. keeps the previous pointer for rollback;
6. backfills existing published revisions before removing legacy rendering;
7. omits compiler supervision on delivery-only nodes.

A static-template host may compile in CI/build and ship artifacts, avoiding Node
in production entirely.

Legacy importers must output profile source and schema, invoke the normal
Letterpress compile gate, retain source provenance in the host, and quarantine
failures. Letterpress does not read a legacy database or decide acceptance.

## 17. Initial acceptance gates

The first implementation is accepted only when:

- official MJML compilation is supervised and independent of delivery render;
- all persisted artifacts are deterministic and decode/render without Node;
- unsafe Liquid, includes, untyped variables, context confusion, and budget
  overflow fail closed with source-appropriate diagnostics;
- the frontend contract is generated and both npm packages pass package and
  consumer smokes;
- shared conformance fixtures pass in Elixir and JavaScript;
- a real consumer migrates preview, publication, delivery, and legacy-import
  validation to Letterpress without product logic entering this repository;
- repository quality, coverage, audit, docs, and dry-run release gates pass.
