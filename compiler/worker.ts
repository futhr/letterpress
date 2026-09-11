import process from "node:process"
import { dispatch, normalizeError, type Request } from "./operations"

const maxFrameBytes = 2_000_000
let input = Buffer.alloc(0)

const drainFrames = (): void => {
  while (input.length >= 4) {
    const length = input.readUInt32BE(0)
    if (length > maxFrameBytes) process.exit(64)
    if (input.length < length + 4) return
    const frame = input.subarray(4, length + 4)
    input = input.subarray(length + 4)
    void handleFrame(frame)
  }
}

const handleFrame = async (frame: Buffer): Promise<void> => {
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

const writeFrame = (value: unknown): void => {
  const payload = Buffer.from(JSON.stringify(value), "utf8")
  const header = Buffer.allocUnsafe(4)
  header.writeUInt32BE(payload.length)
  process.stdout.write(Buffer.concat([header, payload]))
}

process.stdin.on("data", (chunk: Buffer) => {
  input = Buffer.concat([input, chunk])
  drainFrames()
})

process.stdin.on("error", () => process.exit(1))
process.stdout.on("error", (error: NodeJS.ErrnoException) => {
  process.exit(error.code === "EPIPE" ? 0 : 1)
})
