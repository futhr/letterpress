defmodule Letterpress.JSON do
  @moduledoc """
  Normalizes caller data into collision-free JSON-native values.

  Atom keys are accepted as an Elixir convenience and converted to strings at
  every depth. Structs, other key types, duplicate normalized keys, PIDs,
  references, tuples, and non-finite numbers are rejected before they reach a
  compiler port or artifact.

  This is an input-boundary helper. It never creates atoms from caller data.

  ## Example

      iex> Letterpress.JSON.normalize_object(%{user: %{name: "Ada"}, active: true})
      {:ok, %{"active" => true, "user" => %{"name" => "Ada"}}}
  """

  @doc """
  Normalizes a map with atom or string keys into a JSON object.

  The entire nested value must be JSON-compatible. Any invalid key or value
  returns `{:error, :invalid_json_object}`.

  ## Examples

      iex> Letterpress.JSON.normalize_object(%{"items" => [1, nil, false]})
      {:ok, %{"items" => [1, nil, false]}}

      iex> Letterpress.JSON.normalize_object(%{"pid" => self()})
      {:error, :invalid_json_object}
  """
  @spec normalize_object(term()) :: {:ok, map()} | {:error, :invalid_json_object}
  def normalize_object(value) when is_map(value) and not is_struct(value) do
    case normalize(value) do
      {:ok, normalized} -> {:ok, normalized}
      :error -> {:error, :invalid_json_object}
    end
  end

  def normalize_object(_), do: {:error, :invalid_json_object}

  defp normalize(value) when is_map(value) and not is_struct(value) do
    Enum.reduce_while(value, {:ok, %{}}, fn {key, item}, {:ok, acc} ->
      with {:ok, key} <- normalize_key(key),
           false <- Map.has_key?(acc, key),
           {:ok, normalized} <- normalize(item) do
        {:cont, {:ok, Map.put(acc, key, normalized)}}
      else
        _ -> {:halt, :error}
      end
    end)
  end

  defp normalize(value) when is_list(value) do
    result =
      Enum.reduce_while(value, {:ok, []}, fn item, {:ok, acc} ->
        case normalize(item) do
          {:ok, normalized} -> {:cont, {:ok, [normalized | acc]}}
          :error -> {:halt, :error}
        end
      end)

    case result do
      {:ok, reversed} -> {:ok, Enum.reverse(reversed)}
      :error -> :error
    end
  end

  defp normalize(value) when is_binary(value) or is_integer(value), do: {:ok, value}
  defp normalize(value) when is_boolean(value) or is_nil(value), do: {:ok, value}

  defp normalize(value) when is_float(value) do
    case Jason.encode(value) do
      {:ok, _} -> {:ok, value}
      {:error, _} -> :error
    end
  end

  defp normalize(_), do: :error

  defp normalize_key(key) when is_binary(key), do: {:ok, key}
  defp normalize_key(key) when is_atom(key), do: {:ok, Atom.to_string(key)}
  defp normalize_key(_), do: :error
end
