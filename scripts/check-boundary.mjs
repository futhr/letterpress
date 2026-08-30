import { readdir, readFile } from "node:fs/promises"
import { extname, join } from "node:path"

const roots = ["lib", "compiler", "contract", "npm"]
const forbidden = ["apace", "hermes", "mydevices", "tenant_id", "application_id"]

for (const root of roots) {
  for (const file of await files(root)) {
    if (![".ex", ".exs", ".ts", ".svelte", ".json", ".md"].includes(extname(file))) continue
    const text = (await readFile(file, "utf8")).toLowerCase()
    for (const word of forbidden) {
      if (text.includes(word)) throw new Error(`${file} contains host vocabulary: ${word}`)
    }
  }
}

async function files(path) {
  const entries = await readdir(path, { withFileTypes: true }).catch(() => [])
  const output = []
  for (const entry of entries) {
    const child = join(path, entry.name)
    if (entry.isDirectory()) output.push(...(await files(child)))
    else output.push(child)
  }
  return output
}
