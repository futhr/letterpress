Code.require_file("notebook_outputs.exs", __DIR__)

{:ok, _supervisor} =
  Supervisor.start_link(
    [{Letterpress.Compiler.Supervisor, pool_size: 1}],
    strategy: :one_for_one
  )

for path <- Letterpress.NotebookOutputs.notebook_paths() do
  text = File.read!(path)
  updated = Letterpress.NotebookOutputs.rewrite(text, path)

  if updated == text do
    IO.puts("unchanged  #{Path.relative_to_cwd(path)}")
  else
    File.write!(path, updated)
    IO.puts("rewrote    #{Path.relative_to_cwd(path)}")
  end
end
