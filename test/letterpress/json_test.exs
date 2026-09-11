defmodule Letterpress.JSONTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Letterpress.JSON

  doctest Letterpress.JSON

  test "rejects duplicate object keys inside arrays at every depth" do
    for json <- [
          ~s([{"name":"first","name":"second"}]),
          ~s({"items":[null,{"name":"first","name":"second"}]}),
          ~s({"items":[[{"nested":{"name":"first","name":"second"}}]]})
        ] do
      assert {:error, :invalid_artifact_json} = JSON.decode(json)
    end

    assert {:ok, [%{"name" => "first"}, %{"name" => "second"}]} =
             JSON.decode(~s([{"name":"first"},{"name":"second"}]))
  end

  test "normalizes nested atom keys and preserves JSON values" do
    assert {:ok, normalized} =
             JSON.normalize_object(%{user: %{name: "Ada"}, flags: [true, nil], score: 1.5})

    assert normalized == %{
             "user" => %{"name" => "Ada"},
             "flags" => [true, nil],
             "score" => 1.5
           }
  end

  test "rejects invalid UTF-8 in keys and nested values" do
    for value <- [%{name: <<255>>}, %{<<255>> => "value"}, %{nested: [<<255>>]}] do
      assert {:error, :invalid_json_object} = JSON.normalize_object(value)
    end
  end

  test "rejects improper lists instead of raising during normalization" do
    assert {:error, :invalid_json_object} = JSON.normalize_object(%{items: [1 | 2]})
  end

  test "rejects structs, invalid keys and normalized-key collisions" do
    assert {:error, :invalid_json_object} = JSON.normalize_object(self())
    assert {:error, :invalid_json_object} = JSON.normalize_object(%{1 => "value"})
    assert {:error, :invalid_json_object} = JSON.normalize_object(%{"same" => 1, same: 2})
    assert {:error, :invalid_json_object} = JSON.normalize_object(%{date: ~D[2026-08-30]})
    assert {:error, :invalid_json_object} = JSON.normalize_object(%{pid: self()})
  end
end
