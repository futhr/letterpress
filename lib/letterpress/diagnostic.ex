defmodule Letterpress.Diagnostic do
  @moduledoc """
  Stable LSP-shaped authoring and runtime diagnostic.

  Ranges use zero-based UTF-16 line/character coordinates. Codes are stable;
  callers must not branch on English messages.
  """

  @type severity :: :error | :warning | :information | :hint
  @type point :: %{line: non_neg_integer(), character: non_neg_integer()}
  @type range :: %{start: point(), end: point()}
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

  @doc "Creates a document-level diagnostic for local validation."
  @spec simple(String.t(), String.t(), severity()) :: t()
  def simple(code, message, severity \\ :error),
    do: %__MODULE__{code: code, message: message, severity: severity}

  @doc "Creates a redacted diagnostic for a compiler/runtime boundary failure."
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

  @doc "Converts worker diagnostic maps into structs without creating atoms."
  @spec from_maps([map()]) :: [t()]
  def from_maps(maps) when is_list(maps), do: Enum.map(maps, &from_map/1)

  @doc "Returns true when at least one diagnostic is an error."
  @spec errors?([t()]) :: boolean()
  def errors?(diagnostics), do: Enum.any?(diagnostics, &(&1.severity == :error))

  @doc "Returns the JSON projection of a diagnostic."
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
