# M1.7 validation + math primitive preview (M1.8 groundwork)

This phase keeps the existing `scan` / `memory` / `compute` / `transfer`
interfaces unchanged and adds a separately importable `zdata.math` package.
It is **not** a numeric library replacing `std.math` or a claim to be faster
than it.

## Commands

```bash
zig build test
zig build test -Doptimize=ReleaseSafe
python3 -m unittest discover -s tests -v
zig build math-audit
zig build bench -Doptimize=ReleaseFast -- \
  --samples --iterations 30 --warmup 5 --size-mib 32 \
  2> m17-baseline.csv
python3 tools/bench_manifest.py m17-baseline.csv --out m17-baseline.meta.json
```

`bench/main.zig` gains `zdata.structural.scalar/newline` against the matching
`std.mem.count` count. Both use precisely the same 32 MiB input. It also now
preserves the chronological order of **raw** benchmark samples (previously
statistics sorting changed the order of `--samples`). It has not introduced
any SIMD-specific structural kernel or parallelism.

Only compare equal `--samples` case sets with `bench_compare.py`. The added
case makes M1.7 samples intentionally incompatible with a full set from M1.5.
Retain the previous file as historical evidence and create a **new baseline**.
The metadata JSON includes a SHA-256 of its corresponding samples file, the
host CPU model, OS, architecture, Zig version, and an **honest** kernel label
for every named operation. std/LLVM kernel selection is not introspected;
`zdata.vector16/vector32` are compile-time vector widths, not runtime CPU
dispatch. A compiled generic binary does not automatically detect AVX2.

## Accuracy gates

`math/reference_test.zig` uses an independent *f128 two-pass* reference to
check Welford/Chan mean/variance on offset-heavy data, and compares a
compensated sum with a higher-precision f128 sum. This is more precise than a
f64 naive variance but **is not arbitrary precision**. The math-specific
scalar tests cover +/-1000, zero, NaN, infinity, in-place softmax and
validation/no-partial-write guarantees. `ulpDistance()` returns `null` on NaN.

Before accepting any approximate vector math kernel we will add a high-
precision external reference (e.g. Python mpmath), an x86-64/ARM64 matrix,
structured and random extremes, and document the maximum ULP discrepancy.
No claim of a ULP-bound, bitwise reproducibility across different CPUs, or
performance gain is made for the new scalar helpers.

## Public math API

```zig
const zde = @import("zdata");
const p = zde.math.sigmoid(-1000.0);
const s = zde.math.softplus(1000.0);
const lse = try zde.math.logSumExp(&.{ 1000.0, 1001.0 });
var pvec: [2]f64 = undefined;
try zde.math.softmax(&.{ 1000.0, 1001.0 }, &pvec);
const steps = zde.math.ulpDistance(@as(f64, 1), @as(f64, 1.0));
const close = zde.math.almostEqual(1.0, 1.00001, 0.0, 1e-4);
_ = .{ p, s, lse, steps, close };
```

`zdata.math.audit.inspect()` uses `@hasDecl` to report the Zig version's
actual `std.math` symbols for complex, big, gamma, lgamma, erf, erfc,
log1p, expm1 and nextAfter. Audit the target compiler rather than assuming a
commit from a different Zig version. Missing mathematical special functions
should only be added following precision/maintenance analysis.

## Future gates

- M1.7: add true target/OS CI and fixed-parameter independent samples runs.
- M1.8: optional external mpmath golden corpus and latency/ULP dashboards.
- M2+: only optimize streaming structural classification if it beats a named
  baseline on representative record densities and remains chunk-correct.
- Parallel executor, dispatch, C ABI and Arrow are *not* implemented here.
