defmodule Letterpress.CanonicalJSON do
  @moduledoc """
  Encodes JSON-compatible data with lexical object keys and no insignificant whitespace.

  It is intentionally small: Letterpress artifacts contain only JSON native
  values and finite floats are rejected before reaching this encoder.
  """

  @doc "Encodes a JSON-compatible value deterministically."
  @spec encode(term()) :: {:ok, binary()} | {:error, term()}
  def encode(value) do
    {:ok, IO.iodata_to_binary(do_encode(value))}
  rescue
    error in [ArgumentError, Protocol.UndefinedError] -> {:error, error}
  end

  @doc "Encodes a JSON-compatible value deterministically or raises."
  @spec encode!(term()) :: binary()
  def encode!(value), do: value |> do_encode() |> IO.iodata_to_binary()

  @doc "Returns the lowercase SHA-256 hash of canonical JSON."
  @spec hash(term()) :: String.t()
  def hash(value), do: :crypto.hash(:sha256, encode!(value)) |> Base.encode16(case: :lower)

  defp do_encode(value) when is_map(value) and not is_struct(value) do
    entries =
      value
      |> Enum.map(fn {key, item} -> {to_string(key), item} end)
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(fn {key, item} -> [Jason.encode!(key), ?:, do_encode(item)] end)

    [?{, Enum.intersperse(entries, ?,), ?}]
  end

  defp do_encode(value) when is_list(value) do
    [?[, Enum.intersperse(Enum.map(value, &do_encode/1), ?,), ?]]
  end

  defp do_encode(value)
       when is_binary(value) or is_number(value) or is_boolean(value) or is_nil(value) do
    Jason.encode!(value)
  end

  defp do_encode(value) do
    raise ArgumentError, "value is not canonical JSON: #{inspect(value)}"
  end
end
