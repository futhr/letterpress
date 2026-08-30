# `@letterpress/svelte`

An unstyled Svelte 5 shell around CodeMirror and `@letterpress/language`. It
owns editor lifecycle, controlled source updates, profile/schema/diagnostic
reconfiguration, keyboard save/format commands, read-only state, focus, and
accessibility. Standard line-number, folding, lint, matching, indentation,
completion, search, wrapping, and placeholder behavior is configurable through
props. It does not call a backend or make publication decisions.

Use the plain `LetterpressEditorTheme` contract for colors. Letterpress creates
the underlying CodeMirror theme and highlighting extensions internally, so
local linked consumers do not exchange identity-sensitive extension objects.
The `extensions` prop remains available for advanced peer-deduplicated hosts.

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
  onSave={saveDraft}
/>
```

The component is intentionally unstyled. Pass a CodeMirror theme through the
`theme` prop and place the editor in the host product's own layout.
