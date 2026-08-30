import { mount, tick, unmount } from "svelte"
import { afterEach, describe, expect, it, vi } from "vitest"
import type { LetterpressEditorTheme } from "../src/letterpress-editor.svelte"
import LetterpressEditor from "../src/letterpress-editor.svelte"

const mounted: ReturnType<typeof mount>[] = []
const schema = { version: 1 as const, variables: { name: { type: "string" as const } } }
const theme: LetterpressEditorTheme = {
  editor: {
    foreground: "#eeeeee",
    background: "#101010",
    selection: "#334455",
    activeLine: "#202020",
    cursor: "#ffffff",
    gutterForeground: "#888888",
    gutterBackground: "#101010",
    gutterBorder: "#303030",
  },
  syntax: {
    tagName: "#111111",
    angleBracket: "#222222",
    attributeName: "#333333",
    attributeValue: "#444444",
    string: "#555555",
    propertyName: "#666666",
    className: "#777777",
    brace: "#888888",
    variableName: "#999999",
    keyword: "#aaaaaa",
    controlKeyword: "#bbbbbb",
    url: "#cccccc",
    number: "#dddddd",
    comment: "#eeeeee",
    content: "#ffffff",
  },
}

afterEach(async () => {
  for (const component of mounted.splice(0)) await unmount(component)
  document.body.replaceChildren()
})

describe("LetterpressEditor", () => {
  it("mounts one accessible CodeMirror editor and destroys it cleanly", async () => {
    const onReady = vi.fn()
    const component = mount(LetterpressEditor, {
      target: document.body,
      props: { source: "Hello {{ name }}", profile: "text/liquid@1", schema, onReady },
    })
    mounted.push(component)
    await tick()
    expect(document.querySelectorAll(".cm-editor")).toHaveLength(1)
    expect(document.querySelector(".cm-content")?.getAttribute("aria-label")).toBe(
      "Template source",
    )
    expect(document.querySelector(".cm-lineNumbers")).not.toBeNull()
    expect(document.querySelector(".cm-foldGutter")).not.toBeNull()
    expect(onReady).toHaveBeenCalledOnce()
    await unmount(component)
    mounted.splice(0)
    expect(document.querySelector(".cm-editor")).toBeNull()
  })

  it("notifies controlled source changes without styling the host", async () => {
    const onChange = vi.fn()
    let editorView: import("@codemirror/view").EditorView | undefined
    const component = mount(LetterpressEditor, {
      target: document.body,
      props: {
        source: "Hello",
        profile: "text/liquid@1",
        schema,
        onChange,
        onReady: (view) => {
          editorView = view
        },
      },
    })
    mounted.push(component)
    await tick()
    editorView?.dispatch({ changes: { from: 5, insert: " world" } })
    expect(onChange).toHaveBeenCalledWith("Hello world")
    expect(document.querySelector("[data-letterpress-editor]")?.getAttribute("style")).toBeNull()
  })

  it("handles save and format keyboard commands", async () => {
    const onSave = vi.fn()
    const onFormat = vi.fn()
    let editorView: import("@codemirror/view").EditorView | undefined
    const component = mount(LetterpressEditor, {
      target: document.body,
      props: {
        source: "Hello  \n",
        profile: "text/liquid@1",
        schema,
        onSave,
        onFormat,
        onReady: (view) => {
          editorView = view
        },
      },
    })
    mounted.push(component)
    await tick()
    editorView?.contentDOM.dispatchEvent(
      new KeyboardEvent("keydown", { key: "s", ctrlKey: true, bubbles: true }),
    )
    expect(onSave).toHaveBeenCalledWith("Hello  \n")
    editorView?.contentDOM.dispatchEvent(
      new KeyboardEvent("keydown", { key: "f", altKey: true, shiftKey: true, bubbles: true }),
    )
    await vi.waitFor(() => expect(onFormat).toHaveBeenCalledWith("Hello"))
    expect(editorView?.state.doc.toString()).toBe("Hello")
  })

  it("supports autofocus and read-only presentation", async () => {
    const component = mount(LetterpressEditor, {
      target: document.body,
      props: {
        source: "Locked",
        profile: "text/liquid@1",
        schema,
        readOnly: true,
        autofocus: true,
      },
    })
    mounted.push(component)
    await tick()
    expect(document.querySelector(".cm-content")?.getAttribute("contenteditable")).toBe("false")
    expect(document.activeElement).toBe(document.querySelector(".cm-content"))
  })

  it("supports host-configurable editor chrome and placeholder text", async () => {
    const component = mount(LetterpressEditor, {
      target: document.body,
      props: {
        source: "",
        profile: "text/liquid@1",
        schema,
        lineNumbers: false,
        folding: false,
        lintGutter: false,
        placeholder: "Write a notification",
      },
    })
    mounted.push(component)
    await tick()
    expect(document.querySelector(".cm-lineNumbers")).toBeNull()
    expect(document.querySelector(".cm-foldGutter")).toBeNull()
    expect(document.querySelector(".cm-placeholder")?.textContent).toBe("Write a notification")
  })

  it("constructs themes internally from the plain cross-package contract", async () => {
    const component = mount(LetterpressEditor, {
      target: document.body,
      props: {
        source: "Hello {{ name }}",
        profile: "text/liquid@1",
        schema,
        theme,
      },
    })
    mounted.push(component)
    await tick()

    expect(document.querySelector(".cm-editor")?.className).toMatch(/cm-editor .+/)
  })
})
