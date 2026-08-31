import {
  autocompletion,
  type Completion,
  type CompletionContext,
  type CompletionResult,
  snippetCompletion,
} from "@codemirror/autocomplete"
import { cssLanguage } from "@codemirror/lang-css"
import { html, type TagSpec } from "@codemirror/lang-html"
import { closePercentBrace, liquid, liquidLanguage } from "@codemirror/lang-liquid"
import { LanguageSupport } from "@codemirror/language"
import { type Diagnostic as CodeMirrorDiagnostic, linter } from "@codemirror/lint"
import type { Extension } from "@codemirror/state"
import type { EditorView } from "@codemirror/view"
import { toLiquidHtmlAST } from "@shopify/liquid-html-parser"
import { contract } from "./generated/contract.js"

export { contract }

export type Profile = keyof typeof contract.profiles
export type VariableContext = (typeof contract.contexts)[number]
export type VariablePhase = (typeof contract.phases)[number]
export type VariableType = (typeof contract.types)[number]

export interface VariableDefinition {
  type: VariableType
  phase?: VariablePhase
  context?: VariableContext
  required?: boolean
  default?: unknown
  description?: string
  sensitive?: boolean
  items?: NestedVariableDefinition
  properties?: Record<string, NestedVariableDefinition>
}

export type NestedVariableDefinition = Omit<VariableDefinition, "phase" | "context">

export interface VariableSchema {
  version: 1
  variables: Record<string, VariableDefinition>
}

export interface ServerDiagnostic {
  version: 1
  source_hash: string
  document_version: number
  range: {
    start: { line: number; character: number }
    end: { line: number; character: number }
  }
  severity: "error" | "warning" | "information" | "hint"
  code: string
  source: string
  message: string
}

export interface LanguageConfig {
  profile: Profile
  schema: VariableSchema
  serverDiagnostics?: readonly ServerDiagnostic[]
  documentVersion?: number
  sourceHash?: string
  lintDelay?: number
}

const emailProfile = contract.profiles["email/mjml-liquid@1"]
const allowedLiquidTags = new Set<string>(contract.liquid.tags)
const allowedLiquidFilters = new Set<string>(contract.liquid.filters)
export function letterpressLanguage(config: LanguageConfig): Extension {
  const language =
    config.profile === "email/mjml-liquid@1"
      ? liquid({ base: emailBaseLanguage() })
      : config.profile === "html/liquid@1"
        ? liquid({ base: html({ autoCloseTags: true, matchClosingTags: true }) })
        : new LanguageSupport(liquidLanguage, [closePercentBrace])

  return [
    language,
    autocompletion({ override: [completionSource(config)] }),
    linter(
      (view) => [
        ...localDiagnostics(view, config),
        ...mapServerDiagnostics(view, config.serverDiagnostics ?? [], config),
      ],
      { delay: config.lintDelay ?? 250 },
    ),
  ]
}

export async function formatLetterpressSource(profile: Profile, source: string): Promise<string> {
  if (profile === "text/liquid@1") return source.trimEnd()
  const { formatLiquidSource } = await import("./formatter.js")
  return formatLiquidSource(source)
}

export function localDiagnostics(view: EditorView, config: LanguageConfig): CodeMirrorDiagnostic[] {
  const source = view.state.doc.toString()
  return validateDocument(source, config)
}

export function mapServerDiagnostics(
  view: EditorView,
  diagnostics: readonly ServerDiagnostic[],
  freshness: Pick<LanguageConfig, "documentVersion" | "sourceHash"> = {},
): CodeMirrorDiagnostic[] {
  return diagnostics
    .filter(
      (diagnostic) =>
        (freshness.documentVersion === undefined ||
          diagnostic.document_version === freshness.documentVersion) &&
        (freshness.sourceHash === undefined || diagnostic.source_hash === freshness.sourceHash),
    )
    .map((diagnostic) => ({
      from: offsetAt(view, diagnostic.range.start.line, diagnostic.range.start.character),
      to: offsetAt(view, diagnostic.range.end.line, diagnostic.range.end.character),
      severity: diagnostic.severity === "information" ? "info" : diagnostic.severity,
      source: `${diagnostic.source} · ${diagnostic.code}`,
      message: diagnostic.message,
    }))
}

function emailBaseLanguage(): LanguageSupport {
  return html({
    autoCloseTags: true,
    matchClosingTags: true,
    selfClosingTags: true,
    extraTags: mjmlTagSpecs(),
    extraGlobalAttributes: { "css-class": null, "mj-class": null },
    nestedLanguages: [{ tag: "mj-style", parser: cssLanguage.parser }],
  })
}

function mjmlTagSpecs(): Record<string, TagSpec> {
  const metadata = emailProfile.element_metadata as Record<
    string,
    { attributes: Record<string, string> }
  >
  const nesting = emailProfile.nesting as Record<string, readonly string[]>
  return Object.fromEntries(
    Object.entries(metadata).map(([name, element]) => [
      name,
      {
        attrs: Object.fromEntries(
          Object.entries(element.attributes).map(([attribute, rule]) => [
            attribute,
            attributeValues(String(rule)),
          ]),
        ),
        children: nesting[name] ?? [],
      },
    ]),
  )
}

function attributeValues(rule: string): readonly string[] | null {
  const match = /^enum\((.*)\)$/.exec(rule)
  return match?.[1]?.split(",").filter(Boolean) ?? null
}

function completionSource(config: LanguageConfig) {
  return (context: CompletionContext): CompletionResult | null => {
    const word = context.matchBefore(/[A-Za-z_][A-Za-z0-9_.-]*\??/)
    if (!context.explicit && !word) return null
    const from = word?.from ?? context.pos
    return { from, options: completionsAt(context.state.doc.toString(), context.pos, config) }
  }
}

export function completionsAt(
  source: string,
  position: number,
  config: Pick<LanguageConfig, "profile" | "schema">,
): Completion[] {
  const before = source.slice(Math.max(0, position - 300), position)
  if (/\|\s*[A-Za-z_]*$/.test(before)) {
    return [...allowedLiquidFilters].sort().map(completion("function"))
  }
  if (/{%[-\s]*[A-Za-z_]*$/.test(before)) {
    return [...allowedLiquidTags].sort().map(completion("keyword"))
  }
  if (/{{[^}]*$/.test(before) || /{%[^%]*$/.test(before)) {
    return variableCompletions(config.schema, variableRequirement(source, position, config.profile))
  }
  if (config.profile === "email/mjml-liquid@1" && /<mj-[^>]*\s+[A-Za-z-]*$/.test(before)) {
    return mjmlAttributeCompletions(before)
  }
  if (config.profile === "email/mjml-liquid@1" && /<\/?[A-Za-z-]*$/.test(before)) {
    return mjmlElementCompletions(before)
  }
  if (config.profile === "html/liquid@1" && /<[^>]*\s+[A-Za-z-]*$/.test(before)) {
    return htmlAttributeCompletions(before)
  }
  if (config.profile === "html/liquid@1" && /<\/?[A-Za-z-]*$/.test(before)) {
    return htmlElementCompletions()
  }
  return contract.snippets[config.profile === "email/mjml-liquid@1" ? "email" : "text"].map(
    (snippet) => snippetCompletion(snippet.template, { label: snippet.label, type: "text" }),
  )
}

function completion(type: string) {
  return (label: string): Completion => ({ label, type })
}

function variableCompletions(
  schema: VariableSchema,
  requirement: { phase?: VariablePhase; context?: VariableContext },
): Completion[] {
  return Object.entries(schema.variables)
    .filter(([, definition]) => {
      const phase = definition.phase ?? "delivery"
      const context = definition.context ?? "text"
      return (
        (requirement.phase === undefined || phase === requirement.phase) &&
        (requirement.context === undefined || compatibleContext(context, requirement.context))
      )
    })
    .sort(([left], [right]) => left.localeCompare(right))
    .map(([label, definition]) => {
      const item: Completion = {
        label,
        type: "variable",
        detail: `${definition.type} · ${definition.phase ?? "delivery"} · ${definition.context ?? "text"}`,
      }
      if (definition.description) item.info = definition.description
      return item
    })
}

function variableRequirement(
  source: string,
  position: number,
  profile: Profile,
): { phase?: VariablePhase; context?: VariableContext } {
  const before = source.slice(0, position)
  if (/{%[^%]*$/.test(before)) return { context: "none" }
  if (profile === "text/liquid@1") return { context: "text" }

  const openStyle = before.lastIndexOf("<mj-style")
  if (openStyle > before.lastIndexOf("</mj-style>")) {
    return { phase: "compile", context: "css" }
  }

  const openTag = before.slice(before.lastIndexOf("<"))
  const attribute = /([A-Za-z_:][A-Za-z0-9_.:-]*)\s*=\s*["'][^"']*$/.exec(openTag)?.[1]
  if (attribute) {
    if (
      emailProfile.url_attributes.includes(
        attribute as (typeof emailProfile.url_attributes)[number],
      ) ||
      contract.embedded_html.url_attributes.includes(
        attribute as (typeof contract.embedded_html.url_attributes)[number],
      )
    ) {
      return { context: "url" }
    }
    if (
      emailProfile.color_attributes.includes(
        attribute as (typeof emailProfile.color_attributes)[number],
      ) ||
      attribute.endsWith("-color")
    ) {
      return { phase: "compile", context: "color" }
    }
    if (attribute === "style") return { phase: "compile", context: "css" }
    return { context: "html_attribute" }
  }

  return { context: "html_text" }
}

function mjmlElementCompletions(before: string): Completion[] {
  const parent = openElementStack(before).at(-1)
  const nesting = emailProfile.nesting as Record<string, readonly string[]>
  const children = parent ? nesting[parent] : ["mjml"]
  const allowed: readonly string[] = children?.includes("*")
    ? emailProfile.elements
    : (children ?? emailProfile.elements)
  return [...allowed].sort().map((label) => ({ label, type: "type" }))
}

function mjmlAttributeCompletions(before: string): Completion[] {
  const name = /<(mj-[A-Za-z-]+)[^>]*$/.exec(before)?.[1]
  if (!name) return []
  const metadata = (
    emailProfile.element_metadata as Record<string, { attributes: Record<string, string> }>
  )[name]
  if (!metadata) return []
  return Object.entries(metadata.attributes)
    .sort(([left], [right]) => left.localeCompare(right))
    .map(([label, rule]) => ({ label, type: "property", detail: String(rule) }))
}

function htmlElementCompletions(): Completion[] {
  return [...contract.embedded_html.elements].sort().map((label) => ({ label, type: "type" }))
}

function htmlAttributeCompletions(before: string): Completion[] {
  const name = /<([A-Za-z][A-Za-z0-9-]*)[^>]*$/.exec(before)?.[1]
  if (!name) return []
  const perElement = contract.embedded_html.attributes as Record<string, readonly string[]>
  return [...new Set([...contract.embedded_html.global_attributes, ...(perElement[name] ?? [])])]
    .sort()
    .map((label) => ({ label, type: "property" }))
}

type AstNode = Record<string, unknown> & {
  type?: string
  name?: unknown
  position?: { start: number; end: number }
}

const htmlElementTypes = new Set([
  "HtmlElement",
  "HtmlSelfClosingElement",
  "HtmlVoidElement",
  "HtmlRawNode",
  "HtmlDanglingMarkerOpen",
  "HtmlDanglingMarkerClose",
])

function validateDocument(source: string, config: LanguageConfig): CodeMirrorDiagnostic[] {
  const diagnostics: CodeMirrorDiagnostic[] = []
  const legacySyntax = /\{\{\{|\{\{\s*[#/^!]/.exec(source)
  if (legacySyntax?.index !== undefined) {
    return [
      {
        from: legacySyntax.index,
        to: legacySyntax.index + legacySyntax[0].length,
        severity: "error",
        source: "letterpress · LP_LEGACY_SYNTAX",
        message: "Legacy Mustache or Handlebars syntax is not supported; use Liquid tags",
      },
    ]
  }
  let ast: AstNode
  try {
    ast = toLiquidHtmlAST(source, {
      mode: "completion",
      allowUnclosedDocumentNode: true,
    }) as unknown as AstNode
  } catch {
    if (sourceLooksIncomplete(source)) return diagnostics
    return [documentProblem("Template syntax is invalid", "LP_PARSE")]
  }

  if (config.profile === "email/mjml-liquid@1") validateMjmlRoot(ast, diagnostics)

  walk(ast, [], (node, ancestors) => {
    validateLiquidNode(node, ancestors, config.profile, config.schema, diagnostics)
    if (config.profile !== "text/liquid@1" && htmlElementTypes.has(node.type ?? "")) {
      validateElementNode(node, ancestors, config.profile, diagnostics)
    }
  })
  return diagnostics
}

function sourceLooksIncomplete(source: string): boolean {
  const trimmed = source.trimEnd()
  return /(?:{{|{%|<\/?[A-Za-z0-9:-]*)$/.test(trimmed)
}

function validateLiquidNode(
  node: AstNode,
  ancestors: AstNode[],
  profile: Profile,
  schema: VariableSchema,
  diagnostics: CodeMirrorDiagnostic[],
): void {
  if (node.type === "LiquidTag" || node.type === "LiquidRawTag") {
    const tag = String(node.name ?? "")
    if (tag && !allowedLiquidTags.has(tag)) {
      diagnostics.push(
        astProblem(node, `Liquid tag ${tag} is not allowed`, "LP_LIQUID_TAG_FORBIDDEN"),
      )
    }
  }

  if (node.type === "LiquidFilter") {
    const filter = String(node.name ?? "")
    if (filter && !allowedLiquidFilters.has(filter)) {
      diagnostics.push(
        astProblem(node, `Liquid filter ${filter} is not allowed`, "LP_LIQUID_FILTER_FORBIDDEN"),
      )
    }
  }

  if (node.type === "VariableLookup") {
    const name = variableLookupName(node)
    if (name && !localVariable(name, ancestors) && !declaredVariable(schema, name)) {
      diagnostics.push(
        astProblem(node, `Variable ${name} is not declared`, "LP_SCHEMA_UNDECLARED_VARIABLE"),
      )
    } else if (name && ancestors.at(-1)?.type === "LiquidVariable") {
      validateVariableContext(node, name, ancestors, profile, schema, diagnostics)
    }
  }
}

function validateVariableContext(
  node: AstNode,
  name: string,
  ancestors: AstNode[],
  profile: Profile,
  schema: VariableSchema,
  diagnostics: CodeMirrorDiagnostic[],
): void {
  const output = ancestors.some((ancestor) => ancestor.type === "LiquidVariableOutput")
  if (!output) return
  const definition = schema.variables[name] ?? schema.variables[name.split(".")[0] ?? name]
  if (!definition) return

  const context = profile === "text/liquid@1" ? "text" : outputContext(ancestors)
  const phase = definition.phase ?? "delivery"
  const declaredContext = definition.context ?? "text"
  if ((context === "css" || context === "color") && phase !== "compile") {
    diagnostics.push(
      astProblem(
        node,
        `${name} must be compile-phase in ${context} context`,
        "LP_SCHEMA_PHASE_MISMATCH",
      ),
    )
  }
  if (declaredContext !== "none" && !compatibleContext(declaredContext, context)) {
    diagnostics.push(
      astProblem(
        node,
        `${name} is declared for ${declaredContext}, not ${context}`,
        "LP_SCHEMA_CONTEXT_MISMATCH",
      ),
    )
  }
}

function outputContext(ancestors: AstNode[]): VariableContext {
  const attribute = [...ancestors].reverse().find((ancestor) => ancestor.type?.startsWith("Attr"))
  if (attribute) {
    const name = elementName(attribute)
    if (
      emailProfile.url_attributes.includes(name as (typeof emailProfile.url_attributes)[number]) ||
      contract.embedded_html.url_attributes.includes(
        name as (typeof contract.embedded_html.url_attributes)[number],
      )
    ) {
      return "url"
    }
    if (
      emailProfile.color_attributes.includes(
        name as (typeof emailProfile.color_attributes)[number],
      ) ||
      name.endsWith("-color")
    ) {
      return "color"
    }
    if (name === "style") return "css"
    return "html_attribute"
  }

  const element = [...ancestors]
    .reverse()
    .find((ancestor) => htmlElementTypes.has(ancestor.type ?? ""))
  return elementName(element) === "mj-style" ? "css" : "html_text"
}

function compatibleContext(declared: VariableContext, actual: VariableContext): boolean {
  if (declared === actual) return true
  if (declared === "text")
    return ["text", "html_text", "html_attribute", "subject"].includes(actual)
  if (declared === "url") return ["url", "text", "html_text", "subject"].includes(actual)
  return declared === "color" && ["color", "css"].includes(actual)
}

function validateMjmlRoot(ast: AstNode, diagnostics: CodeMirrorDiagnostic[]): void {
  const roots = childrenOf(ast).filter((node) => node.type === "HtmlElement")
  if (roots.length !== 1 || elementName(roots[0]) !== "mjml") {
    diagnostics.push(documentProblem("Email source needs exactly one mjml root", "LP_MJML_ROOT"))
  }
  const bodies = roots[0]
    ? childrenOf(roots[0]).filter((node) => elementName(node) === "mj-body")
    : []
  if (bodies.length !== 1) {
    diagnostics.push(documentProblem("Email source needs exactly one mj-body", "LP_MJML_BODY"))
  }
}

function validateElementNode(
  node: AstNode,
  ancestors: AstNode[],
  profile: Profile,
  diagnostics: CodeMirrorDiagnostic[],
): void {
  const name = elementName(node)
  if (!name) {
    diagnostics.push(
      astProblem(node, "Dynamic HTML elements are not allowed", "LP_HTML_ELEMENT_FORBIDDEN"),
    )
    return
  }
  if (profile === "html/liquid@1") {
    validateEmbeddedHtmlNode(node, diagnostics)
    return
  }
  if (name !== "mjml" && !name.startsWith("mj-")) {
    validateEmbeddedHtmlNode(node, diagnostics)
    return
  }

  if (emailProfile.forbidden_elements.includes(name as "mj-include")) {
    diagnostics.push(
      astProblem(node, `MJML element ${name} is forbidden`, "LP_MJML_ELEMENT_FORBIDDEN"),
    )
    return
  }
  if (!emailProfile.elements.includes(name as (typeof emailProfile.elements)[number])) {
    diagnostics.push(astProblem(node, `Unknown MJML element ${name}`, "LP_MJML_UNKNOWN_ELEMENT"))
    return
  }

  const parent = [...ancestors]
    .reverse()
    .find((ancestor) => htmlElementTypes.has(ancestor.type ?? ""))
  const parentName = elementName(parent)
  const nesting = emailProfile.nesting as Record<string, readonly string[]>
  const children = nesting[parentName]
  if (parentName && children && !children.includes(name) && !children.includes("*")) {
    diagnostics.push(
      astProblem(node, `${name} is not allowed inside ${parentName}`, "LP_MJML_INVALID_CHILD"),
    )
  }

  const metadata = (
    emailProfile.element_metadata as Record<string, { attributes: Record<string, string> }>
  )[name]
  const allowed = new Set([
    ...Object.keys(metadata?.attributes ?? {}),
    ...emailProfile.common_attributes,
  ])
  validateAttributes(node, name, allowed, "LP_MJML_ATTRIBUTE_FORBIDDEN", diagnostics)
}

function validateEmbeddedHtmlNode(node: AstNode, diagnostics: CodeMirrorDiagnostic[]): void {
  const name = elementName(node)
  const policy = contract.embedded_html
  if (!policy.elements.includes(name as (typeof policy.elements)[number])) {
    diagnostics.push(
      astProblem(node, `HTML element ${name} is not allowed`, "LP_HTML_ELEMENT_FORBIDDEN"),
    )
    return
  }

  const perElement = policy.attributes as Record<string, readonly string[]>
  const allowed = new Set([...policy.global_attributes, ...(perElement[name] ?? [])])
  validateAttributes(node, name, allowed, "LP_HTML_ATTRIBUTE_FORBIDDEN", diagnostics, true)
}

function validateAttributes(
  node: AstNode,
  element: string,
  allowed: Set<string>,
  code: string,
  diagnostics: CodeMirrorDiagnostic[],
  allowDataAttributes = false,
): void {
  const attributes = Array.isArray(node.attributes) ? (node.attributes as AstNode[]) : []
  for (const attribute of attributes) {
    const name = elementName(attribute)
    if (!name) {
      diagnostics.push(
        astProblem(attribute, `Dynamic attributes are not allowed on ${element}`, code),
      )
      continue
    }
    const dataAttribute = allowDataAttributes && /^data-[a-z0-9_.:-]+$/.test(name)
    if (name.startsWith("on") || (!allowed.has(name) && !dataAttribute)) {
      diagnostics.push(
        astProblem(attribute, `Attribute ${name} is not allowed on ${element}`, code),
      )
    } else if (
      allowDataAttributes &&
      contract.embedded_html.url_attributes.includes(
        name as (typeof contract.embedded_html.url_attributes)[number],
      ) &&
      !safeStaticUrlAttribute(attribute)
    ) {
      diagnostics.push(
        astProblem(attribute, `Attribute ${name} contains an unsafe static URL`, code),
      )
    }
  }
}

function safeStaticUrlAttribute(attribute: AstNode): boolean {
  const values = Array.isArray(attribute.value) ? (attribute.value as AstNode[]) : []
  if (values.some((value) => value.type !== "TextNode")) return true
  const value = values
    .map((item) => String(item.value ?? ""))
    .join("")
    .trim()
  if (value === "" || /[\0-\x20\x7f]/.test(value)) return value === ""
  if (value.startsWith("//") || value.startsWith("\\")) return false
  if (value.startsWith("/") || value.startsWith("#") || value.startsWith("?")) return true
  if (/^(?:https?|mailto|tel|cid):/i.test(value)) return true
  const leadingSegment = value.split(/[/?#]/, 1)[0] ?? ""
  return !/[:&\\]/.test(leadingSegment)
}

function astProblem(node: AstNode, message: string, code: string): CodeMirrorDiagnostic {
  const position = node.position ?? { start: 0, end: 0 }
  return {
    from: position.start,
    to: position.end,
    severity: "error",
    source: `letterpress · ${code}`,
    message,
  }
}

function documentProblem(message: string, code: string): CodeMirrorDiagnostic {
  return { from: 0, to: 0, severity: "error", source: `letterpress · ${code}`, message }
}

function declaredVariable(schema: VariableSchema, name: string): boolean {
  return Boolean(schema.variables[name] ?? schema.variables[name.split(".")[0] ?? name])
}

function walk(
  node: AstNode,
  ancestors: AstNode[],
  visit: (node: AstNode, ancestors: AstNode[]) => void,
): void {
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

function childrenOf(node: AstNode): AstNode[] {
  return Array.isArray(node.children) ? (node.children as AstNode[]) : []
}

function elementName(node: AstNode | undefined): string {
  if (!node) return ""
  if (typeof node.name === "string") return node.name
  if (!Array.isArray(node.name)) return ""
  return String((node.name[0] as AstNode | undefined)?.value ?? "")
}

function variableLookupName(node: AstNode): string {
  const root = String(node.name ?? "")
  const lookups = Array.isArray(node.lookups)
    ? node.lookups.map((lookup) => String((lookup as AstNode).value ?? ""))
    : []
  return [root, ...lookups].filter(Boolean).join(".")
}

function localVariable(name: string, ancestors: AstNode[]): boolean {
  const root = name.split(".")[0]
  if (
    root === "continue" &&
    ancestors.some((ancestor) => ancestor.type === "NamedArgument" && ancestor.name === "offset")
  ) {
    return true
  }
  return ancestors.some((ancestor) => {
    if (ancestor.type !== "LiquidTag" || ancestor.name !== "for") return false
    return String((ancestor.markup as AstNode | undefined)?.variableName ?? "") === root
  })
}

function openElementStack(source: string): string[] {
  const stack: string[] = []
  for (const match of source.matchAll(/<\/?(mj-[A-Za-z-]+|mjml)(?:\s[^>]*)?>/g)) {
    const token = match[0]
    const name = match[1]
    if (!name || token.endsWith("/>")) continue
    if (token.startsWith("</")) {
      if (stack.at(-1) === name) stack.pop()
    } else {
      stack.push(name)
    }
  }
  return stack
}

function offsetAt(view: EditorView, line: number, character: number): number {
  const lineNumber = Math.min(Math.max(line + 1, 1), view.state.doc.lines)
  const documentLine = view.state.doc.line(lineNumber)
  return Math.min(documentLine.from + Math.max(character, 0), documentLine.to)
}
