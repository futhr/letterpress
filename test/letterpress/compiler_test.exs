defmodule Letterpress.CompilerTest do
  @moduledoc false

  use ExUnit.Case, async: false

  import Letterpress.Test.Fixtures
  import ExUnit.CaptureLog

  alias Letterpress.{Artifact, Compiler}
  alias Letterpress.Compiler.Worker

  doctest Letterpress.Compiler
  doctest Letterpress.Compiler.Supervisor
  doctest Letterpress.Compiler.Worker

  test "malformed response envelopes fail the caller and stop the protocol" do
    for response <- [
          %{"id" => "request", "ok" => true, "result" => 42},
          %{"id" => "request"},
          %{"id" => "request", "ok" => false, "error" => %{}}
        ] do
      reply = make_ref()
      timer = Process.send_after(self(), :unexpected_timeout, 60_000)

      state = %{
        port: :test_port,
        pending: %{
          id: "request",
          timer: timer,
          from: {self(), reply},
          deadline: System.monotonic_time(:millisecond) + 1000
        },
        queue: :queue.new(),
        waiting: %{},
        max_frame_bytes: 1000
      }

      frame = Jason.encode!(response)

      assert {:stop, :compiler_protocol_error, %{pending: nil}} =
               Letterpress.Compiler.Worker.handle_info({:test_port, {:data, frame}}, state)

      assert_receive {^reply, {:error, :compiler_protocol_error}}
    end
  end

  test "a request that expires before the worker handles it cannot succeed" do
    start_supervised!(
      {Letterpress.Compiler.Supervisor, pool: Letterpress.DeadlinePool, pool_size: 1}
    )

    assert {:ok, "warm"} =
             Letterpress.format("text/liquid@1", "warm", compiler_pool: Letterpress.DeadlinePool)

    [{pid, _}] = Registry.lookup(Letterpress.DeadlinePool, 0)
    :ok = :sys.suspend(pid)

    task =
      Task.async(fn ->
        Letterpress.format("text/liquid@1", "ok",
          compiler_pool: Letterpress.DeadlinePool,
          compiler_timeout: 10
        )
      end)

    try do
      Process.sleep(50)
    after
      :sys.resume(pid)
    end

    assert {:error, [%{code: "LP_COMPILER_TIMEOUT"}]} = Task.await(task)

    assert {:ok, "next"} =
             Letterpress.format("text/liquid@1", "next", compiler_pool: Letterpress.DeadlinePool)
  end

  test "a late response fails pending and queued callers and cancels their timers" do
    pending_reply = make_ref()
    queued_reply = make_ref()
    pending_timer = Process.send_after(self(), :unexpected_pending_timeout, 60_000)
    queued_timer = Process.send_after(self(), :unexpected_queued_timeout, 60_000)

    state = %{
      port: :test_port,
      pending: %{
        id: "pending",
        timer: pending_timer,
        from: {self(), pending_reply},
        deadline: System.monotonic_time(:millisecond) - 1
      },
      queue: :queue.from_list(["queued"]),
      waiting: %{"queued" => %{timer: queued_timer, from: {self(), queued_reply}}},
      max_frame_bytes: 1000
    }

    frame = Jason.encode!(%{id: "pending", ok: true, result: %{formatted: "late"}})

    assert {:stop, :compiler_timeout, stopped} =
             Worker.handle_info({:test_port, {:data, frame}}, state)

    assert stopped.pending == nil
    assert stopped.waiting == %{}
    assert :queue.is_empty(stopped.queue)
    assert_receive {^pending_reply, {:error, :compiler_timeout}}
    assert_receive {^queued_reply, {:error, :compiler_timeout}}
    assert Process.read_timer(pending_timer) == false
    assert Process.read_timer(queued_timer) == false
    refute_received {^pending_reply, {:ok, _}}
  end

  test "compile numbers retain exact values through the Node boundary" do
    for {number, type} <- [
          {9_007_199_254_740_993, "integer"},
          {-9_007_199_254_740_993, "integer"},
          {1.0, "number"}
        ] do
      definition = %{"type" => type, "phase" => "compile"}
      schema = %{"version" => 1, "variables" => %{"n" => definition}}

      assert {:ok, artifact, []} =
               Letterpress.compile("text/liquid@1", "{{ n }}", schema,
                 compile_values: %{n: number}
               )

      assert {:ok, %{text: text}} = Letterpress.render(artifact, %{})
      assert text == to_string(number)

      schema = put_in(schema, ["variables", "n", "default"], number)
      assert {:ok, artifact, []} = Letterpress.compile("text/liquid@1", "{{ n }}", schema)
      assert {:ok, %{text: ^text}} = Letterpress.render(artifact, %{})
    end
  end

  test "queued requests expire independently while the compiler is paused" do
    start_supervised!(
      {Letterpress.Compiler.Supervisor, pool: Letterpress.QueueDeadlinePool, pool_size: 1}
    )

    opts = [compiler_pool: Letterpress.QueueDeadlinePool]
    assert {:ok, "warm"} = Letterpress.format("text/liquid@1", "warm", opts)
    [{pid, _}] = Registry.lookup(Letterpress.QueueDeadlinePool, 0)
    {:os_pid, os_pid} = Port.info(:sys.get_state(pid).port, :os_pid)
    {_, 0} = signal_compiler(os_pid, "-STOP")

    task = Task.async(fn -> Letterpress.format("text/liquid@1", "first", opts) end)

    try do
      assert eventually(fn -> :sys.get_state(pid).pending != nil end)

      assert {:error, [%{code: "LP_COMPILER_TIMEOUT"}]} =
               Letterpress.format(
                 "text/liquid@1",
                 "expired",
                 Keyword.put(opts, :compiler_timeout, 20)
               )
    after
      signal_compiler(os_pid, "-CONT")
    end

    assert {:ok, "first"} = Task.await(task)
    assert {:ok, "next"} = Letterpress.format("text/liquid@1", "next", opts)
  end

  test "compile numbers nested in objects retain their exact values" do
    for {number, type} <- [
          {9_007_199_254_740_993, "integer"},
          {-9_007_199_254_740_993, "integer"},
          {1.0, "number"}
        ] do
      schema = %{
        version: 1,
        variables: %{
          totals: %{
            type: "object",
            phase: "compile",
            properties: %{
              invoice: %{type: "object", properties: %{amount: %{type: type}}}
            }
          }
        }
      }

      assert {:ok, artifact, []} =
               Letterpress.compile("text/liquid@1", "{{ totals.invoice.amount }}", schema,
                 compile_values: %{totals: %{invoice: %{amount: number}}}
               )

      assert {:ok, json} = Letterpress.encode_artifact(artifact)
      assert {:ok, decoded} = Letterpress.decode_artifact(json)
      assert {:ok, %{text: text}} = Letterpress.render(decoded, %{})
      assert text == to_string(number)
    end
  end

  test "sentinel restoration treats dollar replacement patterns literally" do
    schema = %{"version" => 1, "variables" => %{}}

    for suffix <- ["$&", "$$", "$`", "$'"] do
      source = "before {{ \"x\" | append: \"#{suffix}\" }} after"
      expected = "before x#{suffix} after"
      assert {:ok, artifact, []} = Letterpress.compile("text/liquid@1", source, schema)
      assert {:ok, %{text: ^expected}} = Letterpress.render(artifact, %{})
    end
  end

  test "compiles deterministic email artifacts through the supervised official worker" do
    assert {:ok, first, diagnostics} =
             Letterpress.compile(
               "email/mjml-liquid@1",
               email_source(),
               email_schema(),
               email_compile_options()
             )

    assert Enum.all?(diagnostics, &(&1.severity != :error))
    assert first.profile == "email/mjml-liquid@1"
    assert first.compiler["mjml"] == "5.4.0"
    assert first.compiler["parser"] == "2.10.0"
    assert first.html =~ "{% if show_message %}"
    assert first.html =~ ~s(letterpress_escape: "html_text")
    assert first.html =~ ~s(letterpress_escape: "url")
    assert first.html =~ "#3366ff"
    assert first.subject =~ ~s(letterpress_escape: "subject")
    assert first.text =~ ~s(letterpress_escape: "text")
    assert first.html =~ ~s(<title>{{ title | letterpress_escape: "html_text" }}</title>)

    assert first.html =~
             ~s(aria-label="{{ title | letterpress_escape: "html_attribute" }}")

    assert {:ok, second, _} =
             Letterpress.compile(
               "email/mjml-liquid@1",
               email_source(),
               email_schema(),
               email_compile_options()
             )

    assert Artifact.to_map(first) == Artifact.to_map(second)
  end

  test "compile-phase values obey their declared types and URL contexts" do
    for {type, context, source, value} <- [
          {"integer", "text", "{{ value }}", "not an integer"},
          {"string", "url", ~s(<a href="{{ value }}">Open</a>), "javascript:alert(1)"}
        ] do
      schema = %{
        "version" => 1,
        "variables" => %{
          "value" => %{"type" => type, "phase" => "compile", "context" => context}
        }
      }

      profile = if context == "url", do: "html/liquid@1", else: "text/liquid@1"

      assert {:error, diagnostics} =
               Letterpress.compile(profile, source, schema, compile_values: %{"value" => value})

      assert Enum.any?(diagnostics, &(&1.code == "LP_COMPILE_VALUE_INVALID"))
    end
  end

  test "compile-phase attributes cannot break out of single quotes" do
    schema = %{
      "version" => 1,
      "variables" => %{
        "value" => %{"type" => "string", "phase" => "compile", "context" => "html_attribute"}
      }
    }

    assert {:ok, artifact, []} =
             Letterpress.compile("html/liquid@1", "<p title='{{ value }}'>Text</p>", schema,
               compile_values: %{"value" => "' onclick='alert(1)"}
             )

    assert artifact.html == "<p title='&#39; onclick=&#39;alert(1)'>Text</p>"
  end

  test "compiles text artifacts without MJML output" do
    assert {:ok, artifact, []} =
             Letterpress.compile("text/liquid@1", text_source(), text_schema())

    assert artifact.html == nil
    assert artifact.text =~ ~s(letterpress_escape: "text")
  end

  test "compiles bounded HTML fragments with final output-context escaping" do
    schema = %{
      "version" => 1,
      "variables" => %{
        "action_url" => %{"type" => "url", "context" => "url"},
        "name" => %{"type" => "string", "context" => "html_text"}
      }
    }

    source = ~s(<p>Hello <strong>{{ name }}</strong>. <a href="{{ action_url }}">Open</a></p>)

    assert {:ok, artifact, []} = Letterpress.compile("html/liquid@1", source, schema)
    assert artifact.profile == "html/liquid@1"
    assert artifact.text == nil
    assert artifact.subject == nil
    assert artifact.html =~ ~s(letterpress_escape: "html_text")
    assert artifact.html =~ ~s(letterpress_escape: "url")

    assert {:ok, %{html: html}} =
             Letterpress.render(artifact, %{
               "name" => "<script>alert(1)</script>",
               "action_url" => "https://example.test/?a=1&b=2"
             })

    assert html =~ "&lt;script&gt;alert(1)&lt;/script&gt;"
    assert html =~ "https://example.test/?a=1&amp;b=2"

    assert [%{"context" => "html_text"}] = artifact.translation_units
  end

  test "rejects unsafe HTML fragment elements and attributes" do
    schema = %{"version" => 1, "variables" => %{}}

    assert {:error, diagnostics} =
             Letterpress.compile(
               "html/liquid@1",
               ~s|<p onclick="steal()">safe</p><script>alert(1)</script>|,
               schema
             )

    assert Enum.any?(diagnostics, &(&1.code == "LP_HTML_ATTRIBUTE_FORBIDDEN"))
    assert Enum.any?(diagnostics, &(&1.code == "LP_HTML_ELEMENT_FORBIDDEN"))
  end

  test "rejects dynamic attributes and unsafe static HTML URLs" do
    schema = %{
      "version" => 1,
      "variables" => %{
        "attribute" => %{"type" => "string", "context" => "html_attribute"}
      }
    }

    for source <- [
          ~s|<p {{ attribute }}>unsafe</p>|,
          ~s|<a href="javascript:alert(1)">unsafe</a>|,
          ~s|<a href="//example.test/steal">unsafe</a>|,
          ~s|<a href="javascript&#58;alert(1)">unsafe</a>|
        ] do
      assert {:error, diagnostics} = Letterpress.compile("html/liquid@1", source, schema)
      assert Enum.any?(diagnostics, &(&1.code == "LP_HTML_ATTRIBUTE_FORBIDDEN"))
    end
  end

  test "validates and renders an email text alternative atomically" do
    assert {:ok, artifact, diagnostics} =
             Letterpress.compile(
               "email/mjml-liquid@1",
               email_source(),
               email_schema(),
               email_compile_options()
             )

    assert Enum.all?(diagnostics, &(&1.severity != :error))

    assert {:ok, rendered} = Letterpress.render(artifact, email_values())
    assert rendered.text == "Hello Ada <Lovelace>. Open https://example.test/account?a=1&b=2"

    assert {:error, text_diagnostics} =
             Letterpress.compile(
               "email/mjml-liquid@1",
               email_source(),
               email_schema(),
               Keyword.put(email_compile_options(), :text, "Unknown {{ missing }}")
             )

    assert Enum.any?(text_diagnostics, &(&1.code == "LP_SCHEMA_UNDECLARED_VARIABLE"))
  end

  test "declared-variable usage is calculated across HTML, subject, and text" do
    schema = %{
      "version" => 1,
      "variables" => %{
        "body" => %{"type" => "string", "context" => "text"},
        "subject_only" => %{"type" => "string", "context" => "subject"},
        "text_only" => %{"type" => "string", "context" => "text"}
      }
    }

    source =
      "<mjml><mj-body><mj-section><mj-column><mj-text>{{ body }}</mj-text></mj-column></mj-section></mj-body></mjml>"

    assert {:ok, _, diagnostics} =
             Letterpress.compile("email/mjml-liquid@1", source, schema,
               subject: "{{ subject_only }}",
               text: "{{ text_only }}"
             )

    refute Enum.any?(diagnostics, &(&1.code == "LP_SCHEMA_UNUSED_VARIABLE"))
  end

  test "one typed value may span compatible email output contexts" do
    source = """
    <mjml>
      <mj-head>
        <mj-title>{{ label }}</mj-title>
        <mj-style>.accent { border-color: {{ accent }}; }</mj-style>
      </mj-head>
      <mj-body>
        <mj-section>
          <mj-column>
            <mj-image src="https://example.test/logo.png" alt="{{ label }}" />
            <mj-text color="{{ accent }}">
              {{ label }} <a href="{{ action_url }}">{{ action_url }}</a>
            </mj-text>
          </mj-column>
        </mj-section>
      </mj-body>
    </mjml>
    """

    schema = %{
      "version" => 1,
      "variables" => %{
        "accent" => %{"type" => "string", "phase" => "compile", "context" => "color"},
        "action_url" => %{"type" => "url", "context" => "url"},
        "label" => %{"type" => "string", "context" => "text"}
      }
    }

    assert {:ok, artifact, diagnostics} =
             Letterpress.compile("email/mjml-liquid@1", source, schema,
               subject: "{{ label }}",
               text: "{{ label }}: {{ action_url }}",
               compile_values: %{"accent" => "#336699"}
             )

    assert Enum.all?(diagnostics, &(&1.severity != :error))

    assert {:ok, rendered} =
             Letterpress.render(artifact, %{
               "action_url" => "https://example.test/path?a=1&b=2",
               "label" => ~s(Acme "North")
             })

    assert rendered.subject == ~s(Acme "North")
    assert rendered.text == ~s(Acme "North": https://example.test/path?a=1&b=2)
    assert rendered.html =~ ~s(alt="Acme &quot;North&quot;")
    assert rendered.html =~ "https://example.test/path?a=1&amp;b=2"
  end

  test "discovers variable contexts before a consumer schema exists" do
    source = """
    <mjml><mj-body><mj-section><mj-column><mj-text>
      Hello {{ user.name }}. <a href="{{ action_url }}">Open</a>
    </mj-text></mj-column></mj-section></mj-body></mjml>
    """

    assert {:ok, analysis, []} = Letterpress.discover("email/mjml-liquid@1", source)

    assert Enum.map(analysis["variables"], &{&1["name"], &1["context"]}) == [
             {"user.name", "html_text"},
             {"action_url", "url"}
           ]

    assert {:error, diagnostics} =
             Letterpress.discover(
               "email/mjml-liquid@1",
               "<mjml><mj-body><mj-text>{{ name | escape }}</mj-text></mj-body></mjml>"
             )

    assert Enum.any?(diagnostics, &(&1.code == "LP_LIQUID_FILTER_FORBIDDEN"))
  end

  test "discovers control-flow dependencies without treating loop locals as schema variables" do
    source = "{% if enabled %}{% for item in items %}{{ item.name }}{% endfor %}{% endif %}"

    assert {:ok, analysis, []} = Letterpress.discover("text/liquid@1", source)

    assert Enum.map(analysis["dependencies"], &{&1["name"], &1["context"], &1["kind"]}) == [
             {"enabled", "none", "condition"},
             {"items", "none", "collection"}
           ]

    assert Enum.all?(analysis["dependencies"], &(&1["local"] == false))

    assert [
             %{
               "name" => "item.name",
               "local" => true,
               "binding" => %{"name" => "item", "collection" => "items"}
             }
           ] = analysis["variables"]
  end

  test "rejects legacy Mustache and Handlebars constructs with one stable diagnostic" do
    for source <- ["{{#enabled}}yes{{/enabled}}", "{{#if enabled}}yes{{/if}}", "{{{html}}}"] do
      assert {:error, diagnostics} = Letterpress.discover("text/liquid@1", source)
      assert [%{code: "LP_LEGACY_SYNTAX", data: %{}}] = diagnostics
    end
  end

  test "discovers nested loop collections as scoped dependencies" do
    source =
      "{% for user in users %}{{ user.name }}{% for order in user.orders %}{{ order.id }}{% endfor %}{% endfor %}"

    assert {:ok, analysis, []} = Letterpress.discover("text/liquid@1", source)

    assert [
             %{"name" => "users", "kind" => "collection", "local" => false},
             %{
               "name" => "user.orders",
               "kind" => "collection",
               "local" => true,
               "binding" => %{"name" => "user", "collection" => "users"}
             }
           ] = analysis["dependencies"]

    schema = %{
      "version" => 1,
      "variables" => %{
        "users" => %{
          "type" => "list",
          "items" => %{
            "type" => "object",
            "properties" => %{
              "name" => %{"type" => "string"},
              "orders" => %{
                "type" => "list",
                "items" => %{
                  "type" => "object",
                  "properties" => %{"id" => %{"type" => "string"}}
                }
              }
            }
          }
        }
      }
    }

    assert {:ok, _, []} = Letterpress.compile("text/liquid@1", source, schema)
  end

  test "reports forbidden elements, tags, filters, contexts, and undeclared variables" do
    cases = [
      {"<mjml><mj-body><mj-include path=\"x\" /></mj-body></mjml>", "LP_MJML_ELEMENT_FORBIDDEN"},
      {"<mjml><mj-body><mj-raw>{% raw %}x{% endraw %}</mj-raw></mj-body></mjml>",
       "LP_LIQUID_TAG_FORBIDDEN"},
      {"<mjml><mj-body><mj-text>{{ name | escape }}</mj-text></mj-body></mjml>",
       "LP_LIQUID_FILTER_FORBIDDEN"},
      {"<mjml><mj-body><mj-text>{{ missing }}</mj-text></mj-body></mjml>",
       "LP_SCHEMA_UNDECLARED_VARIABLE"}
    ]

    for {source, expected_code} <- cases do
      assert {:error, diagnostics} =
               Letterpress.compile("email/mjml-liquid@1", source, text_schema())

      assert Enum.any?(diagnostics, &(&1.code == expected_code)),
             "#{source}: #{inspect(diagnostics)}"
    end
  end

  test "a killed compiler worker is supervised and later requests recover" do
    [{pid, _}] = Registry.lookup(Letterpress.Compiler.Pool, 0)
    Process.exit(pid, :kill)

    assert eventually(fn ->
             case Registry.lookup(Letterpress.Compiler.Pool, 0) do
               [{replacement, _}] -> replacement != pid and Process.alive?(replacement)
               _ -> false
             end
           end)

    assert {:ok, _} = Compiler.request(:contract, %{})
  end

  test "formats idempotently with the pinned Liquid formatter" do
    source =
      "<mjml><mj-body><mj-section><mj-column><mj-text>Hello</mj-text></mj-column></mj-section></mj-body></mjml>"

    assert {:ok, once} = Letterpress.format("email/mjml-liquid@1", source)
    assert {:ok, twice} = Letterpress.format("email/mjml-liquid@1", once)
    assert once == twice
  end

  test "reports ready and unavailable compiler states" do
    assert Compiler.available?()
    assert Compiler.status() == :ready

    :ok = Supervisor.terminate_child(Letterpress.TestSupervisor, Letterpress.Compiler.Pool)
    refute Compiler.available?()
    assert Compiler.status() == :unavailable
    assert {:error, :compiler_unavailable} = Compiler.request(:contract, %{})

    on_exit(fn ->
      case Supervisor.restart_child(Letterpress.TestSupervisor, Letterpress.Compiler.Pool) do
        {:ok, _} -> :ok
        {:ok, _, _} -> :ok
      end
    end)
  end

  test "supports independently named caller-owned compiler pools" do
    pool = Letterpress.Test.SecondCompilerPool

    start_supervised!({Letterpress.Compiler.Supervisor, pool: pool, pool_size: 1})

    assert Compiler.status(pool: pool) == :ready
    assert {:ok, contract} = Compiler.request(:contract, %{}, pool: pool)
    assert contract["contract_version"] == 1

    assert {:ok, artifact, []} =
             Letterpress.compile("text/liquid@1", text_source(), text_schema(),
               compiler_pool: pool
             )

    assert artifact.profile == "text/liquid@1"
  end

  test "rejects invalid compiler child options" do
    assert_raise NimbleOptions.ValidationError, fn ->
      Letterpress.Compiler.Supervisor.child_spec(pool_size: 0)
    end
  end

  test "recognizes scoped loop variables without weakening schema checks" do
    source = "{% for item in items %}{{ item.name }}{% endfor %}"

    schema = %{
      "version" => 1,
      "variables" => %{
        "items" => %{
          "type" => "list",
          "context" => "none",
          "items" => %{
            "type" => "object",
            "properties" => %{"name" => %{"type" => "string"}}
          }
        }
      }
    }

    assert {:ok, artifact, []} = Letterpress.compile("text/liquid@1", source, schema)
    assert artifact.text =~ ~s(item.name | letterpress_escape: "text")

    assert {:ok, %{text: "AdaGrace"}} =
             Letterpress.render(artifact, %{
               "items" => [%{"name" => "Ada"}, %{"name" => "Grace"}]
             })
  end

  test "worker boundary rejects invalid targets, operations, and oversized frames" do
    assert {:error, :compiler_unavailable} = Worker.request(99, :contract, %{}, 100)

    assert {:error, {:compiler_error, message}} =
             Worker.request(0, :unsupported, %{}, 1_000)

    assert message =~ "unsupported operation"

    assert {:error, :compiler_frame_too_large} =
             Compiler.request(:contract, %{"padding" => String.duplicate("x", 2_000_000)})

    assert {:ok, _} = Compiler.request(:contract, %{})
  end

  test "accepts safe rich email content and exact official MJML attributes" do
    source = """
    <mjml lang="en" dir="ltr">
      <mj-head>
        <mj-attributes>
          <mj-class name="body" color="#112233" />
        </mj-attributes>
      </mj-head>
      <mj-body>
        <mj-section padding="8px">
          <mj-column>
            <mj-text mj-class="body">
              Hello <strong>{{ name }}</strong>
              <a href="{{ action_url }}" rel="noopener" data-track="account">Open</a>
            </mj-text>
          </mj-column>
        </mj-section>
      </mj-body>
    </mjml>
    """

    schema = %{
      "version" => 1,
      "variables" => %{
        "action_url" => %{"type" => "url", "context" => "url"},
        "name" => %{"type" => "string", "context" => "html_text"}
      }
    }

    assert {:ok, artifact, []} = Letterpress.compile("email/mjml-liquid@1", source, schema)
    assert artifact.html =~ "<strong>"
    assert artifact.html =~ ~s(letterpress_escape: "url")
  end

  test "rejects unsafe embedded HTML and attributes that belong to another MJML element" do
    cases = [
      {"<mjml><mj-body><mj-section href=\"https://example.test\"><mj-column /></mj-section></mj-body></mjml>",
       "LP_MJML_ATTRIBUTE_FORBIDDEN"},
      {"<mjml><mj-body><mj-section><mj-column><mj-text><script>alert(1)</script></mj-text></mj-column></mj-section></mj-body></mjml>",
       "LP_HTML_ELEMENT_FORBIDDEN"},
      {"<mjml><mj-body><mj-section><mj-column><mj-text><a href=\"https://example.test\" onclick=\"steal()\">Open</a></mj-text></mj-column></mj-section></mj-body></mjml>",
       "LP_HTML_ATTRIBUTE_FORBIDDEN"}
    ]

    for {source, code} <- cases do
      assert {:error, diagnostics} =
               Letterpress.compile(
                 "email/mjml-liquid@1",
                 source,
                 %{"version" => 1, "variables" => %{}}
               )

      assert Enum.any?(diagnostics, &(&1.code == code)), inspect(diagnostics)
    end
  end

  @tag capture_log: true
  test "a worker timeout fails closed and supervision restores service" do
    parent = self()

    capture_log(fn ->
      result =
        Compiler.request(
          :format,
          %{
            "profile" => "email/mjml-liquid@1",
            "source" => String.duplicate("<mj-text>x</mj-text>", 20_000)
          },
          timeout: 1
        )

      send(parent, {:timeout_result, result})
      Process.sleep(20)
    end)

    assert_receive {:timeout_result, result}

    assert result in [{:error, :compiler_timeout}, {:error, :compiler_unavailable}]

    assert eventually(fn -> match?({:ok, _}, Compiler.request(:contract, %{})) end)
  end

  defp eventually(fun, attempts \\ 50)

  defp eventually(fun, attempts) when attempts > 0 do
    if fun.() do
      true
    else
      Process.sleep(20)
      eventually(fun, attempts - 1)
    end
  end

  defp eventually(_, 0), do: false

  defp signal_compiler(os_pid, signal) do
    environment = Enum.map(System.get_env(), fn {key, _} -> {key, nil} end)
    System.cmd("kill", [signal, to_string(os_pid)], env: environment)
  end
end
