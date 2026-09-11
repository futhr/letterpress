import { EditorState } from "@codemirror/state"
import { expect, it, vi } from "vitest"

vi.mock("@codemirror/lang-liquid", async (importOriginal) => {
  const original = await importOriginal<typeof import("@codemirror/lang-liquid")>()
  return { ...original, closePercentBrace: undefined }
})

it("creates a language extension when an older peer has no percent-brace enhancement", async () => {
  const { letterpressLanguage } = await import("./index")
  const state = EditorState.create({
    doc: "Hello {{ name }}",
    extensions: letterpressLanguage({
      profile: "text/liquid@1",
      schema: { version: 1, variables: { name: { type: "string" } } },
    }),
  })
  expect(state.doc.toString()).toBe("Hello {{ name }}")
})
