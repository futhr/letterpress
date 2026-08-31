export type LetterpressEditorColorScheme = "light" | "dark"

export interface LetterpressEditorPalette {
  editor: {
    foreground: string
    background: string
    mutedForeground: string
    mutedBackground: string
    border: string
    accent: string
    accentForeground: string
    selection: string
    activeLine: string
    cursor: string
    fontFamily: string
    fontSize: string
    lineHeight: string
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

export interface LetterpressEditorTheme {
  light: LetterpressEditorPalette
  dark: LetterpressEditorPalette
}

export interface LetterpressEditorPaletteOverride {
  editor?: Partial<LetterpressEditorPalette["editor"]>
  syntax?: Partial<LetterpressEditorPalette["syntax"]>
}

export interface LetterpressEditorThemeOverrides {
  light?: LetterpressEditorPaletteOverride
  dark?: LetterpressEditorPaletteOverride
}

const lightPalette: LetterpressEditorPalette = {
  editor: {
    foreground: "var(--letterpress-editor-foreground, #334155)",
    background: "var(--letterpress-editor-background, #ffffff)",
    mutedForeground: "var(--letterpress-editor-muted-foreground, #64748b)",
    mutedBackground: "var(--letterpress-editor-muted-background, #f8fafc)",
    border: "var(--letterpress-editor-border, #e2e8f0)",
    accent: "var(--letterpress-editor-accent, #2563eb)",
    accentForeground: "var(--letterpress-editor-accent-foreground, #ffffff)",
    selection: "var(--letterpress-editor-selection, #bfdbfe)",
    activeLine: "var(--letterpress-editor-active-line, #f1f5f9)",
    cursor: "var(--letterpress-editor-cursor, #2563eb)",
    fontFamily:
      "var(--letterpress-editor-font-family, ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace)",
    fontSize: "var(--letterpress-editor-font-size, 0.875rem)",
    lineHeight: "var(--letterpress-editor-line-height, 1.6)",
  },
  syntax: {
    tagName: "var(--letterpress-syntax-tag-name, #1d4ed8)",
    angleBracket: "var(--letterpress-syntax-angle-bracket, #64748b)",
    attributeName: "var(--letterpress-syntax-attribute-name, #6d28d9)",
    attributeValue: "var(--letterpress-syntax-attribute-value, #047857)",
    string: "var(--letterpress-syntax-string, #047857)",
    propertyName: "var(--letterpress-syntax-property-name, #b45309)",
    className: "var(--letterpress-syntax-class-name, #0369a1)",
    brace: "var(--letterpress-syntax-brace, #7e22ce)",
    variableName: "var(--letterpress-syntax-variable-name, #7e22ce)",
    keyword: "var(--letterpress-syntax-keyword, #be123c)",
    controlKeyword: "var(--letterpress-syntax-control-keyword, #c2410c)",
    url: "var(--letterpress-syntax-url, #0369a1)",
    number: "var(--letterpress-syntax-number, #b45309)",
    comment: "var(--letterpress-syntax-comment, #64748b)",
    content: "var(--letterpress-syntax-content, #334155)",
  },
}

const darkPalette: LetterpressEditorPalette = {
  editor: {
    foreground: "var(--letterpress-editor-foreground, #dbe4f0)",
    background: "var(--letterpress-editor-background, #111827)",
    mutedForeground: "var(--letterpress-editor-muted-foreground, #8b9bb2)",
    mutedBackground: "var(--letterpress-editor-muted-background, #172033)",
    border: "var(--letterpress-editor-border, #334155)",
    accent: "var(--letterpress-editor-accent, #60a5fa)",
    accentForeground: "var(--letterpress-editor-accent-foreground, #0f172a)",
    selection: "var(--letterpress-editor-selection, #1e3a5f)",
    activeLine: "var(--letterpress-editor-active-line, #1e293b)",
    cursor: "var(--letterpress-editor-cursor, #60a5fa)",
    fontFamily:
      "var(--letterpress-editor-font-family, ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace)",
    fontSize: "var(--letterpress-editor-font-size, 0.875rem)",
    lineHeight: "var(--letterpress-editor-line-height, 1.6)",
  },
  syntax: {
    tagName: "var(--letterpress-syntax-tag-name, #7dd3fc)",
    angleBracket: "var(--letterpress-syntax-angle-bracket, #94a3b8)",
    attributeName: "var(--letterpress-syntax-attribute-name, #c4b5fd)",
    attributeValue: "var(--letterpress-syntax-attribute-value, #86efac)",
    string: "var(--letterpress-syntax-string, #86efac)",
    propertyName: "var(--letterpress-syntax-property-name, #fcd34d)",
    className: "var(--letterpress-syntax-class-name, #67e8f9)",
    brace: "var(--letterpress-syntax-brace, #d8b4fe)",
    variableName: "var(--letterpress-syntax-variable-name, #d8b4fe)",
    keyword: "var(--letterpress-syntax-keyword, #fda4af)",
    controlKeyword: "var(--letterpress-syntax-control-keyword, #fdba74)",
    url: "var(--letterpress-syntax-url, #7dd3fc)",
    number: "var(--letterpress-syntax-number, #fcd34d)",
    comment: "var(--letterpress-syntax-comment, #8b9bb2)",
    content: "var(--letterpress-syntax-content, #dbe4f0)",
  },
}

export const defaultLetterpressEditorTheme: LetterpressEditorTheme = {
  light: lightPalette,
  dark: darkPalette,
}

export function createLetterpressEditorTheme(
  overrides: LetterpressEditorThemeOverrides = {},
): LetterpressEditorTheme {
  return {
    light: mergePalette(lightPalette, overrides.light),
    dark: mergePalette(darkPalette, overrides.dark),
  }
}

function mergePalette(
  palette: LetterpressEditorPalette,
  override: LetterpressEditorPaletteOverride | undefined,
): LetterpressEditorPalette {
  return {
    editor: { ...palette.editor, ...override?.editor },
    syntax: { ...palette.syntax, ...override?.syntax },
  }
}
