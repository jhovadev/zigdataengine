# Zig Data Engine — format-independent primitives

ZDE is a collection of independently usable algorithms, data structures,
streaming tools and numerical primitives. It is **not** a CSV or JSON parser,
and not a replacement for `std`.

## Dependency direction

```text
applications/adapters (CSV, TSV, NDJSON, JSON, proprietary binary)
         ↓
scanning / numeric processing / bit masks / memory / transfer
         ↓
                  Zig std
```

The core does not import formats, DVUI, or a specific runtime. A consumer may
import only `zdata.bits`, `zdata.scan`, `zdata.stats`, or `zdata.memory`.

## Entry points as of M1.6

| Module | Public use | Stability |
|---|---|---|
| `memory.Pool` | Leased fixed-size buffers | Existing M0 contract |
| `memory.CountingAllocator` | Optional instrumentation + requested-live-byte budget | Experimental |
| `bits.positions` | Bitmask → caller-owned absolute offsets | Experimental |
| `bits.inclusivePrefixXor` | Parity prefix for generic event masks | Experimental |
| `scan.structural.Scanner(Dialect)` | Stateful classification over <=64-byte chunks | **Scalar reference only** |
| `scan.Matcher` | Streaming KMP (overlap-aware) | Existing M0 contract |
| `stats.Moments` | Welford, Chan merge, population/sample variance | Experimental |
| `stats.CompensatedSum` | Neumaier sum, mergeable | Experimental |
| `math` | Stable scalar numerical compositions, ULP/testing helpers | Experimental M1.7 |
| `transfer.copy` | Bounded stream transfer | Existing M0 contract |

## Contracts

- Allocator and I/O are passed by the host where needed; never create threads
  behind the host's back.
- No formats are imported by any core primitive.
- `Scanner` reports only **selected structural marks outside quotes** and is
  not a CSV, JSON, XML, or UTF-8 validator. No SIMD performance claim exists.
  Full JSON needs additional pseudo-structural classification, lexical
  validation and a stage-2 parser. XML needs distinct quote/comment/CDATA rules.
- The scan kernel accepts 0–64 bytes per call and returns a relative `u64`
  mask. The caller uses `bits.positions(mask, base, scratch)` to materialize
  offsets without allocations, or can process masks directly.
- `max_bytes` is an absolute per-scanner byte budget. On limit failure the
  scanner state is unchanged. The user owns buffers and the output index.
- The counting allocator controls *requested live bytes*, not physical RSS or
  underlying page retention. Instances are not thread safe. Host-supplied
  allocators define alignment and allocation behavior.
- Floating-point merged accumulators can differ slightly with merge order.
  Use a fixed merge tree for reproducible results within a target configuration.

## Validation gates

1. Differential correctness against a simple independent reference.
2. Exhaustive or randomized fragmentation tests at every block boundary.
3. Fuzz and injected allocation errors where relevant.
4. Benchmarks with saved raw samples, medians and p95 vs comparable std baselines.
5. Only after meeting the gates: build an optional scalar/SIMD dispatch path.

## Format coverage and non-goals

- TSV / pipe-delimited: marker classification can be configured without code
  changes in core. Quoting rules are the adapter's responsibility.
- NDJSON/line logs: `\n` classification without quoted records provides fast
  candidate record boundaries. **NDJSON strings must not contain literal
  newlines**; escaped `\\n` is not a record break.
- JSON: `backslash` quote mode can identify punctuation outside strings, but
  this is not an RFC 8259 parser or full simdjson stage 1.
- CSV: `doubled_quote` mode supports quoted regions, including split `""`.
  Additional CSV grammar and error recovery belong in a separate adapter.
- XML: intentionally not supported by this first scanner; XML is not merely
  JSON with another set of delimiters.
- Binary formats: length-prefix / TLV decoding is a separate stream primitive,
  not a structural character scanner.

**Rule:** We will not label this layer 'stable' or 'SIMD-optimized' until two
independent adapters use it without changing the kernel and measurements show
value on representative workloads.
