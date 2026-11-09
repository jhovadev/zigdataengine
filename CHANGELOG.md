# Changelog

This project is pre-1.0. Version numbers describe development milestones, not
promises of a stable Zig API or ABI.

## [Unreleased]

- Repository publication cleanup: contributor guidance, CI, benchmark-result
  hygiene and a compact quick-start README.

## [0.1.0] — 2026-11-09 (M0–M1.9)

### Primitives

- Streaming byte scanning (including KMP) and bounded I/O copying.
- Format-independent bit masks and structural classification.
- Fixed-capacity buffers, budgeted counting allocator and explicit ownership.
- Incremental moments, covariance/correlation and compensated sums.
- Numerically stable sigmoid, softplus, log-sum-exp and softmax.

### Verification and developer tooling

- Zig correctness, chunk-fragmentation and differential tests.
- Numerical golden vectors generated using 100-digit `mpmath` references.
- Numerical stress corpus and accuracy reporting with ULP/relative error.
- Repeated benchmarks with medians/p95, raw samples, host manifest and
  bootstrap comparison tooling.

See `docs/m15-validation.md` through `docs/m19-numeric-validation.md` for
milestone-level technical details and caveats. No SIMD, parallel-execution,
FFI, or cross-platform speedup guarantee is part of this release.
