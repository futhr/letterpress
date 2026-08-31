# Compiler and runtime

## Authoring nodes

The host starts a supervised pool of bundled Node workers. Each worker runs the
pinned official MJML compiler behind a framed JSON protocol. Requests have byte
and time limits; a crashed or late worker is replaced without desynchronizing
later requests.

```elixir
children = [
  {Letterpress.Compiler.Supervisor,
   pool_size: 2,
   max_frame_bytes: 2_000_000}
]

Supervisor.start_link(children, strategy: :one_for_one)
```

Letterpress has no application callback and reads no global application
configuration. The caller therefore chooses where the pool sits, how it is
supervised, and whether a node starts one at all.

For more than one pool, give each a distinct name and select it per call:

```elixir
children = [
  {Letterpress.Compiler.Supervisor, pool: MyApp.MarketingCompiler, pool_size: 2},
  {Letterpress.Compiler.Supervisor, pool: MyApp.TransactionalCompiler, pool_size: 4}
]

Letterpress.compile(profile, source, schema,
  compiler_pool: MyApp.TransactionalCompiler,
  compiler_timeout: 20_000
)
```

The worker launches with Node permission restrictions and a scrubbed
environment. Permission mode is defense in depth, not a substitute for normal
container or process isolation when template authors are untrusted.

## Delivery nodes

Delivery-only nodes omit the compiler child. Valid stored artifacts still
decode and render. Rendering runs in an isolated BEAM process with strict
variables, output limits, collection/loop budgets, a timeout, and an
allow-listed Liquid surface.

For email artifacts, pass the plain-text alternative as the `:text` compile
option. It is schema-checked and stored with the HTML and subject so delivery
renders all configured channels atomically.

```elixir
Letterpress.render(artifact, values,
  timeout: 5_000,
  max_output_bytes: 1_000_000,
  max_heap_words: 2_000_000,
  subject_max_bytes: 998,
  allowed_url_schemes: ~w(http https mailto tel cid)
)
```

Tune limits from measured templates. Increasing a limit changes resource
policy; it should be reviewed like any other capacity or abuse-control change.

## Artifact rules

Artifacts are canonical JSON with compiler provenance and a content hash.
Decode rejects missing, extra, or forged fields and unsupported versions. Keep
the artifact whole; extracting only generated HTML discards schema and
provenance needed for safe rendering and future migrations.
