defmodule Letterpress do
  @moduledoc """
  Public entry point for profile analysis, deterministic compilation, and safe rendering.

  Compilation is an authoring operation backed by the supervised official MJML
  worker. Rendering consumes only a decoded immutable artifact and runs in
  bounded pure-BEAM code.
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
  @base_options [document_version: [type: :non_neg_integer, default: 0]]
  @compile_options @base_options ++
                     [
                       subject: [type: :string],
                       compile_values: [type: {:map, :any, :any}, default: %{}]
                     ]

  @doc "Returns the Letterpress library version used to stamp artifacts."
  @spec version() :: String.t()
  def version, do: @version

  @doc "Returns all supported immutable profile identifiers."
  @spec profiles() :: [String.t()]
  def profiles, do: Profile.all()

  @doc "Returns the generated backend/browser contract."
  @spec contract() :: map()
  def contract, do: Contract.get()

  @doc "Analyzes source without creating an artifact."
  @spec analyze(String.t(), String.t(), map(), keyword()) ::
          {:ok, map(), [Diagnostic.t()]} | {:error, [Diagnostic.t()]}
  def analyze(profile, source, schema, opts \\ []) do
    Telemetry.span(:analyze, profile_name(profile), input_size(source), fn ->
      do_analyze(profile, source, schema, opts)
    end)
  end

  @doc "Compiles profile source into a deterministic immutable artifact."
  @spec compile(String.t(), String.t(), map(), keyword()) ::
          {:ok, Artifact.t(), [Diagnostic.t()]} | {:error, [Diagnostic.t()]}
  def compile(profile, source, schema, opts \\ []) do
    Telemetry.span(:compile, profile_name(profile), input_size(source), fn ->
      with :ok <- validate_source(source),
           {:ok, opts} <- validate_options(opts, @compile_options),
           {:ok, compile_values} <- normalize_json_map(Keyword.fetch!(opts, :compile_values)),
           opts = Keyword.put(opts, :compile_values, compile_values),
           :ok <- Profile.validate(profile),
           {:ok, normalized_schema} <- Schema.normalize(schema),
           payload = compiler_payload(profile, source, normalized_schema, opts),
           {:ok, result} <- Compiler.request(:compile, payload) do
        finish_compile(profile, source, normalized_schema, opts, result)
      else
        {:error, diagnostics} when is_list(diagnostics) -> {:error, diagnostics}
        {:error, reason} -> {:error, [Diagnostic.system(reason, profile, source, opts)]}
      end
    end)
  end

  @doc "Renders all channels in an artifact atomically with bounded pure-BEAM Liquid."
  @spec render(Artifact.t() | map(), map(), keyword()) ::
          {:ok, %{optional(atom()) => String.t()}} | {:error, [Diagnostic.t()]}
  def render(artifact, values, opts \\ []), do: Renderer.render(artifact, values, opts)

  @doc "Returns stable translatable units discovered in source."
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

  @doc "Applies translated units after proving source and placeholder identity."
  @spec apply_translations(String.t(), String.t(), map(), map(), keyword()) ::
          {:ok, String.t(), [Diagnostic.t()]} | {:error, [Diagnostic.t()]}
  def apply_translations(profile, source, schema, translations, opts \\ []) do
    Telemetry.span(:apply_translations, profile_name(profile), input_size(source), fn ->
      do_apply_translations(profile, source, schema, translations, opts)
    end)
  end

  @doc "Formats source with the profile's pinned formatter."
  @spec format(String.t(), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, [Diagnostic.t()]}
  def format(profile, source, opts \\ []) do
    Telemetry.span(:format, profile_name(profile), input_size(source), fn ->
      with :ok <- validate_source(source),
           {:ok, opts} <- validate_options(opts, @base_options),
           :ok <- Profile.validate(profile),
           {:ok, result} <-
             Compiler.request(:format, %{
               "profile" => profile,
               "source" => source,
               "document_version" => Keyword.fetch!(opts, :document_version)
             }) do
        {:ok, result["source"]}
      else
        {:error, diagnostics} when is_list(diagnostics) ->
          {:error, diagnostics}

        {:error, reason} ->
          {:error, [Diagnostic.system(reason, profile_name(profile), source, opts)]}
      end
    end)
  end

  @doc "Decodes and verifies canonical artifact JSON or a decoded map."
  @spec decode_artifact(binary() | map()) :: {:ok, Artifact.t()} | {:error, term()}
  def decode_artifact(value), do: Artifact.decode(value)

  @doc "Encodes a verified artifact as canonical JSON."
  @spec encode_artifact(Artifact.t()) :: {:ok, binary()} | {:error, term()}
  def encode_artifact(value), do: Artifact.encode(value)

  defp compiler_payload(profile, source, schema, opts) do
    %{
      "profile" => profile,
      "source" => source,
      "subject" => Keyword.get(opts, :subject),
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
         {:ok, result} <-
           Compiler.request(:analyze, compiler_payload(profile, source, normalized_schema, opts)) do
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
         {:ok, result} <- Compiler.request(:apply_translations, payload) do
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
