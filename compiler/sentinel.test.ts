import { describe, expect, test } from "vitest"
import { inspectSentinelOutput } from "./sentinel"

describe("inspectSentinelOutput", () => {
  test("accepts one sentinel in its declared output context", () => {
    expect(
      inspectSentinelOutput(
        '<a href="LPX_url_XPL" title="LPX_title_XPL">LPX_text_XPL</a>',
        new Map([
          ["LPX_url_XPL", ["url"]],
          ["LPX_title_XPL", ["html_attribute"]],
          ["LPX_text_XPL", ["html_text"]],
        ]),
      ).issues,
    ).toEqual([])
  })

  test("rejects sentinel loss, duplication, and relocation", () => {
    expect(
      inspectSentinelOutput(
        '<a href="LPX_text_XPL">LPX_duplicate_XPL LPX_duplicate_XPL</a>',
        new Map([
          ["LPX_missing_XPL", ["html_text"]],
          ["LPX_duplicate_XPL", ["html_text"]],
          ["LPX_text_XPL", ["html_text"]],
        ]),
      ).issues,
    ).toEqual([
      { token: "LPX_missing_XPL", count: 0, contexts: [] },
      {
        token: "LPX_duplicate_XPL",
        count: 2,
        contexts: ["html_text", "html_text"],
      },
      { token: "LPX_text_XPL", count: 1, contexts: ["url"] },
    ])
  })

  test("treats style, comments, and raw document positions as unsafe", () => {
    expect(
      inspectSentinelOutput(
        "<style>.x { content: 'LPX_css_XPL' }</style><!-- LPX_comment_XPL -->LPX_text_XPL",
        new Map([
          ["LPX_css_XPL", ["html_text"]],
          ["LPX_comment_XPL", ["html_text"]],
          ["LPX_text_XPL", ["html_text"]],
        ]),
      ).issues,
    ).toEqual([
      { token: "LPX_css_XPL", count: 1, contexts: ["css"] },
      { token: "LPX_comment_XPL", count: 1, contexts: ["none"] },
    ])
  })

  test("allows only an explicitly modeled compiler duplication", () => {
    const inspection = inspectSentinelOutput(
      '<title>LPX_title_XPL</title><meta content="LPX_title_XPL">',
      new Map([["LPX_title_XPL", ["html_text", "html_attribute"]]]),
    )

    expect(inspection.issues).toEqual([])
    expect(inspection.occurrences.get("LPX_title_XPL")).toEqual([
      { start: 7, end: 20, context: "html_text" },
      { start: 43, end: 56, context: "html_attribute" },
    ])
  })
})
