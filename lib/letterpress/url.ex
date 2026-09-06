defmodule Letterpress.URL do
  @moduledoc false

  @schemes ~w(http https mailto tel cid)

  @doc false
  @spec safe?(term(), [String.t()]) :: boolean()
  def safe?(value, schemes \\ @schemes)

  def safe?(value, schemes) when is_binary(value) do
    String.valid?(value) and value != "" and
      not Regex.match?(~r/[\x00-\x20\x7f\\\\]/, value) and
      not String.starts_with?(value, "//") and safe_scheme?(value, schemes)
  end

  def safe?(_, _), do: false

  defp safe_scheme?(value, schemes) do
    case URI.parse(value) do
      %URI{scheme: nil, host: nil} -> true
      %URI{scheme: scheme} -> scheme in @schemes and scheme in schemes
    end
  end
end
