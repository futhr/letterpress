defmodule Letterpress.Bench do
  @moduledoc false

  @output_dir "bench/output"
  @markdown_file Path.join(@output_dir, "benchmarks.md")
  @full_config [warmup: 2, time: 5, memory_time: 1]
  @smoke_config [warmup: 0, time: 0.01, memory_time: 0]

  @spec run([String.t()]) :: map()
  def run(argv \\ System.argv()) do
    smoke? = "--smoke" in argv
    File.mkdir_p!(@output_dir)

    {:ok, supervisor} =
      Supervisor.start_link(
        [{Letterpress.Compiler.Supervisor, pool_size: 1}],
        strategy: :one_for_one
      )

    try do
      Benchee.run(
        scenarios(),
        Keyword.merge(bench_config(smoke?),
          percentiles: [50, 95, 99],
          formatters: [
            Benchee.Formatters.Console,
            {Benchee.Formatters.Markdown, file: @markdown_file, description: description(smoke?)}
          ]
        )
      )
    after
      Supervisor.stop(supervisor)
    end
  end

  defp scenarios do
    text_source = "Hello {{ name }}"
    text_schema = text_schema()
    text_artifact = compile!("text/liquid@1", text_source, text_schema)
    {:ok, text_json} = Letterpress.encode_artifact(text_artifact)

    loop_source = "{% for item in items %}{{ item }}{% endfor %}"
    loop_schema = loop_schema()
    loop_artifact = compile!("text/liquid@1", loop_source, loop_schema)
    loop_values = %{"items" => List.duplicate("item", 100)}

    email_source = email_source()
    email_schema = email_schema()
    email_options = email_options()
    email_artifact = compile!("email/mjml-liquid@1", email_source, email_schema, email_options)

    %{
      "render text scalar" => fn ->
        Letterpress.render(text_artifact, %{"name" => "Taylor"})
      end,
      "render text 100-item loop" => fn ->
        Letterpress.render(loop_artifact, loop_values)
      end,
      "render email channels" => fn ->
        Letterpress.render(email_artifact, email_values())
      end,
      "encode artifact" => fn ->
        Letterpress.encode_artifact(text_artifact)
      end,
      "decode artifact" => fn ->
        Letterpress.decode_artifact(text_json)
      end,
      "compile text" => fn ->
        Letterpress.compile("text/liquid@1", text_source, text_schema)
      end,
      "compile MJML email" => fn ->
        Letterpress.compile("email/mjml-liquid@1", email_source, email_schema, email_options)
      end
    }
  end

  defp compile!(profile, source, schema, options \\ []) do
    case Letterpress.compile(profile, source, schema, options) do
      {:ok, artifact, _diagnostics} -> artifact
      {:error, diagnostics} -> raise "benchmark fixture failed: #{inspect(diagnostics)}"
    end
  end

  defp text_schema do
    %{
      "version" => 1,
      "variables" => %{"name" => %{"type" => "string", "context" => "text"}}
    }
  end

  defp loop_schema do
    %{
      "version" => 1,
      "variables" => %{
        "items" => %{
          "type" => "list",
          "context" => "none",
          "items" => %{"type" => "string"}
        }
      }
    }
  end

  defp email_source do
    """
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
  end

  defp email_schema do
    %{
      "version" => 1,
      "variables" => %{
        "action_url" => %{"type" => "url", "context" => "url"},
        "html_name" => %{"type" => "string", "context" => "html_text"},
        "subject_name" => %{"type" => "string", "context" => "subject"},
        "text_name" => %{"type" => "string", "context" => "text"}
      }
    }
  end

  defp email_options do
    [
      subject: "Welcome, {{ subject_name }}",
      text: "Hello {{ text_name }}. Open {{ action_url }}"
    ]
  end

  defp email_values do
    %{
      "action_url" => "https://example.test/account",
      "html_name" => "Taylor",
      "subject_name" => "Taylor",
      "text_name" => "Taylor"
    }
  end

  defp bench_config(true), do: @smoke_config
  defp bench_config(false), do: @full_config

  defp description(true) do
    "Smoke run for scenario and documentation verification. Run `mix bench` for stable local measurements."
  end

  defp description(false) do
    "Stable local run of Letterpress rendering, artifact, and compiler boundaries."
  end
end

Letterpress.Bench.run()
