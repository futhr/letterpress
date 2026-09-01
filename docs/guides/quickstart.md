# Quick start

Letterpress has two separate jobs: compile a template while an operator is
authoring it, then render the stored artifact when a notification is sent.
Source analysis, compilation, formatting, and translation run through the
bundled Node worker; only the email profile invokes MJML. Delivery rendering is
pure BEAM.

Add Letterpress to your dependencies:

```elixir
{:letterpress, "~> 0.1"}
```

On nodes that compile templates, add a compiler pool to the host application's
supervision tree:

```elixir
children = [
  {Letterpress.Compiler.Supervisor, pool_size: 2}
]

Supervisor.start_link(children, strategy: :one_for_one)
```

Letterpress does not start processes automatically. Delivery-only nodes omit
this child.

Define an explicit schema. Contexts describe where a value may be emitted;
they are security rules, not documentation labels.

The `text`, `url`, and compile-phase `color` contexts support the documented
compatible email sinks, so the same typed value can safely appear in HTML,
subject, and plain-text alternatives while each occurrence receives its
sink-specific validation and escaping.

```elixir
schema = %{
  "version" => 1,
  "variables" => %{
    "html_name" => %{"type" => "string", "context" => "html_text"},
    "subject_name" => %{"type" => "string", "context" => "subject"},
    "text_name" => %{"type" => "string", "context" => "text"},
    "action_url" => %{"type" => "url", "context" => "url"}
  }
}

source = """
<mjml>
  <mj-body>
    <mj-section>
      <mj-column>
        <mj-text>Hello {{ html_name }}</mj-text>
        <mj-button href="{{ action_url }}">Open account</mj-button>
      </mj-column>
    </mj-section>
  </mj-body>
</mjml>
"""

{:ok, artifact, diagnostics} =
  Letterpress.compile("email/mjml-liquid@1", source, schema,
    subject: "Welcome, {{ subject_name }}",
    text: "Hello {{ text_name }}. Open {{ action_url }}"
  )
```

Persist the complete artifact. At delivery, decode persisted JSON if needed
and render all channels atomically:

```elixir
{:ok, result} =
  Letterpress.render(artifact, %{
    "html_name" => "Taylor",
    "subject_name" => "Taylor",
    "text_name" => "Taylor",
    "action_url" => "https://example.test/account"
  })

send_email(result.subject, result.html, result.text)
```

Do not recompile in a queue worker and do not fall back to a permissive
renderer after a compiler failure. A publication without a valid artifact is
not deliverable.
