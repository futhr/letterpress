import { describe, expect, it } from "vitest"
import { createLetterpressEditorTheme, defaultLetterpressEditorTheme } from "../src/theme"

describe("Letterpress editor themes", () => {
  it("ships distinct light and dark reference palettes", () => {
    expect(defaultLetterpressEditorTheme.light.editor.background).toContain("#ffffff")
    expect(defaultLetterpressEditorTheme.dark.editor.background).toContain("#111827")
    expect(defaultLetterpressEditorTheme.light.syntax.tagName).not.toBe(
      defaultLetterpressEditorTheme.dark.syntax.tagName,
    )
  })

  it("deep-merges consumer overrides without dropping reference values", () => {
    const theme = createLetterpressEditorTheme({
      light: {
        editor: { background: "var(--surface)" },
        syntax: { tagName: "var(--syntax-tag)" },
      },
      dark: {
        editor: { background: "var(--surface-dark)" },
      },
    })

    expect(theme.light.editor.background).toBe("var(--surface)")
    expect(theme.light.syntax.tagName).toBe("var(--syntax-tag)")
    expect(theme.light.editor.foreground).toBe(
      defaultLetterpressEditorTheme.light.editor.foreground,
    )
    expect(theme.dark.editor.background).toBe("var(--surface-dark)")
    expect(theme.dark.syntax.tagName).toBe(defaultLetterpressEditorTheme.dark.syntax.tagName)
  })

  it("returns independent palette objects", () => {
    const theme = createLetterpressEditorTheme()

    expect(theme.light).not.toBe(defaultLetterpressEditorTheme.light)
    expect(theme.dark).not.toBe(defaultLetterpressEditorTheme.dark)
    expect(theme.light.editor).not.toBe(theme.dark.editor)
    expect(theme.light.syntax).not.toBe(theme.dark.syntax)
  })
})
