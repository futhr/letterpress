defmodule Letterpress.Compiler do
  @moduledoc """
  Routes authoring requests to a caller-owned compiler pool.

  Start `Letterpress.Compiler.Supervisor` in the host application's supervision
  tree before calling authoring functions. The framed protocol and worker
  lifecycle remain private; callers receive tagged errors and never observe
  port messages or worker process identities.
  """

  alias Letterpress.Compiler.Worker

  @typedoc "An operation implemented by the bundled compiler protocol."
  @type operation ::
          :discover | :analyze | :compile | :format | :apply_translations | :contract

  @default_pool Letterpress.Compiler.Pool
  @default_timeout 15_000

  @doc """
  Returns whether `:pool` has at least one registered compiler worker.

  The default pool is `#{inspect(@default_pool)}`.
  """
  @spec available?(keyword()) :: boolean()
  def available?(opts \\ []), do: available_indices(pool_name(opts)) != []

  @doc """
  Executes a bounded operation in a compiler pool.

  ## Options

    * `:pool` - registered compiler pool; defaults to
      `#{inspect(@default_pool)}`
    * `:timeout` - request deadline in milliseconds; defaults to
      `#{@default_timeout}`

  Most consumers should call the facade functions in `Letterpress`.
  """
  @spec request(operation(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def request(operation, payload, opts \\ []) when is_atom(operation) and is_map(payload) do
    pool = pool_name(opts)

    case available_indices(pool) do
      [] ->
        {:error, :compiler_unavailable}

      indices ->
        offset = :erlang.phash2({self(), System.unique_integer([:positive])}, length(indices))
        index = Enum.at(indices, offset)
        timeout = Keyword.get(opts, :timeout, @default_timeout)
        Worker.request(pool, index, operation, payload, timeout)
    end
  end

  @doc """
  Returns `:ready` when `:pool` has a worker, otherwise `:unavailable`.

  This is suitable for authoring-node readiness checks. Delivery-only nodes do
  not need a compiler pool and should not include it in their readiness policy.
  """
  @spec status(keyword()) :: :unavailable | :ready
  def status(opts \\ []), do: if(available?(opts), do: :ready, else: :unavailable)

  defp pool_name(opts), do: Keyword.get(opts, :pool, @default_pool)

  defp available_indices(pool) do
    if Process.whereis(pool) do
      Registry.select(pool, [{{:"$1", :_, :_}, [{:is_integer, :"$1"}], [:"$1"]}])
    else
      []
    end
  end
end
