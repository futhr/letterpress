import { readFileSync } from "node:fs"
import { resolve } from "node:path"
import { cssLanguage } from "@codemirror/lang-css"
import { liquidLanguage } from "@codemirror/lang-liquid"
import { EditorState } from "@codemirror/state"
import { EditorView } from "@codemirror/view"
import { afterEach, describe, expect, it } from "vitest"
import {
  completionsAt,
  contract,
  formatLetterpressSource,
  letterpressLanguage,
  localDiagnostics,
  mapServerDiagnostics,
  type VariableSchema,
} from "./index.js"

const schema: VariableSchema = {
  version: 1,
  variables: {
    "user.name": { type: "string", context: "html_text", description: "Recipient name" },
    show: { type: "boolean", context: "none" },
    items: {
      type: "list",
      context: "none",
      items: { type: "object", properties: { name: { type: "string" } } },
    },
    url: { type: "url", context: "url" },
    color: { type: "string", phase: "compile", context: "color" },
    css: { type: "string", phase: "compile", context: "css" },
    attribute: { type: "string", context: "html_attribute" },
  },
}

const views: EditorView[] = []
const conformance = JSON.parse(
  readFileSync(resolve(process.cwd(), "../../conformance/fixtures.json"), "utf8"),
) as {
  version: number
  analysis: Array<{
    name: string
    profile: "email/mjml-liquid@1" | "text/liquid@1"
    source: string
    schema: VariableSchema
    browser_codes: string[]
  }>
}
afterEach(() => {
  for (const view of views.splice(0)) view.destroy()
})

describe("Letterpress language contract", () => {
  it("consumes the shared analysis conformance corpus", () => {
    expect(conformance.version).toBe(1)
    for (const fixture of conformance.analysis) {
      const view = createView(fixture.source, fixture.profile, fixture.schema)
      const codes = localDiagnostics(view, {
        profile: fixture.profile,
        schema: fixture.schema,
      }).map((diagnostic) => diagnostic.source?.split(" · ").at(-1))
      expect(codes, fixture.name).toEqual(expect.arrayContaining(fixture.browser_codes))
      if (fixture.browser_codes.length === 0) expect(codes, fixture.name).toEqual([])
    }
  })

  it("contains generated official MJML metadata and immutable profiles", () => {
    expect(Object.keys(contract.profiles)).toEqual(["email/mjml-liquid@1", "text/liquid@1"])
    expect(
      contract.profiles["email/mjml-liquid@1"].element_metadata["mj-button"].attributes.href,
    ).toBe("string")
    expect(contract.profiles["email/mjml-liquid@1"].nesting["mj-section"]).toContain("mj-column")
  })

  it("parses MJML, Liquid, and nested CSS through CodeMirror", () => {
    const view = createView(
      "<mjml><mj-head><mj-style>.brand { color: red; }</mj-style></mj-head><mj-body><mj-section><mj-column><mj-text>{{ user.name }}</mj-text></mj-column></mj-section></mj-body></mjml>",
    )
    expect(
      liquidLanguage.isActiveAt(view.state, view.state.doc.toString().indexOf("user.name")),
    ).toBe(true)
    expect(cssLanguage.isActiveAt(view.state, view.state.doc.toString().indexOf("color"))).toBe(
      true,
    )
  })

  it("reports forbidden language features and undeclared variables locally", () => {
    const source =
      "<mjml><mj-body><mj-section><mj-column><mj-text>{{ missing | escape }}</mj-text></mj-column></mj-section><script>{% raw %}x{% endraw %}</script></mj-body></mjml>"
    const view = createView(source)
    const codes = localDiagnostics(view, { profile: "email/mjml-liquid@1", schema }).map(
      (item) => item.source,
    )
    expect(codes).toContain("letterpress · LP_LIQUID_TAG_FORBIDDEN")
    expect(codes).toContain("letterpress · LP_LIQUID_FILTER_FORBIDDEN")
    expect(codes).toContain("letterpress · LP_SCHEMA_UNDECLARED_VARIABLE")
    expect(codes).toContain("letterpress · LP_HTML_ELEMENT_FORBIDDEN")
  })

  it("reports legacy Mustache and Handlebars constructs locally", () => {
    for (const source of [
      "{{#enabled}}yes{{/enabled}}",
      "{{#if enabled}}yes{{/if}}",
      "{{{html}}}",
    ]) {
      const view = createView(source, "text/liquid@1")
      expect(localDiagnostics(view, { profile: "text/liquid@1", schema })).toEqual([
        expect.objectContaining({ source: "letterpress · LP_LEGACY_SYNTAX" }),
      ])
    }
  })

  it("maps UTF-16 server ranges to document offsets", () => {
    const view = createView("😀 hello\nworld")
    const [diagnostic] = mapServerDiagnostics(view, [
      {
        version: 1,
        source_hash: "hash",
        document_version: 2,
        range: { start: { line: 1, character: 1 }, end: { line: 1, character: 5 } },
        severity: "information",
        code: "LP_TEST",
        source: "server",
        message: "Mapped",
      },
    ])
    expect(diagnostic).toMatchObject({ from: 10, to: 14, severity: "info" })
  })

  it("drops stale asynchronous server diagnostics", () => {
    const view = createView("hello")
    const diagnostics = [
      serverDiagnostic({ source_hash: "current", document_version: 7, message: "current" }),
      serverDiagnostic({ source_hash: "stale", document_version: 7, message: "old source" }),
      serverDiagnostic({ source_hash: "current", document_version: 6, message: "old version" }),
    ]

    expect(
      mapServerDiagnostics(view, diagnostics, {
        sourceHash: "current",
        documentVersion: 7,
      }).map((diagnostic) => diagnostic.message),
    ).toEqual(["current"])
  })

  it("formats email source idempotently", async () => {
    const source =
      "<mjml><mj-body><mj-section><mj-column><mj-text>Hello</mj-text></mj-column></mj-section></mj-body></mjml>"
    const once = await formatLetterpressSource("email/mjml-liquid@1", source)
    expect(await formatLetterpressSource("email/mjml-liquid@1", once)).toBe(once)
    expect(await formatLetterpressSource("text/liquid@1", "Hello  \n")).toBe("Hello")
  })

  it("offers only contract tags, filters, variables, MJML children, and attributes", () => {
    expect(labels("{{ user.na", "email/mjml-liquid@1")).toContain("user.name")
    expect(labels("{{ user.na", "email/mjml-liquid@1")).not.toContain("url")
    expect(labels("{{ name | up", "email/mjml-liquid@1")).toContain("upcase")
    expect(labels("{% i", "email/mjml-liquid@1")).toContain("if")
    expect(labels("{% if sh", "email/mjml-liquid@1")).toContain("show")
    expect(labels('<mj-button href="{{ ur', "email/mjml-liquid@1")).toContain("url")
    expect(labels('<mj-text color="{{ col', "email/mjml-liquid@1")).toContain("color")
    expect(labels('<mj-text style="{{ cs', "email/mjml-liquid@1")).toContain("css")
    expect(labels('<mj-text title="{{ at', "email/mjml-liquid@1")).toContain("attribute")
    expect(labels("<mj-style>{{ cs", "email/mjml-liquid@1")).toContain("css")
    expect(labels("<mjml><mj-body><mj-", "email/mjml-liquid@1")).toEqual(
      expect.arrayContaining(["mj-section", "mj-wrapper"]),
    )
    expect(labels("<mj-button hr", "email/mjml-liquid@1")).toContain("href")
    expect(labels("", "text/liquid@1")).toEqual(
      expect.arrayContaining(["conditional text", "variable"]),
    )
  })

  it("reports missing roots while accepting a valid declared document", () => {
    const invalid = createView("<mj-text>{{ user.name }}</mj-text>")
    expect(
      localDiagnostics(invalid, { profile: "email/mjml-liquid@1", schema }).map(
        (item) => item.source,
      ),
    ).toEqual(expect.arrayContaining(["letterpress · LP_MJML_ROOT", "letterpress · LP_MJML_BODY"]))
    const valid = createView(
      "<mjml><mj-body><mj-section><mj-column><mj-text>{{ user.name }}</mj-text></mj-column></mj-section></mj-body></mjml>",
    )
    expect(localDiagnostics(valid, { profile: "email/mjml-liquid@1", schema })).toEqual([])
  })

  it("accepts safe embedded HTML and understands Liquid loop locals", () => {
    const source = `<mjml><mj-body><mj-section><mj-column><mj-text>
      <a href="{{ url }}" data-id="message-link">
        {% for item in items offset: continue %}{{ item.name | upcase }}{% endfor %}
      </a>
    </mj-text></mj-column></mj-section></mj-body></mjml>`
    const view = createView(source)

    expect(localDiagnostics(view, { profile: "email/mjml-liquid@1", schema })).toEqual([])
  })

  it("reports schema phase and output-context mismatches", () => {
    const source = `<mjml><mj-head><mj-style>.brand { color: {{ show }}; }</mj-style></mj-head><mj-body>
      <mj-section><mj-column><mj-text><a href="{{ user.name }}">Hello</a></mj-text></mj-column></mj-section>
    </mj-body></mjml>`
    const view = createView(source)
    const codes = localDiagnostics(view, {
      profile: "email/mjml-liquid@1",
      schema,
    }).map((diagnostic) => diagnostic.source)

    expect(codes).toEqual(
      expect.arrayContaining([
        "letterpress · LP_SCHEMA_PHASE_MISMATCH",
        "letterpress · LP_SCHEMA_CONTEXT_MISMATCH",
      ]),
    )
  })

  it("rejects unsafe HTML, event handlers, invalid MJML attributes, and nesting", () => {
    const source = `<mjml><mj-body>
      <mj-section href="https://example.com"><mj-text><a onclick="alert(1)">bad</a><script>bad</script></mj-text></mj-section>
    </mj-body></mjml>`
    const view = createView(source)
    const codes = localDiagnostics(view, {
      profile: "email/mjml-liquid@1",
      schema,
    }).map((diagnostic) => diagnostic.source)

    expect(codes).toEqual(
      expect.arrayContaining([
        "letterpress · LP_MJML_ATTRIBUTE_FORBIDDEN",
        "letterpress · LP_MJML_INVALID_CHILD",
        "letterpress · LP_HTML_ATTRIBUTE_FORBIDDEN",
        "letterpress · LP_HTML_ELEMENT_FORBIDDEN",
      ]),
    )
  })
})

function serverDiagnostic(
  overrides: Partial<import("./index.js").ServerDiagnostic>,
): import("./index.js").ServerDiagnostic {
  return {
    version: 1,
    source_hash: "hash",
    document_version: 1,
    range: { start: { line: 0, character: 0 }, end: { line: 0, character: 1 } },
    severity: "error",
    code: "LP_TEST",
    source: "server",
    message: "diagnostic",
    ...overrides,
  }
}

function labels(source: string, profile: "email/mjml-liquid@1" | "text/liquid@1"): string[] {
  return completionsAt(source, source.length, { profile, schema }).map((item) => item.label)
}

function createView(
  doc: string,
  profile: "email/mjml-liquid@1" | "text/liquid@1" = "email/mjml-liquid@1",
  variableSchema: VariableSchema = schema,
): EditorView {
  const state = EditorState.create({
    doc,
    extensions: [letterpressLanguage({ profile, schema: variableSchema, lintDelay: 0 })],
  })
  const view = new EditorView({ state, parent: document.body })
  views.push(view)
  return view
}
