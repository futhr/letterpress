import assert from "node:assert/strict"
import { execFileSync } from "node:child_process"
import { createHash } from "node:crypto"
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import test from "node:test"
import {
  collectReleaseErrors,
  isCanonicalRepositoryRemote,
  mergeSmokeDependencies,
  validateRelease,
  verifyArtifacts,
} from "./release.mjs"

const packages = ["language", "svelte"]

function fixture(options = {}) {
  const root = mkdtempSync(join(tmpdir(), "letterpress-release-test-"))
  mkdirSync(join(root, "npm"))
  mkdirSync(join(root, "priv/compiler"), { recursive: true })
  mkdirSync(join(root, "npm/language/src/generated"), { recursive: true })
  mkdirSync(join(root, ".github/workflows"), { recursive: true })
  writeFileSync(join(root, "mix.exs"), `@version "${options.mixVersion ?? "1.2.3"}"\n`)
  writeFileSync(join(root, "priv/compiler/worker.mjs"), "worker\n")
  writeFileSync(join(root, "priv/contract.json"), "{}\n")
  writeFileSync(join(root, "npm/language/src/generated/contract.ts"), "export {}\n")
  writeFileSync(
    join(root, ".github/workflows/ci.yml"),
    "- uses: actions/checkout@aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n",
  )
  writeFileSync(
    join(root, ".github/workflows/release.yml"),
    "- uses: actions/checkout@aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n",
  )

  for (const name of packages) {
    const directory = `npm/${name}`
    mkdirSync(join(root, directory), {
      recursive: true,
    })
    writeFileSync(
      join(root, directory, "package.json"),
      `${JSON.stringify({
        name: `@letterpress/${name}`,
        version: options.npmVersions?.[name] ?? "1.2.3",
        homepage: "https://github.com/futhr/letterpress",
        repository: {
          type: "git",
          url: "git+https://github.com/futhr/letterpress.git",
          directory,
        },
        publishConfig: { access: "public", provenance: true },
      })}\n`,
    )
  }
  return root
}

function withFixture(options, callback) {
  const root = fixture(options)
  try {
    callback(root)
  } finally {
    rmSync(root, { recursive: true, force: true })
  }
}

test("accepts one version and exact tag across all artifacts", () => {
  withFixture({}, (root) => {
    assert.equal(validateRelease(root, { checkGit: false, tag: "v1.2.3" }), "1.2.3")
  })
})

test("rejects version drift and an incorrect tag", () => {
  withFixture({ npmVersions: { svelte: "1.2.4" } }, (root) => {
    const errors = collectReleaseErrors(root, { checkGit: false, tag: "v1.2.4" })
    assert.ok(errors.some((error) => error.includes("@letterpress/svelte version 1.2.4")))
    assert.ok(errors.some((error) => error.includes("tag v1.2.4 does not match")))
  })
})

test("requires explicit untagged opt-in", () => {
  withFixture({}, (root) => {
    assert.ok(
      collectReleaseErrors(root, { checkGit: false }).some((error) =>
        error.includes("requires --tag"),
      ),
    )
    assert.deepEqual(collectReleaseErrors(root, { allowUntagged: true, checkGit: false }), [])
  })
})

test("rejects noncanonical package metadata and mutable workflow actions", () => {
  withFixture({}, (root) => {
    const manifestPath = join(root, "npm/svelte/package.json")
    const manifest = JSON.parse(readFileSync(manifestPath, "utf8"))
    manifest.repository.url = "git+https://github.com/attacker/letterpress.git"
    writeFileSync(manifestPath, `${JSON.stringify(manifest)}\n`)
    writeFileSync(join(root, ".github/workflows/ci.yml"), "- uses: actions/checkout@main\n")
    const errors = collectReleaseErrors(root, { allowUntagged: true, checkGit: true })
    assert.ok(errors.some((error) => error.includes("repository URL")))
    assert.ok(errors.some((error) => error.includes("mutable action refs")))
  })
})

test("accepts canonical GitHub remotes and rejects lookalikes", () => {
  for (const remote of [
    "https://github.com/futhr/letterpress",
    "https://github.com/futhr/letterpress.git",
    "git@github.com:futhr/letterpress.git",
    "ssh://git@github.com/futhr/letterpress.git",
  ]) {
    assert.equal(isCanonicalRepositoryRemote(remote), true)
  }
  assert.equal(isCanonicalRepositoryRemote("git@github.example:futhr/letterpress.git"), false)
})

test("keeps local tarballs ahead of package peer ranges in release smokes", () => {
  const dependencies = mergeSmokeDependencies(
    { "@letterpress/language": "file:/tmp/letterpress-language-0.1.0.tgz" },
    { "@letterpress/language": "^0.1.0", svelte: "^5.0.0" },
  )

  assert.deepEqual(dependencies, {
    "@letterpress/language": "file:/tmp/letterpress-language-0.1.0.tgz",
    svelte: "^5.0.0",
  })
})

function withArtifacts(callback) {
  withFixture({}, (root) => {
    const git = (args) =>
      execFileSync("git", args, { cwd: root, encoding: "utf8", stdio: "pipe" }).trim()
    git(["init"])
    git([
      "-c",
      "user.name=Release Test",
      "-c",
      "user.email=release@example.test",
      "commit",
      "--allow-empty",
      "-m",
      "fixture",
    ])
    const output = join(root, "artifacts")
    mkdirSync(output)
    const digest = (value, algorithm, encoding) =>
      createHash(algorithm).update(value).digest(encoding)
    const artifacts = [
      { name: "letterpress", ecosystem: "hex", file: "letterpress-1.2.3.tar" },
      ...packages.map((name) => ({
        name: `@letterpress/${name}`,
        ecosystem: "npm",
        file: `letterpress-${name}-1.2.3.tgz`,
      })),
    ].map((artifact) => {
      const bytes = `test package ${artifact.name}`
      writeFileSync(join(output, artifact.file), bytes)
      return {
        ...artifact,
        sha256: digest(bytes, "sha256", "hex"),
        ...(artifact.ecosystem === "npm"
          ? { integrity: `sha512-${digest(bytes, "sha512", "base64")}` }
          : {}),
      }
    })
    const manifest = {
      schema_version: "letterpress/release/v1",
      version: "1.2.3",
      source_repository: "https://github.com/futhr/letterpress",
      source_sha: git(["rev-parse", "HEAD"]),
      source_dirty: false,
      artifacts,
    }
    const writeManifest = () => {
      const bytes = JSON.stringify(manifest)
      writeFileSync(join(output, "release-manifest.json"), bytes)
      writeFileSync(
        join(output, "SHA256SUMS"),
        `${[
          ...artifacts.map(({ file, sha256 }) => `${sha256}  ${file}`),
          `${digest(bytes, "sha256", "hex")}  release-manifest.json`,
        ].join("\n")}\n`,
      )
    }
    writeManifest()
    const verify = () => verifyArtifacts(root, output, { allowUntagged: true, checkGit: false })
    callback({ output, manifest, writeManifest, verify })
  })
}

test("verifies exact artifact identities and bytes", () => {
  withArtifacts(({ output, manifest, verify }) => {
    assert.deepEqual(verify(), manifest)
    writeFileSync(join(output, manifest.artifacts[0].file), "corrupted")
    assert.throws(verify, /checksum mismatch/)
  })
})

test("rejects altered artifact identities even when checksums match", () => {
  for (const field of ["name", "ecosystem"]) {
    withArtifacts(({ manifest, writeManifest, verify }) => {
      manifest.artifacts[1][field] = "other"
      writeManifest()
      assert.throws(verify, /artifact identity mismatch/)
    })
  }
  withArtifacts(({ manifest, writeManifest, verify }) => {
    manifest.source_repository = "https://example.test/other"
    writeManifest()
    assert.throws(verify, /repository does not match/)
  })
  withArtifacts(({ manifest, writeManifest, verify }) => {
    manifest.source_dirty = "false"
    writeManifest()
    assert.throws(verify, /invalid artifact manifest shape/)
  })
})

test("requires exactly one checksum for every artifact and the manifest", () => {
  for (const change of [
    (lines) => lines.slice(0, -1),
    (lines) => [...lines, lines[0]],
    (lines) => [...lines, `${"0".repeat(64)}  ../outside`],
  ]) {
    withArtifacts(({ output, verify }) => {
      const path = join(output, "SHA256SUMS")
      const lines = readFileSync(path, "utf8").trim().split("\n")
      writeFileSync(path, `${change(lines).join("\n")}\n`)
      assert.throws(verify, /SHA256SUMS (is missing|entry)/)
    })
  }
})
