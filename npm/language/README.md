# `@letterpress/language`

Framework-neutral CodeMirror 6 language services for Letterpress's versioned
`email/mjml-liquid@1`, `html/liquid@1`, and `text/liquid@1` profiles. The
generated backend contract supplies profile and element metadata, completion
vocabulary, and diagnostic codes. Pinned CodeMirror parsers and the Shopify
Liquid formatter provide the browser implementation. The browser models a
smaller advisory diagnostic set; publication still requires the Elixir
compiler.

The MJML + Liquid formatter is lazy-loaded as a browser-only bundle. Consumers
do not need to install Prettier or the Shopify formatter plugin.

The package supports its declared CodeMirror peer ranges. Newer Liquid peers
also provide automatic percent-brace closing; older peers retain the language
services without that optional enhancement.

See the [repository README](https://github.com/futhr/letterpress) and
[public contract](https://github.com/futhr/letterpress/blob/main/docs/specs/LP.01-letterpress-contract.md)
for the package boundary and backend guarantees.

```ts
import { letterpressLanguage } from "@letterpress/language"

const extension = letterpressLanguage({
  profile: "email/mjml-liquid@1",
  schema: {
    version: 1,
    variables: {
      name: { type: "string", context: "html_text" },
      action_url: { type: "url", context: "url" },
    },
  },
})
```

The package supplies mixed parsing, folding, indentation, completion,
formatting, contract-aware local diagnostics, and stale-response filtering.
Local diagnostics are authoring feedback; only the Hex compiler can approve a
publication artifact.
