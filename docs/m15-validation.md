# M1.5: correctness, memory instrumentation, and benchmark comparison

Scope: **zig-data-engine only**. No CSV Reader changes and no API changes to
`scan.Matcher`, `transfer.copy`, or the original `memory.Pool` path.

## Why

M1 is a baseline, not a proof of speedups. On the reported x86-64 host,
`std.mem.count` was faster than all custom counters. A correct algorithm over
memory is not a disk throughput benchmark. M1.5 adds evidence collection
before introducing more SIMD, allocators, or formats.

## Validate

```sh
zig version # expected 0.17.1
zig build test
zig build test -Doptimize=ReleaseSafe
zig build bench -Doptimize=ReleaseFast -- --iterations 30 --warmup 5 --size-mib 32
python3 -m unittest discover -s tests -v
```

The existing `zig build bench ... -- --csv` still emits aggregate summaries.
For statistical comparisons, save **individual timed samples**:

```sh
zig build bench -Doptimize=ReleaseFast -- \
  --samples --iterations 30 --warmup 5 --size-mib 32 \
  2> baseline.csv
# After editing the code, with the same compiler, CPU, build mode and input:
zig build bench -Doptimize=ReleaseFast -- \
  --samples --iterations 30 --warmup 5 --size-mib 32 \
  2> candidate.csv
python3 tools/bench_compare.py baseline.csv candidate.csv \
  --bootstrap 5000 --confidence 0.95 --min-effect-pct 3
```

`--samples` is mutually exclusive with `--csv`. Times are in *nanoseconds*;
individual rows have columns `case,bytes,iteration,ns,checksum`. The stdout
of `bench_compare.py` is a summary CSV. The command rejects mismatched cases,
data sizes, checksums and iteration counts, and demands at least 10 samples.

The comparator resamples individual observations from each run to estimate a
percentile-bootstrap 95% confidence interval for the **relative change in
median**. Negative is faster. It reports `faster` if the *upper* interval bound
is below `-min-effect-pct`, `slower` if the *lower* bound is above
`+min-effect-pct`, otherwise `inconclusive`. This is **screening**, not a
statistical guarantee: samples within one run can be correlated, CPU frequency
and thermal effects can drift, and the harness currently tests cases in fixed
order. Repeat at the **process** level, alternating baseline and candidate.
Avoid running other significant loads during the tests. Never interpret a
non-significant result as proof of equivalence.

## Fragmentation and allocation safety

- Exhaustive KMP tests enumerate all 256 split patterns for a 9-byte input,
  including empty chunks, overlaps and no matches.
- Additional seeded splits exercise boundaries in a 4096-byte buffer.
- Differential tests compare matching offsets with an independent
  `std.mem.indexOf`-based oracle.
- `checkAllAllocationFailures` injects failures into KMP construction;
  every partial allocation must be cleaned up.
- A small `testing/smith.zig` helper uses fixed-width `u32` bounds to avoid
  Zig 0.17's error when fuzzing with `usize`.

For extended fuzzing (depends on Zig 0.17.1's fuzz mode):

```sh
zig build test -Doptimize=ReleaseSafe -- --fuzz
```

If your build runner does not forward `--fuzz`, run the root test module with
`zig test src/root.zig -O ReleaseSafe --fuzz`.

## CountingAllocator (opt-in)

The new `zdata.memory.CountingAllocator` wraps a caller-supplied
`std.mem.Allocator`. It never becomes the default allocator.

```zig
var meter = zdata.memory.CountingAllocator.init(std.testing.allocator);
const alloc = meter.allocator();
var matcher = try zdata.scan.Matcher.init(alloc, "abab");
// ... process some chunks ...
matcher.deinit();
std.debug.assert(meter.stats.live_bytes == 0);
std.debug.print("peak={d} requested={d} allocs={d}\n", .{
    meter.stats.peak_bytes,
    meter.stats.total_requested_bytes,
    meter.stats.alloc_calls,
});
```

`peak_bytes` is peak **requested live bytes visible to the wrapper**, not RSS,
actual backing pages, allocator bookkeeping, or a measurement of CPU caches.
`total_requested_bytes` includes successful requested allocations and growth;
failed allocation counts do not include every rejected in-place resize.
`CountingAllocator` is **not thread safe**; the instance must outlive all
allocations. After an Arena `reset`, the wrapper cannot infer reclaimed
suballocations if the arena is inside it; wrap the backing allocator in the
correct position depending on the metric desired.

## Not implemented in this milestone

No new data structures, custom general-purpose allocator, staged CSV parser,
Arrow bindings, live file I/O profiling, `perf` dependency, or artificial
performance claims. A deterministic short-read/error-injecting `std.Io.Reader`
is a later test task; ordinary partial-size testing already exists in M0.
