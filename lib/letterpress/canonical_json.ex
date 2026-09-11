defmodule Letterpress.CanonicalJSON do
  @moduledoc """
  Encodes JSON-compatible data into Letterpress's deterministic byte form.

  Object keys are converted to strings and sorted lexically at every depth.
  Keys that collide after conversion are rejected.
  Arrays keep their order, and no insignificant whitespace is emitted.
  Letterpress normalizes public input before it reaches this module, so callers
  should pass only maps, lists, strings, finite numbers, booleans, and `nil`.

  ## Example

      iex> Letterpress.CanonicalJSON.encode!(%{"z" => 1, "a" => [true, nil]})
      ~s({"a":[true,null],"z":1})
  """

  @doc """
  Encodes a JSON-compatible value.

  Returns `{:error, exception}` instead of raising when the value cannot be
  represented by this canonical form.

  ## Example

      iex> Letterpress.CanonicalJSON.encode(%{b: 2, a: 1})
      {:ok, ~s({"a":1,"b":2})}
  """
  @spec encode(term()) :: {:ok, binary()} | {:error, term()}
  def encode(value) do
    {:ok, IO.iodata_to_binary(do_encode(value))}
  rescue
    error in [ArgumentError, Jason.EncodeError, Protocol.UndefinedError] -> {:error, error}
  end

  @doc """
  Encodes a JSON-compatible value or raises for unsupported input.

  Use `encode/1` at caller-controlled boundaries where invalid data is an
  expected failure.
  """
  @spec encode!(term()) :: binary()
  def encode!(value) do
    value
    |> do_encode()
    |> IO.iodata_to_binary()
  end

  @doc """
  Returns the lowercase SHA-256 digest of the canonical bytes.

  Maps with the same normalized content hash identically regardless of their
  insertion order.

  ## Example

      iex> left = %{"b" => 2, "a" => 1}
      iex> right = %{"a" => 1, "b" => 2}
      iex> Letterpress.CanonicalJSON.hash(left) == Letterpress.CanonicalJSON.hash(right)
      true
  """
  @spec hash(term()) :: String.t()
  def hash(value), do: :crypto.hash(:sha256, encode!(value)) |> Base.encode16(case: :lower)

  defp do_encode(value) when is_map(value) and not is_struct(value) do
    entries =
      value
      |> Enum.reduce(%{}, fn {key, item}, acc ->
        key = to_string(key)
        if Map.has_key?(acc, key), do: raise(ArgumentError, "duplicate canonical JSON key")
        Map.put(acc, key, item)
      end)
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(fn {key, item} -> [Jason.encode!(key), ?:, do_encode(item)] end)

    [?{, Enum.intersperse(entries, ?,), ?}]
  end

  defp do_encode(value) when is_list(value) do
    [?[, encode_list(value), ?]]
  end

  defp do_encode(value)
       when is_binary(value) or is_number(value) or is_boolean(value) or is_nil(value) do
    Jason.encode!(value)
  end

  defp do_encode(value) do
    raise ArgumentError, "value is not canonical JSON: #{inspect(value)}"
  end

  defp encode_list([]), do: []
  defp encode_list([value]), do: do_encode(value)
  defp encode_list([value | rest]), do: [do_encode(value), ?,, encode_list(rest)]
  defp encode_list(_), do: raise(ArgumentError, "improper JSON array")
end
