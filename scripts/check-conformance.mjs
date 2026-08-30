import { readdir, readFile } from "node:fs/promises"
import { extname, join } from "node:path"

const source = await readJson("contract/letterpress-v1.json")
const generated = await readJson("generated/letterpress-v1.json")
const packaged = await readJson("priv/contract.json")
const fixtures = await readJson("conformance/fixtures.json")

assertDeepEqual(generated, packaged, "priv/contract.json")
assertSubset(source, generated, "generated/letterpress-v1.json")

if (fixtures.version !== 1 || !Array.isArray(fixtures.analysis) || fixtures.analysis.length === 0) {
  throw new Error("conformance fixture corpus is empty or has an unknown version")
}

const profileNames = Object.keys(generated.profiles).sort()
if (JSON.stringify(profileNames) !== JSON.stringify(["email/mjml-liquid@1", "text/liquid@1"])) {
  throw new Error(`unexpected profile set: ${profileNames.join(", ")}`)
}

const email = generated.profiles["email/mjml-liquid@1"]
assertExactKeys(email.element_metadata, email.elements, "MJML element metadata")
for (const element of email.structural_elements) {
  if (!Object.hasOwn(email.nesting, element)) {
    throw new Error(`structural element ${element} has no nesting rule`)
  }
}
for (const forbidden of email.forbidden_elements) {
  if (email.elements.includes(forbidden)) {
    throw new Error(`forbidden MJML element ${forbidden} is also enabled`)
  }
}

const diagnosticCodes = new Set(generated.diagnostic_codes)
for (const fixture of fixtures.analysis) {
  if (!generated.profiles[fixture.profile]) {
    throw new Error(`${fixture.name} uses an unknown profile`)
  }
  for (const channel of ["backend_codes", "browser_codes"]) {
    for (const code of fixture[channel] ?? []) {
      if (!diagnosticCodes.has(code)) {
        throw new Error(`${fixture.name} expects unregistered diagnostic ${code}`)
      }
    }
  }
}

const generatedTypeScript = await readFile("npm/language/src/generated/contract.ts", "utf8")
if (!generatedTypeScript.includes(`"contract_version": ${generated.contract_version}`)) {
  throw new Error("generated TypeScript contract has the wrong version")
}
for (const profile of profileNames) {
  if (!generatedTypeScript.includes(JSON.stringify(profile))) {
    throw new Error(`generated TypeScript contract is missing ${profile}`)
  }
}

const sourceFiles = [
  "compiler/worker.ts",
  ...(await sourceList("lib", [".ex"])),
  ...(await sourceList("npm", [".ts", ".svelte"])),
]
const usedCodes = new Set()
for (const file of sourceFiles) {
  const contents = await readFile(file, "utf8")
  for (const match of contents.matchAll(/\bLP_[A-Z0-9_]*[A-Z0-9]\b/g)) usedCodes.add(match[0])
}
for (const code of usedCodes) {
  if (!diagnosticCodes.has(code) && code !== "LP_TEST") {
    throw new Error(`${code} is used in source but absent from the generated contract`)
  }
}

console.log(
  `Conformance contract is aligned: ${profileNames.length} profiles, ${email.elements.length} MJML elements, ${diagnosticCodes.size} diagnostics, ${fixtures.analysis.length} shared fixtures.`,
)

async function readJson(path) {
  return JSON.parse(await readFile(path, "utf8"))
}

function assertDeepEqual(left, right, label) {
  if (JSON.stringify(left) !== JSON.stringify(right)) {
    throw new Error(`${label} differs from contract/letterpress-v1.json; regenerate contracts`)
  }
}

function assertSubset(expected, actual, label, path = "contract") {
  if (Array.isArray(expected) || expected === null || typeof expected !== "object") {
    if (JSON.stringify(expected) !== JSON.stringify(actual)) {
      throw new Error(`${label} changed source field ${path}`)
    }
    return
  }
  if (actual === null || typeof actual !== "object" || Array.isArray(actual)) {
    throw new Error(`${label} is missing source object ${path}`)
  }
  for (const [key, value] of Object.entries(expected)) {
    assertSubset(value, actual[key], label, `${path}.${key}`)
  }
}

function assertExactKeys(object, expected, label) {
  const actual = Object.keys(object).sort()
  const wanted = [...expected].sort()
  if (JSON.stringify(actual) !== JSON.stringify(wanted)) {
    throw new Error(`${label} keys do not match the enabled element registry`)
  }
}

async function sourceList(root, extensions) {
  const entries = await readdir(root, { withFileTypes: true }).catch(() => [])
  const files = []
  for (const entry of entries) {
    const child = join(root, entry.name)
    if (entry.isDirectory()) files.push(...(await sourceList(child, extensions)))
    else if (extensions.includes(extname(child))) files.push(child)
  }
  return files
}
