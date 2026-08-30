defmodule Letterpress.Compiler do
  @moduledoc """
  Routes authoring requests to the supervised bundled Node worker pool.

  The framed protocol and worker lifecycle are private. Public callers receive
  tagged errors and never observe port messages or worker process identities.
  """

  alias Letterpress.Compiler.Worker

  @type operation :: :analyze | :compile | :format | :apply_translations | :contract

  @doc "Returns whether at least one compiler worker is available."
  @spec available?() :: boolean()
  def available?, do: available_indices() != []

  @doc "Executes a bounded compiler operation."
  @spec request(operation(), map()) :: {:ok, map()} | {:error, term()}
  def request(operation, payload) when is_atom(operation) and is_map(payload) do
    case available_indices() do
      [] ->
        {:error, if(compiler_enabled?(), do: :compiler_unavailable, else: :compiler_disabled)}

      indices ->
        offset = :erlang.phash2({self(), System.unique_integer([:positive])}, length(indices))
        index = Enum.at(indices, offset)
        timeout = Application.get_env(:letterpress, :compiler_timeout, 15_000)
        Worker.request(index, operation, payload, timeout)
    end
  end

  @doc "Returns a stable compiler status suitable for readiness checks."
  @spec status() :: :disabled | :unavailable | :ready
  def status do
    cond do
      not compiler_enabled?() -> :disabled
      available?() -> :ready
      true -> :unavailable
    end
  end

  defp compiler_enabled?, do: Application.get_env(:letterpress, :compiler_enabled, true)
  defp worker_count, do: max(Application.get_env(:letterpress, :compiler_pool_size, 2), 1)

  defp available_indices do
    if Process.whereis(Letterpress.Compiler.Registry) do
      Enum.filter(0..(worker_count() - 1), fn index ->
        Registry.lookup(Letterpress.Compiler.Registry, index) != []
      end)
    else
      []
    end
  end
end
