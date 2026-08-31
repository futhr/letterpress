# Consumer adoption

Adopt Letterpress at the template boundary, not inside a provider adapter.

1. Map the consumer's variable registry to a versioned Letterpress schema.
2. Convert legacy source into one of the public profiles.
3. Compile every deliverable locale before moving the publication pointer.
4. Persist the full artifact beside the consumer's version record.
5. Render the artifact in the delivery job with already resolved values.
6. Keep provider policy, tenancy, authorization, retries, and audit records in
   the consumer.

Legacy Mustache, Handlebars, EEx, or unrestricted HTML are conversion inputs,
not runtime profiles. Bounded HTML fragments may use `html/liquid@1` only after
they satisfy its element, attribute, Liquid, and URL rules. A migration adapter
should fail records it cannot convert, surface diagnostics for review, and pass
successful output through the normal compiler. It must not add a compatibility
mode to Letterpress.

Use an expand/backfill/contract migration when adding artifacts to a live
system. Old and new application versions must coexist until every active
publication has a verified artifact and delivery no longer reads the legacy
field.

Translation providers receive only extracted translation units. Apply their
responses with `Letterpress.apply_translations/5`, compile the resulting
locale source, and let the consumer decide review and publication policy.
