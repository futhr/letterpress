defmodule Letterpress.Renderer.ForTag do
  @moduledoc """
  The bounded `for` tag used by the Letterpress Liquid renderer.

  Parsing delegates to Solid's pinned grammar. Rendering preserves Liquid loop
  variables, `limit`, `offset`, `reversed`, `break`, `continue`, and `else`
  behavior while charging every nested iteration to one process-local budget.

  This is an implementation module installed by `Letterpress.Renderer`.
  Template authors use the ordinary Liquid `{% for %}` syntax.
  """

  @behaviour Solid.Tag

  import Solid.NumberHelper, only: [to_integer: 1]

  alias Solid.{Argument, Variable}
  alias Solid.Tags.ForTag, as: SolidForTag

  @typedoc "Parsed state for one bounded Liquid `for` tag."
  @type t :: %__MODULE__{
          loc: Solid.Parser.Loc.t(),
          enumerable: Argument.t(),
          variable: Variable.t(),
          reversed: boolean(),
          parameters: map(),
          body: list(),
          else_body: list()
        }

  @enforce_keys [:loc, :enumerable, :variable, :reversed, :parameters, :body, :else_body]
  defstruct [:loc, :enumerable, :variable, :reversed, :parameters, :body, :else_body]

  @doc false
  @impl Solid.Tag
  def parse("for", loc, context) do
    case SolidForTag.parse("for", loc, context) do
      {:ok, tag, context} -> {:ok, struct!(__MODULE__, Map.from_struct(tag)), context}
      error -> error
    end
  end

  defimpl Solid.Renderable do
    @impl Solid.Renderable
    @spec render(Letterpress.Renderer.ForTag.t(), term(), keyword()) :: term()
    def render(tag, context, options) do
      for_name = "#{tag.variable.identifier}-#{tag.enumerable}"

      with {:ok, enumerable, context} <- enumerable(tag.enumerable, context, options),
           {:ok, enumerable, context} <-
             apply_parameters(enumerable, tag, for_name, context, options) do
        do_for(enumerable, tag, for_name, context, options)
      else
        {:error, message, context} ->
          exception = %Solid.ArgumentError{loc: tag.loc, message: message}
          context = Solid.Context.put_errors(context, exception)
          {Exception.message(exception), context}
      end
    end

    defp do_for([], tag, _, context, _), do: {tag.else_body, context}

    defp do_for(enumerable, tag, for_name, context, options) do
      length = Enum.count(enumerable)
      enumerable_key = tag.variable.identifier
      parent_iteration_vars = context.iteration_vars
      parent_forloop = parent_iteration_vars["forloop"]

      try do
        {result, context} =
          enumerable
          |> Enum.with_index()
          |> Enum.reduce({[], context}, fn {value, index}, {acc_result, acc_context} ->
            consume_iteration!()

            acc_context =
              acc_context
              |> set_enumerable_value(enumerable_key, value)
              |> maybe_put_forloop_map(
                for_name,
                enumerable_key,
                {index, length, parent_forloop}
              )

            try do
              {result, acc_context} = Solid.render(tag.body, acc_context, options)
              {[result | acc_result], acc_context}
            catch
              {:break_exp, result, caught_context} ->
                throw({:result, [result | acc_result], caught_context})

              {:continue_exp, result, caught_context} ->
                {[result | acc_result], caught_context}
            end
          end)

        context = %{context | iteration_vars: parent_iteration_vars}
        {Enum.reverse(result), context}
      catch
        {:result, result, caught_context} ->
          context = %{caught_context | iteration_vars: parent_iteration_vars}
          {Enum.reverse(result), context}
      end
    end

    defp consume_iteration! do
      used = Process.get(:letterpress_loop_iterations, 0)
      limit = Process.get(:letterpress_loop_limit, 0)

      if used >= limit do
        throw(:letterpress_loop_limit)
      else
        Process.put(:letterpress_loop_iterations, used + 1)
      end
    end

    defp set_enumerable_value(context, key, value) do
      %{context | iteration_vars: Map.put(context.iteration_vars, key, value)}
    end

    defp maybe_put_forloop_map(context, for_name, key, {index, length, parent_forloop})
         when key != "forloop" do
      forloop = %{
        "index" => index + 1,
        "index0" => index,
        "rindex" => length - index,
        "rindex0" => length - index - 1,
        "first" => index == 0,
        "last" => length == index + 1,
        "length" => length,
        "parentloop" => parent_forloop,
        "name" => for_name
      }

      %{context | iteration_vars: Map.put(context.iteration_vars, "forloop", forloop)}
    end

    defp maybe_put_forloop_map(context, _, _, _),
      do: context

    defp enumerable(argument, context, options) do
      {:ok, value, context} = Argument.get(argument, context, [], options)
      value = value || []

      case value do
        value when is_list(value) or (is_map(value) and not is_struct(value)) ->
          {:ok, value, context}

        %Range{first: first, last: last} when first <= last ->
          {:ok, first..last, context}

        %Range{} ->
          {:ok, [], context}

        other ->
          {:ok, [other], context}
      end
    end

    defp apply_parameters(enumerable, tag, for_name, context, options) do
      with {:ok, start, context} <- offset(tag, for_name, context, options),
           {:ok, finish, context} <- limit(enumerable, tag, context, options) do
        enumerable = Enum.slice(enumerable, start, finish)
        next_offset = max(start, 0) + Enum.count(enumerable)
        context = %{context | registers: Map.put(context.registers, for_name, next_offset)}
        {:ok, apply_reversed(enumerable, tag), context}
      end
    end

    defp offset(tag, for_name, context, options) do
      case tag.parameters[:offset] do
        %Variable{identifier: "continue", accesses: []} ->
          {:ok, context.registers[for_name] || 0, context}

        nil ->
          {:ok, 0, context}

        argument ->
          {:ok, value, context} = Argument.get(argument, context, [], options)

          case to_integer(value) do
            {:ok, value} -> {:ok, value, context}
            {:error, message} -> {:error, message, context}
          end
      end
    end

    defp limit(enumerable, tag, context, options) do
      if argument = tag.parameters[:limit] do
        {:ok, value, context} = Argument.get(argument, context, [], options)

        case to_integer(value) do
          {:ok, value} -> {:ok, max(value, 0), context}
          {:error, message} -> {:error, message, context}
        end
      else
        {:ok, Enum.count(enumerable), context}
      end
    end

    defp apply_reversed(enumerable, %{reversed: true}), do: Enum.reverse(enumerable)
    defp apply_reversed(enumerable, _), do: enumerable
  end
end
