defmodule Letterpress.ConformanceTest do
  @moduledoc false

  use ExUnit.Case, async: false

  @fixtures Path.expand("../../conformance/fixtures.json", __DIR__)

  test "the backend consumes the shared analysis conformance corpus" do
    fixtures = @fixtures |> File.read!() |> Jason.decode!()
    assert fixtures["version"] == 1

    for fixture <- fixtures["analysis"] do
      codes = analyze_codes(fixture)

      assert Enum.all?(fixture["backend_codes"], &(&1 in codes)),
             "#{fixture["name"]}: expected #{inspect(fixture["backend_codes"])}, got #{inspect(codes)}"

      if fixture["backend_codes"] == [] do
        assert codes == [], "#{fixture["name"]}: expected no errors, got #{inspect(codes)}"
      end
    end
  end

  defp analyze_codes(fixture) do
    case Letterpress.analyze(fixture["profile"], fixture["source"], fixture["schema"]) do
      {:ok, _, diagnostics} -> error_codes(diagnostics)
      {:error, diagnostics} -> error_codes(diagnostics)
    end
  end

  defp error_codes(diagnostics) do
    diagnostics
    |> Enum.filter(&(&1.severity == :error))
    |> Enum.map(& &1.code)
  end
end
