# M1 — Comparative performance methodology

M1 intentionally changes **no existing public M0 API signatures**. It adds
`scan.countByteVector(comptime lanes, ...)` and `Matcher.feedCount(...)` as
opt-in primitives. The old std-backed `scan.countByte` remains the default.

## Run

```sh
zig build test
zig build test -Doptimize=ReleaseSafe
zig build bench -Doptimize=ReleaseFast -- --iterations 30 --warmup 5 --size-mib 32
zig build bench -Doptimize=ReleaseFast -- --iterations 30 --warmup 5 --csv 2> m1-results.csv
```

Repeat the full benchmark three times and retain each CSV. The benchmark writes
through `std.debug.print` (stderr); use `2>` for CSV capture. Do not compare
results captured in `Debug` with `ReleaseFast`.

Flags: `--iterations` (1–200), `--warmup` (0–50), `--size-mib` (1–256), `--csv`.
Default: 30 repetitions, 5 warmups, 32 MiB.

CSV schema: `case,bytes,iterations,warmup,min_ns,median_ns,p95_ns,max_ns,mib_per_s,checksum`.
The median is the middle sorted sample (arithmetic average for even sample
counts). p95 uses nearest-rank `ceil(0.95*N)`. Throughput is input bytes per
median elapsed time, **not** end-to-end application throughput.

## What is measured

- Byte counting: `std.mem.count`, `zdata.scan.countByte`, experimental
  vector 16/32. All count the same `\n` byte; there is no allocation in the
  measured scan and results are checked for equivalence.
- Pattern counting: `std.mem.indexOf` with overlapping matches vs KMP's new
  allocation-free `feedCount` across 256 KiB chunks. The streaming variant
  does more chunk bookkeeping and is useful when the input is genuinely split.
- Transfer: manual copy using `std.Io.Reader`/`Writer` vs `zdata.transfer.copy`
  with **identical fixed memory endpoints and scratch sizes** (4/64/256/1024
  KiB). All bytes are checked after timing. This does not measure disk/network
  throughput, syscalls, `sendfile`, write durability or actual OS backpressure.

The benchmark allocates input, output and a 1 MiB scratch buffer once before
sampling; it measures operation latency, **not** peak RSS or allocations made
by the OS. Current fixed buffer allocation is `2 * dataset MiB + 1 MiB` plus
minor metadata and matcher state. A future M2 stage may add a separately
calibrated counting allocator / real filesystem benchmark.

## Correctness before speed

`zig build test` includes stats, CLI options, vector/scalar differential tests,
KMP offset/count consistency, transfer scratch sizes and the original M0 tests.
`zig test src/scan/bytes.zig --fuzz` can exercise the Smith-based fuzz target
where supported by Zig 0.17.1.

Checks guard against wrong counts and corrupted transfers, but cannot detect
all undefined behavior. Run sanitizer/testing profiles and independent corpora
before deploying any new implementation.

## Interpretation

- Zig may lower `@Vector` to scalar instructions on an unsupported target. No
  runtime feature detection, AVX-specific intrinsics or automatic dispatch is
  promised by `countByteVector`.
- `std.mem.count` and `zdata.countByte` use different API surfaces but may
  ultimately share optimized standard-library machinery. Similar numbers are
  not evidence of improvement.
- Run on the same CPU, build mode, machine load and dataset size. Record
  `zig version`, OS/CPU, and each benchmark CSV. A speedup should survive
  repeated runs and change in data distribution.
- Changing one algorithmic variant to become the default requires a
  correctness gate, a meaningful statistically repeatable win, and no severe
  regression on Linux, Windows and arm64 targets.
