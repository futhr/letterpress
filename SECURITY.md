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

Supported releases receive security fixes.
