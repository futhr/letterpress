import { rm } from "node:fs/promises"
import { basename, dirname, resolve } from "node:path"

const requested = process.argv[2]
const target = resolve(process.cwd(), requested ?? "")
if (basename(target) !== "dist" || dirname(target) !== process.cwd()) {
  throw new Error("clean-package only removes the current package's dist directory")
}
await rm(target, { force: true, recursive: true })
