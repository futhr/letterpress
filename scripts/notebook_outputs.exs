defmodule Letterpress.NotebookOutputs do
  @moduledoc false

  @output_marker ~s(<!-- livebook:{"output":true} -->)
  @inspect_opts [pretty: true, width: 98, custom_options: [sort_maps: true]]

  @spec notebook_paths() :: [Path.t()]
  def notebook_paths do
    __DIR__
    |> Path.join("../notebooks/*.livemd")
    |> Path.expand()
    |> Path.wildcard()
    |> Enum.sort()
  end

  @spec expected_pin(String.t()) :: String.t()
  def expected_pin(version) do
    [major, minor | _] = String.split(version, ".")
    ~s({:letterpress, "~> #{major}.#{minor}"})
  end

  @spec tokenize(String.t()) :: [
          {:md, String.t()} | {:code, [String.t()]} | {:output, [String.t()]}
        ]
  def tokenize(text) do
    text
    |> String.split("\n")
    |> do_tokenize([])
  end

  @spec render([tuple()]) :: String.t()
  def render(tokens) do
    Enum.map_join(tokens, "\n", fn
      {:md, line} -> line
      {:code, block} -> Enum.join(["```elixir" | block] ++ ["```"], "\n")
      {:output, block} -> Enum.join([@output_marker, "", "```" | block] ++ ["```"], "\n")
    end)
  end

  @spec setup_source(String.t()) :: String.t() | nil
  def setup_source(text) do
    text
    |> tokenize()
    |> Enum.find_value(fn
      {:code, block} -> Enum.join(block, "\n")
      _ -> nil
    end)
  end

  @spec evaluate(String.t(), Path.t()) ::
          {[tuple()], [{non_neg_integer(), pos_integer(), String.t(), [String.t()]}]}
  def evaluate(text, path) do
    tokens = tokenize(text)

    {pairs, _binding, _cell, _result} =
      tokens
      |> Enum.with_index()
      |> Enum.reduce({[], [], 0, :no_result}, fn {token, index}, state ->
        evaluate_token(token, index, state, path)
      end)

    {tokens, Enum.reverse(pairs)}
  end

  @spec rewrite(String.t(), Path.t()) :: String.t()
  def rewrite(text, path) do
    {tokens, pairs} = evaluate(text, path)

    replacements =
      Map.new(pairs, fn {index, _cell, rendered, _saved} ->
        {index, {:output, String.split(rendered, "\n")}}
      end)

    tokens
    |> Enum.with_index()
    |> Enum.map(fn {token, index} -> Map.get(replacements, index, token) end)
    |> render()
  end

  @spec mismatches(String.t(), Path.t()) :: [{pos_integer(), String.t(), String.t()}]
  def mismatches(text, path) do
    {_tokens, pairs} = evaluate(text, path)

    for {_index, cell, rendered, saved} <- pairs,
        saved_text = Enum.join(saved, "\n"),
        saved_text != rendered do
      {cell, rendered, saved_text}
    end
  end

  defp do_tokenize([], acc), do: Enum.reverse(acc)

  defp do_tokenize(["```elixir" | rest], acc) do
    {block, rest} = take_until_fence(rest, [])
    do_tokenize(rest, [{:code, block} | acc])
  end

  defp do_tokenize([@output_marker, "", "```" | rest], acc) do
    {block, rest} = take_until_fence(rest, [])
    do_tokenize(rest, [{:output, block} | acc])
  end

  defp do_tokenize([line | rest], acc), do: do_tokenize(rest, [{:md, line} | acc])

  defp take_until_fence(["```" | rest], acc), do: {Enum.reverse(acc), rest}
  defp take_until_fence([line | rest], acc), do: take_until_fence(rest, [line | acc])

  defp evaluate_token({:code, _block}, _index, {pairs, binding, 0, _last}, _path) do
    {pairs, binding, 1, :no_result}
  end

  defp evaluate_token({:code, block}, _index, {pairs, binding, cell, _last}, path) do
    {result, binding} = eval_cell(block, binding, path, cell)
    {pairs, binding, cell + 1, result}
  end

  defp evaluate_token({:output, saved}, index, {pairs, binding, cell, last}, _path)
       when last != :no_result do
    rendered = inspect(last, @inspect_opts)
    {[{index, cell, rendered, saved} | pairs], binding, cell, :no_result}
  end

  defp evaluate_token({:output, _}, index, _state, path) do
    raise "#{path}: output block at token #{index} has no evaluated cell"
  end

  defp evaluate_token({:md, _}, _index, state, _path), do: state

  defp eval_cell(block, binding, path, cell) do
    code = Enum.join(block, "\n")

    try do
      Code.eval_string(code, binding, file: "#{path}:cell-#{cell}")
    rescue
      error ->
        reraise(
          "#{Path.basename(path)} cell #{cell} failed: #{Exception.message(error)}\n\n#{code}",
          __STACKTRACE__
        )
    end
  end
end
