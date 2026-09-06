defmodule Letterpress.Artifact do
  @moduledoc """
  The immutable, portable result of compiling a notification template.

  An artifact contains compiled subject, HTML, and text templates together with
  normalized variable definitions, compiler provenance, source maps, non-error
  diagnostics, and hashes that bind those fields together. It contains no
  recipient values or other resolved delivery data.

  Persist or transport artifacts through `encode/1` and `decode/1`. Decoding
  rejects missing fields, extra fields, unsupported versions, malformed
  provenance, invalid channel combinations, and content-hash mismatches.

  ## Example

      iex> schema = %{
      ...>   "version" => 1,
      ...>   "variables" => %{
      ...>     "name" => %{"type" => "string", "context" => "text"}
      ...>   }
      ...> }
      iex> {:ok, artifact, []} =
      ...>   Letterpress.compile("text/liquid@1", "Hello {{ name }}", schema)
      iex> {:ok, json} = Letterpress.Artifact.encode(artifact)
      iex> Letterpress.Artifact.decode(json) == {:ok, artifact}
      true
  """

  alias Letterpress.{CanonicalJSON, Profile, Schema}

  @keys ~w(
    artifact_version profile source_sha256 schema_sha256 options_sha256 compiler
    subject html text variables translation_units source_map lint content_sha256
  )
  @compiler_keys ~w(letterpress node mjml parser bundle_sha256)
  @hash_pattern ~r/\A[0-9a-f]{64}\z/
  @semantic_version_pattern ~r/\A\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?\z/
  @delivery_contexts ~w(text html_text html_attribute url subject none)
  @translation_channels ~w(html subject text)

  @typedoc "A verified version-1 compiled artifact."
  @type t :: %__MODULE__{
          artifact_version: 1,
          profile: String.t(),
          source_sha256: String.t(),
          schema_sha256: String.t(),
          options_sha256: String.t(),
          compiler: map(),
          subject: String.t() | nil,
          html: String.t() | nil,
          text: String.t() | nil,
          variables: [map()],
          translation_units: [map()],
          source_map: map(),
          lint: [map()],
          content_sha256: String.t()
        }

  @enforce_keys [
    :profile,
    :source_sha256,
    :schema_sha256,
    :options_sha256,
    :compiler,
    :variables,
    :content_sha256
  ]
  defstruct artifact_version: 1,
            profile: nil,
            source_sha256: nil,
            schema_sha256: nil,
            options_sha256: nil,
            compiler: %{},
            subject: nil,
            html: nil,
            text: nil,
            variables: [],
            translation_units: [],
            source_map: %{},
            lint: [],
            content_sha256: nil

  @doc false
  @spec from_compiler(String.t(), String.t(), map(), keyword(), map()) ::
          {:ok, t()} | {:error, term()}
  def from_compiler(profile, source, schema, opts, result) do
    case result do
      %{"compiled" => _, "compiler" => _} ->
        build_compiler_artifact(profile, source, schema, opts, result)

      _ ->
        {:error, :compiler_result_incomplete}
    end
  end

  @doc """
  Decodes and verifies an artifact map or JSON document.

  Map input must use string keys and JSON-native values. The success value is a
  `t:t/0`; failures return a stable reason atom or the JSON decoder error.
  """
  @spec decode(binary() | map()) :: {:ok, t()} | {:error, term()}
  def decode(json) when is_binary(json) do
    with {:ok, map} <- Jason.decode(json), do: decode(map)
  end

  def decode(map) when is_map(map) and not is_struct(map) do
    with :ok <- validate_version(map),
         :ok <- validate_shape(map),
         :ok <- validate_hash(map),
         do: build(map)
  end

  def decode(_), do: {:error, :invalid_artifact}

  @doc """
  Verifies an artifact and encodes it as canonical JSON.

  Object keys are sorted and insignificant whitespace is omitted, so the same
  artifact produces the same bytes on every encode.
  """
  @spec encode(t()) :: {:ok, binary()} | {:error, term()}
  def encode(%__MODULE__{} = artifact) do
    map = to_map(artifact)

    with :ok <- validate_hash(map) do
      CanonicalJSON.encode(map)
    end
  end

  @doc """
  Returns the JSON-native map covered by the artifact's content hash.

  This projection is useful when a JSON encoder or storage adapter owns the
  final serialization. Prefer `encode/1` when exact canonical bytes matter.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = artifact) do
    %{
      "artifact_version" => artifact.artifact_version,
      "profile" => artifact.profile,
      "source_sha256" => artifact.source_sha256,
      "schema_sha256" => artifact.schema_sha256,
      "options_sha256" => artifact.options_sha256,
      "compiler" => artifact.compiler,
      "subject" => artifact.subject,
      "html" => artifact.html,
      "text" => artifact.text,
      "variables" => artifact.variables,
      "translation_units" => artifact.translation_units,
      "source_map" => artifact.source_map,
      "lint" => artifact.lint,
      "content_sha256" => artifact.content_sha256
    }
  end

  defp build_compiler_artifact(
         profile,
         source,
         schema,
         opts,
         %{"compiled" => compiled, "compiler" => compiler} = result
       ) do
    variables =
      schema["variables"]
      |> Enum.map(fn {name, definition} -> Map.put(definition, "name", name) end)
      |> Enum.sort_by(& &1["name"])

    data = %{
      "artifact_version" => 1,
      "profile" => profile,
      "source_sha256" => sha256(source),
      "schema_sha256" => Schema.hash(schema),
      "options_sha256" => CanonicalJSON.hash(artifact_options(opts)),
      "compiler" =>
        compiler
        |> Map.put("letterpress", Letterpress.version())
        |> Map.put("bundle_sha256", bundle_hash()),
      "subject" => compiled["subject"],
      "html" => compiled["html"],
      "text" => compiled["text"],
      "variables" => variables,
      "translation_units" => get_in(result, ["analysis", "translation_units"]) || [],
      "source_map" => compiled["source_map"] || %{},
      "lint" => non_error_diagnostics(result["diagnostics"] || [])
    }

    data
    |> Map.put("content_sha256", CanonicalJSON.hash(data))
    |> decode()
  end

  defp validate_version(%{"artifact_version" => 1}), do: :ok
  defp validate_version(_), do: {:error, :unsupported_artifact_version}

  defp validate_shape(map) do
    with :ok <- validate_keys(map),
         :ok <- validate_json_native(map),
         :ok <- validate_profile(map),
         :ok <- validate_hash_fields(map),
         :ok <- validate_compiler(map["compiler"]),
         :ok <- validate_channels(map),
         :ok <- validate_variables(map["variables"]),
         :ok <- validate_translation_units(map["translation_units"], map["source_sha256"]),
         :ok <- validate_source_map(map["source_map"]),
         :ok <- validate_lint(map["lint"]) do
      :ok
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_artifact}
    end
  end

  defp validate_keys(map) do
    if Enum.sort(Map.keys(map)) == Enum.sort(@keys), do: :ok, else: {:error, :invalid_artifact}
  end

  defp validate_profile(%{"profile" => profile}) do
    case Profile.validate(profile) do
      :ok -> :ok
      _ -> {:error, :invalid_artifact_profile}
    end
  end

  defp validate_hash_fields(map) do
    if Enum.all?(~w(source_sha256 schema_sha256 options_sha256 content_sha256), fn key ->
         is_binary(map[key]) and Regex.match?(@hash_pattern, map[key])
       end) do
      :ok
    else
      {:error, :invalid_artifact_hash}
    end
  end

  defp validate_compiler(compiler) when is_map(compiler) do
    if Enum.sort(Map.keys(compiler)) == Enum.sort(@compiler_keys) and
         Enum.all?(~w(letterpress node mjml parser), fn key ->
           is_binary(compiler[key]) and Regex.match?(@semantic_version_pattern, compiler[key])
         end) and
         is_binary(compiler["bundle_sha256"]) and
         Regex.match?(@hash_pattern, compiler["bundle_sha256"]),
       do: :ok,
       else: {:error, :invalid_artifact_compiler}
  end

  defp validate_compiler(_), do: {:error, :invalid_artifact_compiler}

  defp validate_channels(%{"profile" => "email/mjml-liquid@1", "html" => html} = map)
       when is_binary(html) do
    validate_optional_templates(map)
  end

  defp validate_channels(%{
         "profile" => "html/liquid@1",
         "html" => html,
         "text" => nil,
         "subject" => nil
       })
       when is_binary(html),
       do: validate_template(html)

  defp validate_channels(%{
         "profile" => "text/liquid@1",
         "html" => nil,
         "text" => text,
         "subject" => subject
       })
       when is_binary(text) and is_nil(subject),
       do: validate_template(text)

  defp validate_channels(_), do: {:error, :invalid_artifact_channels}

  defp validate_optional_templates(map) do
    [map["subject"], map["html"], map["text"]]
    |> Enum.reject(&is_nil/1)
    |> Enum.reduce_while(:ok, fn
      template, :ok when is_binary(template) ->
        case validate_template(template) do
          :ok -> {:cont, :ok}
          error -> {:halt, error}
        end

      _, :ok ->
        {:halt, {:error, :invalid_artifact_channels}}
    end)
  end

  defp validate_template(template) do
    outputs = Regex.scan(~r/{{\s*(.*?)\s*}}/s, template, capture: :all_but_first)

    valid? =
      Enum.all?(outputs, fn [expression] ->
        case Regex.run(
               ~r/\|\s*letterpress_escape\s*:\s*"([a-z_]+)"\s*\z/,
               expression,
               capture: :all_but_first
             ) do
          [context] -> context in @delivery_contexts
          _ -> false
        end
      end)

    reserved_count = length(Regex.scan(~r/letterpress_escape/, template))

    cond do
      not valid? ->
        {:error, :invalid_artifact_context_filter}

      reserved_count != length(outputs) ->
        {:error, :invalid_artifact_context_filter}

      true ->
        :ok
    end
  end

  defp validate_variables(variables) when is_list(variables) do
    with true <- Enum.all?(variables, &valid_variable?/1),
         names = Enum.map(variables, & &1["name"]),
         true <- names == Enum.sort(names) and Enum.uniq(names) == names,
         {:ok, normalized} <- normalize_artifact_variables(variables),
         true <- normalized == variables do
      :ok
    else
      _ -> {:error, :invalid_artifact_variables}
    end
  end

  defp validate_variables(_), do: {:error, :invalid_artifact_variables}

  defp valid_variable?(variable) when is_map(variable) do
    is_binary(variable["name"]) and is_binary(variable["type"]) and
      variable["phase"] in ~w(compile delivery) and is_binary(variable["context"]) and
      is_boolean(variable["required"]) and is_boolean(variable["sensitive"])
  end

  defp valid_variable?(_), do: false

  defp normalize_artifact_variables(variables) do
    definitions =
      Map.new(variables, fn variable ->
        {variable["name"], Map.delete(variable, "name")}
      end)

    with {:ok, %{"variables" => normalized}} <-
           Schema.normalize(%{"version" => 1, "variables" => definitions}) do
      {:ok,
       normalized
       |> Enum.map(fn {name, definition} -> Map.put(definition, "name", name) end)
       |> Enum.sort_by(& &1["name"])}
    end
  end

  defp validate_translation_units(units, source_hash) when is_list(units) do
    if Enum.all?(units, &valid_translation_unit?(&1, source_hash)),
      do: :ok,
      else: {:error, :invalid_artifact_translation_units}
  end

  defp validate_translation_units(_, _), do: {:error, :invalid_artifact_translation_units}

  defp valid_translation_unit?(unit, source_hash) when is_map(unit) do
    required = ~w(id context source range source_hash)
    allowed = required ++ ~w(channel description placeholders)

    valid_translation_shape?(unit, required, allowed) and
      valid_translation_identity?(unit, source_hash) and valid_translation_optional?(unit)
  end

  defp valid_translation_unit?(_, _), do: false

  defp valid_translation_shape?(unit, required, allowed) do
    Enum.all?(required, &Map.has_key?(unit, &1)) and Map.keys(unit) -- allowed == []
  end

  defp valid_translation_identity?(unit, source_hash) do
    is_binary(unit["id"]) and Regex.match?(~r/\A[0-9a-f]{24}\z/, unit["id"]) and
      unit["context"] in @delivery_contexts and is_binary(unit["source"]) and
      valid_translation_source_hash?(unit, source_hash) and valid_range?(unit["range"])
  end

  defp valid_translation_source_hash?(%{"channel" => channel, "source_hash" => hash}, _)
       when channel in @translation_channels do
    is_binary(hash) and Regex.match?(@hash_pattern, hash)
  end

  defp valid_translation_source_hash?(%{"channel" => _, "source_hash" => _}, _), do: false

  defp valid_translation_source_hash?(%{"source_hash" => hash}, source_hash),
    do: hash == source_hash

  defp valid_translation_optional?(unit) do
    (not Map.has_key?(unit, "description") or is_binary(unit["description"])) and
      (not Map.has_key?(unit, "placeholders") or is_list(unit["placeholders"]))
  end

  defp validate_source_map(source_map) when is_map(source_map) do
    if Enum.all?(source_map, fn {token, entry} ->
         is_binary(token) and Regex.match?(~r/\ALPX_[0-9a-f]{16}_[0-9a-z]+_XPL\z/, token) and
           is_map(entry) and Enum.sort(Map.keys(entry)) == ~w(context source variable) and
           entry["context"] in @delivery_contexts and is_binary(entry["variable"]) and
           valid_range?(entry["source"])
       end),
       do: :ok,
       else: {:error, :invalid_artifact_source_map}
  end

  defp validate_source_map(_), do: {:error, :invalid_artifact_source_map}

  defp validate_lint(lint) when is_list(lint) do
    if Enum.all?(lint, fn item ->
         is_map(item) and is_binary(item["code"]) and is_binary(item["message"]) and
           item["severity"] in ~w(warning information hint)
       end),
       do: :ok,
       else: {:error, :invalid_artifact_lint}
  end

  defp validate_lint(_), do: {:error, :invalid_artifact_lint}

  defp valid_range?(%{"start" => start, "end" => finish})
       when is_integer(start) and start >= 0 and is_integer(finish) and finish >= start,
       do: true

  defp valid_range?(_), do: false

  defp validate_json_native(value) do
    if json_native?(value), do: :ok, else: {:error, :invalid_artifact_json}
  end

  defp json_native?(value) when is_map(value) and not is_struct(value) do
    Enum.all?(value, fn {key, item} -> is_binary(key) and json_native?(item) end)
  end

  defp json_native?(value) when is_list(value), do: Enum.all?(value, &json_native?/1)
  defp json_native?(value) when is_binary(value) or is_integer(value), do: true
  defp json_native?(value) when is_boolean(value) or is_nil(value), do: true

  defp json_native?(value) when is_float(value) do
    case Jason.encode(value) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  defp json_native?(_), do: false

  defp validate_hash(%{"content_sha256" => expected} = map) when is_binary(expected) do
    actual =
      map
      |> Map.delete("content_sha256")
      |> CanonicalJSON.hash()

    if secure_compare(actual, expected),
      do: :ok,
      else: {:error, :artifact_hash_mismatch}
  end

  defp validate_hash(_), do: {:error, :artifact_hash_missing}

  defp build(map) do
    {:ok,
     %__MODULE__{
       artifact_version: map["artifact_version"],
       profile: map["profile"],
       source_sha256: map["source_sha256"],
       schema_sha256: map["schema_sha256"],
       options_sha256: map["options_sha256"],
       compiler: map["compiler"] || %{},
       subject: map["subject"],
       html: map["html"],
       text: map["text"],
       variables: map["variables"] || [],
       translation_units: map["translation_units"] || [],
       source_map: map["source_map"] || %{},
       lint: map["lint"] || [],
       content_sha256: map["content_sha256"]
     }}
  rescue
    KeyError -> {:error, :invalid_artifact}
  end

  defp artifact_options(opts) do
    %{
      "compile_values_sha256" => CanonicalJSON.hash(Keyword.get(opts, :compile_values, %{})),
      "subject_sha256" => optional_hash(Keyword.get(opts, :subject)),
      "text_sha256" => optional_hash(Keyword.get(opts, :text))
    }
  end

  defp optional_hash(nil), do: nil
  defp optional_hash(value), do: sha256(value)

  defp bundle_hash do
    Application.app_dir(:letterpress, "priv/compiler/worker.mjs")
    |> File.read!()
    |> sha256()
  end

  defp non_error_diagnostics(diagnostics) do
    Enum.reject(diagnostics, &(&1["severity"] == "error"))
  end

  defp sha256(value), do: :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)

  defp secure_compare(left, right) when byte_size(left) == byte_size(right) do
    left
    |> :crypto.exor(right)
    |> :binary.bin_to_list()
    |> Enum.reduce(0, &Bitwise.bor/2)
    |> Kernel.==(0)
  end

  defp secure_compare(_, _), do: false
end
