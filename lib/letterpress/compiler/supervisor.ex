defmodule Letterpress.Compiler.Supervisor do
  @moduledoc """
  Supervises the compiler registry and isolated Node worker processes.

  A worker protocol failure restarts only that worker. Calls already queued on
  the failed worker receive an explicit unavailable result.
  """

  use Supervisor

  @doc "Starts the configured compiler pool."
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts \\ []), do: Supervisor.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_) do
    count =
      case Application.get_env(:letterpress, :compiler_pool_size, 2) do
        configured when is_integer(configured) and configured > 0 -> configured
        _ -> 1
      end

    children =
      [{Registry, keys: :unique, name: Letterpress.Compiler.Registry}] ++
        Enum.map(0..(count - 1), fn index ->
          Supervisor.child_spec(
            {Letterpress.Compiler.Worker, index: index},
            id: {Letterpress.Compiler.Worker, index}
          )
        end)

    Supervisor.init(children, strategy: :one_for_one)
  end
end
