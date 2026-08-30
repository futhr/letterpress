%{
  configs: [
    %{
      name: "default",
      files: %{included: ["config/", "lib/", "test/"], excluded: [~r"/_build/", ~r"/deps/"]},
      strict: true,
      parse_timeout: 5_000,
      checks: %{
        enabled: [
          {Credo.Check.Consistency.UnusedVariableNames, force: :anonymous},
          {Credo.Check.Warning.UnsafeToAtom, []},
          {Credo.Check.Readability.ModuleDoc, []},
          {Credo.Check.Readability.MaxLineLength, max_length: 120},
          {Credo.Check.Refactor.Nesting, max_nesting: 3},
          {Credo.Check.Warning.Dbg, []},
          {Credo.Check.Warning.IoInspect, []}
        ],
        disabled: []
      }
    }
  ]
}
