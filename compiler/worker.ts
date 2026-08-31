import { createHash } from "node:crypto"
import process from "node:process"
import { toLiquidHtmlAST } from "@shopify/liquid-html-parser"
import liquidPlugin from "@shopify/prettier-plugin-liquid"
import mjml2html from "mjml"
import prettier from "prettier"
import contract from "../generated/letterpress-v1.json"
import { inspectSentinelOutput } from "./sentinel"

type JsonObject = Record<string, unknown>
type Position = { start: number; end: number }
type AstNode = JsonObject & { type?: string; name?: unknown; position?: Position }

interface Request {
  id: string
  operation: "discover" | "analyze" | "compile" | "format" | "apply_translations" | "contract"
  payload?: JsonObject
}

interface Diagnostic {
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
  related: never[]
  data: JsonObject
}

interface VariableUse {
  name: string
  context: string
  position: Position
  raw: string
  filters: string[]
  local: boolean
  binding?: {
    name: string
    collection: string
  }
  outputContexts: string[]
}

interface VariableDependency {
  name: string
  context: "none"
  position: Position
  kind: "condition" | "collection" | "lookup"
  local: boolean
  binding?: VariableUse["binding"]
}

interface Analysis {
  ast: AstNode
  diagnostics: Diagnostic[]
  variables: VariableUse[]
  dependencies: VariableDependency[]
  tags: { name: string; position: Position; structural: boolean }[]
  translation_units: JsonObject[]
}

interface Sentinel {
  raw: string
  sourceContext: string
  outputContexts: string[]
}

const htmlElementTypes = new Set([
  "HtmlElement",
  "HtmlSelfClosingElement",
  "HtmlVoidElement",
  "HtmlRawNode",
  "HtmlDanglingMarkerOpen",
  "HtmlDanglingMarkerClose",
])

const liquidTagTypes = new Set(["LiquidTag", "LiquidRawTag"])

const encoder = new TextEncoder()
const maxFrameBytes = 2_000_000
let input = Buffer.alloc(0)

process.stdin.on("data", (chunk: Buffer) => {
  input = Buffer.concat([input, chunk])
  drainFrames()
})

process.stdin.on("error", () => process.exit(1))
process.stdout.on("error", (error: NodeJS.ErrnoException) => {
  process.exit(error.code === "EPIPE" ? 0 : 1)
})

function drainFrames(): void {
  while (input.length >= 4) {
    const length = input.readUInt32BE(0)
    if (length > maxFrameBytes) process.exit(64)
    if (input.length < length + 4) return
    const frame = input.subarray(4, length + 4)
    input = input.subarray(length + 4)
    void handleFrame(frame)
  }
}

async function handleFrame(frame: Buffer): Promise<void> {
  let request: Request | undefined
  try {
    request = JSON.parse(frame.toString("utf8")) as Request
    const result = await dispatch(request)
    writeFrame({ id: request.id, ok: true, result })
  } catch (error) {
    writeFrame({
      id: request?.id ?? "invalid",
      ok: false,
      error: normalizeError(error),
    })
  }
}

function writeFrame(value: unknown): void {
  const payload = Buffer.from(JSON.stringify(value), "utf8")
  const header = Buffer.allocUnsafe(4)
  header.writeUInt32BE(payload.length)
  process.stdout.write(Buffer.concat([header, payload]))
}

async function dispatch(request: Request): Promise<unknown> {
  if (!request || typeof request.id !== "string" || typeof request.operation !== "string") {
    throw new Error("invalid request envelope")
  }

  switch (request.operation) {
    case "contract":
      return contract
    case "discover":
      return discoverPayload(request.payload ?? {})
    case "analyze":
      return analyzePayload(request.payload ?? {})
    case "compile":
      return compilePayload(request.payload ?? {})
    case "format":
      return formatPayload(request.payload ?? {})
    case "apply_translations":
      return applyTranslationsPayload(request.payload ?? {})
    default:
      throw new Error("unsupported operation")
  }
}

function discoverPayload(payload: JsonObject): JsonObject {
  const profile = requireString(payload.profile, "profile")
  const source = requireString(payload.source, "source")
  const documentVersion = optionalInteger(payload.document_version, 0)
  const analysis = analyze(profile, source, {}, documentVersion, undefined, false, false)
  return publicAnalysis(analysis)
}

function analyzePayload(payload: JsonObject): JsonObject {
  const profile = requireString(payload.profile, "profile")
  const source = requireString(payload.source, "source")
  const schema = requireObject(payload.schema, "schema")
  const documentVersion = optionalInteger(payload.document_version, 0)
  const analysis = analyze(profile, source, schema, documentVersion)
  return publicAnalysis(analysis)
}

async function compilePayload(payload: JsonObject): Promise<JsonObject> {
  const profile = requireString(payload.profile, "profile")
  const source = requireString(payload.source, "source")
  const subject = optionalString(payload.subject)
  const text = optionalString(payload.text)
  const schema = requireObject(payload.schema, "schema")
  const compileValues = optionalObject(payload.compile_values)
  const documentVersion = optionalInteger(payload.document_version, 0)
  const analysis = analyze(profile, source, schema, documentVersion, undefined, false)
  const subjectAnalysis =
    subject === null
      ? null
      : analyze("text/liquid@1", subject, schema, documentVersion, "subject", false)
  const textAnalysis =
    text === null ? null : analyze("text/liquid@1", text, schema, documentVersion, undefined, false)
  const initialDiagnostics = [
    ...analysis.diagnostics,
    ...(subjectAnalysis?.diagnostics ?? []),
    ...(textAnalysis?.diagnostics ?? []),
    ...unusedSchemaDiagnostics(
      [analysis, subjectAnalysis, textAnalysis],
      schema,
      source,
      documentVersion,
    ),
  ]

  if (initialDiagnostics.some((item) => item.severity === "error")) {
    return { diagnostics: initialDiagnostics, analysis: publicAnalysis(analysis) }
  }

  const sourceHash = sha256(source)
  const prepared = prepareSource(
    source,
    analysis,
    schema,
    compileValues,
    sourceHash,
    documentVersion,
  )
  const preparedSubject = prepareAuxiliary(
    subject,
    subjectAnalysis,
    schema,
    compileValues,
    documentVersion,
  )
  const preparedText = prepareAuxiliary(text, textAnalysis, schema, compileValues, documentVersion)
  const diagnostics = [
    ...initialDiagnostics,
    ...prepared.diagnostics,
    ...preparedSubject.diagnostics,
    ...preparedText.diagnostics,
  ]
  if (diagnostics.some((item) => item.severity === "error")) {
    return { diagnostics, analysis: publicAnalysis(analysis) }
  }

  if (profile === "text/liquid@1") {
    return {
      diagnostics,
      analysis: publicAnalysis(analysis),
      compiled: {
        html: null,
        text: restoreSentinels(
          prepared.source,
          prepared.sentinels,
          source,
          sourceHash,
          documentVersion,
        ).output,
        subject: preparedSubject.output,
        source_map: {
          ...prepared.sourceMap,
          ...preparedSubject.sourceMap,
        },
      },
      compiler: compilerVersions(),
    }
  }

  try {
    const mjmlOptions = {
      validationLevel: "strict",
      sanitizeStyles: true,
      minify: false,
      keepComments: true,
    } as Parameters<typeof mjml2html>[1] & { sanitizeStyles: boolean }
    const result = await mjml2html(prepared.source, mjmlOptions)
    const mjmlDiagnostics = (result.errors ?? []).map((mjmlError) => {
      const error = mjmlError as unknown as JsonObject
      return diagnostic(
        source,
        sourceHash,
        documentVersion,
        lineRange(source, Number(error.line ?? 1)),
        "error",
        "LP_MJML_COMPILE",
        "letterpress-mjml",
        String(error.formattedMessage ?? error.message ?? "MJML compilation failed"),
        { tag: String(error.tagName ?? "") },
      )
    })
    if (mjmlDiagnostics.length > 0) {
      return {
        diagnostics: [...diagnostics, ...mjmlDiagnostics],
        analysis: publicAnalysis(analysis),
      }
    }

    const restored = restoreSentinels(
      String(result.html),
      prepared.sentinels,
      source,
      sourceHash,
      documentVersion,
      true,
    )
    return {
      diagnostics: [...diagnostics, ...restored.diagnostics],
      analysis: publicAnalysis(analysis),
      compiled: {
        html: restored.output,
        text: preparedText.output,
        subject: preparedSubject.output,
        source_map: {
          ...prepared.sourceMap,
          ...preparedSubject.sourceMap,
          ...preparedText.sourceMap,
        },
      },
      compiler: compilerVersions(),
    }
  } catch (error) {
    return {
      diagnostics: [
        ...diagnostics,
        diagnostic(
          source,
          sourceHash,
          documentVersion,
          { start: 0, end: 0 },
          "error",
          "LP_MJML_COMPILE",
          "letterpress-mjml",
          normalizeError(error),
          {},
        ),
      ],
      analysis: publicAnalysis(analysis),
    }
  }
}

async function formatPayload(payload: JsonObject): Promise<JsonObject> {
  const profile = requireString(payload.profile, "profile")
  const source = requireString(payload.source, "source")
  if (profile === "text/liquid@1") {
    return { source: source.trimEnd() }
  }
  const formatted = await prettier.format(source, {
    parser: "liquid-html",
    plugins: [liquidPlugin],
    printWidth: 100,
    tabWidth: 2,
    singleQuote: false,
  })
  return { source: formatted }
}

function applyTranslationsPayload(payload: JsonObject): JsonObject {
  const profile = requireString(payload.profile, "profile")
  const source = requireString(payload.source, "source")
  const schema = requireObject(payload.schema, "schema")
  const translations = requireObject(payload.translations, "translations")
  const documentVersion = optionalInteger(payload.document_version, 0)
  const sourceHash = sha256(source)
  const analysis = analyze(profile, source, schema, documentVersion)
  const diagnostics = [...analysis.diagnostics]
  const replacements: { start: number; end: number; value: string }[] = []

  for (const unit of analysis.translation_units) {
    const id = String(unit.id ?? "")
    const translated = translationText(translations[id])
    const range = unit.range as Position
    if (translated === null) {
      diagnostics.push(
        diagnostic(
          source,
          sourceHash,
          documentVersion,
          range,
          "error",
          "LP_TRANSLATION_MISSING",
          "letterpress-translation",
          `Translation unit ${id} is missing`,
          { unit_id: id },
        ),
      )
      continue
    }
    const originalSignature = liquidSignature(String(unit.source ?? ""))
    const translatedSignature = liquidSignature(translated)
    if (JSON.stringify(originalSignature) !== JSON.stringify(translatedSignature)) {
      diagnostics.push(
        diagnostic(
          source,
          sourceHash,
          documentVersion,
          range,
          "error",
          "LP_TRANSLATION_PLACEHOLDER",
          "letterpress-translation",
          `Translation unit ${id} changed placeholders or markup`,
          { unit_id: id },
        ),
      )
      continue
    }
    replacements.push({ ...range, value: translated })
  }

  return {
    source: diagnostics.some((item) => item.severity === "error")
      ? source
      : applyReplacements(source, replacements),
    diagnostics,
  }
}

function translationText(value: unknown): string | null {
  if (typeof value === "string") return value
  if (
    value &&
    typeof value === "object" &&
    !Array.isArray(value) &&
    typeof (value as JsonObject).text === "string"
  ) {
    return String((value as JsonObject).text)
  }
  return null
}

function liquidSignature(source: string): string[] {
  try {
    const ast = toLiquidHtmlAST(source, {
      mode: "strict",
      allowUnclosedDocumentNode: false,
    }) as unknown as AstNode
    const signature: string[] = []
    walk(ast, [], (node) => {
      if (node.type === "LiquidVariableOutput") signature.push(`output:${rawLiquid(node)}`)
      if (liquidTagTypes.has(String(node.type))) signature.push(`tag:${String(node.name ?? "")}`)
      if (htmlElementTypes.has(String(node.type))) signature.push(`element:${elementName(node)}`)
    })
    return signature
  } catch {
    return ["invalid"]
  }
}

function analyze(
  profile: string,
  source: string,
  schema: JsonObject,
  documentVersion: number,
  contextOverride?: string,
  reportUnused = true,
  validateSchema = true,
): Analysis {
  const sourceHash = sha256(source)
  const diagnostics: Diagnostic[] = []
  const variables: VariableUse[] = []
  const tags: { name: string; position: Position; structural: boolean }[] = []
  const translationUnits: JsonObject[] = []

  if (!Object.hasOwn(contract.profiles, profile)) {
    diagnostics.push(
      diagnostic(
        source,
        sourceHash,
        documentVersion,
        { start: 0, end: 0 },
        "error",
        "LP_PROFILE_UNKNOWN",
        "letterpress",
        `Unsupported profile ${profile}`,
        {},
      ),
    )
  }
  if (encoder.encode(source).length > contract.limits.source_bytes) {
    diagnostics.push(
      diagnostic(
        source,
        sourceHash,
        documentVersion,
        { start: 0, end: source.length },
        "error",
        "LP_SOURCE_TOO_LARGE",
        "letterpress",
        "Source exceeds the profile byte limit",
        {},
      ),
    )
  }
  if (source.includes("\0")) {
    diagnostics.push(
      diagnostic(
        source,
        sourceHash,
        documentVersion,
        { start: source.indexOf("\0"), end: source.indexOf("\0") + 1 },
        "error",
        "LP_SOURCE_NUL",
        "letterpress",
        "Source contains a NUL character",
        {},
      ),
    )
  }

  const legacySyntax = /\{\{\{|\{\{\s*[#/^!]/.exec(source)
  if (legacySyntax?.index !== undefined) {
    diagnostics.push(
      diagnostic(
        source,
        sourceHash,
        documentVersion,
        { start: legacySyntax.index, end: legacySyntax.index + legacySyntax[0].length },
        "error",
        "LP_LEGACY_SYNTAX",
        "letterpress-liquid",
        "Legacy Mustache or Handlebars syntax is not supported; use Liquid tags",
        {},
      ),
    )
    return {
      ast: {},
      diagnostics,
      variables,
      dependencies: [],
      tags,
      translation_units: translationUnits,
    }
  }

  let ast: AstNode
  try {
    ast = toLiquidHtmlAST(source, {
      mode: "strict",
      allowUnclosedDocumentNode: false,
    }) as unknown as AstNode
  } catch (error) {
    diagnostics.push(parserDiagnostic(source, sourceHash, documentVersion, error))
    return {
      ast: {},
      diagnostics,
      variables,
      dependencies: [],
      tags,
      translation_units: translationUnits,
    }
  }

  const profileData = (contract.profiles as JsonObject)[profile] as JsonObject | undefined
  const rootElements = childrenOf(ast).filter((node) => node.type === "HtmlElement")
  if (profile === "email/mjml-liquid@1") {
    if (rootElements.length !== 1 || elementName(rootElements[0]) !== "mjml") {
      diagnostics.push(
        diagnostic(
          source,
          sourceHash,
          documentVersion,
          rootElements[0]?.position ?? { start: 0, end: 0 },
          "error",
          "LP_MJML_ROOT",
          "letterpress-mjml",
          "Email source must have exactly one mjml root element",
          {},
        ),
      )
    }
    const bodies = rootElements[0]
      ? childrenOf(rootElements[0]).filter((node) => elementName(node) === "mj-body")
      : []
    if (bodies.length !== 1) {
      diagnostics.push(
        diagnostic(
          source,
          sourceHash,
          documentVersion,
          rootElements[0]?.position ?? { start: 0, end: 0 },
          "error",
          "LP_MJML_BODY",
          "letterpress-mjml",
          "Email source must have exactly one mj-body element",
          {},
        ),
      )
    }
  }

  walk(ast, [], (node, ancestors, edge) => {
    if (htmlElementTypes.has(String(node.type))) {
      validateElement(
        node,
        ancestors,
        source,
        sourceHash,
        documentVersion,
        profileData,
        diagnostics,
      )
      collectTranslationUnit(node, ancestors, source, sourceHash, translationUnits)
    }
    if (node.type === "LiquidVariableOutput") {
      const context = contextOverride ?? contextFor(node, ancestors, edge, profile)
      const name = variableName(node)
      const filters = filtersOf(node)
      const binding = localBinding(name, ancestors)
      variables.push({
        name,
        context,
        position: node.position ?? { start: 0, end: 0 },
        raw: rawLiquid(node),
        filters,
        local: localVariable(name, ancestors),
        ...(binding === undefined ? {} : { binding }),
        outputContexts: compilerOutputContexts(context, ancestors),
      })
      validateLiquidUse(
        name,
        context,
        filters,
        node,
        schema,
        source,
        sourceHash,
        documentVersion,
        diagnostics,
      )
    }
    if (liquidTagTypes.has(String(node.type))) {
      const name = String(node.name ?? "")
      const structural = structuralContext(ancestors)
      tags.push({ name, position: node.position ?? { start: 0, end: 0 }, structural })
      if (!contract.liquid.tags.includes(name)) {
        diagnostics.push(
          diagnostic(
            source,
            sourceHash,
            documentVersion,
            node.position ?? { start: 0, end: 0 },
            "error",
            "LP_LIQUID_TAG_FORBIDDEN",
            "letterpress-liquid",
            `Liquid tag ${name} is not allowed`,
            { tag: name },
          ),
        )
      }
    }
  })

  if (profile === "text/liquid@1") {
    collectTextTranslationUnit(ast, source, sourceHash, translationUnits)
  }

  const dependencies = lookupDependencies(ast)
  const used = new Set(
    variables
      .filter((item) => !item.local)
      .map((item) => item.name)
      .filter(Boolean),
  )
  for (const dependency of dependencies) if (!dependency.local) used.add(dependency.name)
  if (validateSchema) {
    const declared = flattenSchema(schema)
    for (const name of [...used].sort()) {
      if (!declared.has(name) && !declared.has(name.split(".")[0] ?? name)) {
        diagnostics.push(
          diagnostic(
            source,
            sourceHash,
            documentVersion,
            findVariablePosition(variables, name),
            "error",
            "LP_SCHEMA_UNDECLARED_VARIABLE",
            "letterpress-schema",
            `Variable ${name} is not declared in the schema`,
            { variable: name },
          ),
        )
      }
    }
    if (reportUnused) {
      for (const name of [...declared.keys()].sort()) {
        if (!used.has(name) && ![...used].some((usedName) => usedName.startsWith(`${name}.`))) {
          diagnostics.push(
            diagnostic(
              source,
              sourceHash,
              documentVersion,
              { start: 0, end: 0 },
              "hint",
              "LP_SCHEMA_UNUSED_VARIABLE",
              "letterpress-schema",
              `Variable ${name} is declared but not used`,
              { variable: name },
            ),
          )
        }
      }
    }
  }

  return { ast, diagnostics, variables, dependencies, tags, translation_units: translationUnits }
}

function unusedSchemaDiagnostics(
  analyses: (Analysis | null)[],
  schema: JsonObject,
  source: string,
  documentVersion: number,
): Diagnostic[] {
  const used = new Set<string>()
  for (const analysis of analyses) {
    if (analysis === null) continue
    for (const variable of analysis.variables) if (!variable.local) used.add(variable.name)
    for (const dependency of analysis.dependencies) if (!dependency.local) used.add(dependency.name)
  }

  const sourceHash = sha256(source)
  return [...flattenSchema(schema).keys()]
    .sort()
    .filter(
      (name) => !used.has(name) && ![...used].some((usedName) => usedName.startsWith(`${name}.`)),
    )
    .map((name) =>
      diagnostic(
        source,
        sourceHash,
        documentVersion,
        { start: 0, end: 0 },
        "hint",
        "LP_SCHEMA_UNUSED_VARIABLE",
        "letterpress-schema",
        `Variable ${name} is declared but not used`,
        { variable: name },
      ),
    )
}

function validateElement(
  node: AstNode,
  ancestors: AstNode[],
  source: string,
  sourceHash: string,
  documentVersion: number,
  profile: JsonObject | undefined,
  diagnostics: Diagnostic[],
): void {
  if (profile?.kind !== "email") return
  const name = elementName(node)
  if (name !== "mjml" && !name.startsWith("mj-")) {
    validateEmbeddedHtml(node, source, sourceHash, documentVersion, diagnostics)
    return
  }
  const allowed = profile.elements as string[]
  const forbidden = profile.forbidden_elements as string[]
  if (forbidden.includes(name)) {
    diagnostics.push(
      diagnostic(
        source,
        sourceHash,
        documentVersion,
        node.position ?? { start: 0, end: 0 },
        "error",
        "LP_MJML_ELEMENT_FORBIDDEN",
        "letterpress-mjml",
        `Element ${name} is forbidden`,
        { element: name },
      ),
    )
  } else if (name && !allowed.includes(name)) {
    diagnostics.push(
      diagnostic(
        source,
        sourceHash,
        documentVersion,
        node.position ?? { start: 0, end: 0 },
        "error",
        "LP_MJML_UNKNOWN_ELEMENT",
        "letterpress-mjml",
        `Unknown MJML element ${name}`,
        { element: name },
      ),
    )
  }

  validateNesting(node, ancestors, source, sourceHash, documentVersion, profile, diagnostics)
  validateAttributes(node, source, sourceHash, documentVersion, profile, diagnostics)
}

function validateEmbeddedHtml(
  node: AstNode,
  source: string,
  sourceHash: string,
  documentVersion: number,
  diagnostics: Diagnostic[],
): void {
  const name = elementName(node)
  const policy = contract.embedded_html
  if (!policy.elements.includes(name)) {
    diagnostics.push(
      diagnostic(
        source,
        sourceHash,
        documentVersion,
        node.position ?? { start: 0, end: 0 },
        "error",
        "LP_HTML_ELEMENT_FORBIDDEN",
        "letterpress-html",
        `HTML element ${name} is not allowed in MJML content`,
        { element: name },
      ),
    )
    return
  }

  const allowed = new Set([
    ...policy.global_attributes,
    ...((policy.attributes as Record<string, string[]>)[name] ?? []),
  ])
  const attributes = Array.isArray(node.attributes) ? (node.attributes as AstNode[]) : []
  for (const attribute of attributes) {
    const attributeNameValue = attributeName(attribute)
    if (!attributeNameValue) continue
    const allowedDataAttribute =
      attributeNameValue.startsWith("data-") && /^data-[a-z0-9_.:-]+$/.test(attributeNameValue)
    if (
      attributeNameValue.startsWith("on") ||
      (!allowed.has(attributeNameValue) && !allowedDataAttribute)
    ) {
      const range = (attribute.attributePosition as Position | undefined) ??
        attribute.position ??
        node.position ?? { start: 0, end: 0 }
      diagnostics.push(
        diagnostic(
          source,
          sourceHash,
          documentVersion,
          range,
          "error",
          "LP_HTML_ATTRIBUTE_FORBIDDEN",
          "letterpress-html",
          `HTML attribute ${attributeNameValue} is not allowed on ${name}`,
          { attribute: attributeNameValue, element: name },
        ),
      )
    }
  }
}

function validateNesting(
  node: AstNode,
  ancestors: AstNode[],
  source: string,
  sourceHash: string,
  documentVersion: number,
  profile: JsonObject,
  diagnostics: Diagnostic[],
): void {
  const parent = [...ancestors].reverse().find((item) => htmlElementTypes.has(String(item.type)))
  const parentName = elementName(parent)
  const name = elementName(node)
  if (!parentName || !name) return
  const dependencies = (profile.nesting as JsonObject | undefined)?.[parentName]
  if (!Array.isArray(dependencies)) return
  if (!dependencies.includes(name) && !dependencies.includes("*")) {
    diagnostics.push(
      diagnostic(
        source,
        sourceHash,
        documentVersion,
        node.position ?? { start: 0, end: 0 },
        "error",
        "LP_MJML_INVALID_CHILD",
        "letterpress-mjml",
        `${name} is not allowed inside ${parentName}`,
        { element: name, parent: parentName },
      ),
    )
  }
}

function validateAttributes(
  node: AstNode,
  source: string,
  sourceHash: string,
  documentVersion: number,
  profile: JsonObject,
  diagnostics: Diagnostic[],
): void {
  const name = elementName(node)
  const metadata = (profile.element_metadata as JsonObject | undefined)?.[name] as
    | JsonObject
    | undefined
  const componentAttributes =
    metadata?.attributes && typeof metadata.attributes === "object"
      ? Object.keys(metadata.attributes as JsonObject)
      : []
  const commonAttributes = Array.isArray(profile.common_attributes)
    ? profile.common_attributes.map(String)
    : []
  const allowed = new Set([...componentAttributes, ...commonAttributes])
  const attributes = Array.isArray(node.attributes) ? (node.attributes as AstNode[]) : []
  for (const attribute of attributes) {
    const attributeNameValue = attributeName(attribute)
    if (!attributeNameValue) continue
    if (
      attributeNameValue.startsWith("on") ||
      attributeNameValue === "style" ||
      !allowed.has(attributeNameValue)
    ) {
      const range = (attribute.attributePosition as Position | undefined) ??
        attribute.position ??
        node.position ?? { start: 0, end: 0 }
      diagnostics.push(
        diagnostic(
          source,
          sourceHash,
          documentVersion,
          range,
          "error",
          "LP_MJML_ATTRIBUTE_FORBIDDEN",
          "letterpress-mjml",
          `Attribute ${attributeNameValue} is not allowed on ${name}`,
          { attribute: attributeNameValue, element: name },
        ),
      )
    }
  }
}

function validateLiquidUse(
  name: string,
  context: string,
  filters: string[],
  node: AstNode,
  schema: JsonObject,
  source: string,
  sourceHash: string,
  documentVersion: number,
  diagnostics: Diagnostic[],
): void {
  for (const filter of filters) {
    if (
      !contract.liquid.filters.includes(filter) ||
      contract.liquid.reserved_filters.includes(filter)
    ) {
      diagnostics.push(
        diagnostic(
          source,
          sourceHash,
          documentVersion,
          node.position ?? { start: 0, end: 0 },
          "error",
          "LP_LIQUID_FILTER_FORBIDDEN",
          "letterpress-liquid",
          `Liquid filter ${filter} is not allowed`,
          { filter },
        ),
      )
    }
  }
  const definition = schemaDefinition(schema, name)
  if (!definition) return
  const phase = String(definition.phase ?? "delivery")
  const declaredContext = String(definition.context ?? "none")
  if (["css", "color"].includes(context) && phase !== "compile") {
    diagnostics.push(
      diagnostic(
        source,
        sourceHash,
        documentVersion,
        node.position ?? { start: 0, end: 0 },
        "error",
        "LP_SCHEMA_PHASE_MISMATCH",
        "letterpress-schema",
        `${name} must be compile-phase in ${context} context`,
        { variable: name, context },
      ),
    )
  }
  if (declaredContext !== "none" && !compatibleContext(declaredContext, context)) {
    diagnostics.push(
      diagnostic(
        source,
        sourceHash,
        documentVersion,
        node.position ?? { start: 0, end: 0 },
        "error",
        "LP_SCHEMA_CONTEXT_MISMATCH",
        "letterpress-schema",
        `${name} is declared for ${declaredContext}, not ${context}`,
        { variable: name, expected: declaredContext, actual: context },
      ),
    )
  }
}

function prepareSource(
  source: string,
  analysis: Analysis,
  schema: JsonObject,
  compileValues: JsonObject,
  sourceHash: string,
  documentVersion: number,
): {
  source: string
  sentinels: Map<string, Sentinel>
  diagnostics: Diagnostic[]
  sourceMap: JsonObject
} {
  const replacements: { start: number; end: number; value: string }[] = []
  const sentinels = new Map<string, Sentinel>()
  const diagnostics: Diagnostic[] = []
  const sourceMap: JsonObject = {}

  analysis.variables.forEach((use, index) => {
    const definition = schemaDefinition(schema, use.name)
    const phase = String(definition?.phase ?? "delivery")
    if (phase === "compile") {
      const value = valueAt(compileValues, use.name)
      if (
        value === undefined &&
        definition?.required !== false &&
        definition?.default === undefined
      ) {
        diagnostics.push(
          diagnostic(
            source,
            sourceHash,
            documentVersion,
            use.position,
            "error",
            "LP_COMPILE_VALUE_MISSING",
            "letterpress-schema",
            `Required compile value ${use.name} is missing`,
            { variable: use.name },
          ),
        )
        return
      }
      const resolved = value === undefined ? definition?.default : value
      const validated = validateCompileValue(resolved, use.context)
      if (validated.ok) replacements.push({ ...use.position, value: validated.value })
      else
        diagnostics.push(
          diagnostic(
            source,
            sourceHash,
            documentVersion,
            use.position,
            "error",
            "LP_COMPILE_VALUE_INVALID",
            "letterpress-schema",
            `${use.name} is invalid for ${use.context} context`,
            { variable: use.name, context: use.context },
          ),
        )
      return
    }

    const token = `LPX_${sourceHash.slice(0, 16)}_${index.toString(36)}_XPL`
    if (source.includes(token)) {
      diagnostics.push(
        diagnostic(
          source,
          sourceHash,
          documentVersion,
          use.position,
          "error",
          "LP_SENTINEL_COLLISION",
          "letterpress-compiler",
          "Source collides with an internal compiler sentinel",
          {},
        ),
      )
      return
    }
    sentinels.set(token, {
      raw: use.raw,
      sourceContext: use.context,
      outputContexts: use.outputContexts,
    })
    replacements.push({ ...use.position, value: token })
    sourceMap[token] = { source: use.position, variable: use.name, context: use.context }
  })

  wrapStructuralTags(analysis.ast, replacements)
  return { source: applyReplacements(source, replacements), sentinels, diagnostics, sourceMap }
}

function wrapStructuralTags(
  ast: AstNode,
  replacements: { start: number; end: number; value: string }[],
): void {
  walk(ast, [], (node, ancestors) => {
    if (!liquidTagTypes.has(String(node.type)) || !structuralContext(ancestors)) return
    const start = node.blockStartPosition as Position | undefined
    const end = node.blockEndPosition as Position | undefined
    if (start && start.end > start.start)
      replacements.push({ ...start, value: `<mj-raw>${sliceNode(node, start)}</mj-raw>` })
    if (end && end.end > end.start)
      replacements.push({ ...end, value: `<mj-raw>${sliceNode(node, end)}</mj-raw>` })
    for (const branch of childrenOf(node)) {
      if (branch.type !== "LiquidBranch") continue
      const branchStart = branch.blockStartPosition as Position | undefined
      if (branchStart && branchStart.end > branchStart.start)
        replacements.push({
          ...branchStart,
          value: `<mj-raw>${sliceNode(branch, branchStart)}</mj-raw>`,
        })
    }
  })
}

function restoreSentinels(
  output: string,
  sentinels: Map<string, Sentinel>,
  source: string,
  sourceHash: string,
  documentVersion: number,
  verifyOutputContext = false,
): { output: string; diagnostics: Diagnostic[] } {
  const diagnostics: Diagnostic[] = []
  let restored = output
  const inspection = verifyOutputContext
    ? inspectSentinelOutput(
        output,
        new Map([...sentinels].map(([token, sentinel]) => [token, sentinel.outputContexts])),
      )
    : null
  const contextIssues = new Map((inspection?.issues ?? []).map((issue) => [issue.token, issue]))
  const replacements: { start: number; end: number; value: string }[] = []

  for (const [token, sentinel] of sentinels) {
    const count = restored.split(token).length - 1
    const issue = contextIssues.get(token)
    const expectedCount = verifyOutputContext ? sentinel.outputContexts.length : 1
    if (count !== expectedCount || issue) {
      diagnostics.push(
        diagnostic(
          source,
          sourceHash,
          documentVersion,
          { start: 0, end: 0 },
          "error",
          "LP_SENTINEL_SURVIVAL",
          "letterpress-compiler",
          "Compiler did not preserve an expression sentinel in its modeled output contexts",
          {
            count,
            expected_contexts: verifyOutputContext
              ? sentinel.outputContexts
              : [sentinel.sourceContext],
            actual_contexts: issue?.contexts ?? [],
          },
        ),
      )
    } else {
      if (verifyOutputContext) {
        for (const occurrence of inspection?.occurrences.get(token) ?? []) {
          replacements.push({
            start: occurrence.start,
            end: occurrence.end,
            value: `{{ ${sentinel.raw} | letterpress_escape: "${occurrence.context}" }}`,
          })
        }
      } else {
        restored = restored.replaceAll(
          token,
          `{{ ${sentinel.raw} | letterpress_escape: "${sentinel.sourceContext}" }}`,
        )
      }
    }
  }
  if (verifyOutputContext && diagnostics.length === 0)
    restored = applyReplacements(output, replacements)
  return { output: restored, diagnostics }
}

function compilerOutputContexts(context: string, ancestors: AstNode[]): string[] {
  const element = [...ancestors].reverse().find((ancestor) => ancestor.type === "HtmlElement")
  if (elementName(element) === "mj-title") return ["html_text", "html_attribute"]
  return [context]
}

function prepareAuxiliary(
  source: string | null,
  analysis: Analysis | null,
  schema: JsonObject,
  compileValues: JsonObject,
  documentVersion: number,
): { output: string | null; diagnostics: Diagnostic[]; sourceMap: JsonObject } {
  if (source === null || analysis === null) return { output: null, diagnostics: [], sourceMap: {} }
  const sourceHash = sha256(source)
  const prepared = prepareSource(
    source,
    analysis,
    schema,
    compileValues,
    sourceHash,
    documentVersion,
  )
  const restored = restoreSentinels(
    prepared.source,
    prepared.sentinels,
    source,
    sourceHash,
    documentVersion,
  )
  return {
    output: restored.output,
    diagnostics: [...prepared.diagnostics, ...restored.diagnostics],
    sourceMap: prepared.sourceMap,
  }
}

function publicAnalysis(analysis: Analysis): JsonObject {
  return {
    diagnostics: analysis.diagnostics,
    variables: analysis.variables.map(({ name, context, position, filters, local, binding }) => ({
      name,
      context,
      position,
      filters,
      local,
      ...(binding === undefined ? {} : { binding }),
    })),
    dependencies: analysis.dependencies,
    translation_units: analysis.translation_units,
  }
}

function collectTranslationUnit(
  node: AstNode,
  ancestors: AstNode[],
  source: string,
  sourceHash: string,
  units: JsonObject[],
): void {
  const name = elementName(node)
  const profile = contract.profiles["email/mjml-liquid@1"]
  if (!profile.text_elements.includes(name)) return
  const children = childrenOf(node)
  if (children.length === 0) return
  const start = children[0]?.position?.start
  const end = children.at(-1)?.position?.end
  if (start === undefined || end === undefined) return
  const text = source.slice(start, end)
  if (text.trim() === "") return
  const path = [...ancestors.map(elementName).filter(Boolean), name].join("/")
  units.push({
    id: sha256(`${path}\0${text}`).slice(0, 24),
    context: "html_text",
    source: text,
    range: { start, end },
    source_hash: sourceHash,
  })
}

function collectTextTranslationUnit(
  ast: AstNode,
  source: string,
  sourceHash: string,
  units: JsonObject[],
): void {
  let hasHumanText = false

  walk(ast, [], (node) => {
    if (node.type === "TextNode" && String(node.value ?? "").trim() !== "") {
      hasHumanText = true
    }
  })

  if (!hasHumanText) return

  units.push({
    id: sha256(`text/liquid@1\0text\0${source}`).slice(0, 24),
    context: "text",
    source,
    range: { start: 0, end: source.length },
    source_hash: sourceHash,
  })
}

function walk(
  node: AstNode,
  ancestors: AstNode[],
  visit: (node: AstNode, ancestors: AstNode[], edge: string) => void,
  edge = "root",
): void {
  if (!node || typeof node !== "object") return
  visit(node, ancestors, edge)
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
    )
      continue
    if (Array.isArray(value)) {
      for (const child of value)
        if (child && typeof child === "object")
          walk(child as AstNode, [...ancestors, node], visit, key)
    } else if (value && typeof value === "object") {
      walk(value as AstNode, [...ancestors, node], visit, key)
    }
  }
}

function lookupDependencies(ast: AstNode): VariableDependency[] {
  const dependencies = new Map<string, VariableDependency>()
  walk(ast, [], (node, ancestors) => {
    if (node.type === "VariableLookup") {
      const root = String(node.name ?? "")
      const lookups = Array.isArray(node.lookups)
        ? node.lookups.map((item) => String((item as JsonObject).value ?? ""))
        : []
      const name = [root, ...lookups].filter(Boolean).join(".")
      const output = ancestors.some((ancestor) => ancestor.type === "LiquidVariableOutput")
      const binding = localBinding(name, ancestors)
      if (root && !output && !liquidInternalVariable(name, ancestors) && !dependencies.has(name)) {
        dependencies.set(name, {
          name,
          context: "none",
          position: node.position ?? { start: 0, end: 0 },
          kind: dependencyKind(node, ancestors),
          local: binding !== undefined,
          ...(binding === undefined ? {} : { binding }),
        })
      }
    }
  })
  return [...dependencies.values()].sort((left, right) =>
    left.position.start === right.position.start
      ? left.name.localeCompare(right.name)
      : left.position.start - right.position.start,
  )
}

function dependencyKind(node: AstNode, ancestors: AstNode[]): VariableDependency["kind"] {
  const forTag = [...ancestors]
    .reverse()
    .find((ancestor) => ancestor.type === "LiquidTag" && ancestor.name === "for")
  const collection = (forTag?.markup as JsonObject | undefined)?.collection

  if (collection === node) return "collection"

  if (
    ancestors.some(
      (ancestor) =>
        ancestor.type === "LiquidTag" && ["if", "unless", "case"].includes(String(ancestor.name)),
    )
  ) {
    return "condition"
  }

  return "lookup"
}

function localBinding(name: string, ancestors: AstNode[]): VariableUse["binding"] | undefined {
  const root = name.split(".")[0] ?? ""
  const forTag = [...ancestors].reverse().find((ancestor) => {
    if (ancestor.type !== "LiquidTag" || ancestor.name !== "for") return false
    const markup = ancestor.markup as JsonObject | undefined
    return String(markup?.variableName ?? "") === root
  })

  if (!forTag) return undefined

  const markup = forTag.markup as JsonObject | undefined
  const collection = markup?.collection as JsonObject | undefined
  const collectionRoot = String(collection?.name ?? "")
  const collectionLookups = Array.isArray(collection?.lookups)
    ? collection.lookups.map((item) => String((item as JsonObject).value ?? ""))
    : []

  return {
    name: root,
    collection: [collectionRoot, ...collectionLookups].filter(Boolean).join("."),
  }
}

function localVariable(name: string, ancestors: AstNode[]): boolean {
  return liquidInternalVariable(name, ancestors) || localBinding(name, ancestors) !== undefined
}

function liquidInternalVariable(name: string, ancestors: AstNode[]): boolean {
  return (
    name.split(".")[0] === "continue" &&
    ancestors.some((ancestor) => ancestor.type === "NamedArgument" && ancestor.name === "offset")
  )
}

function childrenOf(node: AstNode): AstNode[] {
  return Array.isArray(node.children) ? (node.children as AstNode[]) : []
}

function elementName(node: AstNode | undefined): string {
  if (!node) return ""
  if (typeof node.name === "string") return node.name
  if (!Array.isArray(node.name)) return ""
  return String((node.name[0] as JsonObject | undefined)?.value ?? "")
}

function attributeName(node: AstNode | undefined): string {
  return elementName(node)
}

function contextFor(_node: AstNode, ancestors: AstNode[], edge: string, profile: string): string {
  if (profile === "text/liquid@1") return "text"
  const parent = ancestors.at(-1)
  if (parent?.type?.startsWith("Attr") || edge === "value") {
    const name = attributeName(parent)
    const email = contract.profiles["email/mjml-liquid@1"]
    if (email.url_attributes.includes(name) || contract.embedded_html.url_attributes.includes(name))
      return "url"
    if (name === "style") return "css"
    if (email.color_attributes.includes(name) || name.endsWith("-color")) return "color"
    return "html_attribute"
  }
  const element = [...ancestors].reverse().find((item) => item.type === "HtmlElement")
  if (elementName(element) === "mj-style") return "css"
  return "html_text"
}

function structuralContext(ancestors: AstNode[]): boolean {
  const element = [...ancestors].reverse().find((item) => item.type === "HtmlElement")
  return contract.profiles["email/mjml-liquid@1"].structural_elements.includes(elementName(element))
}

function variableName(node: AstNode): string {
  const expression = ((node.markup as JsonObject | undefined)?.expression ?? {}) as JsonObject
  const root = String(expression.name ?? "")
  const lookups = Array.isArray(expression.lookups)
    ? expression.lookups.map((item) => String((item as JsonObject).value ?? ""))
    : []
  return [root, ...lookups].filter(Boolean).join(".")
}

function rawLiquid(node: AstNode): string {
  return String((node.markup as JsonObject | undefined)?.rawSource ?? "")
}

function filtersOf(node: AstNode): string[] {
  const filters = (node.markup as JsonObject | undefined)?.filters
  return Array.isArray(filters)
    ? filters.map((item) => String((item as JsonObject).name ?? ""))
    : []
}

function flattenSchema(schema: JsonObject): Map<string, JsonObject> {
  const variables = optionalObject(schema.variables)
  const result = new Map<string, JsonObject>()
  for (const [name, value] of Object.entries(variables)) {
    if (value && typeof value === "object" && !Array.isArray(value))
      result.set(name, value as JsonObject)
  }
  return result
}

function schemaDefinition(schema: JsonObject, name: string): JsonObject | undefined {
  const variables = flattenSchema(schema)
  return variables.get(name) ?? variables.get(name.split(".")[0] ?? name)
}

function compatibleContext(declared: string, actual: string): boolean {
  if (declared === actual) return true
  if (declared === "text") return ["text", "html_text", "subject"].includes(actual)
  if (declared === "url") return actual === "text"
  if (declared === "html_attribute") return actual === "html_attribute"
  return false
}

function valueAt(values: JsonObject, path: string): unknown {
  let current: unknown = values
  for (const segment of path.split(".")) {
    if (!current || typeof current !== "object" || Array.isArray(current)) return undefined
    current = (current as JsonObject)[segment]
  }
  return current
}

function validateCompileValue(
  value: unknown,
  context: string,
): { ok: true; value: string } | { ok: false } {
  if (!["string", "number", "boolean"].includes(typeof value)) return { ok: false }
  const text = String(value)
  if (text.includes("\0") || /[{}<>]/.test(text)) return { ok: false }
  if (
    context === "color" &&
    !/^(#[0-9a-fA-F]{3,8}|[a-zA-Z]+|rgba?\([0-9., %]+\)|hsla?\([0-9., %]+\))$/.test(text)
  )
    return { ok: false }
  if (context === "css" && /[;{}]|url\s*\(/i.test(text)) return { ok: false }
  return { ok: true, value: context === "html_attribute" ? escapeAttribute(text) : text }
}

function escapeAttribute(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll('"', "&quot;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
}

function applyReplacements(
  source: string,
  replacements: { start: number; end: number; value: string }[],
): string {
  const sorted = [...replacements].sort((a, b) => b.start - a.start || b.end - a.end)
  let output = source
  let previousStart = source.length + 1
  for (const item of sorted) {
    if (item.end > previousStart) throw new Error("overlapping compiler replacements")
    output = `${output.slice(0, item.start)}${item.value}${output.slice(item.end)}`
    previousStart = item.start
  }
  return output
}

function sliceNode(node: AstNode, position: Position): string {
  return String(node.source ?? "").slice(position.start, position.end)
}

function findVariablePosition(uses: VariableUse[], name: string): Position {
  return uses.find((item) => item.name === name)?.position ?? { start: 0, end: 0 }
}

function parserDiagnostic(
  source: string,
  sourceHash: string,
  documentVersion: number,
  error: unknown,
): Diagnostic {
  const record = error && typeof error === "object" ? (error as JsonObject) : {}
  const loc = (record.loc ?? {}) as JsonObject
  const locStart = (loc.start ?? {}) as JsonObject
  const start = offsetForLineColumn(
    source,
    Number(locStart.line ?? record.line ?? 1),
    Number(locStart.column ?? record.column ?? 0),
  )
  return diagnostic(
    source,
    sourceHash,
    documentVersion,
    { start, end: start },
    "error",
    "LP_PARSE",
    "letterpress-parser",
    normalizeError(error),
    {},
  )
}

function diagnostic(
  source: string,
  sourceHash: string,
  documentVersion: number,
  position: Position,
  severity: Diagnostic["severity"],
  code: string,
  diagnosticSource: string,
  message: string,
  data: JsonObject,
): Diagnostic {
  return {
    version: 1,
    source_hash: sourceHash,
    document_version: documentVersion,
    range: { start: pointAt(source, position.start), end: pointAt(source, position.end) },
    severity,
    code,
    source: diagnosticSource,
    message,
    related: [],
    data,
  }
}

function pointAt(source: string, offset: number): { line: number; character: number } {
  const safe = Math.max(0, Math.min(source.length, offset))
  const prefix = source.slice(0, safe)
  const line = prefix.split("\n").length - 1
  const lastNewline = prefix.lastIndexOf("\n")
  return { line, character: safe - (lastNewline + 1) }
}

function lineRange(source: string, oneBasedLine: number): Position {
  const lines = source.split("\n")
  let start = 0
  for (let index = 0; index < Math.max(0, oneBasedLine - 1); index += 1)
    start += (lines[index]?.length ?? 0) + 1
  return { start, end: start + (lines[Math.max(0, oneBasedLine - 1)]?.length ?? 0) }
}

function offsetForLineColumn(source: string, oneBasedLine: number, column: number): number {
  return lineRange(source, oneBasedLine).start + Math.max(0, column)
}

function compilerVersions(): JsonObject {
  return { node: process.versions.node, mjml: "5.4.0", parser: "2.10.0" }
}

function sha256(value: string | Buffer): string {
  return createHash("sha256").update(value).digest("hex")
}

function requireString(value: unknown, name: string): string {
  if (typeof value !== "string") throw new Error(`${name} must be a string`)
  return value
}

function optionalString(value: unknown): string | null {
  if (value === null || value === undefined) return null
  return requireString(value, "subject")
}

function requireObject(value: unknown, name: string): JsonObject {
  if (!value || typeof value !== "object" || Array.isArray(value))
    throw new Error(`${name} must be an object`)
  return value as JsonObject
}

function optionalObject(value: unknown): JsonObject {
  return value && typeof value === "object" && !Array.isArray(value) ? (value as JsonObject) : {}
}

function optionalInteger(value: unknown, fallback: number): number {
  return Number.isInteger(value) ? Number(value) : fallback
}

function normalizeError(error: unknown): string {
  if (error instanceof Error) return error.message
  return "compiler request failed"
}
