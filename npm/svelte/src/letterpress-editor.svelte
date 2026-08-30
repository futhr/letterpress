<script lang="ts" module>
import type { Extension } from "@codemirror/state"
import type { Profile, ServerDiagnostic, VariableSchema } from "@letterpress/language"

export interface LetterpressEditorProps {
  source?: string
  profile: Profile
  schema: VariableSchema
  diagnostics?: readonly ServerDiagnostic[]
  documentVersion?: number
  sourceHash?: string
  extensions?: readonly Extension[]
  theme?: Extension
  readOnly?: boolean
  autofocus?: boolean
  ariaLabel?: string
  class?: string
  onChange?: (source: string) => void
  onSave?: (source: string) => void | Promise<void>
  onFormat?: (source: string) => void | Promise<void>
  onReady?: (view: import("@codemirror/view").EditorView) => void
}
</script>

<script lang="ts">
  import { defaultKeymap, history, historyKeymap, indentWithTab } from "@codemirror/commands"
  import { Compartment, EditorState } from "@codemirror/state"
  import { EditorView, keymap } from "@codemirror/view"
  import { formatLetterpressSource, letterpressLanguage } from "@letterpress/language"
  import { onMount } from "svelte"

  let {
    source = $bindable(""),
    profile,
    schema,
    diagnostics = [],
    documentVersion,
    sourceHash,
    extensions = [],
    theme = [],
    readOnly = false,
    autofocus = false,
    ariaLabel = "Template source",
    class: className = "",
    onChange,
    onSave,
    onFormat,
    onReady,
  }: LetterpressEditorProps = $props()

  let host: HTMLDivElement
  let view: EditorView | undefined
  let applyingExternalSource = false
  const languageCompartment = new Compartment()
  const themeCompartment = new Compartment()
  const editableCompartment = new Compartment()
  const accessibilityCompartment = new Compartment()
  const extraCompartment = new Compartment()

  function languageExtension(): Extension {
    return letterpressLanguage({
      profile,
      schema,
      serverDiagnostics: diagnostics,
      ...(documentVersion === undefined ? {} : { documentVersion }),
      ...(sourceHash === undefined ? {} : { sourceHash }),
    })
  }

  onMount(() => {
    view = new EditorView({
      parent: host,
      state: EditorState.create({
        doc: source,
        extensions: [
          history(),
          keymap.of([
            ...defaultKeymap,
            ...historyKeymap,
            indentWithTab,
            {
              key: "Mod-s",
              preventDefault: true,
              run: () => {
                void onSave?.(view?.state.doc.toString() ?? source)
                return true
              },
            },
            {
              key: "Shift-Mod-f",
              preventDefault: true,
              run: () => {
                void formatEditor()
                return true
              },
            },
          ]),
          accessibilityCompartment.of(EditorView.contentAttributes.of({ "aria-label": ariaLabel })),
          EditorView.updateListener.of((update) => {
            if (!update.docChanged || applyingExternalSource) return
            source = update.state.doc.toString()
            onChange?.(source)
          }),
          languageCompartment.of(languageExtension()),
          themeCompartment.of(theme),
          editableCompartment.of([
            EditorState.readOnly.of(readOnly),
            EditorView.editable.of(!readOnly),
          ]),
          extraCompartment.of(extensions),
        ],
      }),
    })
    if (autofocus) view.focus()
    onReady?.(view)
    return () => {
      view?.destroy()
      view = undefined
    }
  })

  $effect(() => {
    if (!view) return
    view.dispatch({
      effects: languageCompartment.reconfigure(languageExtension()),
    })
  })

  $effect(() => {
    if (!view) return
    view.dispatch({ effects: themeCompartment.reconfigure(theme) })
  })

  $effect(() => {
    if (!view) return
    view.dispatch({
      effects: editableCompartment.reconfigure([
        EditorState.readOnly.of(readOnly),
        EditorView.editable.of(!readOnly),
      ]),
    })
  })

  $effect(() => {
    if (!view) return
    view.dispatch({
      effects: accessibilityCompartment.reconfigure(
        EditorView.contentAttributes.of({ "aria-label": ariaLabel }),
      ),
    })
  })

  $effect(() => {
    if (!view) return
    view.dispatch({ effects: extraCompartment.reconfigure(extensions) })
  })

  $effect(() => {
    if (!view) return
    const current = view.state.doc.toString()
    if (source === current) return
    applyingExternalSource = true
    view.dispatch({ changes: { from: 0, to: current.length, insert: source } })
    applyingExternalSource = false
  })

  async function formatEditor(): Promise<void> {
    if (!view || readOnly) return
    const editor = view
    const current = editor.state.doc.toString()
    const formatted = await formatLetterpressSource(profile, current)
    if (view !== editor) return
    if (formatted !== current) {
      editor.dispatch({ changes: { from: 0, to: current.length, insert: formatted } })
    }
    await onFormat?.(formatted)
  }
</script>

<div bind:this={host} class={className} data-letterpress-editor data-readonly={readOnly}></div>
