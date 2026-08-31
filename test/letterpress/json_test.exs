defmodule Letterpress.JSONTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Letterpress.JSON

  doctest Letterpress.JSON

  test "normalizes nested atom keys and preserves JSON values" do
    assert {:ok, normalized} =
             JSON.normalize_object(%{user: %{name: "Ada"}, flags: [true, nil], score: 1.5})

    assert normalized == %{
             "user" => %{"name" => "Ada"},
             "flags" => [true, nil],
             "score" => 1.5
           }
  end

  test "rejects structs, invalid keys and normalized-key collisions" do
    assert {:error, :invalid_json_object} = JSON.normalize_object(self())
    assert {:error, :invalid_json_object} = JSON.normalize_object(%{1 => "value"})
    assert {:error, :invalid_json_object} = JSON.normalize_object(%{"same" => 1, same: 2})
    assert {:error, :invalid_json_object} = JSON.normalize_object(%{date: ~D[2026-08-30]})
    assert {:error, :invalid_json_object} = JSON.normalize_object(%{pid: self()})
  end
end
