# `@letterpress/svelte`

An unopinionated Svelte 5 shell around CodeMirror and `@letterpress/language`. It
owns editor lifecycle, controlled source updates, profile/schema/diagnostic
reconfiguration, keyboard save/format commands, read-only state, focus, and
accessibility. Standard line-number, folding, lint, matching, indentation,
completion, search, wrapping, and placeholder behavior is configurable through
props. It does not call a backend or make publication decisions.

The bundled editor theme is a complete light/dark reference pair. Override its
`--letterpress-editor-*` CSS properties or build a paired product theme with
`createLetterpressEditorTheme`. Theme values may reference product CSS
variables. Select the active palette with `colorScheme`; changing modes keeps
the current document, selection, and undo history.

Letterpress creates the underlying CodeMirror theme and highlighting extensions
internally, so local linked consumers do not exchange identity-sensitive
extension objects. The `extensions` prop remains available for advanced
peer-deduplicated hosts.

```svelte
<script lang="ts">
  import { LetterpressEditor } from "@letterpress/svelte"

  let source = $state("<mjml><mj-body /></mjml>")
  const schema = { version: 1 as const, variables: {} }
</script>

<LetterpressEditor
  bind:source
  profile="email/mjml-liquid@1"
  {schema}
  {diagnostics}
  {documentVersion}
  {sourceHash}
  colorScheme="light"
  onSave={saveDraft}
/>
```

The component does not own product layout. Place it in the host product's own
container and map the paired theme to that product's semantic tokens.
