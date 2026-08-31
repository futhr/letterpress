<script lang="ts">
import type { EditorView } from "@codemirror/view"
import LetterpressEditor from "../src/letterpress-editor.svelte"
import type { LetterpressEditorColorScheme } from "../src/theme"

const schema = { version: 1 as const, variables: {} }
let source = $state("Hello")
let colorScheme = $state<LetterpressEditorColorScheme>("light")
let view: EditorView | undefined

export function setColorScheme(value: LetterpressEditorColorScheme): void {
  colorScheme = value
}

export function getView(): EditorView | undefined {
  return view
}
</script>

<LetterpressEditor
  bind:source
  profile="text/liquid@1"
  {schema}
  {colorScheme}
  onReady={(editor) => {
    view = editor
  }}
/>
