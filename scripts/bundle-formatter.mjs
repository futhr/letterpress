import { createRequire } from "node:module"
import { dirname, resolve } from "node:path"
import { fileURLToPath } from "node:url"
import { build } from "esbuild"

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..")
const require = createRequire(import.meta.url)
const prettierStandalone = require.resolve("prettier/standalone.mjs")

await build({
  entryPoints: [resolve(root, "npm/language/src/formatter.ts")],
  outfile: resolve(root, "npm/language/dist/formatter.js"),
  bundle: true,
  format: "esm",
  platform: "browser",
  target: "es2022",
  sourcemap: true,
  legalComments: "eof",
  plugins: [
    {
      name: "prettier-browser-entry",
      setup(buildContext) {
        buildContext.onResolve({ filter: /^prettier$/ }, () => ({ path: prettierStandalone }))
      },
    },
  ],
})
