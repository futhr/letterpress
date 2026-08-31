# Compiler and runtime

## Authoring nodes

The compiler starts a supervised pool of bundled Node workers. Each worker
runs the pinned official MJML compiler behind a framed JSON protocol. Requests
have byte and time limits; a crashed or late worker is replaced without
desynchronizing later requests.

```elixir
config :letterpress,
  compiler_enabled: true,
  compiler_pool_size: 2,
  compiler_timeout: 15_000,
  compiler_max_frame_bytes: 2_000_000
```

The worker launches with Node permission restrictions and a scrubbed
environment. Permission mode is defense in depth, not a substitute for normal
container or process isolation when template authors are untrusted.

## Delivery nodes

Delivery-only nodes can omit the compiler child:

```elixir
config :letterpress, compiler_enabled: false
```

Valid stored artifacts still decode and render. Rendering runs in an isolated
BEAM task with strict variables, output limits, collection/loop budgets, a
timeout, and an allow-listed Liquid surface.

For email artifacts, pass the plain-text alternative as the `:text` compile
option. It is schema-checked and stored with the HTML and subject so delivery
renders all configured channels atomically.

```elixir
config :letterpress,
  render_timeout: 5_000,
  render_max_output_bytes: 1_000_000,
  render_max_heap_words: 2_000_000,
  subject_max_bytes: 998
```

Tune limits from measured templates. Increasing a limit changes resource
policy; it should be reviewed like any other capacity or abuse-control change.

## Artifact rules

Artifacts are canonical JSON with compiler provenance and a content hash.
Decode rejects missing, extra, or forged fields and unsupported versions. Keep
the artifact whole; extracting only generated HTML discards schema and
provenance needed for safe rendering and future migrations.
