ExUnit.start()

children = [{Letterpress.Compiler.Supervisor, pool_size: 1}]

{:ok, _} =
  Supervisor.start_link(children, strategy: :one_for_one, name: Letterpress.TestSupervisor)
