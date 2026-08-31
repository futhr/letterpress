# Documentation map

Letterpress documentation is split by authority and lifecycle.

| Location | Purpose | Can define public behavior? |
|---|---|---|
| `docs/research/` | External evidence, alternatives, and bounded conclusions | No |
| `docs/adr/` | Durable architecture choices and rejected alternatives | No |
| `docs/specs/` | Versioned, normative package and wire contracts | Yes |
| `docs/guides/` | Explanations and runnable usage paths | No |
| `notebooks/` | Executable Livebook tutorials published in HexDocs | No |
| `conformance/` | Cross-runtime fixtures that execute contract claims | Verifies only |
| `bench/` | Reproducible performance scenarios and recorded results | No |

The distinction prevents evidence, rationale, examples, and measured output
from becoming accidental API promises. A public behavior change starts in
`docs/specs/LP.01-letterpress-contract.md`; the code, generated browser
contract, conformance fixtures, and guides follow it.

An ADR is justified only when it explains a durable choice that the spec should
not repeat, including alternatives and conditions that would reopen the
decision. Research is justified only when external evidence affects a choice.
Delete or merge documents that merely restate another authority.

## Current entry points

- [Platform analysis](research/R.01-platform-analysis.md)
- [Elixir library posture](research/R.02-library-posture.md)
- [Backend authority](adr/ADR.001-backend-authority.md)
- [Host boundary](adr/ADR.002-host-boundary.md)
- [Caller-owned supervision](adr/ADR.003-caller-owned-supervision.md)
- [Letterpress contract](specs/LP.01-letterpress-contract.md)
- [Quick start](guides/quickstart.md)
- [Compiler and runtime](guides/compiler-and-runtime.md)
- [Browser editor](guides/browser-editor.md)
- [Consumer adoption](guides/consumer-adoption.md)
- [Troubleshooting](guides/troubleshooting.md)
- [Conformance corpus](../conformance/README.md)
- [Benchmarks](../bench/output/benchmarks.md)
