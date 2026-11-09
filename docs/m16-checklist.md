# M1.6 validation checklist

Scope: format-independent bit masks and structural scanning; streaming
statistics and an opt-in allocator with budget. No CSV Reader files touched.

```
zig build test
zig build test -Doptimize=ReleaseSafe
zig build bench -Doptimize=ReleaseFast -- --samples --iterations 30 --warmup 5 --size-mib 32 2> baseline-m16.csv
python3 -m unittest discover -s tests -v
```

What the tests cover:
- Bit prefix parity against a scalar oracle across 4096 masks.
- Sorted offset extraction, zero mask, output capacity and offset overflow.
- TSV, pipe, NDJSON and JSON-like punctuation classification.
- CSV-style doubled quotes across every chunk length, and JSON-style `\\` escapes.
- Bounded scan / errors, Welford with Chan merge, compensated sums.
- Peak/live allocation budget, OOM without corrupting accounting.

What the tests **do not** prove:
- That scalar scanning is faster than std or other parsers.
- That our classification validates CSV, JSON, or UTF-8 end-to-end.
- That pooled requested bytes equal peak physical memory.
- That numerical results are bit identical across platforms and merge trees.

When compiling fails, keep the first Zig compiler diagnostic and exact line.
This patch was assembled and `git apply --check` validated against the M1.5
baseline; Zig compilation must be performed on a machine with Zig 0.17.1.
