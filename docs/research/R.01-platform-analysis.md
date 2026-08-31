---
title: "R.01 - Notification template platform analysis"
document_id: "R.01"
status: "Accepted"
created: "2026-08-31"
last_updated: "2026-08-31"
decision: "Keep Letterpress a local compiler/runtime/editor contract rather than a hosted notification platform or provider template adapter."
---

# R.01 - Notification template platform analysis

## Research question

What should Letterpress own after comparing hosted notification systems,
provider-side templates, email build frameworks, and Elixir libraries?

The answer must preserve the constraints in `LP.01`: an authoritative Elixir
backend, deterministic compile-once artifacts, bounded pure-BEAM delivery
rendering, advisory browser tools, and host-owned product workflow.

## Method

The review used first-party documentation available on 2026-08-31. Systems
were compared by semantics rather than feature count:

1. Who owns template records, versions, publication, and rollback?
2. Which language renders dynamic content, and when does it execute?
3. Is input typed, and are output contexts such as URL and subject distinct?
4. Is there a portable immutable artifact, or only source/template IDs?
5. Can already-published content render without a network, Node, or provider?
6. Is editor validation authoritative or advisory?
7. Who owns localization, brands, preferences, routing, and delivery?
8. When do missing data and unsafe output fail?

This was a documentation comparison, not a source-code security audit or a
render-compatibility benchmark. Where first-party docs do not describe a
property, this note labels the conclusion as an inference instead of claiming
the property is absent.

## Findings

### Hosted notification systems

#### Knock

Knock is the closest product comparison at the authoring-language level. Its
template editor uses Liquid, supports control flow, partials, previews, tests,
translations, API/CLI management, and a commit/environment version model.
Templates belong to workflow or broadcast channel steps rather than existing
as standalone compiler artifacts. Knock also supports dynamic Liquid helpers
that load users, objects, tenants, and subscriptions from its environment.

Its testing documentation states that render errors caused by missing or
malformed data can retry a step and then halt a workflow run. That is a
delivery-time failure model. Letterpress instead validates declared variables
and contexts before publication, persists the compiled artifact, and runs no
remote data lookup from Liquid.

Useful comparison:

- Adopt the expectation of good Liquid editing, preview data, test sends in a
  consumer, version visibility, and translation placeholder preservation.
- Reject environment lookups, workflow ownership, remote partial resolution,
  and platform-coupled template identity in the core package.
- Inference: the reviewed Knock docs do not describe a portable,
  content-addressed artifact that a host can render offline.

Sources:

- [Working with templates](https://docs.knock.app/template-editor/overview)
- [Liquid helpers](https://docs.knock.app/template-editor/reference-liquid-helpers)
- [Testing and debugging](https://docs.knock.app/template-editor/testing-and-debugging)
- [Translations](https://docs.knock.app/template-editor/translations)
- [Partials](https://docs.knock.app/template-editor/partials/overview)

#### Courier

Courier owns workspace templates, drafts, publication, version history,
approval checks, brands, routing, providers, and delivery. Authors can use a
visual designer or the Elemental JSON format. The Templates API exposes draft
and published content and can publish a selected version. Courier Create adds
tenant-scoped template resources and an embeddable editor.

Elemental is relevant because it is a programmatic, versionable message format,
but its content model is coupled to Courier routing and workspace resources.
Letterpress artifacts deliberately omit those concerns.

Useful comparison:

- Adopt a programmatic contract and previewable structured metadata.
- Keep approval, tenant scoping, brands, routing, and provider configuration in
  consumers.
- Inference: the reviewed Courier docs present provider-hosted template
  resources, not offline artifacts rendered by an Elixir host.

Sources:

- [Templates overview](https://www.courier.com/docs/platform/content/content-overview)
- [Templates API](https://www.courier.com/docs/platform/content/templates-api)
- [Template variables](https://www.courier.com/docs/platform/content/variables/inserting-variables)
- [Courier Create API](https://www.courier.com/docs/tutorials/content/how-to-use-courier-create-api)

#### Novu

Novu supports code-first TypeScript workflows. Its React Email integration uses
Zod payload and control schemas, renders a React component to HTML, and returns
the subject and body from an email step. This is strong evidence that typed
authoring inputs and code-managed notification content are useful.

The execution unit is still a workflow step, and the example renders React
Email content while that step runs. Letterpress has a different deployment
goal: Node is allowed for authoring compilation, but persisted artifacts render
on delivery nodes without Node.

Useful comparison:

- Adopt explicit input schemas and code-reviewable authoring contracts.
- Reject TypeScript workflow execution as the required Elixir delivery path.
- Treat React Email as a possible future import/build input, not as a v1
  Letterpress profile.

Sources:

- [React Email integration](https://docs.novu.co/framework/content/react-email)
- [TypeScript email step](https://docs.novu.co/framework/typescript/steps/email)
- [Template editors](https://docs.novu.co/platform/workflow/add-notification-content/channels-template-editors)

#### Customer.io

Customer.io evaluates Liquid when a message is delivered. Template objects can
reference customer, event, trigger, and workflow data. Its `render_liquid` tag
can evaluate Liquid stored inside another value, adding a second dynamic
evaluation boundary.

This model favors platform-managed campaign data and late binding. Letterpress
forbids raw/dynamic template evaluation, requires declared variables, and
limits Liquid to a fixed profile so output contexts and budgets remain
provable.

Useful comparison:

- Liquid is familiar to notification authors and supports the required control
  flow.
- Nested evaluation and platform data access are outside the Letterpress
  contract because they weaken static analysis and failure timing.

Sources:

- [Personalize messages with Liquid](https://docs.customer.io/messaging/liquid/using-liquid/)
- [Liquid tag list](https://docs.customer.io/journeys/liquid-tag-list/)
- [Test emails](https://docs.customer.io/journeys/testing-emails/)

### Provider-side templates

#### Twilio SendGrid

SendGrid Dynamic Templates store multiple versions and select one active
version. Handlebars renders substitutions, conditions, loops, HTML, text, and
subject content from `dynamic_template_data` during the provider send path.
The official guide documents triple-brace output for unescaped HTML.

Provider templates reduce application-side rendering work, but template IDs
and active versions become external delivery dependencies. Missing data may
render empty output in documented examples, and raw output weakens context
proof unless the caller builds another policy layer.

Letterpress should remain provider-neutral: consumers pass rendered channels
to Swoosh, Bamboo, SendGrid, SES, or another adapter. It should not make a
remote template ID its artifact format.

Sources:

- [Using Handlebars](https://www.twilio.com/docs/sendgrid/for-developers/sending-email/using-handlebars)
- [Dynamic template versions](https://www.twilio.com/docs/sendgrid/ui/sending-email/how-to-send-an-email-with-dynamic-templates)
- [Mail Send API](https://www.twilio.com/docs/sendgrid/api-reference/mail-send/mail-send)

#### Amazon SES

SES supports stored and inline templates. Rendering occurs inside the provider
send operation. SES event publishing has a `RenderingFailure` event for missing
template data or parameter/data mismatches. The send request can therefore be
accepted before the caller learns that no email was produced.

That timing is the failure mode Letterpress avoids. A consumer can compile and
validate before publication, render locally before calling SES, and send raw
HTML/text. SES remains a delivery adapter rather than the template authority.

Sources:

- [SES developer guide](https://docs.aws.amazon.com/ses/latest/dg/)
- [SES rendering failure events](https://docs.aws.amazon.com/ses/latest/dg/monitor-using-event-publishing.html)

### Email compilers and code-first builders

#### MJML

MJML is a semantic responsive-email language whose official Node engine emits
HTML. Its public API exposes validation levels, preprocessors, includes,
configuration files, custom components, and file paths. Those extension points
are useful in developer-controlled builds but too broad for Letterpress's
multi-author compiler boundary.

Letterpress uses the official compiler for fidelity, pins its version, enables
strict validation and style sanitization, forbids includes/plugins, and records
the compiler identity in the artifact. The important addition is not another
MJML implementation; it is the typed, deterministic boundary around MJML and
the removal of MJML from delivery.

Source:

- [MJML documentation](https://documentation.mjml.io/)

#### React Email

React Email renders React components into HTML and can derive plain text. It is
well suited to developer-authored templates that ship with application code.
TypeScript props provide an authoring-time type surface when the host maintains
the component.

It does not by itself define a restricted runtime language for non-developer
source, a canonical portable artifact, or context-specific delivery variables.
Using it as the delivery renderer also brings JavaScript/React into that path.

Source:

- [React Email render API](https://react.email/docs/utilities/render)

#### Maizzle

Maizzle uses Vue components and Tailwind CSS, then applies email-specific
transformers during a production build. It provides a development server,
compatibility tooling, and programmatic build APIs. This is a broad code-first
email build system, including host configuration and component logic.

Maizzle validates the value of a compile-time frontend pipeline, but its open
Vue/JavaScript extension surface does not fit untrusted dynamic authoring.
Letterpress should retain the smaller MJML profile and closed compiler bundle.

Sources:

- [Maizzle introduction](https://maizzle.com/docs/introduction)
- [Maizzle templates](https://maizzle.com/docs/development/templates)
- [Maizzle API utilities](https://maizzle.com/docs/api/utilities)

### Elixir libraries

#### Solid

Solid provides strict Liquid parsing and BEAM rendering, including custom tags,
filters, matchers, and file-system behavior. It is the appropriate parsing and
rendering substrate for Letterpress, not the complete public policy.

Letterpress adds a closed tag/filter set, blank file loading, typed schemas,
context filters, URL/subject validation, render isolation, budgets,
diagnostics, canonical artifacts, and cross-runtime metadata. Consumers should
use the Letterpress artifact contract rather than treating arbitrary Solid
templates as artifacts.

Sources:

- [Solid overview](https://hexdocs.pm/solid/readme.html)
- [Solid API](https://hexdocs.pm/solid/Solid.html)

#### `mjml` Hex package

The `mjml` Hex package uses Rust NIF bindings to the MRML implementation. It
offers a convenient BEAM-facing compiler and removes the Node process, but it
does not use the official MJML compiler selected by `LP.01`. Compiler identity
and output fidelity are part of Letterpress artifact determinism, so swapping
implementations is not an operational detail.

The package is a valid alternative if the project later accepts MRML output as
a new profile or artifact compiler identity. It is not a drop-in backend for
`email/mjml-liquid@1`.

Source:

- [`mjml` on Hex](https://hex.pm/packages/mjml)

#### Swoosh and Bamboo

Swoosh and Bamboo compose and deliver emails through adapters. Their Phoenix
integrations render application templates and layouts into HTML/text bodies.
They solve a downstream concern and remain good consumer integrations.

They do not replace Letterpress's dynamic authoring contract, typed output
contexts, immutable artifact, or browser language package. Letterpress should
return rendered channels; a consumer should put those channels into a Swoosh
or Bamboo email and own delivery.

Sources:

- [Swoosh email API](https://swoosh.hexdocs.pm/Swoosh.Email.html)
- [Phoenix.Swoosh](https://hexdocs.pm/phoenix_swoosh/Phoenix.Swoosh.html)
- [Bamboo email API](https://bamboo.hexdocs.pm/Bamboo.Email.html)
- [Bamboo.Phoenix](https://hexdocs.pm/bamboo_phoenix/Bamboo.Phoenix.html)

## Comparison matrix

| System | Primary owner | Dynamic execution | Typed input | Portable offline artifact | Delivery dependency |
|---|---|---|---|---|---|
| Knock | Hosted workflow platform | Liquid at workflow runtime | Trigger validation available | Not described in reviewed docs | Knock service |
| Courier | Hosted template/delivery platform | Platform template runtime | Structured Elemental content | Not described in reviewed docs | Courier service |
| Novu | Hosted/self-hosted workflow runtime | TypeScript/React workflow step | Zod payload/control schemas | Workflow code, not Letterpress-style artifact | Novu/Node runtime |
| Customer.io | Hosted campaign platform | Liquid at delivery | Data namespaces; late-bound values | Not described in reviewed docs | Customer.io service |
| SendGrid | Email provider | Handlebars at send | JSON data without output contexts | Remote template/version ID | SendGrid service |
| SES | Email provider | Provider template render | JSON data without output contexts | Remote resource or inline source | SES service |
| MJML | Email compiler | Build/compile time | Component attributes | HTML output | Node only when compiling |
| React Email | Code-first builder | React render | TypeScript props | HTML output | Node/React when rendering |
| Maizzle | Code-first builder | Vue build pipeline | TypeScript/Vue surface | HTML output | Node build runtime |
| Solid | Elixir Liquid engine | BEAM render | Dynamic maps | Parsed internal template | BEAM/Solid |
| `mjml` Hex | BEAM MJML compiler | NIF compile time | MJML source | HTML output | Native MRML NIF |
| Swoosh/Bamboo | Elixir mail composition/delivery | Host template render | Host assigns | Email struct/body | Host and adapter |
| Letterpress | Embedded language boundary | Compile phase plus bounded BEAM delivery phase | Schema with type, phase, and context | Canonical content-addressed artifact | BEAM after compilation |

"Not described" is limited to the reviewed first-party pages. It is not proof
that a private or undocumented export format cannot exist.

## Decision

Keep Letterpress an embedded language/compiler/runtime/editor contract. Do not
turn it into a hosted notification platform, provider adapter, template
database, or workflow engine.

Adopt these principles:

- Liquid is the author-facing delivery language, but only through a closed,
  versioned profile.
- MJML compilation happens before publication with the pinned official
  compiler.
- Typed phase/context schemas are a core difference, not optional editor hints.
- The artifact, not a remote template ID or raw source, is the delivery input.
- Browser tools share generated metadata but never approve publication.
- Swoosh, Bamboo, SES, SendGrid, and platform APIs remain consumer adapters.

Reject these v1 additions:

- remote data lookup from Liquid;
- runtime includes, partial loaders, plugins, or nested template evaluation;
- raw/unescaped Liquid output;
- provider template IDs as Letterpress artifacts;
- tenancy, brands, preferences, approval, routing, or delivery orchestration;
- React Email, Vue/Maizzle, Handlebars, EEx, or arbitrary HTML profiles.

Bounded future validation:

- A new source profile may be considered only if it compiles to a closed,
  canonical artifact and does not add a delivery-time toolchain.
- Reusable content may be considered only with deterministic, publication-time
  resolution and explicit source identity; runtime file or network loading
  remains out of scope.
- Provider/Swoosh helpers belong in consumer examples or separate adapter
  packages unless they can remain dependency-free data conversion.

## Falsifiers and review triggers

Reopen the decision if one of these becomes true:

- The official MJML compiler can no longer meet deterministic build or
  isolation requirements under the pinned worker model.
- A real consumer cannot migrate publication and delivery without product
  behavior entering Letterpress.
- Artifact rendering requires information that cannot be captured in the
  source, schema, profile, options, and pinned compiler identity.
- Cross-runtime editor metadata cannot remain generated from one backend
  contract.

Feature parity with a hosted platform is not a falsifier. It is outside the
chosen ownership boundary.
