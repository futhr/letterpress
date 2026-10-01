---
name: research
description: Resolve a design or compatibility question that depends on current external MJML/Liquid, editor, Elixir/npm, security, or agent-client behavior. Use primary sources and repository evidence to recommend a bounded decision. Do not activate for implementation questions answered by local code and specs.
user-invocable: false
---

# External evidence

Input: a concrete unresolved question and the repository boundary it affects.
Output: a sourced decision or material uncertainty, with follow-up ownership,
in chat. Write a repository research document only when the task requests or
requires that durable artifact and permits it.

Read related local code/tests and relevant specs first. Load existing research
or ADRs only if they bear on the question. Compare alternatives by semantic
ownership: source language, schema, compile/render boundary, artifact
portability, delivery dependencies, editor authority, localization, workflow,
and failure timing. Do not compare by feature count alone.

Verify external facts with current official specifications, product docs,
maintainer source repositories, or package documentation. Preserve the relevant
version and access date for changing compatibility facts. Distinguish
documented behavior, observed local behavior, and inference; name exclusions
that affect the choice.

Explain the adopted, rejected, deferred, or still-unverified direction and the
layer owning any next step. External evidence supports a choice; it does not
override the normative [LP.01 contract](../../../docs/specs/LP.01-letterpress-contract.md)
or authorize runtime changes on its own.
