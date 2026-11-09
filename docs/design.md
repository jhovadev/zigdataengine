# Design notes — M0

## Layers

1. Consumers (CLI, CSV Reader, network transport, logs, etc.)
2. `zdata` primitives (memory, scans, transformations, transfers)
3. `compat` adapter to `std.Io` and future platform-specific implementations
4. Zig standard library / OS

Compatibility boundaries do **not** make new std.Io versions binary-compatible or
automatically faster. A change in Zig can require API changes, regression tests,
and benchmarks. Upgrades are deliberate and versioned.

## Contracts

- `Pool` has fixed, nonzero chunk size and count. Not thread-safe. Requires
  single ownership of a `Lease`; deinit must happen after all leases return.
- `Matcher` performs O(m) prefix-table setup and O(n) scanning amortized.
  Overlaps are returned, byte offsets are absolute. Output collection is external.
- `transfer.copy` uses short reads + writeAll, not a platform sendfile optimization.
  Its `max_bytes` is a bound on bytes **copied**, not a full size-validation check.
  On error, destination may be partially written.
- `scan.findByte` delegates to `std.mem.indexOfScalar`; benchmark alternatives
  before attempting new vector instructions.

## Bench methodology

The included `zig build bench` is a correctness-checked exploratory microbenchmark:
32 MiB scan, 32 MiB in-memory copy and chunked KMP. It is **not** a full
performance characterization. For decisions compare `std` baseline on the same
machine and dataset, run warmups and multiple repetitions, report medians and
p95, record mode/CPU/OS, and track memory allocations and peak RSS.

Recommended future CI matrix: Linux x86-64 / ARM64, Windows x86-64, macOS
ARM64, Debug and ReleaseSafe; run ReleaseFast benches outside CI as
observations because shared CI machines vary.

## M1 incremental changes

The experimental 16-/32-byte scan is an explicit opt-in alternative, not the
default. `Matcher.feedCount` shares streaming KMP matching semantics with
`feed`, but returns a bounded count rather than growing an offset list.

`bench/main.zig` now compares equivalent operations against standard-library
implementations and keeps setup outside timed samples. Bench results are not
a claim of superiority over Zig std; see `docs/benchmarks-m1.md`.
