# Letterpress usage rules

## Compile before publication

Call `Letterpress.compile/4` when validating preview or publication. Persist the
complete returned artifact for every deliverable locale. A compiler error is an
authoring/publication failure, not a reason to fall back to another renderer.

## Render stored artifacts

Call `Letterpress.render/3` at delivery with resolved values. Delivery nodes may
omit `Letterpress.Compiler.Supervisor`; valid stored artifacts still render
without Node.

## Keep application policy in the host

The host owns authorization, tenancy, locales, publication state, retries,
providers, and migrations. Convert legacy formats into a Letterpress profile
before calling the normal compiler. Do not add a permissive migration mode.

## Treat diagnostics as untrusted structured data

Match on diagnostic codes and ranges, not English prose. Escape messages in
the UI. Correlate asynchronous responses with `source_hash` and
`document_version` before displaying them.

## Do not persist resolved values

Delivery values are supplied when rendering. Compile-phase values, schema
defaults, and literal source are stored in artifacts, so keep secrets and
recipient data out of those authoring inputs. Never place source, rendered
output, or variable values in telemetry.
