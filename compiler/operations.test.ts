import { describe, expect, test } from "vitest"
import fixtures from "../conformance/fixtures.json"
import { dispatch, type Request } from "./operations"

const freeze = <T>(value: T): T => {
  if (value && typeof value === "object") {
    for (const child of Object.values(value)) freeze(child)
    Object.freeze(value)
  }
  return value
}

describe("compiler operation ownership", () => {
  test.each(fixtures.analysis)("analyzes frozen inputs: $name", async (fixture) => {
    const request = freeze({
      id: fixture.name,
      operation: "analyze",
      payload: { profile: fixture.profile, source: fixture.source, schema: fixture.schema },
    } satisfies Request)
    const result = await dispatch(request)
    const diagnostics = result.diagnostics as readonly { code: string; severity: string }[]

    expect(diagnostics.map(({ code }) => code)).toEqual(
      expect.arrayContaining(fixture.backend_codes),
    )
    if (fixture.backend_codes.length === 0) {
      expect(diagnostics.filter(({ severity }) => severity === "error")).toEqual([])
    }
  })

  test("compiles all email channels without changing inputs or earlier results", async () => {
    const request = freeze({
      id: "email",
      operation: "compile",
      payload: {
        profile: "email/mjml-liquid@1",
        source:
          "<mjml><mj-body><mj-section><mj-column><mj-text>Hello {{ name }}</mj-text></mj-column></mj-section></mj-body></mjml>",
        subject: "Hello {{ name }}",
        text: "Hello {{ name }}",
        schema: {
          version: 1,
          variables: { name: { type: "string", context: "text" } },
        },
      },
    } satisfies Request)
    const first = freeze(await dispatch(request))
    expect(first.diagnostics).toEqual([])
    expect(first.compiled).toMatchObject({
      html: expect.stringContaining('{{ name | letterpress_escape: "html_text" }}'),
      subject: 'Hello {{ name | letterpress_escape: "subject" }}',
      text: 'Hello {{ name | letterpress_escape: "text" }}',
    })

    const invalid = await dispatch({
      ...request,
      payload: { ...request.payload, source: "<mjml><mj-body><mj-include /></mj-body></mjml>" },
    })
    expect(invalid.diagnostics).toEqual(
      expect.arrayContaining([expect.objectContaining({ code: "LP_MJML_ELEMENT_FORBIDDEN" })]),
    )
    expect(await dispatch(request)).toEqual(first)
  })

  test("returns a translation result without changing its input map", async () => {
    const payload = freeze({
      profile: "text/liquid@1",
      source: "Hello {{ name }}",
      schema: { version: 1, variables: { name: { type: "string", context: "text" } } },
    })
    const analysis = await dispatch({ id: "units", operation: "analyze", payload })
    const [unit] = analysis.translation_units as readonly { id: string }[]
    expect(unit).toBeDefined()
    const translations = freeze({ [unit?.id ?? ""]: { text: "Hej {{ name }}" } })
    const request = freeze({
      id: "translate",
      operation: "apply_translations",
      payload: { ...payload, translations },
    } satisfies Request)

    expect(await dispatch(request)).toEqual({
      source: "Hej {{ name }}",
      subject: null,
      text: null,
      diagnostics: [],
    })
    expect(payload.source).toBe("Hello {{ name }}")
    expect(Object.values(translations)).toEqual([{ text: "Hej {{ name }}" }])
  })
})
