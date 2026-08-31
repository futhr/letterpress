defmodule Letterpress.Compiler.Supervisor do
  @moduledoc """
  A caller-owned supervisor for a pool of isolated compiler workers.

  Letterpress does not start this supervisor automatically. Add it to the host
  application's supervision tree on nodes that perform authoring work. Nodes
  that only render stored artifacts do not need a compiler pool or Node.

  Each pool has a registered `:pool` name. Pass that name as `:compiler_pool`
  to the functions in `Letterpress` when using a non-default pool.

  ## Example

      children = [
        {Letterpress.Compiler.Supervisor,
         pool: MyApp.LetterpressCompiler,
         pool_size: 2,
         max_frame_bytes: 2_000_000}
      ]

      Supervisor.start_link(children, strategy: :one_for_one)

  A protocol failure restarts only the affected worker. Calls already queued
  on that worker receive an explicit error.
  """

  use Supervisor

  @default_pool Letterpress.Compiler.Pool

  @options NimbleOptions.new!(
             pool: [type: :atom, default: @default_pool],
             pool_size: [type: :pos_integer, default: 2],
             max_frame_bytes: [type: :pos_integer, default: 2_000_000]
           )

  @doc """
  Returns a child specification for a compiler pool.

  ## Options

    * `:pool` - registered pool name; defaults to `#{inspect(@default_pool)}`
    * `:pool_size` - number of compiler workers; defaults to `2`
    * `:max_frame_bytes` - largest accepted response frame; defaults to
      `2_000_000`

  Use a distinct `:pool` for each independently configured instance. The pool
  name is also the child specification ID, so several pools can share one host
  supervisor.
  """
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    opts = NimbleOptions.validate!(opts, @options)

    %{
      id: Keyword.fetch!(opts, :pool),
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor
    }
  end

  @doc """
  Starts a compiler pool linked to the caller.

  Applications normally start the child specification returned by
  `child_spec/1` instead of calling this function directly.
  """
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts \\ []) do
    opts = NimbleOptions.validate!(opts, @options)
    Supervisor.start_link(__MODULE__, opts)
  end

  @impl Supervisor
  def init(opts) do
    pool = Keyword.fetch!(opts, :pool)
    count = Keyword.fetch!(opts, :pool_size)
    max_frame_bytes = Keyword.fetch!(opts, :max_frame_bytes)

    children =
      [{Registry, keys: :unique, name: pool}] ++
        Enum.map(0..(count - 1), fn index ->
          Supervisor.child_spec(
            {Letterpress.Compiler.Worker,
             index: index, pool: pool, max_frame_bytes: max_frame_bytes},
            id: {Letterpress.Compiler.Worker, index}
          )
        end)

    Supervisor.init(children, strategy: :one_for_one)
  end
end
