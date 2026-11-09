# Zig Data Engine (ZData)

**Composable primitives for reliable, memory-conscious data processing in Zig.**

ZData is a format-independent library built for **Zig 0.17.1**. It provides
byte scanning, structural bitmasks, bounded-memory I/O, incremental statistics,
numerically stable math, and explicit memory instrumentation. Import only the
primitives your application needs; ZData does not impose a parser, UI,
database, or execution runtime.

**Status:** `v0.1.0` · M1.9 · **experimental**. No stable Zig API or C ABI is
promised yet. Correctness is tested on Zig 0.17.1; performance claims must be
backed by measurements on the target hardware. No third-party runtime, libc,
network, or UI dependency is required by the library.

## Features

| Public API | Capabilities |
| --- | --- |
| `zdata.scan` | Byte lookup/counting, bounded chunks, streaming KMP, configurable scalar structural scanning |
| `zdata.bits` | 64-bit masks, prefix XOR and mask-to-offset extraction |
| `zdata.memory` | Fixed-capacity buffer pool and budgeted counting allocator |
| `zdata.stats` | Welford/Chan moments, covariance/correlation, compensated and fixed-tree sums |
| `zdata.math` | Stable sigmoid, softplus, log-sum-exp, softmax, and accuracy utilities |
| `zdata.transfer` | Bounded-memory copying over `std.Io.Reader` / `std.Io.Writer` |

`zdata.compute` is also available as an alias for `zdata.stats`. The byte-vector
counter is **experimental**; benchmarking has not established that it beats
`std.mem.count`. Structural scanning is a correctness-first **scalar** kernel,
not a complete CSV/JSON/XML parser.

## Quick start

```sh
zig version             # Expected: 0.17.1
zig build test
zig build test -Doptimize=ReleaseSafe
zig build math-accuracy -Doptimize=ReleaseSafe
```

To use the package from a neighboring Zig project, add a local dependency to
its `build.zig.zon`:

```zig
.dependencies = .{
    .zdata = .{ .path = "../zig-data-engine" },
},
```

Then add the module in the consuming project's `build.zig`:

```zig
const dep = b.dependency("zdata", .{ .target = target, .optimize = optimize });
exe.root_module.addImport("zdata", dep.module("zdata"));
```

An independent numerical primitive (no I/O or memory allocation):

```zig
const zdata = @import("zdata");

var moments: zdata.stats.Moments = .{};
try moments.update(10.0);
try moments.update(20.0);
const mean = moments.average().?; // 15.0
```

A streaming substring matcher that handles matches spanning input chunks:

```zig
const std = @import("std");
const zdata = @import("zdata");

// Inside a function, with a caller-provided allocator:
var matcher = try zdata.scan.Matcher.init(allocator, "ERROR");
defer matcher.deinit();
const first = try matcher.feedCount("ER");    // 0
const second = try matcher.feedCount("ROR!"); // 1
std.debug.assert(first + second == 1);
```

For a complete file-copy example, see `examples/copy_file.zig`. Run it with:

```sh
printf 'hello\n' > input.txt
zig build run -Doptimize=ReleaseFast -- input.txt output.txt
cmp input.txt output.txt
```

The copy example rejects an existing destination; delete `output.txt` before
rerunning. It is a demo, not an atomic/durable copy utility.

## Testing and benchmarking

```sh
# Unit, differential, fuzz-support and numerical tests
zig build test
zig build test -Doptimize=ReleaseSafe

# High-precision regression report (reference vectors are checked into src/)
zig build math-accuracy -Doptimize=ReleaseSafe

# Benchmark summaries: median, p95 and correctness checks
zig build bench -Doptimize=ReleaseFast -- --iterations 30 --warmup 5 --size-mib 32
zig build math-bench -Doptimize=ReleaseFast -- --size 32768 --iterations 30 --warmup 5

# Python developer tools (optional mpmath for re-checking golden vectors)
python3 -m unittest discover -s tests -v
uv run --with mpmath python -m unittest discover -s tests -v
```

To capture comparable raw timings and record the environment:

```sh
zig build math-bench -Doptimize=ReleaseFast -- --samples --size 32768 --iterations 30 --warmup 5 2> m19-numeric-baseline.csv
python3 tools/bench_manifest.py m19-numeric-baseline.csv --out m19-numeric-baseline.meta.json
python3 tools/bench_compare.py m19-numeric-baseline.csv candidate.csv
```

The root-level CSV and metadata outputs are **intentionally gitignored**. The
benchmark manifests identify the CPU and kernel label. The statistical
comparator is an exploratory regression detector, not proof of speedup.
Numerical validation has reported at most 2 ULP in the sigmoid stress corpus
and 112 ULP for some tiny softmax probabilities on the tested x86-64 machine;
these are observed results, not universal error bounds.

## Documentation

- [Design principles and constraints](docs/vision.md)
- [Architecture and tradeoffs](docs/design.md)
- [M1.9 numeric benchmarks and precision gates](docs/m19-numeric-validation.md)
- [Benchmark methodology](docs/benchmarks-m1.md)
- [Version history](CHANGELOG.md)
- [Contributing and testing](CONTRIBUTING.md)
- [Release checklist](docs/RELEASE_CHECKLIST.md)

**Not implemented:** a general CSV/JSON parser, SIMD CPU dispatch, a parallel
executor, Arrow/C/Python bindings, FFT, or a database engine. Potential
extensions are research proposals, not present features.

## License

MIT — see [LICENSE](LICENSE).
