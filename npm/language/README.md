# `@letterpress/language`

Framework-neutral CodeMirror 6 language services for Letterpress's immutable
`email/mjml-liquid@1` and `text/liquid@1` profiles. The generated contract,
MJML metadata, completion, folding, formatting, and local diagnostics mirror
the authoritative Hex compiler; publication must still use the backend.

The MJML + Liquid formatter is lazy-loaded as a browser-only bundle. Consumers
do not need to install Prettier or the Shopify formatter plugin.

See the repository README and public contract for setup and guarantees.

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
  documentVersion: 12,
  sourceHash: "backend-source-sha256",
  serverDiagnostics,
})
```

The package supplies mixed parsing, folding, indentation, completion,
formatting, contract-aware local diagnostics, and stale-response filtering.
Local diagnostics are authoring feedback; only the Hex compiler can approve a
publication artifact.
