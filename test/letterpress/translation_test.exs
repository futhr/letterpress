defmodule Letterpress.TranslationTest do
  @moduledoc false

  use ExUnit.Case, async: false

  test "localized channels respect source budgets after all replacements" do
    source =
      "<mjml><mj-body><mj-section><mj-column><mj-text>Hello</mj-text><mj-text>Goodbye</mj-text></mj-column></mj-section></mj-body></mjml>"

    schema = %{version: 1, variables: %{}}

    assert {:ok, units, []} =
             Letterpress.extract_translation_units("email/mjml-liquid@1", source, schema)

    translations = Map.new(units, &{&1["id"], String.duplicate("x", 260_000)})

    assert {:error, diagnostics} =
             Letterpress.localize("email/mjml-liquid@1", source, schema, translations)

    assert Enum.any?(diagnostics, &(&1.code == "LP_SOURCE_TOO_LARGE"))
  end

  test "attribute escaping counts toward the localized source budget" do
    source =
      "<mjml><mj-body><mj-section><mj-column><mj-image src=\"https://example.test/image\" alt=\"Hello\" /></mj-column></mj-section></mj-body></mjml>"

    schema = %{version: 1, variables: %{}}

    assert {:ok, [unit], []} =
             Letterpress.extract_translation_units("email/mjml-liquid@1", source, schema)

    assert {:error, diagnostics} =
             Letterpress.localize("email/mjml-liquid@1", source, schema, %{
               unit["id"] => String.duplicate("\"", 90_000)
             })

    assert Enum.any?(diagnostics, &(&1.code == "LP_SOURCE_TOO_LARGE"))
  end

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

  test "extracts and localizes every email channel atomically" do
    source = email_source()
    subject = "Welcome {{ name }}"
    text = "Hello {{ name }}"

    schema = %{
      "version" => 1,
      "variables" => %{"name" => %{"type" => "string", "context" => "text"}}
    }

    assert {:ok, units, []} =
             Letterpress.extract_translation_units(
               "email/mjml-liquid@1",
               source,
               schema,
               subject: subject,
               text: text
             )

    channels =
      units
      |> Enum.map(& &1["channel"])
      |> Enum.sort()

    unit_ids =
      units
      |> Enum.map(& &1["id"])
      |> Enum.uniq()

    assert channels == ["html", "subject", "text"]
    assert length(unit_ids) == 3

    translations =
      Map.new(units, fn unit ->
        translated =
          case unit["channel"] do
            "html" -> "Hej {{ name }}"
            "subject" -> "Välkommen {{ name }}"
            "text" -> "Hej {{ name }}"
          end

        {unit["id"], translated}
      end)

    assert {:ok,
            %{
              source: localized_source,
              subject: "Välkommen {{ name }}",
              text: "Hej {{ name }}"
            }, []} =
             Letterpress.localize(
               "email/mjml-liquid@1",
               source,
               schema,
               translations,
               subject: subject,
               text: text
             )

    assert localized_source =~ "Hej {{ name }}"

    assert {:ok, artifact, []} =
             Letterpress.compile(
               "email/mjml-liquid@1",
               localized_source,
               schema,
               subject: "Välkommen {{ name }}",
               text: "Hej {{ name }}"
             )

    artifact_channels =
      artifact.translation_units
      |> Enum.map(& &1["channel"])
      |> Enum.sort()

    assert artifact_channels == ["html", "subject", "text"]

    assert {:ok, encoded} = Letterpress.encode_artifact(artifact)
    assert {:ok, ^artifact} = Letterpress.decode_artifact(encoded)

    assert {:error, diagnostics} =
             Letterpress.localize(
               "email/mjml-liquid@1",
               source,
               schema,
               Map.delete(translations, hd(units)["id"]),
               subject: subject,
               text: text
             )

    assert Enum.any?(diagnostics, &(&1.code == "LP_TRANSLATION_MISSING"))
  end

  test "identical sibling copy has distinct translation identities" do
    source =
      "<mjml><mj-body><mj-section><mj-column><mj-text>Hello</mj-text><mj-text>Hello</mj-text></mj-column></mj-section></mj-body></mjml>"

    schema = %{"version" => 1, "variables" => %{}}

    assert {:ok, [first, second], []} =
             Letterpress.extract_translation_units("email/mjml-liquid@1", source, schema)

    refute first["id"] == second["id"]

    assert {:ok, translated, []} =
             Letterpress.apply_translations("email/mjml-liquid@1", source, schema, %{
               first["id"] => "Hej",
               second["id"] => "Välkommen"
             })

    assert translated =~ "<mj-text>Hej</mj-text><mj-text>Välkommen</mj-text>"
  end

  test "translations reject NUL and multiline subjects before returning localized source" do
    schema = %{"version" => 1, "variables" => %{}}

    assert {:ok, [unit], []} =
             Letterpress.extract_translation_units("text/liquid@1", "Hello", schema)

    assert {:error, _} =
             Letterpress.apply_translations("text/liquid@1", "Hello", schema, %{
               unit["id"] => "Hello\0"
             })

    source = String.replace(email_source(), "{{ name }}", "friend")

    assert {:ok, units, []} =
             Letterpress.extract_translation_units("email/mjml-liquid@1", source, schema,
               subject: "Welcome"
             )

    translations =
      Map.new(units, fn unit ->
        {unit["id"],
         if(unit["channel"] == "subject", do: "Welcome\r\nInjected", else: unit["source"])}
      end)

    assert {:error, _} =
             Letterpress.localize("email/mjml-liquid@1", source, schema, translations,
               subject: "Welcome"
             )
  end

  test "extracts human-facing email attributes and escapes translated quotes" do
    source =
      ~s(<mjml><mj-body><mj-section><mj-column><mj-image src="https://example.test/logo.png" alt="Hello {{ name }}" /></mj-column></mj-section></mj-body></mjml>)

    schema = %{
      "version" => 1,
      "variables" => %{"name" => %{"type" => "string", "context" => "text"}}
    }

    assert {:ok, [unit], []} =
             Letterpress.extract_translation_units("email/mjml-liquid@1", source, schema)

    assert unit["context"] == "html_attribute"
    assert unit["source"] == "Hello {{ name }}"

    assert {:ok, localized, []} =
             Letterpress.apply_translations("email/mjml-liquid@1", source, schema, %{
               unit["id"] => ~s(Hej "{{ name }}")
             })

    assert localized =~ ~s(alt="Hej &quot;{{ name }}&quot;")
    assert {:ok, artifact, []} = Letterpress.compile("email/mjml-liquid@1", localized, schema)
    assert {:ok, %{html: html}} = Letterpress.render(artifact, %{"name" => "Ada"})
    assert html =~ ~s(alt="Hej &quot;Ada&quot;")
  end

  test "attribute translations preserve entities and do not overlap text units" do
    source =
      ~s(<mjml><mj-body><mj-section><mj-column><mj-image src="https://example.test/logo.png" alt="Tea &amp; coffee" /><mj-text>Hello <span title="Greeting">friend</span></mj-text></mj-column></mj-section></mj-body></mjml>)

    schema = %{"version" => 1, "variables" => %{}}

    assert {:ok, [attribute, text], []} =
             Letterpress.extract_translation_units("email/mjml-liquid@1", source, schema)

    assert attribute["source"] == "Tea &amp; coffee"
    assert text["source"] == ~s(Hello <span title="Greeting">friend</span>)

    assert {:ok, ^source, []} =
             Letterpress.apply_translations("email/mjml-liquid@1", source, schema, %{
               attribute["id"] => attribute["source"],
               text["id"] => text["source"]
             })

    assert {:ok, localized, []} =
             Letterpress.apply_translations("email/mjml-liquid@1", source, schema, %{
               attribute["id"] => "Tea &amp; cake & coffee",
               text["id"] => ~s(Hej <span title="Greeting">vän</span>)
             })

    assert localized =~ ~s(alt="Tea &amp; cake &amp; coffee")
    assert localized =~ ~s(<mj-text>Hej <span title="Greeting">vän</span></mj-text>)
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

  test "HTML fragment translations preserve markup, attributes, and Liquid exactly" do
    source = ~s(<p class="notice">Hello <a href="{{ action_url }}">{{ name }}</a></p>)

    schema = %{
      "version" => 1,
      "variables" => %{
        "action_url" => %{"type" => "url", "context" => "url"},
        "name" => %{"type" => "string", "context" => "html_text"}
      }
    }

    assert {:ok, [unit], []} =
             Letterpress.extract_translation_units("html/liquid@1", source, schema)

    translated =
      ~s(<p class="notice">Hej <a href="{{ action_url }}">{{ name }}</a></p>)

    assert {:ok, ^translated, []} =
             Letterpress.apply_translations(
               "html/liquid@1",
               source,
               schema,
               %{unit["id"] => translated}
             )

    for changed <- [
          ~s(<p class="warning">Hej <a href="{{ action_url }}">{{ name }}</a></p>),
          ~s(<p class="notice">Hej <a href="https://example.test">{{ name }}</a></p>),
          ~s(<p class="notice">Hej <strong>{{ name }}</strong></p>)
        ] do
      assert {:error, diagnostics} =
               Letterpress.apply_translations(
                 "html/liquid@1",
                 source,
                 schema,
                 %{unit["id"] => changed}
               )

      assert Enum.any?(diagnostics, &(&1.code == "LP_TRANSLATION_PLACEHOLDER"))
    end
  end

  defp email_source do
    "<mjml><mj-body><mj-section><mj-column><mj-text>Hello {{ name }}</mj-text></mj-column></mj-section></mj-body></mjml>"
  end
end
