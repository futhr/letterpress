# Browser editor

Install the framework-neutral language package, or the Svelte shell plus its
peer dependencies:

```bash
pnpm add @letterpress/language
pnpm add @letterpress/svelte svelte @codemirror/state @codemirror/view @codemirror/commands
```

`@letterpress/language` combines CodeMirror's HTML, Liquid, and CSS parsers.
MJML tags and attributes come from the generated backend contract. It provides
folding, matching, indentation, closing tags, snippets, typed variable
completion, context-aware diagnostics, and deterministic formatting.

The Svelte component owns CodeMirror lifecycle only. The host owns layout,
theme, persistence, backend calls, draft state, AI actions, and publication.
Pass backend diagnostics together with the source hash and document version;
the extension drops stale responses so an older validation request cannot
annotate newer text.

```svelte
<LetterpressEditor
  bind:source
  profile="email/mjml-liquid@1"
  {schema}
  diagnostics={validation.diagnostics}
  sourceHash={validation.source_hash}
  documentVersion={validation.document_version}
  theme={editorTheme}
  onSave={() => saveDraft(source)}
/>
```

Local diagnostics are deliberately advisory. A product must call the backend
compiler before publishing and persist only the returned immutable artifact.
