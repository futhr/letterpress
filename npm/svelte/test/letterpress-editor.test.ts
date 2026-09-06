import { EditorView } from "@codemirror/view"
import { mount, tick, unmount } from "svelte"
import { afterEach, describe, expect, it, vi } from "vitest"
import LetterpressEditor from "../src/letterpress-editor.svelte"
import { createLetterpressEditorTheme } from "../src/theme"
import ThemeHarness from "./theme-harness.svelte"

const mounted: ReturnType<typeof mount>[] = []
const schema = { version: 1 as const, variables: { name: { type: "string" as const } } }
const theme = createLetterpressEditorTheme({
  light: {
    editor: {
      background: "#fafafa",
    },
  },
  dark: {
    editor: {
      background: "#121820",
    },
    syntax: {
      tagName: "#80d8ff",
    },
  },
})

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

  it("discards formatting when the document changes before it completes", async () => {
    const onFormat = vi.fn()
    let view: EditorView | undefined
    mounted.push(
      mount(LetterpressEditor, {
        target: document.body,
        props: {
          source: "Hello  ",
          profile: "text/liquid@1",
          schema,
          onFormat,
          onReady: (editor) => {
            view = editor
          },
        },
      }),
    )
    await tick()
    view?.contentDOM.dispatchEvent(
      new KeyboardEvent("keydown", { key: "f", altKey: true, shiftKey: true, bubbles: true }),
    )
    view?.dispatch({ changes: { from: 0, to: 7, insert: "New draft" } })
    await tick()
    expect(view?.state.doc.toString()).toBe("New draft")
    expect(onFormat).not.toHaveBeenCalled()
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

  it("lets preprocessing hosts disable only client diagnostics", async () => {
    const component = mount(LetterpressEditor, {
      target: document.body,
      props: {
        source: "{{# host_slot }}",
        profile: "text/liquid@1",
        schema,
        clientDiagnostics: false,
      },
    })
    mounted.push(component)
    await tick()
    await new Promise((resolve) => setTimeout(resolve, 300))
    expect(document.querySelector(".cm-lintRange-error")).toBeNull()
  })

  it("constructs the selected palette internally from the paired theme contract", async () => {
    const component = mount(LetterpressEditor, {
      target: document.body,
      props: {
        source: "Hello {{ name }}",
        profile: "text/liquid@1",
        schema,
        theme,
        colorScheme: "dark",
      },
    })
    mounted.push(component)
    await tick()

    expect(document.querySelector(".cm-editor")?.className).toMatch(/cm-editor .+/)
    expect(
      document.querySelector("[data-letterpress-editor]")?.getAttribute("data-color-scheme"),
    ).toBe("dark")
    expect(
      [...document.querySelectorAll("style")].some((style) =>
        style.textContent?.includes("#121820"),
      ),
    ).toBe(true)
  })

  it("reconfigures color scheme without replacing editor state", async () => {
    const component = mount(ThemeHarness, { target: document.body })
    mounted.push(component)
    await tick()

    const view = component.getView()
    expect(view?.state.facet(EditorView.darkTheme)).toBe(false)
    view?.dispatch({ changes: { from: 5, insert: " world" } })

    component.setColorScheme("dark")
    await tick()

    expect(component.getView()).toBe(view)
    expect(view?.state.doc.toString()).toBe("Hello world")
    expect(view?.state.facet(EditorView.darkTheme)).toBe(true)
    expect(
      document.querySelector("[data-letterpress-editor]")?.getAttribute("data-color-scheme"),
    ).toBe("dark")
  })
})
