import assert from "node:assert/strict"
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import test from "node:test"
import { collectReleaseErrors, isCanonicalRepositoryRemote, validateRelease } from "./release.mjs"

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
    mkdirSync(directory === "npm/language" ? join(root, directory) : join(root, directory), {
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
