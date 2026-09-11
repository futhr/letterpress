defmodule Letterpress.RendererTest do
  @moduledoc false

  use ExUnit.Case, async: false

  import Letterpress.Test.Fixtures

  alias Letterpress.{Artifact, CanonicalJSON}

  doctest Letterpress.Renderer
  doctest Letterpress.Renderer.ForTag

  setup do
    {:ok, email, _} =
      Letterpress.compile(
        "email/mjml-liquid@1",
        email_source(),
        email_schema(),
        email_compile_options()
      )

    {:ok, text, _} = Letterpress.compile("text/liquid@1", text_source(), text_schema())
    %{email: email, text: text}
  end

  test "renders structural Liquid and context-escapes text, URL, and subject", %{email: artifact} do
    assert {:ok, rendered} = Letterpress.render(artifact, email_values())
    assert rendered.html =~ "ADA &lt;LOVELACE&gt;"
    assert rendered.html =~ "https://example.test/account?a=1&amp;b=2"
    assert rendered.subject == "Notice for Ada <Lovelace>"
  end

  test "validates the complete subject after concatenating static and dynamic text", %{
    email: artifact
  } do
    assert {:error, [%{code: "LP_RENDER_LIQUID"}]} =
             Letterpress.render(artifact, email_values(), subject_max_bytes: 20)
  end

  test "rejects static subject line breaks atomically" do
    for subject <- ["Notice\rInjected", "Notice\nInjected", String.duplicate("x", 999)] do
      assert {:ok, artifact, _} =
               Letterpress.compile(
                 "email/mjml-liquid@1",
                 email_source(),
                 email_schema(),
                 Keyword.put(email_compile_options(), :subject, subject)
               )

      assert {:error, [%{code: "LP_RENDER_LIQUID"}]} =
               Letterpress.render(artifact, email_values())
    end
  end

  test "URL scheme options cannot widen the contract", %{email: artifact} do
    assert {:error, [%{code: "LP_OPTIONS_INVALID"}]} =
             Letterpress.render(artifact, email_values(), allowed_url_schemes: ["javascript"])
  end

  test "rejects obfuscated delivery URLs before rendering", %{email: artifact} do
    for url <- ["java\tscript:alert(1)", "/\\evil.test", "\\\\evil.test"] do
      assert {:error, [%{code: "LP_RENDER_VALUE_INVALID"}]} =
               Letterpress.render(artifact, Map.put(email_values(), "action_url", url))
    end
  end

  test "a false structural branch disappears", %{email: artifact} do
    values = Map.put(email_values(), "show_message", false)
    assert {:ok, rendered} = Letterpress.render(artifact, values)
    refute rendered.html =~ "Open account"
  end

  test "rejects unsafe URLs, missing values, wrong types, and oversized output", %{
    email: email,
    text: text
  } do
    assert {:error, diagnostics} =
             Letterpress.render(
               email,
               Map.put(email_values(), "action_url", "javascript:alert(1)")
             )

    assert Enum.any?(diagnostics, &(&1.code == "LP_RENDER_VALUE_INVALID"))

    assert {:error, diagnostics} = Letterpress.render(text, %{"name" => "Ada"})

    assert Enum.any?(diagnostics, fn diagnostic ->
             diagnostic.code == "LP_RENDER_VALUE_MISSING" and
               diagnostic.data == %{"variable" => "code"}
           end)

    assert {:error, diagnostics} =
             Letterpress.render(text, %{"name" => "Ada", "code" => 123})

    assert Enum.any?(diagnostics, &(&1.code == "LP_RENDER_VALUE_INVALID"))

    assert {:error, diagnostics} =
             Letterpress.render(text, %{"name" => "Ada", "code" => "123"}, max_output_bytes: 4)

    assert Enum.any?(diagnostics, &(&1.code == "LP_RENDER_OUTPUT_LIMIT"))
  end

  test "rendering does not depend on compiler process availability", %{text: artifact} do
    :ok = Supervisor.terminate_child(Letterpress.TestSupervisor, Letterpress.Compiler.Pool)

    assert {:ok, %{text: "Hello Ada, code 123"}} =
             Letterpress.render(artifact, %{"name" => "Ada", "code" => "123"})

    assert {:ok, _} =
             Supervisor.restart_child(Letterpress.TestSupervisor, Letterpress.Compiler.Pool)
  end

  test "rejects undeclared values and malformed runtime options", %{text: artifact} do
    values = %{"name" => "Ada", "code" => "123", "secret" => "do not accept me"}

    assert {:error, [%{code: "LP_RENDER_VALUE_UNKNOWN"}]} =
             Letterpress.render(artifact, values)

    assert {:ok, %{text: "Hello Ada, code 123"}} =
             Letterpress.render(artifact, values, strict_values: false)

    assert {:error, [%{code: "LP_OPTIONS_INVALID"}]} =
             Letterpress.render(artifact, values, timeout: 0)
  end

  test "keeps URL and subject limits local to each render call", %{email: artifact} do
    values = email_values()

    assert {:ok, rendered} = Letterpress.render(artifact, values)
    assert rendered.html =~ "https://example.test/account"

    assert {:error, [%{code: "LP_RENDER_LIQUID"}]} =
             Letterpress.render(artifact, values, allowed_url_schemes: ~w(mailto tel))

    assert {:error, [%{code: "LP_RENDER_LIQUID"}]} =
             Letterpress.render(artifact, values, subject_max_bytes: 5)
  end

  test "bounds nested Liquid loops independently of input collection limits" do
    source =
      "{% for first in items %}{% for second in items %}x{% endfor %}{% endfor %}"

    schema = %{
      "version" => 1,
      "variables" => %{
        "items" => %{
          "type" => "list",
          "context" => "none",
          "items" => %{"type" => "string"}
        }
      }
    }

    assert {:ok, artifact, []} = Letterpress.compile("text/liquid@1", source, schema)

    assert {:error, [%{code: "LP_RENDER_LOOP_LIMIT"}]} =
             Letterpress.render(artifact, %{"items" => List.duplicate("x", 101)})
  end

  test "zero loop limits take the else branch and nested bindings restore their parent" do
    schema = %{"version" => 1, "variables" => %{}}

    cases = [
      {"{% for item in (1..3) limit: 0 %}x{% else %}empty{% endfor %}", "empty"},
      {"{% for item in (1..2) %}{{ item }}{% for item in (3..4) %}{{ item }}{% endfor %}{{ item }}|{% endfor %}",
       "1341|2342|"}
    ]

    for {source, expected} <- cases do
      assert {:ok, artifact, []} = Letterpress.compile("text/liquid@1", source, schema)
      assert {:ok, %{text: ^expected}} = Letterpress.render(artifact, %{})
    end
  end

  test "applies nested defaults before rendering" do
    schema = %{
      "version" => 1,
      "variables" => %{
        "recipient" => %{
          "type" => "object",
          "context" => "text",
          "properties" => %{
            "name" => %{"type" => "string", "default" => "friend", "required" => false}
          }
        }
      }
    }

    assert {:ok, artifact, []} =
             Letterpress.compile("text/liquid@1", "Hello {{ recipient.name }}", schema)

    assert {:ok, %{text: "Hello friend"}} =
             Letterpress.render(artifact, %{"recipient" => %{}})
  end

  test "effective values cannot bypass input budgets through defaults" do
    cases = [
      {%{type: "string", default: String.duplicate("x", 100_001)}, "LP_RENDER_INPUT_SCALAR"},
      {%{type: "list", items: %{type: "string"}, default: List.duplicate("x", 1001)},
       "LP_RENDER_INPUT_ITEMS"},
      {%{
         type: "object",
         properties: %{child: %{type: "string", default: String.duplicate("x", 100_001)}},
         default: %{}
       }, "LP_RENDER_INPUT_SCALAR"}
    ]

    for {definition, code} <- cases do
      schema = %{version: 1, variables: %{value: definition}}
      assert {:ok, artifact, _} = Letterpress.compile("text/liquid@1", "{{ value }}", schema)
      assert {:error, [%{code: ^code}]} = Letterpress.render(artifact, %{})
    end
  end

  test "artifact validation runs under the render heap limit", %{text: artifact} do
    map =
      Artifact.to_map(artifact)
      |> Map.put(
        "lint",
        List.duplicate(%{"severity" => "hint", "code" => "test", "message" => "test"}, 20_000)
      )

    assert {:error, [%{code: "LP_RENDER_RESOURCE_LIMIT"}]} =
             Letterpress.render(map, %{}, max_heap_words: 10_000)
  end

  test "rejects every render-input budget violation before Liquid execution", %{text: artifact} do
    too_deep = Enum.reduce(1..13, "value", fn index, acc -> %{"level_#{index}" => acc} end)

    cases = [
      {%{"name" => "Ada", "code" => String.duplicate("x", 100_001)}, "LP_RENDER_INPUT_SCALAR"},
      {%{"name" => "Ada", "code" => "123", "extra" => too_deep}, "LP_RENDER_INPUT_DEPTH"},
      {Map.new(0..2000, &{"key_#{&1}", &1}), "LP_RENDER_INPUT_KEYS"},
      {%{"items" => Enum.to_list(0..1000)}, "LP_RENDER_INPUT_ITEMS"}
    ]

    for {values, code} <- cases do
      assert {:error, diagnostics} = Letterpress.render(artifact, values, strict_values: false)
      assert Enum.any?(diagnostics, &(&1.code == code)), inspect(diagnostics)
    end

    assert {:error, [%{code: "LP_RENDER_INVALID"}]} = Letterpress.render(artifact, self())
  end

  test "rejects a checksum-valid artifact containing unsupported Liquid", %{text: artifact} do
    map =
      artifact
      |> Artifact.to_map()
      |> Map.put("text", "{% assign secret = 'x' %}")
      |> Map.put("variables", [])
      |> Map.put("schema_sha256", CanonicalJSON.hash(%{"version" => 1, "variables" => %{}}))

    forged =
      Map.put(
        map,
        "content_sha256",
        map
        |> Map.delete("content_sha256")
        |> CanonicalJSON.hash()
      )

    assert {:error, [%{code: "LP_ARTIFACT_LIQUID"}]} = Letterpress.render(forged, %{})
  end

  test "preserves bounded Liquid range, reverse, offset, else, break, and continue semantics" do
    schema = %{
      "version" => 1,
      "variables" => %{
        "items" => %{
          "type" => "list",
          "context" => "none",
          "required" => false,
          "default" => [],
          "items" => %{"type" => "string"}
        }
      }
    }

    cases = [
      {"{% for item in (1..5) reversed limit: 2 offset: 1 %}{{ item }}{% endfor %}", "32"},
      {"{% for item in items %}x{% else %}empty{% endfor %}", "empty"},
      {"{% for item in (1..5) %}{% if item == 2 %}{% continue %}{% endif %}{{ item }}{% if item == 3 %}{% break %}{% endif %}{% endfor %}",
       "13"},
      {"{% for item in (1..4) limit: 2 %}{{ item }}{% endfor %}|{% for item in (1..4) offset: continue limit: 2 %}{{ item }}{% endfor %}",
       "12|34"}
    ]

    for {source, expected} <- cases do
      assert {:ok, artifact, _} = Letterpress.compile("text/liquid@1", source, schema)
      assert {:ok, %{text: ^expected}} = Letterpress.render(artifact, %{})
    end
  end
end
