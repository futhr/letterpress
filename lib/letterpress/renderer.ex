defmodule Letterpress.Renderer do
  @moduledoc """
  Renders verified artifacts in bounded, isolated BEAM processes.

  Rendering is atomic across channels: a caller receives every configured
  subject, HTML, and text value or an error with no partial output. Values are
  normalized as JSON, checked against the artifact's typed schema, and escaped
  according to contexts proven during compilation.

  Each render runs in a monitored process with a deadline, maximum heap, input
  budgets, loop budget, and per-channel output limit. The MJML compiler and Node
  are never used in this path.

  ## Example

      iex> schema = %{
      ...>   "version" => 1,
      ...>   "variables" => %{
      ...>     "name" => %{"type" => "string", "context" => "text"}
      ...>   }
      ...> }
      iex> {:ok, artifact, []} =
      ...>   Letterpress.compile("text/liquid@1", "Hello {{ name }}", schema)
      iex> Letterpress.Renderer.render(artifact, %{"name" => "Grace"})
      {:ok, %{text: "Hello Grace"}}
  """

  alias Letterpress.{Artifact, Contract, Diagnostic, JSON, Schema, Telemetry}
  alias Letterpress.Renderer.Filters

  @allowed_tags ~w(if unless for case comment break continue)
  @options_schema [
    timeout: [type: :pos_integer, default: 5_000],
    max_output_bytes: [type: :pos_integer, default: 1_000_000],
    max_heap_words: [type: :pos_integer, default: 2_000_000],
    subject_max_bytes: [type: :pos_integer, default: 998],
    allowed_url_schemes: [
      type: {:list, {:in, ~w(http https mailto tel cid)}},
      default: ~w(http https mailto tel cid)
    ],
    strict_values: [type: :boolean, default: true]
  ]

  @doc """
  Renders a decoded artifact with typed values and runtime budgets.

  `artifact` may be a verified `Letterpress.Artifact` or its string-keyed map
  projection. `values` must be a JSON object whose delivery-phase values match
  the embedded schema.

  ## Options

    * `:strict_values` - reject undeclared root keys; defaults to `true`
    * `:timeout` - whole-render deadline in milliseconds; defaults to `5_000`
    * `:max_heap_words` - isolated process heap limit; defaults to `2_000_000`
    * `:max_output_bytes` - limit for each rendered channel; defaults to
      `1_000_000`
    * `:subject_max_bytes` - subject byte limit; defaults to `998`
    * `:allowed_url_schemes` - narrows the contract's absolute URL schemes for
      this call; defaults to `http`, `https`, `mailto`, `tel`, and `cid`

  Relative paths and fragment URLs remain valid regardless of the absolute
  scheme list. Invalid options and expected render failures return diagnostics.
  """
  @spec render(Artifact.t() | map(), map(), keyword()) ::
          {:ok, %{optional(atom()) => String.t()}} | {:error, [Diagnostic.t()]}
  def render(artifact, values, opts \\ []) do
    profile = artifact_profile(artifact)

    Telemetry.span(:render, profile, input_size(values), fn ->
      with {:ok, opts} <- validate_options(opts),
           {:ok, decoded} <- decode(artifact),
           {:ok, normalized_values} <- validate_values(decoded, values, opts),
           {:ok, rendered} <- isolated_render(decoded, normalized_values, opts) do
        {:ok, rendered}
      else
        {:error, diagnostics} when is_list(diagnostics) -> {:error, diagnostics}
        {:error, reason} -> {:error, [runtime_diagnostic(reason, decoded_source_hash(artifact))]}
      end
    end)
  end

  defp decode(%Artifact{} = artifact) do
    artifact
    |> Artifact.to_map()
    |> Artifact.decode()
  end

  defp decode(map) when is_map(map), do: Artifact.decode(map)
  defp decode(_), do: {:error, :invalid_artifact}

  defp validate_values(%Artifact{} = artifact, values, opts)
       when is_map(values) and not is_struct(values) do
    with {:ok, values} <- JSON.normalize_object(values),
         :ok <- validate_input_limits(values),
         :ok <- validate_known_values(artifact.variables, values, opts),
         :ok <- validate_definitions(artifact.variables, values) do
      {:ok, apply_defaults(artifact.variables, values)}
    end
  end

  defp validate_values(_, _, _), do: {:error, :invalid_render_values}

  defp validate_options(opts) when is_list(opts) do
    case NimbleOptions.validate(opts, @options_schema) do
      {:ok, validated} -> {:ok, validated}
      {:error, _} -> {:error, :invalid_render_options}
    end
  end

  defp validate_options(_), do: {:error, :invalid_render_options}

  defp validate_known_values(definitions, values, opts) do
    if Keyword.fetch!(opts, :strict_values) do
      known_roots =
        definitions
        |> Enum.filter(&(&1["phase"] == "delivery"))
        |> Enum.map(fn definition ->
          definition["name"]
          |> String.split(".")
          |> hd()
        end)
        |> MapSet.new()

      case Enum.find(Map.keys(values), &(not MapSet.member?(known_roots, &1))) do
        nil -> :ok
        name -> {:error, [runtime_diagnostic({:unknown_value, name}, "")]}
      end
    else
      :ok
    end
  end

  defp validate_definitions(definitions, values) do
    definitions
    |> Enum.filter(&(&1["phase"] == "delivery"))
    |> Enum.reduce_while(:ok, fn definition, :ok ->
      name = definition["name"]
      value = value_at(values, name)

      cond do
        is_nil(value) and definition["required"] == true and
            not Map.has_key?(definition, "default") ->
          {:halt, {:error, [runtime_diagnostic({:missing_value, name}, "")]}}

        is_nil(value) ->
          {:cont, :ok}

        Schema.value_matches_definition?(value, definition) ->
          {:cont, :ok}

        true ->
          {:halt, {:error, [runtime_diagnostic({:invalid_value, name}, "")]}}
      end
    end)
  end

  defp isolated_render(artifact, values, opts) do
    timeout = Keyword.fetch!(opts, :timeout)
    max_heap = Keyword.fetch!(opts, :max_heap_words)
    parent = self()
    ref = make_ref()

    {pid, monitor} =
      :erlang.spawn_opt(
        fn -> send(parent, {ref, render_channels(artifact, values, opts)}) end,
        [:monitor, {:max_heap_size, %{size: max_heap, kill: true, error_logger: false}}]
      )

    receive do
      {^ref, result} ->
        Process.demonitor(monitor, [:flush])
        result

      {:DOWN, ^monitor, :process, ^pid, reason} ->
        {:error, {:render_process_exit, reason}}
    after
      timeout ->
        Process.exit(pid, :kill)
        receive do: ({:DOWN, ^monitor, :process, ^pid, _} -> :ok)
        {:error, :render_timeout}
    end
  end

  defp render_channels(artifact, values, opts) do
    Process.put(:letterpress_subject_max_bytes, Keyword.fetch!(opts, :subject_max_bytes))
    Process.put(:letterpress_allowed_url_schemes, Keyword.fetch!(opts, :allowed_url_schemes))

    channels = [subject: artifact.subject, html: artifact.html, text: artifact.text]

    channels
    |> Enum.reject(fn {_, template} -> is_nil(template) end)
    |> Enum.reduce_while({:ok, %{}}, fn {channel, template}, {:ok, acc} ->
      reduce_rendered_channel(render_template(template, values), channel, acc, opts)
    end)
  end

  defp reduce_rendered_channel({:ok, output}, :subject, acc, opts) do
    case Filters.escape(output, "subject") do
      {:ok, subject} -> store_rendered_channel(subject, :subject, acc, opts)
      :error -> {:halt, {:error, {:liquid_errors, []}}}
    end
  end

  defp reduce_rendered_channel({:ok, output}, channel, acc, opts),
    do: store_rendered_channel(output, channel, acc, opts)

  defp reduce_rendered_channel(error, _, _, _), do: {:halt, error}

  defp store_rendered_channel(output, channel, acc, opts) do
    if within_output_limit?(output, opts),
      do: {:cont, {:ok, Map.put(acc, channel, output)}},
      else: {:halt, {:error, :render_output_too_large}}
  end

  defp render_template(template, values) do
    Process.put(:letterpress_loop_iterations, 0)
    Process.put(:letterpress_loop_limit, Contract.get()["limits"]["loop_iterations"])

    try do
      with :ok <- reject_legacy_syntax(template),
           {:ok, parsed} <- Solid.parse(template, tags: allowed_tags()),
           {:ok, output, []} <-
             Solid.render(parsed, values,
               strict_variables: true,
               strict_filters: true,
               custom_filters: &Filters.apply/2
             ) do
        {:ok, IO.iodata_to_binary(output)}
      else
        {:ok, _, errors} -> {:error, {:liquid_errors, errors}}
        {:error, errors, _} -> {:error, {:liquid_errors, errors}}
        {:error, error} -> {:error, {:liquid_parse, error}}
      end
    catch
      :letterpress_loop_limit -> {:error, :render_loop_limit}
    after
      Process.delete(:letterpress_loop_iterations)
      Process.delete(:letterpress_loop_limit)
    end
  end

  defp reject_legacy_syntax(template) do
    if Regex.match?(~r/\{\{\{|\{\{\s*[#\/^!]/, template),
      do: {:error, :legacy_syntax},
      else: :ok
  end

  defp allowed_tags do
    Solid.Tag.default_tags()
    |> Map.take(@allowed_tags)
    |> Map.put("for", Letterpress.Renderer.ForTag)
  end

  defp validate_input_limits(values) do
    limits = Contract.get()["limits"]

    case inspect_value(values, 0, limits, %{keys: 0, items: 0}) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, [runtime_diagnostic(reason, "")]}
    end
  end

  defp inspect_value(value, depth, limits, counts) do
    if depth > limits["input_depth"] do
      {:error, :render_input_too_deep}
    else
      do_inspect_value(value, depth, limits, counts)
    end
  end

  defp do_inspect_value(value, depth, limits, counts) when is_map(value) do
    next = %{counts | keys: counts.keys + map_size(value)}

    if next.keys > limits["input_keys"] do
      {:error, :render_input_too_many_keys}
    else
      value
      |> Map.values()
      |> inspect_children(depth, limits, next)
    end
  end

  defp do_inspect_value(value, depth, limits, counts) when is_list(value) do
    next = %{counts | items: counts.items + length(value)}

    if next.items > limits["collection_items"] do
      {:error, :render_input_too_many_items}
    else
      inspect_children(value, depth, limits, next)
    end
  end

  defp do_inspect_value(value, _, limits, counts) when is_binary(value) do
    if byte_size(value) <= limits["scalar_bytes"],
      do: {:ok, counts},
      else: {:error, :render_scalar_too_large}
  end

  defp do_inspect_value(value, _, _, counts)
       when is_number(value) or is_boolean(value) or is_nil(value),
       do: {:ok, counts}

  defp do_inspect_value(_, _, _, _), do: {:error, :render_input_invalid}

  defp inspect_children(children, depth, limits, counts) do
    Enum.reduce_while(children, {:ok, counts}, fn child, {:ok, current} ->
      continue_inspection(inspect_value(child, depth + 1, limits, current))
    end)
  end

  defp continue_inspection({:ok, updated}), do: {:cont, {:ok, updated}}
  defp continue_inspection(error), do: {:halt, error}

  defp within_output_limit?(output, opts) do
    byte_size(output) <= Keyword.fetch!(opts, :max_output_bytes)
  end

  defp value_at(values, path) do
    path
    |> String.split(".")
    |> Enum.reduce_while(values, fn segment, current ->
      if is_map(current) and Map.has_key?(current, segment) do
        {:cont, current[segment]}
      else
        {:halt, nil}
      end
    end)
  end

  defp apply_defaults(definitions, values) do
    definitions
    |> Enum.filter(&(&1["phase"] == "delivery"))
    |> Enum.reduce(values, fn definition, acc ->
      name = definition["name"]
      current = value_at(acc, name)

      cond do
        not is_nil(current) ->
          put_value_at(acc, name, apply_nested_defaults(current, definition))

        Map.has_key?(definition, "default") ->
          put_value_at(acc, name, apply_nested_defaults(definition["default"], definition))

        true ->
          put_value_at(acc, name, nil)
      end
    end)
  end

  defp apply_nested_defaults(value, %{"type" => "object", "properties" => properties})
       when is_map(value) do
    Enum.reduce(properties, value, fn {name, definition}, acc ->
      current = acc[name]

      cond do
        not is_nil(current) ->
          Map.put(acc, name, apply_nested_defaults(current, definition))

        Map.has_key?(definition, "default") ->
          Map.put(acc, name, apply_nested_defaults(definition["default"], definition))

        true ->
          acc
      end
    end)
  end

  defp apply_nested_defaults(value, %{"type" => "list", "items" => items})
       when is_list(value),
       do: Enum.map(value, &apply_nested_defaults(&1, items))

  defp apply_nested_defaults(value, _), do: value

  defp put_value_at(values, path, value) do
    put_nested(values, String.split(path, "."), value)
  end

  defp put_nested(values, [key], value), do: Map.put(values, key, value)

  defp put_nested(values, [key | rest], value) do
    nested = if is_map(values[key]), do: values[key], else: %{}
    Map.put(values, key, put_nested(nested, rest, value))
  end

  defp runtime_diagnostic(reason, source_hash) do
    {code, message} = runtime_diagnostic_message(reason)

    %{
      Diagnostic.simple(code, message)
      | source_hash: source_hash,
        data: runtime_diagnostic_data(reason)
    }
  end

  defp runtime_diagnostic_data({kind, name})
       when kind in [:missing_value, :invalid_value, :unknown_value],
       do: %{"variable" => name}

  defp runtime_diagnostic_data(_), do: %{}

  defp runtime_diagnostic_message({:missing_value, name}),
    do: {"LP_RENDER_VALUE_MISSING", "Required delivery value #{name} is missing"}

  defp runtime_diagnostic_message({:invalid_value, name}),
    do: {"LP_RENDER_VALUE_INVALID", "Delivery value #{name} has the wrong type"}

  defp runtime_diagnostic_message({:unknown_value, name}),
    do: {"LP_RENDER_VALUE_UNKNOWN", "Delivery value #{name} is not declared"}

  defp runtime_diagnostic_message(:invalid_render_options),
    do: {"LP_OPTIONS_INVALID", "Render options are invalid"}

  defp runtime_diagnostic_message(:render_timeout),
    do: {"LP_RENDER_TIMEOUT", "Template render exceeded its deadline"}

  defp runtime_diagnostic_message(:render_output_too_large),
    do: {"LP_RENDER_OUTPUT_LIMIT", "Rendered output exceeds its byte limit"}

  defp runtime_diagnostic_message(:render_loop_limit),
    do: {"LP_RENDER_LOOP_LIMIT", "Template render exceeds its loop iteration limit"}

  defp runtime_diagnostic_message(:render_input_too_deep),
    do: {"LP_RENDER_INPUT_DEPTH", "Render input exceeds its depth limit"}

  defp runtime_diagnostic_message(:render_input_too_many_keys),
    do: {"LP_RENDER_INPUT_KEYS", "Render input has too many keys"}

  defp runtime_diagnostic_message(:render_input_too_many_items),
    do: {"LP_RENDER_INPUT_ITEMS", "Render input has too many collection items"}

  defp runtime_diagnostic_message(:render_scalar_too_large),
    do: {"LP_RENDER_INPUT_SCALAR", "Render input scalar exceeds its byte limit"}

  defp runtime_diagnostic_message({:liquid_errors, _}),
    do: {"LP_RENDER_LIQUID", "Liquid rendering failed"}

  defp runtime_diagnostic_message({:liquid_parse, _}),
    do: {"LP_ARTIFACT_LIQUID", "Artifact contains invalid Liquid"}

  defp runtime_diagnostic_message(:legacy_syntax),
    do: {"LP_LEGACY_SYNTAX", "Artifact contains legacy Mustache or Handlebars syntax"}

  defp runtime_diagnostic_message({:render_process_exit, _}),
    do: {"LP_RENDER_RESOURCE_LIMIT", "Template render exceeded a resource limit"}

  defp runtime_diagnostic_message(_),
    do: {"LP_RENDER_INVALID", "Template artifact or render input is invalid"}

  defp artifact_profile(%Artifact{profile: profile}), do: profile
  defp artifact_profile(%{"profile" => profile}), do: profile
  defp artifact_profile(_), do: "unknown"

  defp decoded_source_hash(%Artifact{source_sha256: hash}), do: hash
  defp decoded_source_hash(%{"source_sha256" => hash}), do: hash
  defp decoded_source_hash(_), do: ""

  defp input_size(values) when is_map(values), do: map_size(values)
  defp input_size(_), do: 0
end
