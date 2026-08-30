# `@letterpress/svelte`

An unstyled Svelte 5 shell around CodeMirror and `@letterpress/language`. It
owns editor lifecycle, controlled source updates, profile/schema/diagnostic
reconfiguration, keyboard save/format commands, read-only state, focus, and
accessibility. It does not call a backend or make publication decisions.

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
