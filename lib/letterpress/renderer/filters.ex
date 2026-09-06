defmodule Letterpress.Renderer.Filters do
  @moduledoc """
  Implements the compiler-reserved final output-context filter.

  The trusted compiler appends this filter after every delivery expression.
  User source cannot name it directly. It escapes or validates the final value
  after ordinary Liquid filters have run, which prevents a preceding filter
  from bypassing the context selected during compilation.

  This module is part of the renderer implementation. Template authors should
  declare the correct variable context instead of calling it.

  ## Examples

      iex> Letterpress.Renderer.Filters.escape("<Ada & Grace>", "html_text")
      {:ok, "&lt;Ada &amp; Grace&gt;"}

      iex> Letterpress.Renderer.Filters.escape("javascript:alert(1)", "url")
      :error
  """

  @default_allowed_url_schemes ~w(http https mailto tel cid)
  @default_subject_max_bytes 998

  @doc """
  Implements the custom-filter callback expected by `Solid.render/3`.

  Only the compiler-reserved `"letterpress_escape"` filter and its two
  arguments are accepted.
  """
  @spec apply(String.t(), list()) :: {:ok, String.t()} | :error
  def apply("letterpress_escape", [value, context]) when is_binary(context) do
    escape(value, context)
  end

  def apply(_, _), do: :error

  @doc """
  Escapes or validates a value for a compiler-proven context.

  HTML text and attribute contexts are escaped. Subjects reject CR, LF, NUL,
  and oversized output. URLs reject control characters, protocol-relative
  values, and absolute schemes outside the render call's allowlist.

  ## Example

      iex> Letterpress.Renderer.Filters.escape("https://example.test/?a=1&b=2", "url")
      {:ok, "https://example.test/?a=1&amp;b=2"}
  """
  @spec escape(term(), String.t()) :: {:ok, String.t()} | :error
  def escape(value, "html_text"), do: {:ok, html_escape(to_text(value), false)}
  def escape(value, "html_attribute"), do: {:ok, html_escape(to_text(value), true)}
  def escape(value, "text"), do: safe_plain_text(value)
  def escape(value, "subject"), do: safe_subject(value)
  def escape(value, "url"), do: safe_url(value)
  def escape(value, "none"), do: safe_plain_text(value)
  def escape(_, _), do: :error

  defp safe_plain_text(value) do
    text = to_text(value)
    if String.contains?(text, <<0>>), do: :error, else: {:ok, text}
  end

  defp safe_subject(value) do
    text = to_text(value)
    max_bytes = Process.get(:letterpress_subject_max_bytes, @default_subject_max_bytes)

    if String.contains?(text, ["\r", "\n", <<0>>]) or byte_size(text) > max_bytes do
      :error
    else
      {:ok, text}
    end
  end

  defp safe_url(value) do
    text = to_text(value)

    if Letterpress.URL.safe?(text, allowed_url_schemes()),
      do: {:ok, html_escape(text, true)},
      else: :error
  end

  defp allowed_url_schemes do
    Process.get(:letterpress_allowed_url_schemes, @default_allowed_url_schemes)
  end

  defp html_escape(value, attribute?) do
    escaped =
      value
      |> String.replace("&", "&amp;")
      |> String.replace("<", "&lt;")
      |> String.replace(">", "&gt;")

    if attribute? do
      escaped
      |> String.replace("\"", "&quot;")
      |> String.replace("'", "&#39;")
    else
      escaped
    end
  end

  defp to_text(value) when is_binary(value), do: value

  defp to_text(value) when is_integer(value) or is_float(value) or is_boolean(value),
    do: to_string(value)

  defp to_text(nil), do: ""
  defp to_text(value), do: Jason.encode!(value)
end
