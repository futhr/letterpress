import { toLiquidHtmlAST } from "@shopify/liquid-html-parser"
import contract from "../generated/letterpress-v1.json"

type JsonObject = Record<string, unknown>
type Position = { start: number; end: number }
type AstNode = JsonObject & { type?: string; name?: unknown; position?: Position }

export interface SentinelIssue {
  readonly token: string
  readonly count: number
  readonly contexts: readonly string[]
}

export interface SentinelOccurrence {
  readonly start: number
  readonly end: number
  readonly context: string
}

export interface SentinelInspection {
  readonly issues: readonly SentinelIssue[]
  readonly occurrences: ReadonlyMap<string, readonly SentinelOccurrence[]>
}

const attributeTypes = new Set([
  "AttrDoubleQuoted",
  "AttrSingleQuoted",
  "AttrUnquoted",
  "AttrEmpty",
])

const urlAttributes = new Set([
  ...contract.profiles["email/mjml-liquid@1"].url_attributes,
  ...contract.embedded_html.url_attributes,
])

export const inspectSentinelOutput = (
  output: string,
  sentinels: ReadonlyMap<string, readonly string[]>,
): SentinelInspection => {
  const occurrences = new Map<string, SentinelOccurrence[]>(
    [...sentinels.keys()].map((token) => [token, []]),
  )

  try {
    const ast = toLiquidHtmlAST(output, {
      mode: "strict",
      allowUnclosedDocumentNode: false,
    }) as unknown as AstNode

    walk(ast, [], (node, ancestors) => {
      if (node.type !== "TextNode" && node.type !== "HtmlComment") return
      const position = node.position
      if (!position) return
      const fragment = output.slice(position.start, position.end)

      for (const token of sentinels.keys()) {
        const count = occurrenceCount(fragment, token)
        if (count === 0) continue
        const context = outputContext(node, ancestors)
        let searchStart = position.start
        for (let index = 0; index < count; index += 1) {
          const start = output.indexOf(token, searchStart)
          occurrences.get(token)?.push({ start, end: start + token.length, context })
          searchStart = start + token.length
        }
      }
    })
  } catch {
    for (const token of sentinels.keys()) {
      occurrences.set(
        token,
        occurrencePositions(output, token).map((start) => ({
          start,
          end: start + token.length,
          context: "none",
        })),
      )
    }
  }

  const issues: SentinelIssue[] = []
  for (const [token, expectedContexts] of sentinels) {
    const contexts = (occurrences.get(token) ?? []).map((occurrence) => occurrence.context)
    const count = occurrenceCount(output, token)
    if (count !== expectedContexts.length || !sameContexts(contexts, expectedContexts)) {
      issues.push({ token, count, contexts })
    }
  }
  return { issues, occurrences }
}

const outputContext = (node: AstNode, ancestors: AstNode[]): string => {
  if (node.type === "HtmlComment") return "none"

  const attribute = [...ancestors]
    .reverse()
    .find((ancestor) => attributeTypes.has(String(ancestor.type)))
  if (attribute) return urlAttributes.has(elementName(attribute)) ? "url" : "html_attribute"

  const rawElement = [...ancestors]
    .reverse()
    .find((ancestor) => ["HtmlRawNode", "HtmlElement"].includes(String(ancestor.type)))
  if (elementName(rawElement) === "style") return "css"
  if (elementName(rawElement) === "script") return "none"

  return "html_text"
}

const occurrenceCount = (source: string, token: string): number => source.split(token).length - 1

const occurrencePositions = (source: string, token: string): number[] => {
  const positions: number[] = []
  let searchStart = 0
  while (searchStart <= source.length) {
    const start = source.indexOf(token, searchStart)
    if (start === -1) return positions
    positions.push(start)
    searchStart = start + token.length
  }
  return positions
}

const sameContexts = (actual: readonly string[], expected: readonly string[]): boolean =>
  [...actual].sort().join("\0") === [...expected].sort().join("\0")

const elementName = (node: AstNode | undefined): string => {
  if (!node) return ""
  if (typeof node.name === "string") return node.name
  if (!Array.isArray(node.name)) return ""
  return String((node.name[0] as JsonObject | undefined)?.value ?? "")
}

const walk = (
  node: AstNode,
  ancestors: AstNode[],
  visit: (node: AstNode, ancestors: AstNode[]) => void,
): void => {
  if (!node || typeof node !== "object") return
  visit(node, ancestors)

  for (const [key, value] of Object.entries(node)) {
    if (
      [
        "source",
        "_source",
        "position",
        "blockStartPosition",
        "blockEndPosition",
        "markupPosition",
        "attributePosition",
      ].includes(key)
    ) {
      continue
    }

    if (Array.isArray(value)) {
      for (const child of value) {
        if (child && typeof child === "object") walk(child as AstNode, [...ancestors, node], visit)
      }
    } else if (value && typeof value === "object") {
      walk(value as AstNode, [...ancestors, node], visit)
    }
  }
}
