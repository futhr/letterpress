import { mkdir, copyFile } from "node:fs/promises"
import { build } from "esbuild"

await import("./generate-contract.mjs")

await mkdir("priv/compiler", { recursive: true })
await build({
  entryPoints: ["compiler/worker.ts"],
  outfile: "priv/compiler/worker.mjs",
  bundle: true,
  platform: "node",
  target: "node22",
  format: "esm",
  banner: {
    js: 'import { createRequire as __letterpressCreateRequire } from "node:module"; const require = __letterpressCreateRequire(import.meta.url);',
  },
  sourcemap: false,
  minify: true,
  legalComments: "eof",
})
await copyFile("generated/letterpress-v1.json", "priv/contract.json")
