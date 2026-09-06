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
