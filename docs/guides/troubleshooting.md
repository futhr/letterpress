# Troubleshooting

## Compiler is unavailable or times out

Check `Letterpress.Compiler.status/1`, the Node executable, the caller-owned
`Letterpress.Compiler.Supervisor`, and the per-call `:compiler_timeout`. A
failed request never licenses a fallback compiler. Retry only when the host's
authoring workflow says it is safe.

## MJML or Liquid diagnostics point at old text

Return `source_hash` and `document_version` with every validation response and
pass both to the browser extension. Diagnostics from another source revision
are ignored.

## A value is rejected in one location

Inspect the schema context. A value declared for `url` cannot be emitted as
HTML text, and CSS/color values must be compile-phase. Define separate
variables when the same business value needs distinct output contexts.

## An artifact no longer decodes

Do not edit artifact JSON. Verify that the complete canonical artifact was
stored and that its `content_sha256` and compiler fields were preserved. An
unknown artifact version requires an explicit compatible decoder or a
controlled recompilation from retained source.
