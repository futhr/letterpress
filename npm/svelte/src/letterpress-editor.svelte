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
  lineNumbers?: boolean
  folding?: boolean
  lintGutter?: boolean
  lineWrapping?: boolean
  placeholder?: string
  ariaLabel?: string
  class?: string
  onChange?: (source: string) => void
  onSave?: (source: string) => void | Promise<void>
  onFormat?: (source: string) => void | Promise<void>
  onReady?: (view: import("@codemirror/view").EditorView) => void
}
</script>

<script lang="ts">
  import {
    closeBrackets,
    closeBracketsKeymap,
    completionKeymap,
  } from "@codemirror/autocomplete"
  import { defaultKeymap, history, historyKeymap, indentWithTab } from "@codemirror/commands"
  import {
    bracketMatching,
    foldGutter,
    foldKeymap,
    indentOnInput,
  } from "@codemirror/language"
  import { lintGutter as codeLintGutter } from "@codemirror/lint"
  import { search, searchKeymap } from "@codemirror/search"
  import { Compartment, EditorState, Prec } from "@codemirror/state"
  import {
    drawSelection,
    dropCursor,
    EditorView,
    highlightActiveLine,
    highlightActiveLineGutter,
    keymap,
    lineNumbers as codeLineNumbers,
    placeholder as editorPlaceholder,
  } from "@codemirror/view"
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
    lineNumbers = true,
    folding = true,
    lintGutter = true,
    lineWrapping = true,
    placeholder,
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
  const interfaceCompartment = new Compartment()
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

  function interfaceExtensions(): Extension {
    return [
      lineNumbers ? [codeLineNumbers(), highlightActiveLineGutter()] : [],
      folding ? foldGutter() : [],
      lintGutter ? codeLintGutter() : [],
      lineWrapping ? EditorView.lineWrapping : [],
      placeholder ? editorPlaceholder(placeholder) : [],
    ]
  }

  onMount(() => {
    view = new EditorView({
      parent: host,
      state: EditorState.create({
        doc: source,
        extensions: [
          history(),
          drawSelection(),
          dropCursor(),
          indentOnInput(),
          bracketMatching(),
          closeBrackets(),
          search(),
          highlightActiveLine(),
          Prec.high(
            keymap.of([
              {
                key: "Mod-s",
                preventDefault: true,
                run: () => {
                  void onSave?.(view?.state.doc.toString() ?? source)
                  return true
                },
              },
              {
                key: "Shift-Alt-f",
                preventDefault: true,
                run: () => {
                  void formatEditor()
                  return true
                },
              },
            ]),
          ),
          keymap.of([
            ...defaultKeymap,
            ...historyKeymap,
            ...closeBracketsKeymap,
            ...completionKeymap,
            ...foldKeymap,
            ...searchKeymap,
            indentWithTab,
          ]),
          accessibilityCompartment.of(EditorView.contentAttributes.of({ "aria-label": ariaLabel })),
          interfaceCompartment.of(interfaceExtensions()),
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
    view.dispatch({ effects: interfaceCompartment.reconfigure(interfaceExtensions()) })
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
