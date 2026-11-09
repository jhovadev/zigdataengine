# Contributing to Zig Data Engine

Thanks for considering a contribution. ZData is experimental and intentionally
small: favor a correct, documented primitive over an unmeasured optimization.

## Local setup

- Use **Zig 0.17.1** (the version in `build.zig.zon`).
- Python 3 is needed only for developer scripts and tests.
- `mpmath` is optional for independently checking high-precision fixtures.

```sh
zig build test
zig build test -Doptimize=ReleaseSafe
zig build math-accuracy -Doptimize=ReleaseSafe
python3 -m unittest discover -s tests -v
uv run --with mpmath python -m unittest discover -s tests -v
python3 tools/repo_audit.py --strict
```

Before opening a PR, run `zig fmt build.zig src bench examples` and review the
diff. Avoid formatting generated golden vectors manually: regenerate them with
the corresponding script and verify byte-for-byte reproduction.

## Design rules

1. Keep the public core format-agnostic; format-specific logic belongs in an
   adapter, not in `bits`, `math`, `memory`, or `scan`.
2. Preserve explicit ownership, bounds, and allocator contracts. Never silently
   add global state, hidden threads, or runtime dependencies.
3. Add deterministic tests, boundary cases, and differential tests against a
   simple reference. Streaming algorithms must be checked under varying chunk
   boundaries.
4. Name the comparison baseline before proposing a faster replacement.
   Benchmark multiple independent runs and disclose CPU, Zig version,
   dataset and statistical uncertainty.
5. Numerical changes need an accuracy budget: absolute/relative/ULP error and
   treatment of NaN, infinities, signed zero and subnormal values.
6. Do not promise performance or bitwise reproducibility across architectures
   without tests on those targets.

## Submitting changes

Keep PRs focused; explain the API, correctness cases, compatibility impact, and
benchmark evidence when performance is relevant. Prefer small incremental
changes over broad refactors. New public interfaces may change during the
`0.x` series; describe breaking changes explicitly.

CI checks Zig correctness, numerical accuracy, Python developer tests and
repository hygiene. Performance benchmarks run as smoke tests in CI; they are
**not** used as fixed-speed gates on shared runners.
