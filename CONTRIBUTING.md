# Contributing

Letterpress is one Hex package and two coordinated npm packages. Install the
pinned toolchain, then run:

```bash
mix setup
mix check
```

Changes to grammar, profiles, diagnostics, schemas, artifacts, or browser
metadata start in `docs/specs/LP.01-letterpress-contract.md`. Regenerate with
`pnpm build:compiler`; never hand-edit generated contract files.

Add cross-runtime behavior to `conformance/fixtures.json`. Use focused unit
tests for worker supervision, render budgets, and component lifecycle. Public
Elixir modules need docs and specs. Commits use Conventional Commit subjects.

Do not publish packages from a workstation. Follow `RELEASING.md`; one tag
coordinates all three registry artifacts.
