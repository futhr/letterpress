# `@letterpress/svelte`

A Svelte 5 editor component built on CodeMirror and `@letterpress/language`. It
owns editor lifecycle, controlled source updates, profile/schema/diagnostic
reconfiguration, keyboard save/format commands, read-only state, focus, and
accessibility. Line numbers, folding, lint, matching, indentation, completion,
search, wrapping, and placeholder behavior are configurable through props. It
does not call a backend or make publication decisions.

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
  colorScheme="light"
/>
```

The component does not own product layout. Place it in the host product's own
container and map the paired theme to that product's semantic tokens.

Hosts that edit a preprocessing language may set `clientDiagnostics={false}`
and pass diagnostics from the backend after expansion. Grammar, highlighting,
completion, formatting, and freshness-filtered server diagnostics remain
enabled. Strict client diagnostics stay enabled by default.
