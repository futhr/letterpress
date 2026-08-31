# Benchmarks

The suite measures Letterpress-owned boundaries:

- pure-BEAM text and email rendering;
- bounded Liquid iteration;
- canonical artifact encoding and verified decoding;
- text-profile analysis/compilation through the worker;
- MJML email compilation through the worker.

Run the stable local suite:

```bash
mix bench
```

Run a short harness and documentation check:

```bash
mix bench.smoke
```

Both commands write `bench/output/benchmarks.md`. The checked-in report names
its run mode and machine. Smoke values prove that scenarios execute and the
formatter works; they are not performance baselines. Compare stable runs only
on controlled hardware with matching Elixir, OTP, Node, and dependency
versions.
