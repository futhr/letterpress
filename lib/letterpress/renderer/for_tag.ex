defmodule Letterpress.Renderer.ForTag do
  @moduledoc """
  Restricted Solid `for` tag with a render-process iteration budget.

  Parsing delegates to Solid's pinned grammar. Rendering preserves Liquid's
  loop semantics while counting every nested iteration against one process-
  local budget, so a small input cannot create unbounded nested work.
  """

  alias Solid.{Argument, Variable}

  import Solid.NumberHelper, only: [to_integer: 1]

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

  @behaviour Solid.Tag

  @doc false
  @impl true
  def parse("for", loc, context) do
    case Solid.Tags.ForTag.parse("for", loc, context) do
      {:ok, tag, context} -> {:ok, struct!(__MODULE__, Map.from_struct(tag)), context}
      error -> error
    end
  end

  defimpl Solid.Renderable do
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
      parent_forloop = context.iteration_vars["forloop"]

      try do
        {result, context} =
          enumerable
          |> Enum.with_index()
          |> Enum.reduce({[], context}, fn {value, index}, {acc_result, acc_context} ->
            consume_iteration!()

            acc_context =
              acc_context
              |> set_enumerable_value(enumerable_key, value)
              |> maybe_put_forloop_map(for_name, enumerable_key, index, length, parent_forloop)

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

        context = cleanup_context(context, enumerable_key, parent_forloop)
        {Enum.reverse(result), context}
      catch
        {:result, result, caught_context} ->
          context = cleanup_context(caught_context, enumerable_key, parent_forloop)
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

    defp cleanup_context(context, enumerable_key, parent_forloop) do
      context = %{context | iteration_vars: Map.delete(context.iteration_vars, enumerable_key)}

      if enumerable_key != "forloop" and parent_forloop != nil do
        %{context | iteration_vars: Map.put(context.iteration_vars, "forloop", parent_forloop)}
      else
        %{context | iteration_vars: Map.delete(context.iteration_vars, "forloop")}
      end
    end

    defp set_enumerable_value(context, key, value) do
      %{context | iteration_vars: Map.put(context.iteration_vars, key, value)}
    end

    defp maybe_put_forloop_map(context, for_name, key, index, length, parent_forloop)
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

    defp maybe_put_forloop_map(context, _, _, _, _, _),
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
        last_offset = start + finish
        context = %{context | registers: Map.put(context.registers, for_name, last_offset + 1)}
        enumerable = Enum.slice(enumerable, start..last_offset//1)
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
          {:ok, value} -> {:ok, value - 1, context}
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
