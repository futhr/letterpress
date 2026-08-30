defmodule Letterpress.SchemaTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Letterpress.Schema

  test "normalizes atom keys without creating atoms from input" do
    schema = %{version: 1, variables: %{name: %{type: "string"}}}

    assert {:ok, normalized} = Schema.normalize(schema)
    assert normalized["variables"]["name"]["phase"] == "delivery"
    assert normalized["variables"]["name"]["context"] == "text"
    assert normalized["variables"]["name"]["required"]
  end

  test "accepts every public type with a matching default" do
    defaults = %{
      "string" => "value",
      "integer" => 1,
      "number" => 1.5,
      "boolean" => true,
      "date" => "2026-08-30",
      "datetime" => "2026-08-30T09:00:00Z",
      "url" => "https://example.test",
      "email" => "person@example.test",
      "phone" => "+15555550100",
      "object" => %{
        "default" => %{"key" => "value"},
        "properties" => %{"key" => %{"type" => "string"}}
      },
      "list" => %{"default" => [1, 2], "items" => %{"type" => "integer"}}
    }

    variables =
      Map.new(defaults, fn
        {type, %{"default" => default} = definition} when type in ["object", "list"] ->
          {"value_#{type}", definition |> Map.put("type", type) |> Map.put("default", default)}

        {type, default} ->
          {"value_#{type}", %{"type" => type, "default" => default}}
      end)

    assert {:ok, _} = Schema.normalize(%{"version" => 1, "variables" => variables})
  end

  test "rejects unsafe phase/context combinations and reserved names" do
    assert {:error, [diagnostic]} =
             Schema.normalize(%{
               "version" => 1,
               "variables" => %{
                 "color" => %{"type" => "string", "phase" => "delivery", "context" => "css"}
               }
             })

    assert diagnostic.code == "LP_SCHEMA_PHASE_CONTEXT"

    assert {:error, [diagnostic]} =
             Schema.normalize(%{
               "version" => 1,
               "variables" => %{"letterpress_escape" => %{"type" => "string"}}
             })

    assert diagnostic.code == "LP_SCHEMA_RESERVED"
  end

  test "normalizes and strictly validates nested object and list shapes" do
    schema = %{
      "version" => 1,
      "variables" => %{
        "recipient" => %{
          "type" => "object",
          "properties" => %{
            "name" => %{"type" => "string"},
            "phones" => %{"type" => "list", "items" => %{"type" => "phone"}}
          }
        }
      }
    }

    assert {:ok, normalized} = Schema.normalize(schema)
    definition = normalized["variables"]["recipient"]

    assert Schema.value_matches_definition?(
             %{"name" => "Ada", "phones" => ["+15555550100"]},
             definition
           )

    refute Schema.value_matches_definition?(
             %{"name" => "Ada", "phones" => ["not-a-phone"]},
             definition
           )

    refute Schema.value_matches_definition?(%{"name" => "Ada", "extra" => true}, definition)
  end

  test "rejects missing collection shapes, malformed descriptions, and unsafe URLs" do
    for definition <- [
          %{"type" => "object"},
          %{"type" => "list"},
          %{"type" => "string", "description" => 123},
          %{"type" => "url", "default" => "javascript:alert(1)"}
        ] do
      assert {:error, [_]} =
               Schema.normalize(%{"version" => 1, "variables" => %{"value" => definition}})
    end
  end

  test "rejects malformed top-level schemas and variable definitions with stable codes" do
    cases = [
      {nil, "LP_SCHEMA_INVALID"},
      {%{"version" => 2, "variables" => %{}}, "LP_SCHEMA_VERSION"},
      {%{"version" => 1, "variables" => [], "extra" => true}, "LP_SCHEMA_FIELD"},
      {%{"version" => 1, "variables" => []}, "LP_SCHEMA_VARIABLES"},
      {schema_with("bad-name", %{"type" => "string"}), "LP_SCHEMA_NAME"},
      {schema_with("value", "string"), "LP_SCHEMA_DEFINITION"},
      {schema_with("value", %{"type" => "string", "unknown" => true}), "LP_SCHEMA_FIELD"},
      {schema_with("value", %{"type" => "unknown"}), "LP_SCHEMA_TYPE"},
      {schema_with("value", %{"type" => "string", "phase" => "later"}), "LP_SCHEMA_PHASE"},
      {schema_with("value", %{"type" => "string", "context" => "shell"}), "LP_SCHEMA_CONTEXT"},
      {schema_with("value", %{"type" => "string", "required" => "yes"}), "LP_SCHEMA_REQUIRED"},
      {schema_with("value", %{"type" => "string", "sensitive" => "no"}), "LP_SCHEMA_SENSITIVE"},
      {schema_with("value", %{"type" => "integer", "default" => "one"}), "LP_SCHEMA_DEFAULT"}
    ]

    for {schema, code} <- cases do
      assert {:error, [%{code: ^code}]} = Schema.normalize(schema)
    end
  end

  test "enforces variable count, nested names, fields, shape, and depth" do
    oversized =
      Map.new(0..500, fn index -> {"value_#{index}", %{"type" => "string"}} end)

    assert {:error, [%{code: "LP_SCHEMA_TOO_LARGE"}]} =
             Schema.normalize(%{"version" => 1, "variables" => oversized})

    malformed_nested = [
      {%{"type" => "object", "properties" => %{"bad-name" => %{"type" => "string"}}},
       "LP_SCHEMA_NAME"},
      {%{"type" => "object", "properties" => %{"name" => "string"}}, "LP_SCHEMA_DEFINITION"},
      {%{
         "type" => "object",
         "properties" => %{"name" => %{"type" => "string", "phase" => "delivery"}}
       }, "LP_SCHEMA_FIELD"},
      {%{"type" => "string", "items" => %{"type" => "string"}}, "LP_SCHEMA_SHAPE"}
    ]

    for {definition, code} <- malformed_nested do
      assert {:error, [%{code: ^code}]} = Schema.normalize(schema_with("value", definition))
    end

    assert {:error, [%{code: "LP_SCHEMA_DEPTH"}]} =
             Schema.normalize(schema_with("value", nested_list(13)))
  end

  test "validates every scalar type against malformed values" do
    invalid = [
      {1, "string"},
      {1.5, "integer"},
      {"1", "number"},
      {1, "boolean"},
      {"2026-02-30", "date"},
      {"yesterday", "datetime"},
      {"javascript:alert(1)", "url"},
      {"invalid", "email"},
      {"0046700000000", "phone"},
      {[], "object"},
      {%{}, "list"},
      {"value", "unknown"}
    ]

    for {value, type} <- invalid do
      refute Schema.value_matches_type?(value, type),
             "#{inspect(value)} unexpectedly matched #{type}"
    end
  end

  defp schema_with(name, definition) do
    %{"version" => 1, "variables" => %{name => definition}}
  end

  defp nested_list(0), do: %{"type" => "string"}
  defp nested_list(depth), do: %{"type" => "list", "items" => nested_list(depth - 1)}
end
