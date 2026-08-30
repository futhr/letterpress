# Conformance corpus

The checked-in fixtures under this directory are the portable executable
definition of LP.01. Elixir compiler/runtime tests and npm language/editor tests
must consume the same cases rather than maintaining parallel examples.

Each fixture records a profile, source, schema, compile values, delivery values,
expected diagnostics, expected artifact hashes when deterministic output is
under test, and expected rendered channels. Sensitive payloads and product
vocabulary are forbidden.
