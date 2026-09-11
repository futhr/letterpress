defmodule Letterpress.Schema do
  @moduledoc """
  Validates and canonicalizes Letterpress variable schemas.

  A schema declares every template variable's type, phase, output context,
  required/default behavior, description, and sensitivity. Object and list
  definitions may describe nested values. The normalized form is deliberately
  JSON-native so it can cross runtimes without serializing Elixir terms.

  Atom keys are accepted at the Elixir boundary. Normalization converts them to
  strings, fills contract defaults, sorts variables, and rejects unknown fields
  or values that do not match the generated contract. Defaults apply only to
  omitted fields; conflicting collection shape fields are invalid.

  ## Example

      iex> schema = %{version: 1, variables: %{name: %{type: "string"}}}
      iex> {:ok, normalized} = Letterpress.Schema.normalize(schema)
      iex> definition = normalized["variables"]["name"]
      iex> {definition["phase"], definition["context"], definition["required"]}
      {"delivery", "text", true}
  """

  alias Letterpress.{CanonicalJSON, Contract, Diagnostic, JSON}

  @name_regex ~r/\A[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*\??\z/
  @segment_regex ~r/\A[A-Za-z_][A-Za-z0-9_]*\??\z/
  @allowed_fields ~w(type phase context required default description sensitive items properties)
  @nested_fields ~w(type required default description sensitive items properties)

  @doc """
  Normalizes a version-1 schema or returns diagnostics.

  Successful output has exactly the `"version"` and `"variables"` top-level
  keys. Expected user-authored failures return one or more
  `Letterpress.Diagnostic` structs rather than raising.

  ## Example

      iex> {:error, [diagnostic]} =
      ...>   Letterpress.Schema.normalize(%{"version" => 2, "variables" => %{}})
      iex> diagnostic.code
      "LP_SCHEMA_VERSION"
  """
  @spec normalize(map()) :: {:ok, map()} | {:error, [Diagnostic.t()]}
  def normalize(schema) when is_map(schema) and not is_struct(schema) do
    with {:ok, normalized} <- JSON.normalize_object(schema),
         :ok <- validate_top_level_keys(normalized),
         :ok <- validate_version(normalized),
         {:ok, variables} <- normalize_variables(normalized["variables"]) do
      {:ok, %{"version" => 1, "variables" => variables}}
    else
      {:error, :invalid_json_object} ->
        {:error, [Diagnostic.simple("LP_SCHEMA_INVALID", "Schema must contain JSON values")]}

      error ->
        error
    end
  end

  def normalize(_),
    do: {:error, [Diagnostic.simple("LP_SCHEMA_INVALID", "Schema must be a JSON object")]}

  @doc """
  Returns the lowercase SHA-256 digest of a normalized schema.

  Call `normalize/1` first when the map came from an external caller. This
  function hashes the value it receives and does not validate it again.

  ## Example

      iex> schema = %{"version" => 1, "variables" => %{}}
      iex> byte_size(Letterpress.Schema.hash(schema))
      64
  """
  @spec hash(map()) :: String.t()
  def hash(schema), do: CanonicalJSON.hash(schema)

  defp validate_version(%{"version" => 1}), do: :ok

  defp validate_version(_) do
    {:error, [Diagnostic.simple("LP_SCHEMA_VERSION", "Schema version must be 1")]}
  end

  defp validate_top_level_keys(schema) do
    if Enum.sort(Map.keys(schema)) == ~w(variables version) do
      :ok
    else
      {:error,
       [Diagnostic.simple("LP_SCHEMA_FIELD", "Schema must contain only version and variables")]}
    end
  end

  defp normalize_variables(variables) when is_map(variables) and not is_struct(variables) do
    limit = Contract.get()["limits"]["schema_variables"]

    if map_size(variables) > limit do
      {:error, [Diagnostic.simple("LP_SCHEMA_TOO_LARGE", "Schema has too many variables")]}
    else
      variables
      |> Enum.sort_by(fn {name, _} -> to_string(name) end)
      |> Enum.reduce_while({:ok, %{}}, &normalize_variable/2)
    end
  end

  defp normalize_variables(_) do
    {:error, [Diagnostic.simple("LP_SCHEMA_VARIABLES", "Schema variables must be an object")]}
  end

  defp normalize_variable({name, definition}, {:ok, acc}) do
    name = to_string(name)

    with :ok <- validate_name(name),
         {:ok, normalized} <- normalize_definition(name, definition) do
      {:cont, {:ok, Map.put(acc, name, normalized)}}
    else
      {:error, diagnostics} -> {:halt, {:error, diagnostics}}
    end
  end

  defp validate_name(name) do
    cond do
      not Regex.match?(@name_regex, name) ->
        {:error, [Diagnostic.simple("LP_SCHEMA_NAME", "Invalid variable name #{name}")]}

      String.starts_with?(name, "letterpress_") ->
        {:error, [Diagnostic.simple("LP_SCHEMA_RESERVED", "Variable name #{name} is reserved")]}

      true ->
        :ok
    end
  end

  defp normalize_definition(name, definition)
       when is_map(definition) and not is_struct(definition) do
    unknown = Map.keys(definition) -- @allowed_fields
    types = Contract.get()["types"]
    phases = Contract.get()["phases"]
    contexts = Contract.get()["contexts"]
    type = definition["type"]
    phase = Map.get(definition, "phase", "delivery")
    context = Map.get(definition, "context", "text")

    with :ok <- validate_fields(name, unknown),
         :ok <- validate_member(name, "type", type, types),
         :ok <- validate_member(name, "phase", phase, phases),
         :ok <- validate_member(name, "context", context, contexts),
         :ok <- validate_phase_context(name, phase, context),
         :ok <- validate_boolean_field(name, definition, "required", true),
         :ok <- validate_boolean_field(name, definition, "sensitive", false) do
      normalized =
        definition
        |> Map.put("phase", phase)
        |> Map.put("context", context)
        |> Map.put_new("required", true)
        |> Map.put_new("sensitive", false)

      with :ok <- validate_description(name, normalized),
           {:ok, normalized} <- normalize_shape(name, normalized, 1),
           :ok <- validate_default(name, normalized) do
        {:ok, normalized}
      end
    end
  end

  defp normalize_definition(name, _) do
    {:error,
     [Diagnostic.simple("LP_SCHEMA_DEFINITION", "Definition for #{name} must be an object")]}
  end

  defp validate_fields(_, []), do: :ok

  defp validate_fields(name, fields) do
    {:error,
     [
       Diagnostic.simple(
         "LP_SCHEMA_FIELD",
         "Unknown fields for #{name}: #{Enum.join(fields, ", ")}"
       )
     ]}
  end

  defp validate_member(name, field, value, allowed) do
    if value in allowed do
      :ok
    else
      code = "LP_SCHEMA_#{String.upcase(field)}"
      {:error, [Diagnostic.simple(code, "Invalid #{field} for #{name}")]}
    end
  end

  defp validate_phase_context(name, "delivery", context) when context in ["css", "color"] do
    {:error,
     [
       Diagnostic.simple(
         "LP_SCHEMA_PHASE_CONTEXT",
         "#{name} must be compile-phase in #{context} context"
       )
     ]}
  end

  defp validate_phase_context(_, _, _), do: :ok

  defp validate_boolean_field(name, definition, field, default) do
    if is_boolean(Map.get(definition, field, default)) do
      :ok
    else
      code = "LP_SCHEMA_#{String.upcase(field)}"
      {:error, [Diagnostic.simple(code, "#{field} must be boolean for #{name}")]}
    end
  end

  defp validate_default(name, %{"default" => value, "type" => type} = definition) do
    if value_matches_definition?(value, definition) do
      :ok
    else
      {:error,
       [Diagnostic.simple("LP_SCHEMA_DEFAULT", "Default for #{name} does not match #{type}")]}
    end
  end

  defp validate_default(_, _), do: :ok

  defp validate_description(name, %{"description" => description}) when is_binary(description) do
    if byte_size(description) <= Contract.get()["limits"]["scalar_bytes"] do
      :ok
    else
      {:error,
       [Diagnostic.simple("LP_SCHEMA_DESCRIPTION", "Description for #{name} is too large")]}
    end
  end

  defp validate_description(name, %{"description" => _}) do
    {:error,
     [Diagnostic.simple("LP_SCHEMA_DESCRIPTION", "Description for #{name} must be a string")]}
  end

  defp validate_description(_, _), do: :ok

  defp normalize_shape(name, %{"type" => "object"} = definition, depth) do
    with :ok <- validate_shape_field(name, definition, "items"),
         :ok <- validate_schema_depth(name, depth),
         {:ok, properties} <- normalize_properties(name, definition["properties"], depth) do
      normalized =
        definition
        |> Map.delete("items")
        |> Map.put("properties", properties)

      {:ok, normalized}
    end
  end

  defp normalize_shape(name, %{"type" => "list"} = definition, depth) do
    with :ok <- validate_shape_field(name, definition, "properties"),
         :ok <- validate_schema_depth(name, depth),
         {:ok, items} <- normalize_nested_definition("#{name}[]", definition["items"], depth + 1) do
      normalized =
        definition
        |> Map.delete("properties")
        |> Map.put("items", items)

      {:ok, normalized}
    end
  end

  defp normalize_shape(name, definition, _) do
    if Map.has_key?(definition, "items") or Map.has_key?(definition, "properties") do
      {:error,
       [
         Diagnostic.simple(
           "LP_SCHEMA_SHAPE",
           "items and properties are only valid for collection variable #{name}"
         )
       ]}
    else
      {:ok, definition}
    end
  end

  defp normalize_properties(name, properties, depth)
       when is_map(properties) and not is_struct(properties) do
    properties
    |> Enum.sort_by(fn {key, _} -> to_string(key) end)
    |> Enum.reduce_while({:ok, %{}}, fn {key, definition}, {:ok, acc} ->
      key = to_string(key)

      with true <- Regex.match?(@segment_regex, key),
           {:ok, normalized} <-
             normalize_nested_definition("#{name}.#{key}", definition, depth + 1) do
        {:cont, {:ok, Map.put(acc, key, normalized)}}
      else
        false ->
          {:halt,
           {:error,
            [Diagnostic.simple("LP_SCHEMA_NAME", "Invalid nested property #{name}.#{key}")]}}

        {:error, diagnostics} ->
          {:halt, {:error, diagnostics}}
      end
    end)
  end

  defp normalize_properties(name, _, _) do
    {:error,
     [Diagnostic.simple("LP_SCHEMA_PROPERTIES", "Object variable #{name} needs properties")]}
  end

  defp validate_shape_field(name, definition, field) do
    if Map.has_key?(definition, field),
      do: {:error, [Diagnostic.simple("LP_SCHEMA_SHAPE", "#{field} is invalid for #{name}")]},
      else: :ok
  end

  defp normalize_nested_definition(name, definition, depth)
       when is_map(definition) and not is_struct(definition) do
    unknown = Map.keys(definition) -- @nested_fields
    type = definition["type"]

    cond do
      unknown != [] ->
        {:error,
         [
           Diagnostic.simple(
             "LP_SCHEMA_FIELD",
             "Unknown nested fields for #{name}: #{Enum.join(unknown, ", ")}"
           )
         ]}

      type not in Contract.get()["types"] ->
        {:error, [Diagnostic.simple("LP_SCHEMA_TYPE", "Invalid type for #{name}")]}

      not is_boolean(Map.get(definition, "required", true)) ->
        {:error,
         [Diagnostic.simple("LP_SCHEMA_REQUIRED", "required must be boolean for #{name}")]}

      not is_boolean(Map.get(definition, "sensitive", false)) ->
        {:error,
         [Diagnostic.simple("LP_SCHEMA_SENSITIVE", "sensitive must be boolean for #{name}")]}

      true ->
        normalized =
          definition
          |> Map.put_new("required", true)
          |> Map.put_new("sensitive", false)

        with :ok <- validate_description(name, normalized),
             {:ok, normalized} <- normalize_shape(name, normalized, depth),
             :ok <- validate_default(name, normalized) do
          {:ok, normalized}
        end
    end
  end

  defp normalize_nested_definition(name, _, _) do
    {:error,
     [Diagnostic.simple("LP_SCHEMA_DEFINITION", "Definition for #{name} must be an object")]}
  end

  defp validate_schema_depth(name, depth) do
    if depth <= Contract.get()["limits"]["input_depth"] do
      :ok
    else
      {:error, [Diagnostic.simple("LP_SCHEMA_DEPTH", "Schema for #{name} is too deep")]}
    end
  end

  @doc false
  @spec value_matches_type?(term(), String.t()) :: boolean()
  def value_matches_type?(value, "string"), do: is_binary(value)
  def value_matches_type?(value, "integer"), do: is_integer(value)
  def value_matches_type?(value, "number"), do: is_number(value)
  def value_matches_type?(value, "boolean"), do: is_boolean(value)

  def value_matches_type?(value, "date"),
    do: is_binary(value) and match?({:ok, _}, Date.from_iso8601(value))

  def value_matches_type?(value, "datetime") do
    is_binary(value) and match?({:ok, _, _}, DateTime.from_iso8601(value))
  end

  def value_matches_type?(value, "url"), do: Letterpress.URL.safe?(value)

  def value_matches_type?(value, "email") when is_binary(value),
    do: Regex.match?(~r/\A[^\s@]+@[^\s@]+\.[^\s@]+\z/u, value)

  def value_matches_type?(_, "email"), do: false

  def value_matches_type?(value, "phone") when is_binary(value),
    do: Regex.match?(~r/\A\+[1-9][0-9]{7,14}\z/, value)

  def value_matches_type?(_, "phone"), do: false
  def value_matches_type?(value, "object"), do: is_map(value) and not is_struct(value)
  def value_matches_type?(value, "list"), do: is_list(value)
  def value_matches_type?(_, _), do: false

  @doc false
  @spec value_matches_definition?(term(), map()) :: boolean()
  def value_matches_definition?(value, %{"type" => "object", "properties" => properties})
      when is_map(value) and not is_struct(value) and is_map(properties) do
    case JSON.normalize_object(value) do
      {:ok, value} -> valid_object_properties?(value, properties)
      {:error, _} -> false
    end
  end

  def value_matches_definition?(value, %{"type" => "list", "items" => items})
      when is_list(value) and is_map(items),
      do: Enum.all?(value, &value_matches_definition?(&1, items))

  def value_matches_definition?(value, %{"type" => type}),
    do: value_matches_type?(value, type)

  def value_matches_definition?(_, _), do: false

  defp valid_object_properties?(value, properties) do
    Map.keys(value) -- Map.keys(properties) == [] and
      Enum.all?(properties, fn {name, definition} ->
        valid_property?(value[name], definition)
      end)
  end

  defp valid_property?(nil, %{"required" => true} = definition),
    do: Map.has_key?(definition, "default")

  defp valid_property?(nil, _), do: true
  defp valid_property?(value, definition), do: value_matches_definition?(value, definition)
end
