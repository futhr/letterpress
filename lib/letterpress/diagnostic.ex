defmodule Letterpress.Diagnostic do
  @moduledoc """
  A stable, LSP-shaped diagnostic returned by Letterpress operations.

  Ranges use zero-based UTF-16 line and character coordinates so the same
  positions work in Elixir responses and browser editors. `source_hash` and
  `document_version` let a host discard stale asynchronous results.

  Diagnostic codes and the JSON shape are public contract. English messages
  are written for people and may improve between releases; application logic
  should match on `code` and, when needed, structured `data`.

  ## Example

      iex> diagnostic =
      ...>   Letterpress.Diagnostic.simple("LP_SCHEMA_UNUSED_VARIABLE", "Check this value", :warning)
      iex> {diagnostic.code, diagnostic.severity, diagnostic.range.start}
      {"LP_SCHEMA_UNUSED_VARIABLE", :warning, %{line: 0, character: 0}}
  """

  @typedoc "Severity understood by ExDoc consumers and LSP-compatible editors."
  @type severity :: :error | :warning | :information | :hint

  @typedoc "A zero-based UTF-16 document position."
  @type point :: %{line: non_neg_integer(), character: non_neg_integer()}

  @typedoc "A half-open source range from `:start` to `:end`."
  @type range :: %{start: point(), end: point()}

  @typedoc "A version-1 Letterpress diagnostic."
  @type t :: %__MODULE__{
          version: 1,
          source_hash: String.t(),
          document_version: non_neg_integer(),
          range: range(),
          severity: severity(),
          code: String.t(),
          source: String.t(),
          message: String.t(),
          related: [map()],
          data: map()
        }

  @enforce_keys [:code, :message]
  defstruct version: 1,
            source_hash: "",
            document_version: 0,
            range: %{start: %{line: 0, character: 0}, end: %{line: 0, character: 0}},
            severity: :error,
            code: nil,
            source: "letterpress",
            message: nil,
            related: [],
            data: %{}

  @doc """
  Creates a document-level diagnostic for local validation.

  The range points to the start of the document, and the severity defaults to
  `:error`.
  """
  @spec simple(String.t(), String.t(), severity()) :: t()
  def simple(code, message, severity \\ :error),
    do: %__MODULE__{code: code, message: message, severity: severity}

  @doc """
  Creates a redacted diagnostic for a compiler or runtime boundary failure.

  The returned diagnostic preserves the profile, source hash, and document
  version but never copies template source or resolved values into its message
  or data.
  """
  @spec system(term(), String.t(), String.t(), keyword()) :: t()
  def system(reason, profile, source, opts) do
    code =
      case reason do
        :compiler_disabled -> "LP_COMPILER_DISABLED"
        :compiler_unavailable -> "LP_COMPILER_UNAVAILABLE"
        :compiler_timeout -> "LP_COMPILER_TIMEOUT"
        _ -> "LP_INTERNAL_BOUNDARY"
      end

    %__MODULE__{
      code: code,
      message: system_message(code),
      source_hash: hash_source(source),
      document_version: Keyword.get(opts, :document_version, 0),
      data: %{"profile" => profile}
    }
  end

  @doc """
  Converts compiler diagnostic maps into `t:t/0` structs.

  Only the four known severity strings become atoms. Unknown severities fall
  back to `:error`, and missing optional fields receive contract defaults.
  """
  @spec from_maps([map()]) :: [t()]
  def from_maps(maps) when is_list(maps), do: Enum.map(maps, &from_map/1)

  @doc """
  Returns whether a list contains an error diagnostic.

  ## Example

      iex> warning =
      ...>   Letterpress.Diagnostic.simple("LP_SCHEMA_UNUSED_VARIABLE", "Heads up", :warning)
      iex> error = Letterpress.Diagnostic.simple("LP_SCHEMA_INVALID", "Stop")
      iex> Letterpress.Diagnostic.errors?([warning, error])
      true
  """
  @spec errors?([t()]) :: boolean()
  def errors?(diagnostics), do: Enum.any?(diagnostics, &(&1.severity == :error))

  @doc """
  Returns the string-keyed JSON projection of a diagnostic.

  Severity becomes a string; range point keys also become strings. The result
  contains only JSON-native values when the struct came from Letterpress.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = diagnostic) do
    %{
      "version" => diagnostic.version,
      "source_hash" => diagnostic.source_hash,
      "document_version" => diagnostic.document_version,
      "range" => stringify_range(diagnostic.range),
      "severity" => Atom.to_string(diagnostic.severity),
      "code" => diagnostic.code,
      "source" => diagnostic.source,
      "message" => diagnostic.message,
      "related" => diagnostic.related,
      "data" => diagnostic.data
    }
  end

  defp from_map(map) do
    %__MODULE__{
      version: map["version"] || 1,
      source_hash: map["source_hash"] || "",
      document_version: map["document_version"] || 0,
      range: atomize_range(map["range"]),
      severity: severity(map["severity"]),
      code: map["code"] || "LP_UNKNOWN",
      source: map["source"] || "letterpress",
      message: map["message"] || "Template operation failed",
      related: map["related"] || [],
      data: map["data"] || %{}
    }
  end

  defp severity("warning"), do: :warning
  defp severity("information"), do: :information
  defp severity("hint"), do: :hint
  defp severity(_), do: :error

  defp atomize_range(%{"start" => start, "end" => finish}) do
    %{start: atomize_point(start), end: atomize_point(finish)}
  end

  defp atomize_range(_), do: %{start: %{line: 0, character: 0}, end: %{line: 0, character: 0}}
  defp atomize_point(point), do: %{line: point["line"] || 0, character: point["character"] || 0}

  defp stringify_range(range) do
    %{
      "start" => %{"line" => range.start.line, "character" => range.start.character},
      "end" => %{"line" => range.end.line, "character" => range.end.character}
    }
  end

  defp hash_source(source) when is_binary(source),
    do: :crypto.hash(:sha256, source) |> Base.encode16(case: :lower)

  defp hash_source(_), do: ""

  defp system_message("LP_COMPILER_DISABLED"), do: "Template compilation is disabled on this node"
  defp system_message("LP_COMPILER_UNAVAILABLE"), do: "Template compiler is unavailable"
  defp system_message("LP_COMPILER_TIMEOUT"), do: "Template compiler exceeded its deadline"
  defp system_message(_), do: "Template operation failed at an internal boundary"
end
