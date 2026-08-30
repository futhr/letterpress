defmodule Letterpress.Application do
  @moduledoc """
  Starts the optional authoring compiler and the isolated render-task supervisor.

  Delivery-only applications can disable compiler supervision while retaining
  artifact decoding and pure-BEAM rendering.
  """

  use Application

  @impl true
  def start(_, _) do
    children =
      [{Task.Supervisor, name: Letterpress.RenderSupervisor}]
      |> maybe_add_compiler()

    Supervisor.start_link(children, strategy: :one_for_one, name: Letterpress.Supervisor)
  end

  defp maybe_add_compiler(children) do
    if Application.get_env(:letterpress, :compiler_enabled, true) == true do
      [Letterpress.Compiler.Supervisor | children]
    else
      children
    end
  end
end
