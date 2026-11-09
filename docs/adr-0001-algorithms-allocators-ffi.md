# ADR-0001 (research) — graphs, allocators, and foreign-language consumers

Status: **proposed / not implemented**. Scope: later milestones, not M1 API.

## Non-goal

Do not turn `zdata` into another tabular database/CSV reader. It is a small,
format-neutral, measurable collection of algorithms. `zdata` should not try
to replicate Polars, NumPy, or a general-purpose malloc implementation.

## Graph representations

Benchmark CSR (compressed sparse row): `offsets: []u64` and
`neighbors: []u32`, plus an optional edge-weight buffer. Include overflow,
node-range, monotonic-offset, and edge-index checks at construction time.
Edges can be sorted/compacted using a temporary arena. Start with BFS and
connected components, verify against a simple adjacency-list reference, then
consider weighted shortest paths and dynamic graphs. CSR is excellent for
mostly-static graph traversal but poor for frequent inserts; use separate
mutable builders and immutable snapshots. Keep algorithms independent from I/O.

## Allocators

- **Baseline:** `std.heap.ArenaAllocator` with `reset(.retain_capacity)`,
  `std.heap.FixedBufferAllocator`, `std.heap.smp_allocator`, and `Pool` in M0.
- **Experiment 1:** request-/batch-scoped arena with per-batch budget and
  logging of reserved/committed bytes, high-water usage, allocation counts,
  growth and time to reset. Never let borrowed slices outlive a reset.
- **Experiment 2:** size-class slab for fixed-size objects and optional
  per-thread caches. Use freed-slot poison only in debug tests.
- **Experiment 3:** optional mimalloc/jemalloc interoperability via an adapter;
  do not silently replace the host allocator or mix allocate/free families.
  Compare on multithreaded churn and fragmentation workloads; not just a
  sequential bump-allocator benchmark.

Always accept an `std.mem.Allocator` where appropriate; the application owns
its lifetime. No claim that a custom allocator outperforms Zig's std.

## Cross-language packaging

A versioned C ABI (`include/zdata.h`) would be the lowest common denominator.
Build a shared library for each platform (Linux `.so`, Windows `.dll`, macOS
`.dylib`). Keep ABI signatures restricted to fixed-width integers, pointers,
lengths, and opaque handles; return explicit status codes. Add
`zdata_version()` and allocator-aware `zdata_release_*` functions. Do not
expose Zig slices, enums, errors or `std.mem.Allocator` directly across C.

A Python prototype can use `ctypes` or `cffi`, then an optional CPython
extension for NumPy buffer protocol / Arrow C Data Interface / Arrow PyCapsule.
Keep native memory alive while Python retains a view. Use long vectorized or
batched calls to amortize FFI overhead; avoid Python -> Zig calls per element.
Whether Python releases the GIL depends on the wrapper and callbacks, and must
be tested. Build Python wheels per OS/arch/Python ABI.

Rust and Go may link the same ABI, with language-native wrappers; include
cross-language ownership tests and race/concurrency tests. For Arrow,
prefer existing Arrow C Data / Stream contracts and `nanoarrow` over a custom
format. Zero-copy is conditional on compatible layouts, alignment, lifetime
and mutation rules; serialization between processes remains necessary.

## When can it be faster?

Promising candidates: long byte scans, parsers needing unusual rules, graph
traversal over CSR with efficient layout, byte transformations, bounded I/O,
and Python loops doing millions of small allocations or comparisons. No
assumed win versus NumPy, Polars, DuckDB, SIMDJSON, C/C++ or specialized
kernel syscalls. Compare whole operation (FFI conversion included), peak RSS,
CPU and latency (median/p95) on real datasets.

## Graduation criteria

Every proposal starts as an isolated experiment: correctness reference,
property/fuzz tests, macro/microbenchmark, feature detection where relevant,
public ownership contract, and Windows/Linux/ARM64 build/test. Keep default
`std` implementations unless significant repeatable improvements justify
shipping new variants.

References:
- Zig 0.17.1 documentation: https://ziglang.org/documentation/0.17.1/
- Polars: https://github.com/pola-rs/polars
- Arrow C Data Interface: https://arrow.apache.org/docs/format/CDataInterface.html
- Polars Arrow interoperability: https://docs.pola.rs/user-guide/misc/arrow/
- mimalloc: https://github.com/microsoft/mimalloc
- nanoarrow: https://arrow.apache.org/nanoarrow/
