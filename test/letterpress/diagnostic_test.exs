defmodule Letterpress.DiagnosticTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Letterpress.Diagnostic

  test "maps worker diagnostics to the stable public JSON projection" do
    base = %{
      "version" => 1,
      "source_hash" => String.duplicate("a", 64),
      "document_version" => 7,
      "range" => %{
        "start" => %{"line" => 2, "character" => 3},
        "end" => %{"line" => 2, "character" => 9}
      },
      "code" => "LP_TEST",
      "source" => "letterpress-test",
      "message" => "Test diagnostic",
      "related" => [%{"message" => "Related"}],
      "data" => %{"safe" => true}
    }

    diagnostics =
      Diagnostic.from_maps(
        Enum.map(~w(error warning information hint unknown), &Map.put(base, "severity", &1))
      )

    assert Enum.map(diagnostics, & &1.severity) == [:error, :warning, :information, :hint, :error]
    assert Diagnostic.errors?(diagnostics)

    projection = diagnostics |> Enum.at(1) |> Diagnostic.to_map()
    assert projection["severity"] == "warning"
    assert projection["range"]["start"] == %{"line" => 2, "character" => 3}
    assert projection["data"] == %{"safe" => true}
  end

  test "system diagnostics are redacted and classify compiler failures" do
    for {reason, code} <- [
          compiler_disabled: "LP_COMPILER_DISABLED",
          compiler_unavailable: "LP_COMPILER_UNAVAILABLE",
          compiler_timeout: "LP_COMPILER_TIMEOUT",
          protocol_failure: "LP_INTERNAL_BOUNDARY"
        ] do
      diagnostic =
        Diagnostic.system(reason, "text/liquid@1", "secret source", document_version: 4)

      assert diagnostic.code == code
      assert diagnostic.document_version == 4
      assert byte_size(diagnostic.source_hash) == 64
      refute diagnostic.message =~ "secret source"
      assert diagnostic.data == %{"profile" => "text/liquid@1"}
    end

    assert Diagnostic.system(:failure, "unknown", nil, []).source_hash == ""
  end

  test "malformed worker fields receive deterministic defaults" do
    assert [diagnostic] = Diagnostic.from_maps([%{}])
    assert diagnostic.code == "LP_UNKNOWN"
    assert diagnostic.severity == :error
    assert diagnostic.range.start == %{line: 0, character: 0}
  end
end
