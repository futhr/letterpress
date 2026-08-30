[
  parallel: true,
  tools: [
    {:compiler, command: "mix compile --warnings-as-errors --force"},
    {:formatter, command: "mix format --check-formatted"},
    {:credo, command: "mix credo --strict"},
    {:doctor, command: "mix doctor"},
    {:ex_doc, command: "mix docs --warnings-as-errors"},
    {:unused_deps, command: "mix deps.unlock --check-unused"},
    {:hex_audit, command: "mix hex.audit"},
    {:mix_audit, command: "mix deps.audit"},
    {:dialyzer, true},
    {:ex_unit, false},
    {:coveralls, command: "env MIX_ENV=test mix coveralls.lcov"},
    {:pnpm_install, command: "pnpm install --frozen-lockfile"},
    {:frontend_lint, command: "pnpm lint", deps: [:pnpm_install]},
    {:frontend_typecheck, command: "pnpm typecheck", deps: [:pnpm_install]},
    {:frontend_test, command: "pnpm test", deps: [:pnpm_install]},
    {:package_exports, command: "pnpm check:exports", deps: [:pnpm_install]},
    {:conformance, command: "pnpm check:conformance", deps: [:pnpm_install]},
    {:boundary, command: "node scripts/check-boundary.mjs"},
    {:release_tests, command: "pnpm test:release", deps: [:pnpm_install]},
    {:release_contract, command: "pnpm check:release", deps: [:pnpm_install]}
  ]
]
