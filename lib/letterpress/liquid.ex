defmodule Letterpress.Liquid do
  @moduledoc false

  alias Letterpress.Contract

  @contexts ~w(text html_text html_attribute url subject none)

  @doc false
  @spec parse(String.t()) :: {:ok, Solid.Template.t()} | {:error, atom()}
  def parse(source) do
    tags =
      Solid.Tag.default_tags()
      |> Map.take(Contract.get()["liquid"]["tags"])
      |> Map.put("for", Letterpress.Renderer.ForTag)

    case Solid.parse(source, tags: tags) do
      {:ok, template} ->
        if valid_node?(template.parsed_template),
          do: {:ok, template},
          else: {:error, :invalid_artifact_context_filter}

      {:error, _} ->
        {:error, :invalid_artifact_liquid}
    end
  end

  defp valid_node?(%Solid.Object{filters: filters, argument: argument}) do
    case Enum.reverse(filters) do
      [
        %Solid.Filter{
          function: "letterpress_escape",
          positional_arguments: [%Solid.Literal{value: context}],
          named_arguments: named
        }
        | preceding
      ]
      when context in @contexts and map_size(named) == 0 ->
        valid_node?(preceding) and valid_node?(argument)

      _ ->
        false
    end
  end

  defp valid_node?(%Solid.Filter{function: function} = filter) do
    function in Contract.get()["liquid"]["filters"] and
      function != "letterpress_escape" and
      valid_node?(filter.positional_arguments) and valid_node?(filter.named_arguments)
  end

  defp valid_node?(value) when is_struct(value), do: valid_node?(Map.from_struct(value))

  defp valid_node?(value) when is_map(value),
    do: Enum.all?(value, fn {_, item} -> valid_node?(item) end)

  defp valid_node?(value) when is_list(value), do: Enum.all?(value, &valid_node?/1)
  defp valid_node?(value) when is_tuple(value), do: valid_node?(Tuple.to_list(value))
  defp valid_node?(_), do: true
end
