defmodule Letterpress.PublicAPITest do
  @moduledoc false

  use ExUnit.Case, async: false

  import Letterpress.Test.Fixtures

  doctest Letterpress
  doctest Letterpress.Contract
  doctest Letterpress.Profile

  test "malformed option lists return tagged errors" do
    schema = %{"version" => 1, "variables" => %{}}
    assert {:ok, artifact, []} = Letterpress.compile("text/liquid@1", "Hello", schema)

    for opts <- [["invalid"], [{"timeout", 1}], [{:timeout, 1} | :invalid]] do
      assert {:error, [%{code: "LP_OPTIONS_INVALID"}]} =
               Letterpress.compile("text/liquid@1", "Hello", schema, opts)

      assert {:error, [%{code: "LP_OPTIONS_INVALID"}]} = Letterpress.render(artifact, %{}, opts)
    end
  end

  test "invalid UTF-8 email channels return option diagnostics" do
    schema = %{"version" => 1, "variables" => %{}}

    for opts <- [[subject: <<255>>], [text: <<255>>]] do
      assert {:error, [%{code: "LP_OPTIONS_INVALID"}]} =
               Letterpress.compile("email/mjml-liquid@1", "<mjml></mjml>", schema, opts)
    end
  end

  test "invalid UTF-8 source returns diagnostics without sending it to a worker" do
    schema = %{"version" => 1, "variables" => %{}}

    assert {:error, [%{code: "LP_SOURCE_INVALID"}]} =
             Letterpress.compile("text/liquid@1", <<255>>, schema)

    assert {:error, [%{code: "LP_SOURCE_INVALID"}]} =
             Letterpress.analyze("text/liquid@1", <<255>>, schema)

    assert {:error, [%{code: "LP_SOURCE_INVALID"}]} =
             Letterpress.discover("text/liquid@1", <<255>>)

    assert {:error, [%{code: "LP_SOURCE_INVALID"}]} = Letterpress.format("text/liquid@1", <<255>>)
  end

  test "the package leaves compiler supervision to the caller" do
    assert Application.spec(:letterpress, :mod) == []
    refute Code.ensure_loaded?(Letterpress.Application)

    %{id: Letterpress.Compiler.Pool, type: :supervisor} =
      Letterpress.Compiler.Supervisor.child_spec(pool_size: 1)
  end

  test "exposes the versioned profiles and generated contract" do
    assert Letterpress.version() == "0.1.0"

    assert Letterpress.profiles() == [
             "email/mjml-liquid@1",
             "html/liquid@1",
             "text/liquid@1"
           ]

    assert Letterpress.contract()["contract_version"] == 1
    assert {:ok, %{"kind" => "email"}} = Letterpress.Profile.fetch("email/mjml-liquid@1")
    assert :error = Letterpress.Profile.fetch("unknown")

    assert :ok = Letterpress.Contract.reset()
    assert Letterpress.Contract.get()["artifact_version"] == 1
    assert Letterpress.Contract.get()["artifact_version"] == 1
  end

  test "public authoring calls reject malformed source, profile, options, and JSON input" do
    assert_error_code(Letterpress.analyze(:email, "source", text_schema()), "LP_PROFILE_INVALID")

    assert_error_code(
      Letterpress.analyze("unknown", "source", text_schema()),
      "LP_PROFILE_UNKNOWN"
    )

    assert_error_code(
      Letterpress.analyze("text/liquid@1", nil, text_schema()),
      "LP_SOURCE_INVALID"
    )

    assert_error_code(
      Letterpress.compile("text/liquid@1", text_source(), text_schema(), %{timeout: 1}),
      "LP_OPTIONS_INVALID"
    )

    assert_error_code(
      Letterpress.compile("text/liquid@1", text_source(), text_schema(), unknown: true),
      "LP_OPTIONS_INVALID"
    )

    assert_error_code(
      Letterpress.compile("text/liquid@1", text_source(), text_schema(), text: "duplicate"),
      "LP_OPTIONS_INVALID"
    )

    assert_error_code(
      Letterpress.compile("html/liquid@1", "<p>Hello</p>", text_schema(), subject: "duplicate"),
      "LP_OPTIONS_INVALID"
    )

    assert_error_code(
      Letterpress.compile("text/liquid@1", text_source(), text_schema(),
        compile_values: %{bad: self()}
      ),
      "LP_INPUT_INVALID"
    )

    assert_error_code(
      Letterpress.apply_translations("text/liquid@1", text_source(), text_schema(), self()),
      "LP_INPUT_INVALID"
    )

    assert_error_code(
      Letterpress.extract_translation_units("text/liquid@1", text_source(), text_schema(),
        subject: "Not accepted"
      ),
      "LP_OPTIONS_INVALID"
    )

    assert_error_code(
      Letterpress.localize("text/liquid@1", text_source(), text_schema(), %{}),
      "LP_OPTIONS_INVALID"
    )

    assert_error_code(Letterpress.format("text/liquid@1", :source), "LP_SOURCE_INVALID")
    assert_error_code(Letterpress.format(:profile, "source"), "LP_PROFILE_INVALID")
  end

  test "artifact facade round trips canonical JSON" do
    {:ok, artifact, _} = Letterpress.compile("text/liquid@1", text_source(), text_schema())
    assert {:ok, json} = Letterpress.encode_artifact(artifact)
    assert {:ok, ^artifact} = Letterpress.decode_artifact(json)
    assert {:error, :invalid_artifact} = Letterpress.decode_artifact(:not_an_artifact)
  end

  test "compiles and renders predicate-style variable names" do
    schema = %{
      "version" => 1,
      "variables" => %{
        "campaign.csd_registered?" => %{"type" => "boolean", "context" => "text"}
      }
    }

    assert {:ok, artifact, []} =
             Letterpress.compile(
               "text/liquid@1",
               "CSD registered: {{ campaign.csd_registered? }}",
               schema
             )

    assert {:ok, %{text: "CSD registered: true"}} =
             Letterpress.render(artifact, %{"campaign" => %{"csd_registered?" => true}})
  end

  test "translation extraction returns parser diagnostics for invalid source" do
    assert {:error, diagnostics} =
             Letterpress.extract_translation_units(
               "email/mjml-liquid@1",
               "<mjml>",
               %{"version" => 1, "variables" => %{}}
             )

    assert Enum.any?(diagnostics, &(&1.severity == :error))
  end

  defp assert_error_code({:error, diagnostics}, code) do
    assert Enum.any?(diagnostics, &(&1.code == code)), inspect(diagnostics)
  end
end
