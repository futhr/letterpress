defmodule Letterpress.CompilerTest do
  @moduledoc false

  use ExUnit.Case, async: false

  import Letterpress.Test.Fixtures
  import ExUnit.CaptureLog

  alias Letterpress.{Artifact, Compiler}
  alias Letterpress.Compiler.Worker

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

    assert {:ok, second, _} =
             Letterpress.compile(
               "email/mjml-liquid@1",
               email_source(),
               email_schema(),
               email_compile_options()
             )

    assert Artifact.to_map(first) == Artifact.to_map(second)
  end

  test "compiles text artifacts without MJML output" do
    assert {:ok, artifact, []} =
             Letterpress.compile("text/liquid@1", text_source(), text_schema())

    assert artifact.html == nil
    assert artifact.text =~ ~s(letterpress_escape: "text")
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

    assert [
             %{
               "name" => "item.name",
               "local" => true,
               "binding" => %{"name" => "item", "collection" => "items"}
             }
           ] = analysis["variables"]
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
    [{pid, _}] = Registry.lookup(Letterpress.Compiler.Registry, 0)
    Process.exit(pid, :kill)

    assert eventually(fn ->
             case Registry.lookup(Letterpress.Compiler.Registry, 0) do
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

  test "reports ready, disabled, and unavailable compiler states" do
    assert Compiler.available?()
    assert Compiler.status() == :ready

    :ok = Supervisor.terminate_child(Letterpress.Supervisor, Letterpress.Compiler.Supervisor)
    refute Compiler.available?()
    assert Compiler.status() == :unavailable
    assert {:error, :compiler_unavailable} = Compiler.request(:contract, %{})

    previous = Application.get_env(:letterpress, :compiler_enabled)
    Application.put_env(:letterpress, :compiler_enabled, false)
    assert Compiler.status() == :disabled
    assert {:error, :compiler_disabled} = Compiler.request(:contract, %{})

    Application.put_env(:letterpress, :compiler_enabled, nil)
    assert Compiler.status() == :disabled
    assert {:error, :compiler_disabled} = Compiler.request(:contract, %{})

    on_exit(fn ->
      Application.put_env(:letterpress, :compiler_enabled, previous)

      case Supervisor.restart_child(Letterpress.Supervisor, Letterpress.Compiler.Supervisor) do
        {:ok, _} -> :ok
        {:ok, _, _} -> :ok
      end
    end)
  end

  test "normalizes invalid worker-count configuration at the status boundary" do
    previous = Application.get_env(:letterpress, :compiler_pool_size)

    on_exit(fn -> Application.put_env(:letterpress, :compiler_pool_size, previous) end)

    for configured <- [0, -1, nil, "one"] do
      Application.put_env(:letterpress, :compiler_pool_size, configured)
      assert Compiler.available?()
      assert Compiler.status() == :ready
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
    previous = Application.get_env(:letterpress, :compiler_timeout)
    Application.put_env(:letterpress, :compiler_timeout, 1)

    on_exit(fn -> Application.put_env(:letterpress, :compiler_timeout, previous) end)

    parent = self()

    capture_log(fn ->
      result =
        Compiler.request(:format, %{
          "profile" => "email/mjml-liquid@1",
          "source" => String.duplicate("<mj-text>x</mj-text>", 20_000)
        })

      send(parent, {:timeout_result, result})
      Process.sleep(20)
    end)

    assert_receive {:timeout_result, result}

    assert result in [{:error, :compiler_timeout}, {:error, :compiler_unavailable}]

    Application.put_env(:letterpress, :compiler_timeout, previous)
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
end
