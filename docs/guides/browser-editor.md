# Browser editor

Install the framework-neutral language package, or the Svelte shell plus its
peer dependencies:

```bash
pnpm add @letterpress/language @letterpress/svelte svelte \
  @codemirror/autocomplete @codemirror/commands @codemirror/lang-css \
  @codemirror/lang-html @codemirror/lang-liquid @codemirror/language \
  @codemirror/lint @codemirror/search @codemirror/state @codemirror/view \
  @lezer/highlight
```

`@letterpress/language` combines CodeMirror's HTML, Liquid, and CSS parsers.
MJML tags and attributes come from the generated backend contract. It provides
folding, matching, indentation, closing tags, snippets, typed variable
completion, contract-aware local diagnostics, and deterministic formatting.

The Svelte component owns CodeMirror lifecycle and standard editor behavior:
line numbers, folding, lint markers, matching, indentation, completion, search,
line wrapping, save/format keys, and controlled updates. The host owns layout,
persistence, backend calls, draft state, AI actions, and publication.

Letterpress supplies a complete light/dark reference theme. Use it directly,
override its `--letterpress-editor-*` custom properties, or create a paired host
theme with `createLetterpressEditorTheme`. Palette values may reference host CSS
variables, which is the preferred way to inherit a product design system.
Pass the current mode through `colorScheme`; mode changes preserve document
history and selection.

The component creates CodeMirror extensions internally, which keeps linked
local consumers on one runtime identity. Reserve raw `extensions` for advanced
behavior and deduplicate CodeMirror peers when using them.

Pass backend diagnostics together with the source hash and document version.
Update those freshness values on every source change, and clear diagnostics
while a new validation request is pending. The extension compares responses
with the values you supply; it does not calculate a source hash or increment
your document version.

```svelte
<script lang="ts">
  import type { ServerDiagnostic } from "@letterpress/language"
  import { LetterpressEditor } from "@letterpress/svelte"

  let source = $state("<mjml><mj-body /></mjml>")
  let diagnostics = $state<ServerDiagnostic[]>([])
  let sourceHash = $state("")
  let documentVersion = $state(0)
  const schema = { version: 1 as const, variables: {} }
</script>

<LetterpressEditor
  bind:source
  profile="email/mjml-liquid@1"
  {schema}
  {diagnostics}
  {sourceHash}
  {documentVersion}
  colorScheme="dark"
  onChange={() => {
    documentVersion += 1
    sourceHash = ""
    diagnostics = []
  }}
/>
```

Local diagnostics are deliberately advisory. A product must call the backend
compiler before publishing and persist only the returned immutable artifact.
