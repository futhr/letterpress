# R.02 - Elixir library posture

Status: reviewed
Last reviewed: 2026-08-31

## Question

Should Letterpress start and configure its compiler processes automatically, or
should the consuming application own their placement and configuration?

## Sources

- Johanna Larsson, [Let libraries be libraries](https://jola.dev/posts/let-libraries-be-libraries),
  published 2026-07-07. The article argues that an automatic application
  callback fixes process placement, supervision strategy, and instance count
  for every consumer.
- Elixir,
  [Using application configuration for libraries](https://elixir.hexdocs.pm/design-anti-patterns.html#using-application-configuration-for-libraries).
  The official guidance recommends call-level options for behavioral choices
  and caller-owned child specifications when a library needs processes.
- `../ex_maude`, inspected 2026-08-31. The sibling Hex library has an executable
  posture test requiring no automatic application callback and exposes a named,
  configurable pool child specification.

## Findings

Letterpress needs long-lived compiler processes because each worker owns a
framed port connection to the pinned Node bundle. That requirement does not
require Letterpress to own the root of the process tree.

Automatic startup had four costs:

1. every dependency consumer received the same compiler pool, even on
   delivery-only nodes;
2. pool size and resource limits lived in global application configuration;
3. a host could not place the pool beneath its own authoring subsystem; and
4. two consumers could not run independently named pools with different
   capacity.

The renderer does not need a long-lived process. It can accept resource policy
per call and spawn its bounded monitored process only for the duration of that
render.

## Conclusion

Letterpress is an OTP library application without an application
callback. Authoring hosts add `Letterpress.Compiler.Supervisor` to their own
tree and may start more than one named pool. Compiler deadlines and render
limits belong to the call that uses them. Delivery-only hosts start no
Letterpress process.

This conclusion informs [ADR.003](../adr/ADR.003-caller-owned-supervision.md).
The normative worker behavior remains in
[LP.01 section 6](../specs/LP.01-letterpress-contract.md#6-supervised-compiler-worker).
