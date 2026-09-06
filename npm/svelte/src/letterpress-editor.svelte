<script lang="ts">
import { closeBrackets, closeBracketsKeymap, completionKeymap } from "@codemirror/autocomplete"
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
import { Compartment, EditorState, type Extension, Prec } from "@codemirror/state"
import {
  lineNumbers as codeLineNumbers,
  drawSelection,
  dropCursor,
  EditorView,
  placeholder as editorPlaceholder,
  highlightActiveLine,
  highlightActiveLineGutter,
  keymap,
} from "@codemirror/view"
import { formatLetterpressSource, letterpressLanguage } from "@letterpress/language"
import { tags } from "@lezer/highlight"
import { onMount } from "svelte"
import { defaultLetterpressEditorTheme } from "./theme"
import type { LetterpressEditorProps } from "./types"

let {
  source = $bindable(""),
  profile,
  schema,
  diagnostics = [],
  clientDiagnostics = true,
  documentVersion,
  sourceHash,
  extensions = [],
  theme = defaultLetterpressEditorTheme,
  colorScheme = "light",
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
  onError,
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
    clientDiagnostics,
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
  const palette = theme[colorScheme]
  const editor = palette.editor

  return [
    EditorView.theme(
      {
        "&": {
          color: editor.foreground,
          backgroundColor: editor.background,
          fontSize: editor.fontSize,
        },
        ".cm-scroller": {
          fontFamily: editor.fontFamily,
          lineHeight: editor.lineHeight,
        },
        ".cm-content": { caretColor: editor.cursor },
        ".cm-cursor, .cm-dropCursor": { borderLeftColor: editor.cursor },
        "&.cm-focused > .cm-scroller > .cm-selectionLayer .cm-selectionBackground, .cm-selectionBackground, .cm-content ::selection":
          { backgroundColor: editor.selection },
        ".cm-activeLine, .cm-activeLineGutter": {
          backgroundColor: editor.activeLine,
        },
        ".cm-gutters": {
          backgroundColor: editor.mutedBackground,
          color: editor.mutedForeground,
          borderRight: `1px solid ${editor.border}`,
        },
        ".cm-lineNumbers .cm-gutterElement": { color: editor.mutedForeground },
        ".cm-panels": {
          backgroundColor: editor.mutedBackground,
          color: editor.foreground,
        },
        ".cm-panels.cm-panels-top": { borderBottom: `1px solid ${editor.border}` },
        ".cm-panels.cm-panels-bottom": { borderTop: `1px solid ${editor.border}` },
        ".cm-textfield, .cm-button": {
          backgroundColor: editor.background,
          color: editor.foreground,
          border: `1px solid ${editor.border}`,
        },
        ".cm-button": {
          backgroundImage: "none",
        },
        ".cm-tooltip": {
          backgroundColor: editor.mutedBackground,
          color: editor.foreground,
          border: `1px solid ${editor.border}`,
        },
        ".cm-tooltip-autocomplete > ul > li[aria-selected]": {
          backgroundColor: editor.accent,
          color: editor.accentForeground,
        },
        ".cm-searchMatch": {
          backgroundColor: editor.selection,
          outline: `1px solid ${editor.accent}`,
        },
        ".cm-searchMatch.cm-searchMatch-selected, .cm-matchingBracket": {
          backgroundColor: editor.activeLine,
          outline: `1px solid ${editor.accent}`,
        },
        ".cm-foldPlaceholder": {
          backgroundColor: editor.mutedBackground,
          color: editor.mutedForeground,
          border: `1px solid ${editor.border}`,
        },
      },
      { dark: colorScheme === "dark" },
    ),
    syntaxHighlighting(
      HighlightStyle.define([
        { tag: tags.tagName, color: palette.syntax.tagName },
        { tag: tags.angleBracket, color: palette.syntax.angleBracket },
        { tag: tags.attributeName, color: palette.syntax.attributeName },
        { tag: tags.attributeValue, color: palette.syntax.attributeValue },
        { tag: tags.string, color: palette.syntax.string },
        { tag: tags.propertyName, color: palette.syntax.propertyName },
        { tag: tags.className, color: palette.syntax.className },
        { tag: tags.special(tags.brace), color: palette.syntax.brace },
        { tag: tags.variableName, color: palette.syntax.variableName },
        { tag: tags.keyword, color: palette.syntax.keyword },
        { tag: tags.controlKeyword, color: palette.syntax.controlKeyword },
        { tag: tags.url, color: palette.syntax.url },
        { tag: tags.number, color: palette.syntax.number },
        { tag: tags.comment, color: palette.syntax.comment, fontStyle: "italic" },
        { tag: tags.content, color: palette.syntax.content },
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
                void runCommand("save", () => onSave?.(view?.state.doc.toString() ?? source))
                return true
              },
            },
            {
              key: "Shift-Alt-f",
              preventDefault: true,
              run: () => {
                void runCommand("format", formatEditor)
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

async function runCommand(
  operation: "save" | "format",
  action: () => void | Promise<void>,
): Promise<void> {
  try {
    await action()
  } catch (error) {
    onError?.(error, operation)
  }
}

async function formatEditor(): Promise<void> {
  if (!view || readOnly) return
  const editor = view
  const document = editor.state.doc
  const currentProfile = profile
  const current = document.toString()
  const formatted = await formatLetterpressSource(currentProfile, current)
  if (view !== editor || editor.state.doc !== document || profile !== currentProfile || readOnly) {
    return
  }
  if (formatted !== current) {
    editor.dispatch({ changes: { from: 0, to: current.length, insert: formatted } })
  }
  await onFormat?.(formatted)
}
</script>

<div
  bind:this={host}
  class={className}
  data-letterpress-editor
  data-color-scheme={colorScheme}
  data-readonly={readOnly}
></div>
