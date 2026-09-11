import { createHash } from "node:crypto"
import process from "node:process"
import { toLiquidHtmlAST } from "@shopify/liquid-html-parser"
import liquidPlugin from "@shopify/prettier-plugin-liquid"
import mjml2html from "mjml"
import prettier from "prettier"
import contract from "../generated/letterpress-v1.json"
import { inspectSentinelOutput } from "./sentinel"

type JsonObject = Readonly<Record<string, unknown>>
type Position = Readonly<{ start: number; end: number }>
type Replacement = Readonly<Position & { value: string }>
type AstNode = JsonObject & {
  readonly type?: string
  readonly name?: unknown
  readonly position?: Position
  readonly blockStartPosition?: Position
  readonly blockEndPosition?: Position
}

export interface Request {
  readonly id: string
  readonly operation:
    | "discover"
    | "analyze"
    | "compile"
    | "format"
    | "apply_translations"
    | "contract"
  readonly payload?: JsonObject
}

interface Diagnostic {
  readonly version: 1
  readonly source_hash: string
  readonly document_version: number
  readonly range: {
    readonly start: { line: number; character: number }
    readonly end: { line: number; character: number }
  }
  readonly severity: "error" | "warning" | "information" | "hint"
  readonly code: string
  readonly source: string
  readonly message: string
  readonly related: readonly never[]
  readonly data: JsonObject
}

interface VariableUse {
  readonly name: string
  readonly context: string
  readonly position: Position
  readonly raw: string
  readonly filters: readonly string[]
  readonly local: boolean
  readonly binding?: {
    readonly name: string
    readonly collection: string
  }
  readonly outputContexts: readonly string[]
}

interface VariableDependency {
  readonly name: string
  readonly context: "none"
  readonly position: Position
  readonly kind: "condition" | "collection" | "lookup"
  readonly local: boolean
  readonly binding?: VariableUse["binding"]
}

interface Analysis {
  readonly ast: AstNode
  readonly diagnostics: readonly Diagnostic[]
  readonly variables: readonly VariableUse[]
  readonly dependencies: readonly VariableDependency[]
  readonly tags: readonly Readonly<{ name: string; position: Position; structural: boolean }>[]
  readonly translation_units: readonly JsonObject[]
}

interface ChannelAnalyses {
  readonly source: Analysis
  readonly subject: Analysis | null
  readonly text: Analysis | null
}

interface Sentinel {
  readonly raw: string
  readonly sourceContext: string
  readonly outputContexts: readonly string[]
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
export const dispatch = async (request: Request): Promise<JsonObject> => {
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

const discoverPayload = (payload: JsonObject): JsonObject => {
  const profile = requireString(payload.profile, "profile")
  const source = requireString(payload.source, "source")
  const documentVersion = optionalInteger(payload.document_version, 0)
  const analysis = analyze(profile, source, {}, documentVersion, undefined, false, false)
  return publicAnalysis(analysis)
}

const analyzePayload = (payload: JsonObject): JsonObject => {
  const profile = requireString(payload.profile, "profile")
  const source = requireString(payload.source, "source")
  const subject = optionalString(payload.subject)
  const text = optionalString(payload.text)
  const schema = requireObject(payload.schema, "schema")
  const documentVersion = optionalInteger(payload.document_version, 0)
  const analyses = analyzeChannels(profile, source, subject, text, schema, documentVersion)
  return publicAnalysis(mergeChannelAnalyses(analyses, schema, source, documentVersion))
}

const compilePayload = async (payload: JsonObject): Promise<JsonObject> => {
  const profile = requireString(payload.profile, "profile")
  const source = requireString(payload.source, "source")
  const subject = optionalString(payload.subject)
  const text = optionalString(payload.text)
  const schema = requireObject(payload.schema, "schema")
  const compileValues = optionalObject(payload.compile_values)
  const compileNumbers = optionalObject(payload.compile_numbers)
  const documentVersion = optionalInteger(payload.document_version, 0)
  const analyses = analyzeChannels(profile, source, subject, text, schema, documentVersion)
  const analysis = analyses.source
  const subjectAnalysis = analyses.subject
  const textAnalysis = analyses.text
  const mergedAnalysis = mergeChannelAnalyses(analyses, schema, source, documentVersion)
  const initialDiagnostics = mergedAnalysis.diagnostics

  if (initialDiagnostics.some((item) => item.severity === "error")) {
    return { diagnostics: initialDiagnostics, analysis: publicAnalysis(mergedAnalysis) }
  }

  const sourceHash = sha256(source)
  const prepared = prepareSource(
    source,
    analysis,
    schema,
    compileValues,
    compileNumbers,
    sourceHash,
    documentVersion,
  )
  const preparedSubject = prepareAuxiliary(
    subject,
    subjectAnalysis,
    schema,
    compileValues,
    compileNumbers,
    documentVersion,
  )
  const preparedText = prepareAuxiliary(
    text,
    textAnalysis,
    schema,
    compileValues,
    compileNumbers,
    documentVersion,
  )
  const diagnostics = [
    ...initialDiagnostics,
    ...prepared.diagnostics,
    ...preparedSubject.diagnostics,
    ...preparedText.diagnostics,
  ]
  if (diagnostics.some((item) => item.severity === "error")) {
    return { diagnostics, analysis: publicAnalysis(mergedAnalysis) }
  }

  if (profile === "text/liquid@1") {
    return {
      diagnostics,
      analysis: publicAnalysis(mergedAnalysis),
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

  if (profile === "html/liquid@1") {
    const restored = restoreSentinels(
      prepared.source,
      prepared.sentinels,
      source,
      sourceHash,
      documentVersion,
      true,
    )

    return {
      diagnostics: [...diagnostics, ...restored.diagnostics],
      analysis: publicAnalysis(mergedAnalysis),
      compiled: {
        html: restored.output,
        text: null,
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
        analysis: publicAnalysis(mergedAnalysis),
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
      analysis: publicAnalysis(mergedAnalysis),
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
      analysis: publicAnalysis(mergedAnalysis),
    }
  }
}

const formatPayload = async (payload: JsonObject): Promise<JsonObject> => {
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

const applyTranslationsPayload = (payload: JsonObject): JsonObject => {
  const profile = requireString(payload.profile, "profile")
  const source = requireString(payload.source, "source")
  const subject = optionalString(payload.subject)
  const text = optionalString(payload.text)
  const schema = requireObject(payload.schema, "schema")
  const translations = requireObject(payload.translations, "translations")
  const documentVersion = optionalInteger(payload.document_version, 0)
  const analyses = analyzeChannels(profile, source, subject, text, schema, documentVersion)
  const mergedAnalysis = mergeChannelAnalyses(analyses, schema, source, documentVersion)
  const sourceResult = applyChannelTranslations(
    source,
    analyses.source,
    translations,
    documentVersion,
  )
  const subjectResult = applyOptionalChannelTranslations(
    subject,
    analyses.subject,
    translations,
    documentVersion,
  )
  const textResult = applyOptionalChannelTranslations(
    text,
    analyses.text,
    translations,
    documentVersion,
  )
  const diagnostics = [
    ...mergedAnalysis.diagnostics,
    ...sourceResult.diagnostics,
    ...subjectResult.diagnostics,
    ...textResult.diagnostics,
  ]
  const failed = diagnostics.some((item) => item.severity === "error")

  return {
    source: failed ? source : sourceResult.source,
    subject: failed ? subject : subjectResult.source,
    text: failed ? text : textResult.source,
    diagnostics,
  }
}

const applyOptionalChannelTranslations = (
  source: string | null,
  analysis: Analysis | null,
  translations: JsonObject,
  documentVersion: number,
): Readonly<{ source: string | null; diagnostics: readonly Diagnostic[] }> => {
  if (source === null || analysis === null) return { source: null, diagnostics: [] }
  return applyChannelTranslations(source, analysis, translations, documentVersion)
}

const applyChannelTranslations = (
  source: string,
  analysis: Analysis,
  translations: JsonObject,
  documentVersion: number,
): Readonly<{ source: string; diagnostics: readonly Diagnostic[] }> => {
  const sourceHash = sha256(source)
  const diagnostics: Diagnostic[] = []
  const replacements: Replacement[] = []
  let outputBytes = Buffer.byteLength(source, "utf8")

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
    if (
      translated.includes("\0") ||
      (unit.context === "subject" && /[\r\n]/.test(translated)) ||
      encoder.encode(translated).length > contract.limits.source_bytes
    ) {
      diagnostics.push(
        diagnostic(
          source,
          sourceHash,
          documentVersion,
          range,
          "error",
          "LP_TRANSLATION_PLACEHOLDER",
          "letterpress-translation",
          "Translation is invalid for its output context or byte limit",
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
    const value =
      unit.context === "html_attribute" ? escapeTranslatedAttribute(translated) : translated
    outputBytes +=
      Buffer.byteLength(value, "utf8") -
      Buffer.byteLength(source.slice(range.start, range.end), "utf8")
    replacements.push({ ...range, value })
  }

  if (outputBytes > contract.limits.source_bytes) {
    diagnostics.push(
      diagnostic(
        source,
        sourceHash,
        documentVersion,
        { start: 0, end: 0 },
        "error",
        "LP_SOURCE_TOO_LARGE",
        "letterpress-translation",
        "Localized source exceeds the profile byte limit",
        {},
      ),
    )
  }

  return {
    source: diagnostics.some((item) => item.severity === "error")
      ? source
      : applyReplacements(source, replacements),
    diagnostics,
  }
}

const translationText = (value: unknown): string | null => {
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

const liquidSignature = (source: string): string[] => {
  try {
    const ast = toLiquidHtmlAST(source, {
      mode: "strict",
      allowUnclosedDocumentNode: false,
    }) as unknown as AstNode
    const signature: string[] = []
    walk(ast, [], (node, ancestors) => {
      if (node.type === "LiquidVariableOutput") {
        signature.push(`output:${sliceOptionalNode(node, node.position)}`)
      }
      if (liquidTagTypes.has(String(node.type))) {
        signature.push(`tag-open:${sliceOptionalNode(node, node.blockStartPosition)}`)
        signature.push(`tag-close:${sliceOptionalNode(node, node.blockEndPosition)}`)
      }
      if (node.type === "LiquidBranch" && node.name !== null) {
        signature.push(`branch:${sliceOptionalNode(node, node.blockStartPosition)}`)
      }
      if (htmlElementTypes.has(String(node.type))) {
        const path = [...ancestors, node]
          .filter((item) => htmlElementTypes.has(String(item.type)))
          .map(elementName)
          .join("/")
        signature.push(`element:${path}:open:${sliceOptionalNode(node, node.blockStartPosition)}`)
        signature.push(`element:${path}:close:${sliceOptionalNode(node, node.blockEndPosition)}`)
      }
    })
    return signature
  } catch {
    return ["invalid"]
  }
}

const analyze = (
  profile: string,
  source: string,
  schema: JsonObject,
  documentVersion: number,
  contextOverride?: string,
  reportUnused = true,
  validateSchema = true,
): Analysis => {
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
      for (const item of validateElement(
        node,
        ancestors,
        source,
        sourceHash,
        documentVersion,
        profileData,
      ))
        diagnostics.push(item)
      if (profile === "email/mjml-liquid@1") {
        for (const unit of collectTranslationUnit(node, ancestors, source, sourceHash))
          translationUnits.push(unit)
      }
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
      for (const item of validateLiquidUse(
        name,
        context,
        filters,
        node,
        schema,
        source,
        sourceHash,
        documentVersion,
      ))
        diagnostics.push(item)
    }
    if (liquidTagTypes.has(String(node.type))) {
      const name = String(node.name ?? "")
      const structural = structuralContext(ancestors, profile)
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
    for (const unit of collectTextTranslationUnit(ast, source, sourceHash))
      translationUnits.push(unit)
  }
  if (profile === "html/liquid@1") {
    for (const unit of collectHtmlTranslationUnit(ast, source, sourceHash))
      translationUnits.push(unit)
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
    for (const dependency of dependencies) {
      if (!dependency.local && schemaDefinition(schema, dependency.name)?.phase === "compile") {
        diagnostics.push(
          diagnostic(
            source,
            sourceHash,
            documentVersion,
            dependency.position,
            "error",
            "LP_SCHEMA_PHASE_MISMATCH",
            "letterpress-schema",
            "Liquid conditions, collections, and filter arguments require delivery-phase values",
            { variable: dependency.name },
          ),
        )
      }
    }
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

const analyzeChannels = (
  profile: string,
  source: string,
  subject: string | null,
  text: string | null,
  schema: JsonObject,
  documentVersion: number,
): ChannelAnalyses => {
  const sourceAnalysis = analyze(profile, source, schema, documentVersion, undefined, false)
  if (profile !== "email/mjml-liquid@1") {
    return { source: sourceAnalysis, subject: null, text: null }
  }

  return {
    source: channelizeTranslationUnits(sourceAnalysis, profile, "html"),
    subject:
      subject === null
        ? null
        : channelizeTranslationUnits(
            analyze("text/liquid@1", subject, schema, documentVersion, "subject", false),
            profile,
            "subject",
          ),
    text:
      text === null
        ? null
        : channelizeTranslationUnits(
            analyze("text/liquid@1", text, schema, documentVersion, undefined, false),
            profile,
            "text",
          ),
  }
}

const channelizeTranslationUnits = (
  analysis: Analysis,
  profile: string,
  channel: "html" | "subject" | "text",
): Analysis => ({
  ...analysis,
  translation_units: analysis.translation_units.map((unit) => ({
    ...unit,
    id: sha256(`${profile}\0${channel}\0${String(unit.id ?? "")}`).slice(0, 24),
    channel,
    context: channel === "subject" ? "subject" : unit.context,
  })),
})

const mergeChannelAnalyses = (
  analyses: ChannelAnalyses,
  schema: JsonObject,
  source: string,
  documentVersion: number,
): Analysis => {
  const present = [analyses.source, analyses.subject, analyses.text].filter(
    (analysis): analysis is Analysis => analysis !== null,
  )

  return {
    ast: analyses.source.ast,
    diagnostics: [
      ...present.flatMap((analysis) => analysis.diagnostics),
      ...unusedSchemaDiagnostics(present, schema, source, documentVersion),
    ],
    variables: present.flatMap((analysis) => analysis.variables),
    dependencies: present.flatMap((analysis) => analysis.dependencies),
    tags: present.flatMap((analysis) => analysis.tags),
    translation_units: present.flatMap((analysis) => analysis.translation_units),
  }
}

const unusedSchemaDiagnostics = (
  analyses: readonly (Analysis | null)[],
  schema: JsonObject,
  source: string,
  documentVersion: number,
): Diagnostic[] => {
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

const validateElement = (
  node: AstNode,
  ancestors: readonly AstNode[],
  source: string,
  sourceHash: string,
  documentVersion: number,
  profile: JsonObject | undefined,
): readonly Diagnostic[] => {
  const diagnostics: Diagnostic[] = []
  if (profile?.kind === "html") {
    return validateEmbeddedHtml(node, source, sourceHash, documentVersion)
  }
  if (profile?.kind !== "email") return diagnostics
  const name = elementName(node)
  if (name !== "mjml" && !name.startsWith("mj-")) {
    return validateEmbeddedHtml(node, source, sourceHash, documentVersion)
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

  return [
    ...diagnostics,
    ...validateNesting(node, ancestors, source, sourceHash, documentVersion, profile),
    ...validateAttributes(node, source, sourceHash, documentVersion, profile),
  ]
}

const validateEmbeddedHtml = (
  node: AstNode,
  source: string,
  sourceHash: string,
  documentVersion: number,
): readonly Diagnostic[] => {
  const diagnostics: Diagnostic[] = []
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
        `HTML element ${name} is not allowed`,
        { element: name },
      ),
    )
    return diagnostics
  }

  const allowed = new Set([
    ...policy.global_attributes,
    ...((policy.attributes as Record<string, string[]>)[name] ?? []),
  ])
  const attributes = Array.isArray(node.attributes) ? (node.attributes as readonly AstNode[]) : []
  for (const attribute of attributes) {
    const attributeNameValue = attributeName(attribute)
    const range = (attribute.attributePosition as Position | undefined) ??
      attribute.position ??
      node.position ?? { start: 0, end: 0 }
    if (!attributeNameValue) {
      diagnostics.push(
        diagnostic(
          source,
          sourceHash,
          documentVersion,
          range,
          "error",
          "LP_HTML_ATTRIBUTE_FORBIDDEN",
          "letterpress-html",
          `Dynamic HTML attributes are not allowed on ${name}`,
          { attribute: "dynamic", element: name },
        ),
      )
      continue
    }
    const allowedDataAttribute =
      attributeNameValue.startsWith("data-") && /^data-[a-z0-9_.:-]+$/.test(attributeNameValue)
    if (
      attributeNameValue.startsWith("on") ||
      (!allowed.has(attributeNameValue) && !allowedDataAttribute)
    ) {
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
    } else if (policy.url_attributes.includes(attributeNameValue) && !safeUrlAttribute(attribute)) {
      diagnostics.push(
        diagnostic(
          source,
          sourceHash,
          documentVersion,
          range,
          "error",
          "LP_HTML_ATTRIBUTE_FORBIDDEN",
          "letterpress-html",
          `HTML attribute ${attributeNameValue} contains an unsafe static URL`,
          { attribute: attributeNameValue, element: name },
        ),
      )
    }
  }
  return diagnostics
}

const validateNesting = (
  node: AstNode,
  ancestors: readonly AstNode[],
  source: string,
  sourceHash: string,
  documentVersion: number,
  profile: JsonObject,
): readonly Diagnostic[] => {
  const diagnostics: Diagnostic[] = []
  const parent = [...ancestors].reverse().find((item) => htmlElementTypes.has(String(item.type)))
  const parentName = elementName(parent)
  const name = elementName(node)
  if (!parentName || !name) return diagnostics
  const dependencies = (profile.nesting as JsonObject | undefined)?.[parentName]
  if (!Array.isArray(dependencies)) return diagnostics
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
  return diagnostics
}

const validateAttributes = (
  node: AstNode,
  source: string,
  sourceHash: string,
  documentVersion: number,
  profile: JsonObject,
): readonly Diagnostic[] => {
  const diagnostics: Diagnostic[] = []
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
  const attributes = Array.isArray(node.attributes) ? (node.attributes as readonly AstNode[]) : []
  for (const attribute of attributes) {
    const attributeNameValue = attributeName(attribute)
    if (!attributeNameValue) continue
    if (
      attributeNameValue.startsWith("on") ||
      attributeNameValue === "style" ||
      !allowed.has(attributeNameValue) ||
      (contract.profiles["email/mjml-liquid@1"].url_attributes.includes(attributeNameValue) &&
        !safeUrlAttribute(attribute))
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
  return diagnostics
}

const validateLiquidUse = (
  name: string,
  context: string,
  filters: readonly string[],
  node: AstNode,
  schema: JsonObject,
  source: string,
  sourceHash: string,
  documentVersion: number,
): readonly Diagnostic[] => {
  const diagnostics: Diagnostic[] = []
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
  if (!definition) return diagnostics
  const phase = String(definition.phase ?? "delivery")
  const declaredContext = String(definition.context ?? "none")
  if (phase === "compile" && filters.length > 0) {
    diagnostics.push(
      diagnostic(
        source,
        sourceHash,
        documentVersion,
        node.position ?? { start: 0, end: 0 },
        "error",
        "LP_SCHEMA_PHASE_MISMATCH",
        "letterpress-schema",
        "Compile-phase outputs do not support Liquid filters",
        { variable: name },
      ),
    )
  }
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
  return diagnostics
}

const prepareSource = (
  source: string,
  analysis: Analysis,
  schema: JsonObject,
  compileValues: JsonObject,
  compileNumbers: JsonObject,
  sourceHash: string,
  documentVersion: number,
): Readonly<{
  source: string
  sentinels: ReadonlyMap<string, Sentinel>
  diagnostics: readonly Diagnostic[]
  sourceMap: JsonObject
}> => {
  const replacements: Replacement[] = []
  const sentinels = new Map<string, Sentinel>()
  const diagnostics: Diagnostic[] = []
  const sourceMap: Record<string, unknown> = {}

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
      const numberText = Object.hasOwn(compileNumbers, use.name)
        ? compileNumbers[use.name]
        : undefined
      const validated = validateCompileValue(resolved, use.context, numberText)
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

  return {
    source: applyReplacements(source, [
      ...replacements,
      ...structuralTagReplacements(analysis.ast),
    ]),
    sentinels,
    diagnostics,
    sourceMap,
  }
}

const structuralTagReplacements = (ast: AstNode): readonly Replacement[] => {
  const replacements: Replacement[] = []
  walk(ast, [], (node, ancestors) => {
    if (
      !liquidTagTypes.has(String(node.type)) ||
      !structuralContext(ancestors, "email/mjml-liquid@1")
    )
      return
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
  return replacements
}

const restoreSentinels = (
  output: string,
  sentinels: ReadonlyMap<string, Sentinel>,
  source: string,
  sourceHash: string,
  documentVersion: number,
  verifyOutputContext = false,
): Readonly<{ output: string; diagnostics: readonly Diagnostic[] }> => {
  const diagnostics: Diagnostic[] = []
  let restored = output
  const inspection = verifyOutputContext
    ? inspectSentinelOutput(
        output,
        new Map([...sentinels].map(([token, sentinel]) => [token, sentinel.outputContexts])),
      )
    : null
  const contextIssues = new Map((inspection?.issues ?? []).map((issue) => [issue.token, issue]))
  const replacements: Replacement[] = []

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
          () => `{{ ${sentinel.raw} | letterpress_escape: "${sentinel.sourceContext}" }}`,
        )
      }
    }
  }
  if (verifyOutputContext && diagnostics.length === 0)
    restored = applyReplacements(output, replacements)
  return { output: restored, diagnostics }
}

const compilerOutputContexts = (context: string, ancestors: readonly AstNode[]): string[] => {
  const element = [...ancestors].reverse().find((ancestor) => ancestor.type === "HtmlElement")
  if (elementName(element) === "mj-title") return ["html_text", "html_attribute"]
  return [context]
}

const prepareAuxiliary = (
  source: string | null,
  analysis: Analysis | null,
  schema: JsonObject,
  compileValues: JsonObject,
  compileNumbers: JsonObject,
  documentVersion: number,
): Readonly<{
  output: string | null
  diagnostics: readonly Diagnostic[]
  sourceMap: JsonObject
}> => {
  if (source === null || analysis === null) return { output: null, diagnostics: [], sourceMap: {} }
  const sourceHash = sha256(source)
  const prepared = prepareSource(
    source,
    analysis,
    schema,
    compileValues,
    compileNumbers,
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

const publicAnalysis = (analysis: Analysis): JsonObject => ({
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
})

const collectTranslationUnit = (
  node: AstNode,
  ancestors: readonly AstNode[],
  source: string,
  sourceHash: string,
): readonly JsonObject[] => {
  const units: JsonObject[] = []
  const name = elementName(node)
  const profile = contract.profiles["email/mjml-liquid@1"]
  const path = structuralPath(node, ancestors)
  if (ancestors.some((ancestor) => profile.text_elements.includes(elementName(ancestor))))
    return units
  for (const unit of collectAttributeTranslationUnits(node, path, source, sourceHash))
    units.push(unit)
  if (!profile.text_elements.includes(name)) return units
  const children = childrenOf(node)
  if (children.length === 0) return units
  const start = children[0]?.position?.start
  const end = children.at(-1)?.position?.end
  if (start === undefined || end === undefined) return units
  const text = source.slice(start, end)
  if (text.trim() === "") return units
  units.push({
    id: sha256(`${path}\0${text}`).slice(0, 24),
    context: "html_text",
    source: text,
    range: { start, end },
    source_hash: sourceHash,
  })
  return units
}

const structuralPath = (node: AstNode, ancestors: readonly AstNode[]): string =>
  [...ancestors, node]
    .map((entry, index, trail) => {
      const parent = trail[index - 1]
      const siblingIndex = parent ? childrenOf(parent).indexOf(entry) : 0
      return `${elementName(entry) || entry.type}[${siblingIndex}]`
    })
    .join("/")

const collectAttributeTranslationUnits = (
  node: AstNode,
  path: string,
  source: string,
  sourceHash: string,
): readonly JsonObject[] => {
  const units: JsonObject[] = []
  const attributes = Array.isArray(node.attributes) ? (node.attributes as readonly AstNode[]) : []
  for (const attribute of attributes) {
    const name = attributeName(attribute)
    if (!contract.profiles["email/mjml-liquid@1"].translation_attributes.includes(name)) continue
    const values = Array.isArray(attribute.value) ? (attribute.value as readonly AstNode[]) : []
    if (!values.some((value) => value.type === "TextNode" && String(value.value ?? "").trim()))
      continue
    const start = values[0]?.position?.start
    const end = values.at(-1)?.position?.end
    if (start === undefined || end === undefined) continue
    const text = source.slice(start, end)
    units.push({
      id: sha256(`${path}\0@${name}\0${text}`).slice(0, 24),
      context: "html_attribute",
      source: text,
      range: { start, end },
      source_hash: sourceHash,
    })
  }
  return units
}

const escapeTranslatedAttribute = (source: string): string => {
  const ast = toLiquidHtmlAST(source, {
    mode: "strict",
    allowUnclosedDocumentNode: false,
  }) as unknown as AstNode
  const replacements: Replacement[] = []
  walk(ast, [], (node) => {
    if (node.type === "TextNode" && node.position) {
      replacements.push({
        ...node.position,
        value: source
          .slice(node.position.start, node.position.end)
          .replace(/&(?!(?:#\d+|#x[\da-f]+|[a-z][a-z\d]+);)/gi, "&amp;")
          .replace(/</g, "&lt;")
          .replace(/>/g, "&gt;")
          .replace(/"/g, "&quot;")
          .replace(/'/g, "&#39;"),
      })
    }
  })
  return applyReplacements(source, replacements)
}

const collectTextTranslationUnit = (
  ast: AstNode,
  source: string,
  sourceHash: string,
): readonly JsonObject[] => {
  const units: JsonObject[] = []
  let hasHumanText = false

  walk(ast, [], (node) => {
    if (node.type === "TextNode" && String(node.value ?? "").trim() !== "") {
      hasHumanText = true
    }
  })

  if (!hasHumanText) return units

  units.push({
    id: sha256(`text/liquid@1\0text\0${source}`).slice(0, 24),
    context: "text",
    source,
    range: { start: 0, end: source.length },
    source_hash: sourceHash,
  })
  return units
}

const collectHtmlTranslationUnit = (
  ast: AstNode,
  source: string,
  sourceHash: string,
): readonly JsonObject[] => {
  const units: JsonObject[] = []
  let hasHumanText = false

  walk(ast, [], (node) => {
    if (node.type === "TextNode" && String(node.value ?? "").trim() !== "") {
      hasHumanText = true
    }
  })

  if (!hasHumanText) return units

  units.push({
    id: sha256(`html/liquid@1\0html\0${source}`).slice(0, 24),
    context: "html_text",
    source,
    range: { start: 0, end: source.length },
    source_hash: sourceHash,
  })
  return units
}

const walk = (
  node: AstNode,
  ancestors: readonly AstNode[],
  visit: (node: AstNode, ancestors: readonly AstNode[], edge: string) => void,
  edge = "root",
): void => {
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

const lookupDependencies = (ast: AstNode): VariableDependency[] => {
  const dependencies = new Map<string, VariableDependency>()
  walk(ast, [], (node, ancestors) => {
    if (node.type === "VariableLookup") {
      const root = String(node.name ?? "")
      const lookups = Array.isArray(node.lookups)
        ? node.lookups.map((item) => String((item as JsonObject).value ?? ""))
        : []
      const name = [root, ...lookups].filter(Boolean).join(".")
      const parent = ancestors.at(-1)
      const output = parent?.type === "LiquidVariable" && parent.expression === node
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

const dependencyKind = (
  node: AstNode,
  ancestors: readonly AstNode[],
): VariableDependency["kind"] => {
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

const localBinding = (
  name: string,
  ancestors: readonly AstNode[],
): VariableUse["binding"] | undefined => {
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

const localVariable = (name: string, ancestors: readonly AstNode[]): boolean =>
  liquidInternalVariable(name, ancestors) || localBinding(name, ancestors) !== undefined

const liquidInternalVariable = (name: string, ancestors: readonly AstNode[]): boolean => {
  if (name.split(".")[0] === "forloop") {
    return ancestors.some(
      (ancestor, index) =>
        ancestor.type === "LiquidTag" &&
        ancestor.name === "for" &&
        childrenOf(ancestor).includes(ancestors[index + 1] as AstNode),
    )
  }
  return (
    name.split(".")[0] === "continue" &&
    ancestors.some((ancestor) => ancestor.type === "NamedArgument" && ancestor.name === "offset")
  )
}

const childrenOf = (node: AstNode): readonly AstNode[] =>
  Array.isArray(node.children) ? (node.children as readonly AstNode[]) : []

const elementName = (node: AstNode | undefined): string => {
  if (!node) return ""
  if (typeof node.name === "string") return node.name
  if (!Array.isArray(node.name)) return ""
  return String((node.name[0] as JsonObject | undefined)?.value ?? "")
}

const attributeName = (node: AstNode | undefined): string => elementName(node)

const safeUrlAttribute = (attribute: AstNode): boolean => {
  const values = Array.isArray(attribute.value) ? (attribute.value as readonly AstNode[]) : []
  if (values.some((value) => value.type !== "TextNode")) {
    return values.length === 1 && values[0]?.type === "LiquidVariableOutput"
  }
  const value = values
    .map((item) => String(item.value ?? ""))
    .join("")
    .trim()
  return value === "" || safeUrl(value)
}

const safeUrl = (value: string): boolean => {
  if (value === "" || /[\0-\x20\x7f\\]/.test(value)) return false
  if (value.startsWith("//")) return false
  if (value.startsWith("/") || value.startsWith("#") || value.startsWith("?")) return true
  if (/^(?:https?|mailto|tel|cid):/i.test(value)) return true
  const leadingSegment = value.split(/[/?#]/, 1)[0] ?? ""
  return !/[:&]/.test(leadingSegment)
}

const contextFor = (
  _node: AstNode,
  ancestors: readonly AstNode[],
  edge: string,
  profile: string,
): string => {
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

const structuralContext = (ancestors: readonly AstNode[], profile: string): boolean => {
  if (profile !== "email/mjml-liquid@1") return false
  const element = [...ancestors].reverse().find((item) => item.type === "HtmlElement")
  return contract.profiles["email/mjml-liquid@1"].structural_elements.includes(elementName(element))
}

const variableName = (node: AstNode): string => {
  const expression = ((node.markup as JsonObject | undefined)?.expression ?? {}) as JsonObject
  const root = String(expression.name ?? "")
  const lookups = Array.isArray(expression.lookups)
    ? expression.lookups.map((item) => String((item as JsonObject).value ?? ""))
    : []
  return [root, ...lookups].filter(Boolean).join(".")
}

const rawLiquid = (node: AstNode): string =>
  String((node.markup as JsonObject | undefined)?.rawSource ?? "")

const filtersOf = (node: AstNode): string[] => {
  const filters = (node.markup as JsonObject | undefined)?.filters
  return Array.isArray(filters)
    ? filters.map((item) => String((item as JsonObject).name ?? ""))
    : []
}

const flattenSchema = (schema: JsonObject): Map<string, JsonObject> => {
  const variables = optionalObject(schema.variables)
  const result = new Map<string, JsonObject>()
  for (const [name, value] of Object.entries(variables)) {
    if (value && typeof value === "object" && !Array.isArray(value))
      result.set(name, value as JsonObject)
  }
  return result
}

const schemaDefinition = (schema: JsonObject, name: string): JsonObject | undefined => {
  const variables = optionalObject(schema.variables)
  const root = name.split(".")[0] ?? name
  const key = Object.hasOwn(variables, name) ? name : root
  return Object.hasOwn(variables, key) ? (variables[key] as JsonObject) : undefined
}

const compatibleContext = (declared: string, actual: string): boolean => {
  if (declared === actual) return true
  if (declared === "text")
    return ["text", "html_text", "html_attribute", "subject"].includes(actual)
  if (declared === "url") return ["url", "text", "html_text", "subject"].includes(actual)
  if (declared === "color") return ["color", "css"].includes(actual)
  if (declared === "html_attribute") return actual === "html_attribute"
  return false
}

const valueAt = (values: JsonObject, path: string): unknown => {
  let current: unknown = values
  for (const segment of path.split(".")) {
    if (
      !current ||
      typeof current !== "object" ||
      Array.isArray(current) ||
      !Object.hasOwn(current, segment)
    )
      return undefined
    current = (current as JsonObject)[segment]
  }
  return current
}

const validateCompileValue = (
  value: unknown,
  context: string,
  numberText?: unknown,
): { ok: true; value: string } | { ok: false } => {
  if (!["string", "number", "boolean"].includes(typeof value)) return { ok: false }
  const text =
    typeof value === "number" && typeof numberText === "string" ? numberText : String(value)
  if (text.includes("\0") || /[{}<>]/.test(text)) return { ok: false }
  if (
    context === "color" &&
    !/^(#[0-9a-fA-F]{3,8}|[a-zA-Z]+|rgba?\([0-9., %]+\)|hsla?\([0-9., %]+\))$/.test(text)
  )
    return { ok: false }
  if (context === "css" && /[;{}]|url\s*\(/i.test(text)) return { ok: false }
  if (context === "url" && !safeUrl(text)) return { ok: false }
  if (context === "subject" && /[\r\n]/.test(text)) return { ok: false }
  return {
    ok: true,
    value: ["html_attribute", "url"].includes(context) ? escapeAttribute(text) : text,
  }
}

const escapeAttribute = (value: string): string =>
  value
    .replaceAll("&", "&amp;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")

const applyReplacements = (source: string, replacements: readonly Replacement[]): string => {
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

const sliceNode = (node: AstNode, position: Position): string =>
  String(node.source ?? "").slice(position.start, position.end)

const sliceOptionalNode = (node: AstNode, position: Position | undefined): string =>
  position === undefined ? "" : sliceNode(node, position)

const findVariablePosition = (uses: readonly VariableUse[], name: string): Position =>
  uses.find((item) => item.name === name)?.position ?? { start: 0, end: 0 }

const parserDiagnostic = (
  source: string,
  sourceHash: string,
  documentVersion: number,
  error: unknown,
): Diagnostic => {
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

const diagnostic = (
  source: string,
  sourceHash: string,
  documentVersion: number,
  position: Position,
  severity: Diagnostic["severity"],
  code: string,
  diagnosticSource: string,
  message: string,
  data: JsonObject,
): Diagnostic => ({
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
})

const pointAt = (source: string, offset: number): { line: number; character: number } => {
  const safe = Math.max(0, Math.min(source.length, offset))
  const prefix = source.slice(0, safe)
  const line = prefix.split("\n").length - 1
  const lastNewline = prefix.lastIndexOf("\n")
  return { line, character: safe - (lastNewline + 1) }
}

const lineRange = (source: string, oneBasedLine: number): Position => {
  const lines = source.split("\n")
  let start = 0
  for (let index = 0; index < Math.max(0, oneBasedLine - 1); index += 1)
    start += (lines[index]?.length ?? 0) + 1
  return { start, end: start + (lines[Math.max(0, oneBasedLine - 1)]?.length ?? 0) }
}

const offsetForLineColumn = (source: string, oneBasedLine: number, column: number): number =>
  lineRange(source, oneBasedLine).start + Math.max(0, column)

const compilerVersions = (): JsonObject => ({
  node: process.versions.node,
  mjml: "5.4.0",
  parser: "2.10.0",
})

const sha256 = (value: string | Buffer): string => createHash("sha256").update(value).digest("hex")

const requireString = (value: unknown, name: string): string => {
  if (typeof value !== "string") throw new Error(`${name} must be a string`)
  return value
}

const optionalString = (value: unknown): string | null => {
  if (value === null || value === undefined) return null
  return requireString(value, "subject")
}

const requireObject = (value: unknown, name: string): JsonObject => {
  if (!value || typeof value !== "object" || Array.isArray(value))
    throw new Error(`${name} must be an object`)
  return value as JsonObject
}

const optionalObject = (value: unknown): JsonObject =>
  value && typeof value === "object" && !Array.isArray(value) ? (value as JsonObject) : {}

const optionalInteger = (value: unknown, fallback: number): number =>
  Number.isInteger(value) ? Number(value) : fallback

export const normalizeError = (error: unknown): string => {
  if (error instanceof Error) return error.message
  return "compiler request failed"
}
