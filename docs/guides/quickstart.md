# Quick start

Letterpress has two separate jobs: compile a template while an operator is
authoring it, then render the stored artifact when a notification is sent.
Node and MJML are required for compilation. Delivery rendering is pure BEAM.

Add the Hex dependency and start the application normally:

```elixir
{:letterpress, "~> 0.1"}
```

Define an explicit schema. Contexts describe where a value may be emitted;
they are security rules, not documentation labels.

```elixir
schema = %{
  "version" => 1,
  "variables" => %{
    "name" => %{"type" => "string", "context" => "html_text"},
    "action_url" => %{"type" => "url", "context" => "url"}
  }
}

source = """
<mjml>
  <mj-body>
    <mj-section>
      <mj-column>
        <mj-text>Hello {{ name }}</mj-text>
        <mj-button href="{{ action_url }}">Open account</mj-button>
      </mj-column>
    </mj-section>
  </mj-body>
</mjml>
"""

{:ok, artifact, diagnostics} =
  Letterpress.compile("email/mjml-liquid@1", source, schema,
    subject: "Welcome, {{ name }}"
  )
```

Persist the complete artifact. At delivery, decode persisted JSON if needed
and render all channels atomically:

```elixir
{:ok, result} =
  Letterpress.render(artifact, %{
    "name" => "Taylor",
    "action_url" => "https://example.test/account"
  })

send_email(result.subject, result.html, result.text)
```

Do not recompile in a queue worker and do not fall back to a permissive
renderer after a compiler failure. A publication without a valid artifact is
not deliverable.
