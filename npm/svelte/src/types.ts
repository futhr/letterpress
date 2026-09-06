import type { Extension } from "@codemirror/state"
import type { EditorView } from "@codemirror/view"
import type { Profile, ServerDiagnostic, VariableSchema } from "@letterpress/language"
import type { LetterpressEditorColorScheme, LetterpressEditorTheme } from "./theme"

export interface LetterpressEditorProps {
  source?: string
  profile: Profile
  schema: VariableSchema
  diagnostics?: readonly ServerDiagnostic[]
  clientDiagnostics?: boolean
  documentVersion?: number
  sourceHash?: string
  extensions?: readonly Extension[]
  theme?: LetterpressEditorTheme
  colorScheme?: LetterpressEditorColorScheme
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
  onError?: (error: unknown, operation: "save" | "format") => void
  onReady?: (view: EditorView) => void
}
