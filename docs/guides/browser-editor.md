# Browser editor

Install the framework-neutral language package, or the Svelte shell plus its
peer dependencies:

```bash
pnpm add @letterpress/language
pnpm add @letterpress/svelte svelte @codemirror/autocomplete @codemirror/commands @codemirror/language @codemirror/lint @codemirror/search @codemirror/state @codemirror/view
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
The extension drops stale responses so an older validation request cannot
annotate newer text.

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
/>
```

Local diagnostics are deliberately advisory. A product must call the backend
compiler before publishing and persist only the returned immutable artifact.
