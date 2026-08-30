import liquidPlugin from "@shopify/prettier-plugin-liquid"
import { format } from "prettier/standalone"

/** Format an MJML + Liquid document without loading Node's Prettier entry point. */
export function formatLiquidSource(source: string): Promise<string> {
  return format(source, {
    parser: "liquid-html",
    plugins: [liquidPlugin],
    printWidth: 100,
    tabWidth: 2,
    singleQuote: false,
  })
}
