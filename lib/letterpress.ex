defmodule Letterpress do
  @moduledoc """
  Safe, deterministic notification templates for Elixir.

  `Letterpress` is the public facade for discovering template variables,
  validating source, compiling immutable artifacts, rendering stored artifacts,
  formatting source, and applying translations.

  Compilation belongs in an authoring or publication path. It uses the bundled
  Node/MJML compiler through a caller-owned `Letterpress.Compiler.Supervisor`.
  Rendering belongs in the delivery path: it needs only a verified artifact and
  runs Liquid in an isolated BEAM process with explicit limits.

  Expected template, schema, artifact, and value failures return tagged errors
  with `Letterpress.Diagnostic` structs. Callers should branch on diagnostic
  codes, not English messages.

  ## Example

      iex> schema = %{
      ...>   "version" => 1,
      ...>   "variables" => %{
      ...>     "name" => %{"type" => "string", "context" => "text"}
      ...>   }
      ...> }
      iex> {:ok, artifact, []} =
      ...>   Letterpress.compile("text/liquid@1", "Hello {{ name }}", schema)
      iex> Letterpress.render(artifact, %{"name" => "Ada"})
      {:ok, %{text: "Hello Ada"}}
  """

  alias Letterpress.{
    Artifact,
    Compiler,
    Contract,
    Diagnostic,
    JSON,
    Profile,
    Renderer,
    Schema,
    Telemetry
  }

  @version Mix.Project.config()[:version]
  @base_options [
    document_version: [type: :non_neg_integer, default: 0],
    compiler_pool: [type: :atom, default: Letterpress.Compiler.Pool],
    compiler_timeout: [type: :pos_integer, default: 15_000]
  ]
  @compile_options @base_options ++
                     [
                       subject: [type: :string],
                       text: [type: :string],
                       compile_values: [type: {:map, :any, :any}, default: %{}]
                     ]

  @doc """
  Returns the Letterpress version used to stamp new artifacts.

  Artifact provenance also records the pinned compiler components. See
  `Letterpress.Artifact` for the complete serialized contract.
  """
  @spec version() :: String.t()
  def version, do: @version

  @doc """
  Returns the supported profile identifiers in lexical order.

  Profile identifiers are versioned. An existing identifier does not change
  meaning after release.

  ## Example

      iex> Letterpress.profiles()
      ["email/mjml-liquid@1", "html/liquid@1", "text/liquid@1"]
  """
  @spec profiles() :: [String.t()]
  def profiles, do: Profile.all()

  @doc """
  Returns the generated contract shared by the Elixir and browser packages.

  The map describes profiles, schema types, diagnostics, limits, grammar, and
  editor metadata for the current contract version.

  ## Example

      iex> Letterpress.contract()["contract_version"]
      1
  """
  @spec contract() :: map()
  def contract, do: Contract.get()

  @doc """
  Discovers variables, dependencies, contexts, and translation units in source.

  Discovery does not require a schema and never infers one. The successful
  result is `{:ok, analysis, diagnostics}`; diagnostics may contain non-error
  hints or warnings. Any error diagnostic changes the return to
  `{:error, diagnostics}`.

  ## Options

    * `:document_version` - caller-owned revision echoed in diagnostics;
      defaults to `0`
    * `:compiler_pool` - registered compiler pool; defaults to
      `Letterpress.Compiler.Pool`
    * `:compiler_timeout` - request deadline in milliseconds; defaults to
      `15_000`
  """
  @spec discover(String.t(), String.t(), keyword()) ::
          {:ok, map(), [Diagnostic.t()]} | {:error, [Diagnostic.t()]}
  def discover(profile, source, opts \\ []) do
    Telemetry.span(:discover, profile_name(profile), input_size(source), fn ->
      with :ok <- validate_source(source),
           {:ok, opts} <- validate_options(opts, @base_options),
           :ok <- Profile.validate(profile),
           {:ok, result} <-
             compiler_request(
               :discover,
               %{
                 "profile" => profile,
                 "source" => source,
                 "document_version" => Keyword.fetch!(opts, :document_version)
               },
               opts
             ) do
        finish_analysis(result)
      else
        {:error, diagnostics} when is_list(diagnostics) -> {:error, diagnostics}
        {:error, reason} -> {:error, [Diagnostic.system(reason, profile, source, opts)]}
      end
    end)
  end

  @doc """
  Validates source against a typed schema without creating an artifact.

  Analysis performs profile parsing, schema checks, context checks, dependency
  discovery, and linting. Use `compile/4` when the source is ready to become a
  persistable delivery artifact.

  Accepts the same `:document_version`, `:compiler_pool`, and
  `:compiler_timeout` options as `discover/3`.
  """
  @spec analyze(String.t(), String.t(), map(), keyword()) ::
          {:ok, map(), [Diagnostic.t()]} | {:error, [Diagnostic.t()]}
  def analyze(profile, source, schema, opts \\ []) do
    Telemetry.span(:analyze, profile_name(profile), input_size(source), fn ->
      do_analyze(profile, source, schema, opts)
    end)
  end

  @doc """
  Compiles source and a schema into an immutable `Letterpress.Artifact`.

  A successful call returns `{:ok, artifact, diagnostics}`. The artifact is
  emitted only when no error diagnostic exists. Store the complete artifact;
  extracting generated HTML or text discards the schema, provenance, and
  integrity data needed by `render/3`.

  ## Options

    * `:subject` - email subject template
    * `:text` - email plain-text alternative
    * `:compile_values` - JSON object containing compile-phase values
    * `:document_version`, `:compiler_pool`, and `:compiler_timeout` - see
      `discover/3`

  `:subject` and `:text` are valid only for the email profile. All configured
  channels are schema-checked and later rendered atomically.
  """
  @spec compile(String.t(), String.t(), map(), keyword()) ::
          {:ok, Artifact.t(), [Diagnostic.t()]} | {:error, [Diagnostic.t()]}
  def compile(profile, source, schema, opts \\ []) do
    Telemetry.span(:compile, profile_name(profile), input_size(source), fn ->
      with :ok <- validate_source(source),
           {:ok, opts} <- validate_options(opts, @compile_options),
           :ok <- validate_compile_channels(profile, opts),
           {:ok, compile_values} <- normalize_json_map(Keyword.fetch!(opts, :compile_values)),
           opts = Keyword.put(opts, :compile_values, compile_values),
           :ok <- Profile.validate(profile),
           {:ok, normalized_schema} <- Schema.normalize(schema),
           payload = compiler_payload(profile, source, normalized_schema, opts),
           {:ok, result} <- compiler_request(:compile, payload, opts) do
        finish_compile(profile, source, normalized_schema, opts, result)
      else
        {:error, diagnostics} when is_list(diagnostics) -> {:error, diagnostics}
        {:error, reason} -> {:error, [Diagnostic.system(reason, profile, source, opts)]}
      end
    end)
  end

  @doc """
  Renders every channel in an artifact atomically in pure BEAM code.

  The values must form a JSON object and match the artifact's delivery-phase
  schema. No channel is returned if another channel fails. Rendering does not
  use the compiler pool, Node, or MJML.

  See `Letterpress.Renderer.render/3` for resource and validation options.
  """
  @spec render(Artifact.t() | map(), map(), keyword()) ::
          {:ok, %{optional(atom()) => String.t()}} | {:error, [Diagnostic.t()]}
  def render(artifact, values, opts \\ []), do: Renderer.render(artifact, values, opts)

  @doc """
  Returns the stable translatable units discovered in source.

  Each unit carries an ID, source range, context, source hash, and original
  text. Unit IDs are derived from the source structure and are inputs to
  `apply_translations/5`.
  """
  @spec extract_translation_units(String.t(), String.t(), map(), keyword()) ::
          {:ok, [map()], [Diagnostic.t()]} | {:error, [Diagnostic.t()]}
  def extract_translation_units(profile, source, schema, opts \\ []) do
    case analyze(profile, source, schema, opts) do
      {:ok, analysis, diagnostics} ->
        {:ok, analysis["translation_units"] || [], diagnostics}

      {:error, diagnostics} ->
        {:error, diagnostics}
    end
  end

  @doc """
  Applies translations after checking source and placeholder identity.

  `translations` is a JSON object keyed by translation-unit ID. A value may be
  the translated string or an object containing a `"text"` string. Missing
  units, changed Liquid placeholders, or changed protected markup return error
  diagnostics and leave the source unpublished.
  """
  @spec apply_translations(String.t(), String.t(), map(), map(), keyword()) ::
          {:ok, String.t(), [Diagnostic.t()]} | {:error, [Diagnostic.t()]}
  def apply_translations(profile, source, schema, translations, opts \\ []) do
    Telemetry.span(:apply_translations, profile_name(profile), input_size(source), fn ->
      do_apply_translations(profile, source, schema, translations, opts)
    end)
  end

  @doc """
  Formats source with the formatter pinned to the profile contract.

  Formatting is deterministic for the same source and pinned compiler bundle.
  Text-profile formatting removes trailing whitespace; email formatting uses
  the bundled Liquid/HTML formatter.

  ## Example

      iex> Letterpress.format("text/liquid@1", "Hello  ")
      {:ok, "Hello"}
  """
  @spec format(String.t(), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, [Diagnostic.t()]}
  def format(profile, source, opts \\ []) do
    Telemetry.span(:format, profile_name(profile), input_size(source), fn ->
      with :ok <- validate_source(source),
           {:ok, opts} <- validate_options(opts, @base_options),
           :ok <- Profile.validate(profile),
           {:ok, result} <-
             compiler_request(
               :format,
               %{
                 "profile" => profile,
                 "source" => source,
                 "document_version" => Keyword.fetch!(opts, :document_version)
               },
               opts
             ) do
        {:ok, result["source"]}
      else
        {:error, diagnostics} when is_list(diagnostics) ->
          {:error, diagnostics}

        {:error, reason} ->
          {:error, [Diagnostic.system(reason, profile_name(profile), source, opts)]}
      end
    end)
  end

  @doc """
  Decodes and verifies canonical artifact JSON or a decoded map.

  Verification covers the artifact version, exact shape, profile, compiler
  provenance, hashes, schema entries, channels, and content hash. Invalid input
  returns `{:error, reason}`.
  """
  @spec decode_artifact(binary() | map()) :: {:ok, Artifact.t()} | {:error, term()}
  def decode_artifact(value), do: Artifact.decode(value)

  @doc """
  Encodes a verified artifact as canonical JSON.

  The artifact's content hash is checked before encoding. The resulting bytes
  are suitable for persistence or transport across runtimes.
  """
  @spec encode_artifact(Artifact.t()) :: {:ok, binary()} | {:error, term()}
  def encode_artifact(value), do: Artifact.encode(value)

  defp compiler_payload(profile, source, schema, opts) do
    %{
      "profile" => profile,
      "source" => source,
      "subject" => Keyword.get(opts, :subject),
      "text" => Keyword.get(opts, :text),
      "schema" => schema,
      "compile_values" => Keyword.get(opts, :compile_values, %{}),
      "document_version" => Keyword.fetch!(opts, :document_version)
    }
  end

  defp do_analyze(profile, source, schema, opts) do
    with :ok <- validate_source(source),
         {:ok, opts} <- validate_options(opts, @base_options),
         :ok <- Profile.validate(profile),
         {:ok, normalized_schema} <- Schema.normalize(schema),
         payload = compiler_payload(profile, source, normalized_schema, opts),
         {:ok, result} <- compiler_request(:analyze, payload, opts) do
      finish_analysis(result)
    else
      {:error, diagnostics} when is_list(diagnostics) -> {:error, diagnostics}
      {:error, reason} -> {:error, [Diagnostic.system(reason, profile, source, opts)]}
    end
  end

  defp finish_analysis(result) do
    diagnostics = Diagnostic.from_maps(result["diagnostics"] || [])

    if Diagnostic.errors?(diagnostics),
      do: {:error, diagnostics},
      else: {:ok, Map.drop(result, ["diagnostics"]), diagnostics}
  end

  defp do_apply_translations(profile, source, schema, translations, opts) do
    with :ok <- validate_source(source),
         {:ok, translations} <- normalize_json_map(translations),
         {:ok, opts} <- validate_options(opts, @base_options),
         :ok <- Profile.validate(profile),
         {:ok, normalized_schema} <- Schema.normalize(schema),
         payload =
           profile
           |> compiler_payload(source, normalized_schema, opts)
           |> Map.put("translations", translations),
         {:ok, result} <- compiler_request(:apply_translations, payload, opts) do
      finish_translation(result)
    else
      {:error, diagnostics} when is_list(diagnostics) ->
        {:error, diagnostics}

      {:error, reason} ->
        {:error, [Diagnostic.system(reason, profile_name(profile), source, opts)]}
    end
  end

  defp finish_translation(result) do
    diagnostics = Diagnostic.from_maps(result["diagnostics"] || [])

    if Diagnostic.errors?(diagnostics),
      do: {:error, diagnostics},
      else: {:ok, result["source"], diagnostics}
  end

  defp compiler_request(operation, payload, opts) do
    Compiler.request(operation, payload,
      pool: Keyword.fetch!(opts, :compiler_pool),
      timeout: Keyword.fetch!(opts, :compiler_timeout)
    )
  end

  defp validate_options(opts, schema) when is_list(opts) do
    case NimbleOptions.validate(opts, schema) do
      {:ok, validated} -> {:ok, validated}
      {:error, _} -> {:error, [Diagnostic.simple("LP_OPTIONS_INVALID", "Options are invalid")]}
    end
  end

  defp validate_options(_, _),
    do: {:error, [Diagnostic.simple("LP_OPTIONS_INVALID", "Options must be a keyword list")]}

  defp validate_source(source) when is_binary(source), do: :ok

  defp validate_source(_),
    do: {:error, [Diagnostic.simple("LP_SOURCE_INVALID", "Source must be a string")]}

  defp validate_compile_channels(profile, opts)
       when profile in ["html/liquid@1", "text/liquid@1"] do
    if Keyword.has_key?(opts, :subject) or Keyword.has_key?(opts, :text) do
      {:error,
       [
         Diagnostic.simple(
           "LP_OPTIONS_INVALID",
           "Single-channel profiles do not accept email subject or text-alternative options"
         )
       ]}
    else
      :ok
    end
  end

  defp validate_compile_channels(_, _), do: :ok

  defp normalize_json_map(value) do
    case JSON.normalize_object(value) do
      {:ok, normalized} ->
        {:ok, normalized}

      {:error, _} ->
        {:error, [Diagnostic.simple("LP_INPUT_INVALID", "Input must be a JSON object")]}
    end
  end

  defp profile_name(profile) when is_binary(profile), do: profile
  defp profile_name(_), do: "unknown"

  defp input_size(source) when is_binary(source), do: byte_size(source)
  defp input_size(_), do: 0

  defp diagnostics_from_result(result) when is_map(result) do
    Diagnostic.from_maps(result["diagnostics"] || [])
  end

  defp finish_compile(profile, source, schema, opts, result) do
    diagnostics = diagnostics_from_result(result)

    if Diagnostic.errors?(diagnostics) do
      {:error, diagnostics}
    else
      case Artifact.from_compiler(profile, source, schema, opts, result) do
        {:ok, artifact} -> {:ok, artifact, diagnostics}
        {:error, reason} -> {:error, [Diagnostic.system(reason, profile, source, opts)]}
      end
    end
  end
end
