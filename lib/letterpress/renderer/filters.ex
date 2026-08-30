defmodule Letterpress.Renderer.Filters do
  @moduledoc """
  Implements the compiler-reserved final context filter.

  The filter is appended by the trusted compiler after every delivery output.
  User source cannot name it directly. It escapes or validates the final value
  after all ordinary Liquid filters have executed.
  """

  @allowed_url_schemes ~w(http https mailto tel cid)

  @doc "Solid custom-filter callback used by the bounded renderer."
  @spec apply(String.t(), list()) :: {:ok, String.t()} | :error
  def apply("letterpress_escape", [value, context]) when is_binary(context) do
    escape(value, context)
  end

  def apply(_, _), do: :error

  @doc "Escapes or validates a value for its compiler-proven context."
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
    max_bytes = Application.get_env(:letterpress, :subject_max_bytes, 998)

    if String.contains?(text, ["\r", "\n", <<0>>]) or byte_size(text) > max_bytes do
      :error
    else
      {:ok, text}
    end
  end

  defp safe_url(value) do
    text = to_text(value)
    uri = URI.parse(text)

    cond do
      String.contains?(text, ["\r", "\n", <<0>>]) ->
        :error

      String.starts_with?(text, "/") and not String.starts_with?(text, "//") ->
        {:ok, html_escape(text, true)}

      String.starts_with?(text, "#") ->
        {:ok, html_escape(text, true)}

      uri.scheme in allowed_url_schemes() ->
        {:ok, html_escape(text, true)}

      is_nil(uri.scheme) and is_nil(uri.host) ->
        {:ok, html_escape(text, true)}

      true ->
        :error
    end
  end

  defp allowed_url_schemes do
    configured = Application.get_env(:letterpress, :allowed_url_schemes, @allowed_url_schemes)
    Enum.map(configured, &to_string/1)
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
