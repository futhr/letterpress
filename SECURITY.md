# Security

Report vulnerabilities privately through GitHub security advisories for
`futhr/letterpress`. Do not open a public issue containing an exploit, template
source, recipient data, credentials, or unpublished artifact details.

Letterpress treats template source and render values as untrusted input. Its
allow-lists, compiler process boundary, canonical artifacts, strict Liquid
runtime, and resource budgets are security controls. Node permission mode is
defense in depth rather than a sandbox. Consumers remain responsible for
author authorization, tenant isolation, provider policy, and workload
isolation.

Artifact hashes provide content integrity, not authentication. Consumers must
keep the compiler-to-storage path trusted or authenticate transported
artifacts before decoding. Artifact decoding is not an HTML sanitizer for
arbitrary caller-supplied documents.

Compile-phase values become artifact content. Do not put secrets or recipient
values in compile-phase variables, defaults, or template source.

Security fixes target the current release line.

The npm audit policy temporarily excludes
[GHSA-gcqx-w48m-w2h4](https://github.com/advisories/GHSA-gcqx-w48m-w2h4)
(CVE-2026-93753), reviewed on 29 October 2026. It affects `deepmerge` 4.3.1,
used by `@sveltejs/vite-plugin-svelte` 7.3.1 to merge repository-controlled
Svelte/Vite configuration. Neither package has a patched release at that date.
This configuration must remain trusted; do not feed template source or render
values into it. The plugin is development tooling and is absent from the Hex
runtime dependencies, compiler bundle, and npm package dependencies.

This exception accepts that advisory rather than patching the dependency. All
other advisories still fail the audit. Remove the exception when a patched
upstream dependency is available, and reassess it before changing the dependency
path, adding it to production dependencies, or accepting untrusted configuration.
