defmodule Letterpress.CanonicalJSONTest do
  @moduledoc false

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Letterpress.CanonicalJSON

  doctest Letterpress.CanonicalJSON

  test "non-bang encoding returns an error for malformed UTF-8" do
    assert {:error, %Jason.EncodeError{}} = Letterpress.CanonicalJSON.encode(<<255>>)
  end

  test "sorts object keys recursively and preserves array order" do
    left = %{"z" => 1, "a" => %{"b" => 2, "a" => [3, 1]}}
    right = %{"a" => %{"a" => [3, 1], "b" => 2}, "z" => 1}

    assert CanonicalJSON.encode!(left) == ~s({"a":{"a":[3,1],"b":2},"z":1})
    assert CanonicalJSON.hash(left) == CanonicalJSON.hash(right)
  end

  property "map insertion order cannot change canonical bytes" do
    generator = list_of({string(:alphanumeric, min_length: 1), integer()}, max_length: 30)

    check all(pairs <- generator) do
      pairs = Enum.uniq_by(pairs, &elem(&1, 0))
      map = Map.new(pairs)
      assert CanonicalJSON.encode!(map) == CanonicalJSON.encode!(Map.new(Enum.reverse(pairs)))
    end
  end

  test "rejects non-JSON terms" do
    assert {:error, %ArgumentError{}} = CanonicalJSON.encode({:tuple, :value})
  end

  test "rejects ambiguous keys at every depth and improper list tails" do
    for value <- [%{:a => 1, "a" => 2}, [%{1 => true, "1" => false}], [1 | 2]] do
      assert {:error, %ArgumentError{}} = CanonicalJSON.encode(value)
    end
  end

  test "preserves native scalar types and distinguishes numeric identities" do
    assert CanonicalJSON.encode!([true, false, nil, 1, 1.0]) == "[true,false,null,1,1.0]"
    refute CanonicalJSON.hash(%{"n" => 1}) == CanonicalJSON.hash(%{"n" => 1.0})
  end
end
