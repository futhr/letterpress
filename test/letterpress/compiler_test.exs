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

    on_exit(fn ->
      Application.put_env(:letterpress, :compiler_enabled, previous)

      case Supervisor.restart_child(Letterpress.Supervisor, Letterpress.Compiler.Supervisor) do
        {:ok, _} -> :ok
        {:ok, _, _} -> :ok
      end
    end)
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
