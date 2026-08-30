<script lang="ts" module>
import type { Extension } from "@codemirror/state"
import type { Profile, ServerDiagnostic, VariableSchema } from "@letterpress/language"

export interface LetterpressEditorTheme {
  editor: {
    foreground: string
    background: string
    selection: string
    activeLine: string
    cursor: string
    gutterForeground: string
    gutterBackground: string
    gutterBorder: string
  }
  syntax: {
    tagName: string
    angleBracket: string
    attributeName: string
    attributeValue: string
    string: string
    propertyName: string
    className: string
    brace: string
    variableName: string
    keyword: string
    controlKeyword: string
    url: string
    number: string
    comment: string
    content: string
  }
}

export interface LetterpressEditorProps {
  source?: string
  profile: Profile
  schema: VariableSchema
  diagnostics?: readonly ServerDiagnostic[]
  documentVersion?: number
  sourceHash?: string
  extensions?: readonly Extension[]
  theme?: LetterpressEditorTheme
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
    HighlightStyle,
    indentOnInput,
    syntaxHighlighting,
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
  import { tags } from "@lezer/highlight"
  import { onMount } from "svelte"

  let {
    source = $bindable(""),
    profile,
    schema,
    diagnostics = [],
    documentVersion,
    sourceHash,
    extensions = [],
    theme,
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

  function themeExtension(): Extension {
    if (!theme) return []

    return [
      EditorView.theme({
        "&": {
          color: theme.editor.foreground,
          backgroundColor: theme.editor.background,
        },
        ".cm-content": { caretColor: theme.editor.cursor },
        ".cm-cursor, .cm-dropCursor": { borderLeftColor: theme.editor.cursor },
        "&.cm-focused > .cm-scroller > .cm-selectionLayer .cm-selectionBackground, .cm-selectionBackground, .cm-content ::selection":
          { backgroundColor: theme.editor.selection },
        ".cm-activeLine, .cm-activeLineGutter": {
          backgroundColor: theme.editor.activeLine,
        },
        ".cm-gutters": {
          backgroundColor: theme.editor.gutterBackground,
          color: theme.editor.gutterForeground,
          borderRight: `1px solid ${theme.editor.gutterBorder}`,
        },
        ".cm-lineNumbers .cm-gutterElement": { color: theme.editor.gutterForeground },
      }),
      syntaxHighlighting(
        HighlightStyle.define([
          { tag: tags.tagName, color: theme.syntax.tagName },
          { tag: tags.angleBracket, color: theme.syntax.angleBracket },
          { tag: tags.attributeName, color: theme.syntax.attributeName },
          { tag: tags.attributeValue, color: theme.syntax.attributeValue },
          { tag: tags.string, color: theme.syntax.string },
          { tag: tags.propertyName, color: theme.syntax.propertyName },
          { tag: tags.className, color: theme.syntax.className },
          { tag: tags.special(tags.brace), color: theme.syntax.brace },
          { tag: tags.variableName, color: theme.syntax.variableName },
          { tag: tags.keyword, color: theme.syntax.keyword },
          { tag: tags.controlKeyword, color: theme.syntax.controlKeyword },
          { tag: tags.url, color: theme.syntax.url },
          { tag: tags.number, color: theme.syntax.number },
          { tag: tags.comment, color: theme.syntax.comment, fontStyle: "italic" },
          { tag: tags.content, color: theme.syntax.content },
        ]),
      ),
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
          themeCompartment.of(themeExtension()),
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
    view.dispatch({ effects: themeCompartment.reconfigure(themeExtension()) })
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
