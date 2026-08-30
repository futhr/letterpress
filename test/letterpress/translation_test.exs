defmodule Letterpress.TranslationTest do
  @moduledoc false

  use ExUnit.Case, async: false

  test "extracts stable units and applies placeholder-preserving translations" do
    source = email_source()

    schema = %{
      "version" => 1,
      "variables" => %{"name" => %{"type" => "string", "context" => "html_text"}}
    }

    assert {:ok, [unit], _} =
             Letterpress.extract_translation_units("email/mjml-liquid@1", source, schema)

    assert {:ok, translated, _} =
             Letterpress.apply_translations(
               "email/mjml-liquid@1",
               source,
               schema,
               %{unit["id"] => "Hej {{ name }}"}
             )

    assert translated =~ "Hej {{ name }}"
  end

  test "missing units and changed placeholders fail closed" do
    source = email_source()

    schema = %{
      "version" => 1,
      "variables" => %{"name" => %{"type" => "string", "context" => "html_text"}}
    }

    {:ok, [unit], _} =
      Letterpress.extract_translation_units("email/mjml-liquid@1", source, schema)

    assert {:error, missing} =
             Letterpress.apply_translations("email/mjml-liquid@1", source, schema, %{})

    assert Enum.any?(missing, &(&1.code == "LP_TRANSLATION_MISSING"))

    assert {:error, changed} =
             Letterpress.apply_translations(
               "email/mjml-liquid@1",
               source,
               schema,
               %{unit["id"] => "Hej {{ other }}"}
             )

    assert Enum.any?(changed, &(&1.code == "LP_TRANSLATION_PLACEHOLDER"))
  end

  test "translates a text document as one unit while preserving Liquid" do
    source = "Hello {{ name }}{% if urgent %} — action required{% endif %}"

    schema = %{
      "version" => 1,
      "variables" => %{
        "name" => %{"type" => "string", "context" => "text"},
        "urgent" => %{"type" => "boolean", "context" => "none"}
      }
    }

    assert {:ok, [unit], []} =
             Letterpress.extract_translation_units("text/liquid@1", source, schema)

    assert unit["context"] == "text"
    assert unit["source"] == source
    assert unit["range"] == %{"start" => 0, "end" => String.length(source)}

    translated = "Hej {{ name }}{% if urgent %} — åtgärd krävs{% endif %}"

    assert {:ok, ^translated, []} =
             Letterpress.apply_translations(
               "text/liquid@1",
               source,
               schema,
               %{unit["id"] => translated}
             )
  end

  test "does not expose a translation unit for Liquid-only text" do
    source = "  {{ name }}{% if urgent %}{{ warning }}{% endif %}\n"

    schema = %{
      "version" => 1,
      "variables" => %{
        "name" => %{"type" => "string", "context" => "text"},
        "urgent" => %{"type" => "boolean", "context" => "none"},
        "warning" => %{"type" => "string", "context" => "text"}
      }
    }

    assert {:ok, [], []} =
             Letterpress.extract_translation_units("text/liquid@1", source, schema)
  end

  test "rejects text translations that change Liquid placeholders or control flow" do
    source = "Hello {{ name }}{% if urgent %}!{% endif %}"

    schema = %{
      "version" => 1,
      "variables" => %{
        "name" => %{"type" => "string", "context" => "text"},
        "urgent" => %{"type" => "boolean", "context" => "none"}
      }
    }

    assert {:ok, [unit], []} =
             Letterpress.extract_translation_units("text/liquid@1", source, schema)

    assert {:error, diagnostics} =
             Letterpress.apply_translations(
               "text/liquid@1",
               source,
               schema,
               %{unit["id"] => "Hej {{ other }}"}
             )

    assert Enum.any?(diagnostics, &(&1.code == "LP_TRANSLATION_PLACEHOLDER"))
  end

  defp email_source do
    "<mjml><mj-body><mj-section><mj-column><mj-text>Hello {{ name }}</mj-text></mj-column></mj-section></mj-body></mjml>"
  end
end
