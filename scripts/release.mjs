import { execFileSync, spawnSync } from "node:child_process"
import { createHash } from "node:crypto"
import {
  existsSync,
  mkdirSync,
  mkdtempSync,
  readdirSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs"
import { tmpdir } from "node:os"
import { basename, join, resolve } from "node:path"
import { fileURLToPath } from "node:url"

const REPOSITORY = "futhr/letterpress"
const REPOSITORY_URL = `https://github.com/${REPOSITORY}`
const NPM_REPOSITORY_URL = `git+${REPOSITORY_URL}.git`
const RELEASE_SCHEMA = "letterpress/release/v1"
const PACKAGES = [
  { directory: "npm/language", name: "@letterpress/language", slug: "language" },
  { directory: "npm/svelte", name: "@letterpress/svelte", slug: "svelte" },
]
const SEMVER = /^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$/
const CANONICAL_REMOTES = new Set([
  REPOSITORY_URL,
  `${REPOSITORY_URL}.git`,
  `git@github.com:${REPOSITORY}.git`,
  `ssh://git@github.com/${REPOSITORY}.git`,
])

export function isCanonicalRepositoryRemote(origin) {
  return CANONICAL_REMOTES.has(origin)
}

export function mergeSmokeDependencies(existing, peers) {
  return { ...peers, ...existing }
}

export function readReleaseVersions(root) {
  const mix = readFileSync(join(root, "mix.exs"), "utf8")
  return {
    hex: mix.match(/@version\s+"([^"]+)"/)?.[1],
    npm: Object.fromEntries(
      PACKAGES.map((pkg) => [
        pkg.name,
        readJson(join(root, pkg.directory, "package.json")).version,
      ]),
    ),
  }
}

export function collectReleaseErrors(
  root,
  { allowUntagged = false, checkGit = true, tag, requireClean = Boolean(tag) } = {},
) {
  const errors = []
  const versions = readReleaseVersions(root)
  const expected = versions.hex

  if (!expected || !SEMVER.test(expected))
    errors.push(`invalid Mix version: ${expected ?? "missing"}`)
  for (const [name, version] of Object.entries(versions.npm)) {
    if (version !== expected)
      errors.push(`${name} version ${version} does not match Mix ${expected}`)
  }
  if (tag && tag !== `v${expected}`) errors.push(`tag ${tag} does not match release v${expected}`)
  if (!tag && !allowUntagged) errors.push("a production release requires --tag v<version>")

  for (const pkg of PACKAGES) {
    const manifest = readJson(join(root, pkg.directory, "package.json"))
    if (manifest.homepage !== REPOSITORY_URL) {
      errors.push(`${pkg.name} homepage must be ${REPOSITORY_URL}`)
    }
    if (manifest.repository?.url !== NPM_REPOSITORY_URL) {
      errors.push(`${pkg.name} repository URL must be ${NPM_REPOSITORY_URL}`)
    }
    if (manifest.repository?.directory !== pkg.directory) {
      errors.push(`${pkg.name} repository directory must be ${pkg.directory}`)
    }
    if (
      manifest.publishConfig?.access !== "public" ||
      manifest.publishConfig?.provenance !== true
    ) {
      errors.push(`${pkg.name} must publish publicly with provenance enabled`)
    }
  }

  for (const path of [
    "priv/compiler/worker.mjs",
    "priv/contract.json",
    "npm/language/src/generated/contract.ts",
  ]) {
    if (!existsSync(join(root, path)))
      errors.push(`required generated artifact is missing: ${path}`)
  }

  if (checkGit) validateGit(root, { errors, tag, requireClean })
  return errors
}

export function validateRelease(root, options = {}) {
  const errors = collectReleaseErrors(root, options)
  if (errors.length > 0) throw new Error(`release validation failed:\n- ${errors.join("\n- ")}`)
  return readReleaseVersions(root).hex
}

export function verifyArtifacts(root, output, options = {}) {
  const version = validateRelease(root, { ...options, requireClean: false })
  const manifest = readJson(join(output, "release-manifest.json"))
  if (manifest.schema_version !== RELEASE_SCHEMA) throw new Error("unknown release manifest schema")
  if (manifest.version !== version)
    throw new Error("artifact manifest version does not match source")
  if (manifest.source_sha !== gitCapture(root, ["rev-parse", "HEAD"])) {
    throw new Error("artifacts were built from another commit")
  }
  if (options.tag && manifest.source_dirty)
    throw new Error("tagged artifacts came from a dirty tree")

  const expected = new Set([
    `letterpress-${version}.tar`,
    ...PACKAGES.map((pkg) => `letterpress-${pkg.slug}-${version}.tgz`),
  ])
  for (const artifact of manifest.artifacts) {
    if (!expected.delete(artifact.file)) throw new Error(`unexpected artifact ${artifact.file}`)
    const path = join(output, artifact.file)
    if (!existsSync(path)) throw new Error(`missing artifact ${artifact.file}`)
    if (hash(path, "sha256") !== artifact.sha256) {
      throw new Error(`checksum mismatch for ${artifact.file}`)
    }
    if (artifact.ecosystem === "npm" && integrity(path) !== artifact.integrity) {
      throw new Error(`npm integrity mismatch for ${artifact.file}`)
    }
  }
  if (expected.size > 0) throw new Error(`manifest is missing ${[...expected].join(", ")}`)

  for (const line of readFileSync(join(output, "SHA256SUMS"), "utf8").trim().split("\n")) {
    const match = /^([a-f\d]{64}) {2}(.+)$/.exec(line)
    if (!match) throw new Error(`invalid SHA256SUMS line: ${line}`)
    if (hash(join(output, match[2]), "sha256") !== match[1]) {
      throw new Error(`SHA256SUMS mismatch for ${match[2]}`)
    }
  }
  return manifest
}

function validateGit(root, { errors, tag, requireClean }) {
  const origin = gitCaptureOptional(root, ["remote", "get-url", "origin"])
  if (tag && !origin) errors.push("tagged releases require an origin remote")
  if (origin && !isCanonicalRepositoryRemote(origin)) {
    errors.push(`origin is not ${REPOSITORY}: ${origin}`)
  }
  if (tag) {
    const head = gitCapture(root, ["rev-parse", "HEAD"])
    const tagged = gitCaptureOptional(root, ["rev-list", "-n", "1", tag])
    if (!tagged) errors.push(`tag ${tag} is not present locally`)
    else if (head !== tagged) errors.push(`${tag} points to ${tagged}, not checked-out ${head}`)
    if (requireClean && gitCapture(root, ["status", "--porcelain"])) {
      errors.push("tagged releases must build from a clean worktree")
    }
  }
  for (const workflow of [".github/workflows/ci.yml", ".github/workflows/release.yml"]) {
    const path = join(root, workflow)
    if (!existsSync(path)) {
      errors.push(`release workflow is missing: ${workflow}`)
      continue
    }
    const mutable = [...readFileSync(path, "utf8").matchAll(/uses:\s+[^\s]+@([^\s#]+)/g)]
      .map((match) => match[1])
      .filter((reference) => !/^[a-f\d]{40}$/.test(reference))
    if (mutable.length > 0)
      errors.push(`${workflow} has mutable action refs: ${mutable.join(", ")}`)
  }
}

function buildArtifacts(root, output, options) {
  const version = validateRelease(root, options)
  const sourceDirty = Boolean(gitCapture(root, ["status", "--porcelain"]))
  mkdirSync(output, { recursive: true })
  if (readdirSync(output).length > 0) throw new Error(`artifact directory must be empty: ${output}`)

  run("pnpm", ["build"], { cwd: root })
  run("pnpm", ["check:exports"], { cwd: root })
  run("pnpm", ["check:conformance"], { cwd: root })

  const paths = artifactPaths(output, version)
  run("mix", ["hex.build", "--output", paths.hex], { cwd: root })
  for (const pkg of PACKAGES) {
    run("pnpm", ["--dir", pkg.directory, "pack", "--out", paths.npm[pkg.name]], { cwd: root })
  }
  writeManifest(root, output, version, paths, sourceDirty)
  verifyArtifacts(root, output, options)
}

function artifactPaths(output, version) {
  return {
    hex: join(output, `letterpress-${version}.tar`),
    npm: Object.fromEntries(
      PACKAGES.map((pkg) => [pkg.name, join(output, `letterpress-${pkg.slug}-${version}.tgz`)]),
    ),
  }
}

function writeManifest(root, output, version, paths, sourceDirty) {
  const artifacts = [
    {
      ecosystem: "hex",
      name: "letterpress",
      file: basename(paths.hex),
      sha256: hash(paths.hex, "sha256"),
    },
    ...PACKAGES.map((pkg) => ({
      ecosystem: "npm",
      name: pkg.name,
      file: basename(paths.npm[pkg.name]),
      sha256: hash(paths.npm[pkg.name], "sha256"),
      integrity: integrity(paths.npm[pkg.name]),
    })),
  ]
  const manifest = {
    schema_version: RELEASE_SCHEMA,
    version,
    source_repository: REPOSITORY_URL,
    source_sha: gitCapture(root, ["rev-parse", "HEAD"]),
    source_dirty: sourceDirty,
    artifacts,
  }
  const manifestPath = join(output, "release-manifest.json")
  writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`)
  const checksumPaths = [...artifacts.map(({ file }) => join(output, file)), manifestPath]
  const checksums = checksumPaths
    .map((path) => `${hash(path, "sha256")}  ${basename(path)}`)
    .sort()
    .join("\n")
  writeFileSync(join(output, "SHA256SUMS"), `${checksums}\n`)
}

function smokeArtifacts(root, output, options) {
  const manifest = verifyArtifacts(root, output, options)
  smokeNpmArtifacts(root, output, manifest)
  smokeHexArtifact(root, output, manifest)
}

function npmRegistryState(name, version, path) {
  const result = spawnSync("npm", ["view", `${name}@${version}`, "dist.integrity", "--json"], {
    encoding: "utf8",
  })
  if (result.status === 0) {
    const published = JSON.parse(result.stdout)
    if (published !== integrity(path))
      throw new Error(`${name}@${version} exists with different bytes`)
    return "identical"
  }
  const output = `${result.stdout}\n${result.stderr}`
  if (/E404|404 Not Found/.test(output)) return "missing"
  throw new Error(`npm preflight failed for ${name}@${version}: ${output.trim()}`)
}

async function hexRegistryState(version, path) {
  const response = await fetch(`https://repo.hex.pm/tarballs/letterpress-${version}.tar`)
  if (response.status === 404) return "missing"
  if (!response.ok) throw new Error(`Hex preflight failed with HTTP ${response.status}`)
  const published = createHash("sha256")
    .update(Buffer.from(await response.arrayBuffer()))
    .digest("hex")
  if (published !== hash(path, "sha256")) {
    throw new Error(`letterpress ${version} exists with different bytes`)
  }
  return "identical"
}

async function publishArtifacts(root, output, options) {
  const manifest = verifyArtifacts(root, output, options)
  const npmArtifacts = manifest.artifacts.filter(({ ecosystem }) => ecosystem === "npm")
  const hexArtifact = manifest.artifacts.find(({ ecosystem }) => ecosystem === "hex")
  if (!hexArtifact) throw new Error("Hex artifact is missing")

  const npmStates = new Map(
    npmArtifacts.map((artifact) => [
      artifact.name,
      npmRegistryState(artifact.name, manifest.version, join(output, artifact.file)),
    ]),
  )
  const hexState = await hexRegistryState(manifest.version, join(output, hexArtifact.file))

  for (const artifact of npmArtifacts) {
    if (npmStates.get(artifact.name) === "identical") {
      console.log(`already published with identical bytes: ${artifact.name}@${manifest.version}`)
      continue
    }
    const args = ["publish", join(output, artifact.file), "--access", "public", "--provenance"]
    if (options.dryRun) args.push("--dry-run")
    run("npm", args, { cwd: root })
  }

  if (hexState === "identical") {
    console.log(`already published with identical bytes: letterpress ${manifest.version}`)
  } else if (options.dryRun) {
    console.log(`dry run: validated ${hexArtifact.file}; Hex registry was not mutated`)
  } else {
    run("elixir", [join(root, "scripts/publish-hex.exs"), join(output, hexArtifact.file)], {
      cwd: root,
    })
  }
}

function smokeNpmArtifacts(sourceRoot, output, manifest) {
  const root = mkdtempSync(join(tmpdir(), "letterpress-npm-smoke-"))
  try {
    let dependencies = Object.fromEntries(
      manifest.artifacts
        .filter(({ ecosystem }) => ecosystem === "npm")
        .map(({ name, file }) => [name, `file:${join(output, file)}`]),
    )
    for (const pkg of PACKAGES) {
      dependencies = mergeSmokeDependencies(
        dependencies,
        readJson(join(sourceRoot, pkg.directory, "package.json")).peerDependencies,
      )
    }
    const rootManifest = readJson(join(sourceRoot, "package.json"))
    dependencies.vite = rootManifest.devDependencies.vite
    dependencies["@sveltejs/vite-plugin-svelte"] =
      rootManifest.devDependencies["@sveltejs/vite-plugin-svelte"]

    writeFileSync(
      join(root, "package.json"),
      `${JSON.stringify({ name: "letterpress-release-smoke", private: true, type: "module", dependencies }, null, 2)}\n`,
    )
    run("npm", ["install", "--ignore-scripts", "--no-audit", "--no-fund", "--package-lock=false"], {
      cwd: root,
    })
    writeFileSync(
      join(root, "smoke.mjs"),
      `import { contract, formatLetterpressSource } from "@letterpress/language"
if (contract.contract_version !== 1) throw new Error("bad contract")
if ((await formatLetterpressSource("text/liquid@1", "Hello  \\n")) !== "Hello") throw new Error("bad formatter")
const email = await formatLetterpressSource("email/mjml-liquid@1", "<mjml><mj-body><mj-section><mj-column><mj-text>Hello</mj-text></mj-column></mj-section></mj-body></mjml>")
if (!email.includes("<mj-text>Hello</mj-text>")) throw new Error("bad email formatter")
`,
    )
    writeFileSync(
      join(root, "consumer.js"),
      `export { LetterpressEditor } from "@letterpress/svelte"
export { letterpressLanguage } from "@letterpress/language"
`,
    )
    writeFileSync(
      join(root, "vite.config.mjs"),
      `import { svelte } from "@sveltejs/vite-plugin-svelte"
import { defineConfig } from "vite"
export default defineConfig({plugins: [svelte()], build: {lib: {entry: "consumer.js", formats: ["es"]}}})
`,
    )
    run("node", ["smoke.mjs"], { cwd: root })
    run(join(root, "node_modules/.bin/vite"), ["build"], { cwd: root })
  } finally {
    rmSync(root, { recursive: true, force: true })
  }
}

function smokeHexArtifact(sourceRoot, output, manifest) {
  const artifact = manifest.artifacts.find(({ ecosystem }) => ecosystem === "hex")
  if (!artifact) throw new Error("Hex artifact is missing")
  const root = mkdtempSync(join(tmpdir(), "letterpress-hex-smoke-"))
  const outer = join(root, "outer")
  const source = join(root, "source")
  mkdirSync(outer)
  mkdirSync(source)
  try {
    const mixEnvironment = {
      ...process.env,
      ...asdfToolVersions(sourceRoot),
      MIX_ENV: "prod",
    }
    run("tar", ["-xf", join(output, artifact.file), "-C", outer])
    run("tar", ["-xzf", join(outer, "contents.tar.gz"), "-C", source])
    run("mix", ["deps.get", "--only", "prod"], {
      cwd: source,
      env: mixEnvironment,
    })
    run("mix", ["compile", "--warnings-as-errors"], {
      cwd: source,
      env: mixEnvironment,
    })
    const smoke = join(source, "release-smoke.exs")
    writeFileSync(
      smoke,
      `schema = %{"version" => 1, "variables" => %{"name" => %{"type" => "string", "context" => "html_text"}}}
source = "<mjml><mj-body><mj-section><mj-column><mj-text>Hello {{ name }}</mj-text></mj-column></mj-section></mj-body></mjml>"
{:ok, _supervisor} = Supervisor.start_link([{Letterpress.Compiler.Supervisor, pool_size: 1}], strategy: :one_for_one)
{:ok, artifact, []} = Letterpress.compile("email/mjml-liquid@1", source, schema)
{:ok, %{html: html}} = Letterpress.render(artifact, %{"name" => "Ada"})
true = String.contains?(html, "Hello Ada")
{:ok, encoded} = Letterpress.encode_artifact(artifact)
{:ok, decoded} = Letterpress.decode_artifact(encoded)
{:ok, %{html: ^html}} = Letterpress.render(decoded, %{"name" => "Ada"})
`,
    )
    run("mix", ["run", smoke], { cwd: source, env: mixEnvironment })
  } finally {
    rmSync(root, { recursive: true, force: true })
  }
}

function asdfToolVersions(root) {
  const path = join(root, ".tool-versions")
  if (!existsSync(path)) return {}

  const variables = { elixir: "ASDF_ELIXIR_VERSION", erlang: "ASDF_ERLANG_VERSION" }
  return Object.fromEntries(
    readFileSync(path, "utf8")
      .trim()
      .split("\n")
      .map((line) => line.trim().split(/\s+/, 2))
      .filter(([tool, version]) => variables[tool] && version)
      .map(([tool, version]) => [variables[tool], version]),
  )
}

function readJson(path) {
  return JSON.parse(readFileSync(path, "utf8"))
}

function hash(path, algorithm) {
  return createHash(algorithm).update(readFileSync(path)).digest("hex")
}

function integrity(path) {
  return `sha512-${createHash("sha512").update(readFileSync(path)).digest("base64")}`
}

function run(command, args, options = {}) {
  execFileSync(command, args, { stdio: "inherit", ...options })
}

function gitCapture(root, args) {
  return execFileSync("git", args, { cwd: root, encoding: "utf8" }).trim()
}

function gitCaptureOptional(root, args) {
  const result = spawnSync("git", args, { cwd: root, encoding: "utf8" })
  return result.status === 0 ? result.stdout.trim() : ""
}

function parseArguments(argv) {
  const [command = "check", ...rest] = argv
  const options = {
    allowUntagged: false,
    tag: undefined,
    artifactDir: "dist/release",
    dryRun: false,
  }
  for (let index = 0; index < rest.length; index += 1) {
    const arg = rest[index]
    if (arg === "--allow-untagged") {
      options.allowUntagged = true
    } else if (arg === "--dry-run") {
      options.dryRun = true
    } else if (arg === "--tag") {
      index += 1
      options.tag = rest[index]
    } else if (arg === "--artifact-dir") {
      index += 1
      options.artifactDir = rest[index]
    } else {
      throw new Error(`unknown release option ${arg}`)
    }
  }
  return { command, options }
}

async function main() {
  const root = resolve(fileURLToPath(new URL("..", import.meta.url)))
  const { command, options } = parseArguments(process.argv.slice(2))
  const releaseOptions = { allowUntagged: options.allowUntagged, tag: options.tag }
  const output = resolve(root, options.artifactDir)
  if (command === "check") validateRelease(root, releaseOptions)
  else if (command === "build") buildArtifacts(root, output, releaseOptions)
  else if (command === "verify") verifyArtifacts(root, output, releaseOptions)
  else if (command === "smoke") smokeArtifacts(root, output, releaseOptions)
  else if (command === "publish") {
    await publishArtifacts(root, output, { ...releaseOptions, dryRun: options.dryRun })
  } else throw new Error(`unknown release command ${command}`)
}

const invoked = process.argv[1] ? resolve(process.argv[1]) : ""
if (invoked === fileURLToPath(import.meta.url)) {
  main().catch((error) => {
    console.error(error instanceof Error ? error.message : error)
    process.exitCode = 1
  })
}
