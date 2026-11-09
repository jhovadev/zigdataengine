# M1.9 — Numerical correctness & performance gates

**Target:** Zig 0.17.1. The core remains format-agnostic, no runtime or third-party
library dependency. This release **does not** implement SIMD, concurrency,
`erf`/`erfc`, FFT, or a replacement for `std.math`.

## 1. High-precision differential regression corpus

`src/math/stress_golden.zig` is committed, so Zig tests do not need Python:

- **2,048** deterministic f64 unary inputs: sigmoid + softplus = **4,096**
  comparisons; structured extremes, small magnitudes, and seeded SplitMix64.
- **256** deterministic three-element vectors: logSumExp + three softmax
  results = **1,024** comparisons.
- **5,120 total** new comparisons against outputs rounded to f64 from
  **100-decimal-digit mpmath** expressions, in addition to M1.8's golden set.
- Regression threshold **16 ULP** for ordinary finite cases. For **softmax
  probabilities below 1e-30**, the gate is **512 ULP AND <=1e-12 relative
  error**, because scalar exponential in a high dynamic range can yield many
  ULPs of tiny absolute magnitude without high relative error. A value that
  becomes zero when the reference is nonzero still fails the relative gate.
  These are corpus regression thresholds, **not universal guarantees**.
  The observed maximum must be measured on each target with `math-accuracy`.
- Generator is deterministic and uses an explicit 64-bit SplitMix64 PRNG.
  A separate Python test compares the fixture byte-for-byte when `mpmath`
  is installed; that test is skipped without it.

```sh
zig build test -Doptimize=ReleaseSafe
zig build math-accuracy -Doptimize=ReleaseSafe
python3 tools/generate_math_stress.py --check  # optional: needs mpmath
python3 -m unittest discover -s tests -v
```

## 2. Numerical aggregation tests

`src/compute/stress_test.zig` compares streaming/merged `Moments`, `Covariance`,
and `CompensatedSum` with an independent **f128 two-pass reference**. It tests
nine partition sizes, forward/reverse fold order, and checks fixed reduction-tree
repeatability in a single executable. Approximate tolerances are declared in
source; reassociation is not expected to preserve the last bit across different
chunking, CPU architectures, compilers, or optimization modes.

`f128` is stronger than an `f64` baseline, **not** an arbitrary-precision
oracle or guarantee of correctly rounded mathematical results.

## 3. Independent numeric benchmark

```sh
zig build math-bench -Doptimize=ReleaseFast -- --size 32768 --iterations 30 --warmup 5
zig build math-bench -Doptimize=ReleaseFast -- --size 32768 --iterations 30 --warmup 5 --samples 2> m19-numeric.csv
python3 tools/bench_manifest.py m19-numeric.csv --out m19-numeric.meta.json
```

The new build step runs 13 cases with **preallocated** inputs and f128 two-pass
references. Data generation, oracle computation, correctness checks and summary
calculations are outside measured intervals. The command reports median/p95 and
absolute error/ULP; `--samples` emits the existing
`case,bytes,iteration,ns,checksum` schema for the M1.5 bootstrap comparator.

| Family | Baseline | ZDE candidates | Notes |
|---|---|---|---|
| Sum | plain f64 accumulation | Neumaier, fixed tree | Deliberately cancellation-heavy values `[1e16,1,-1e16,2]` repeated: the baseline loses precision; the benchmark documents rather than hides it. |
| Variance | independent f64 two-pass | Welford online, 8 partitions merged | f128 two-pass reference, population variance. |
| Covariance | independent f64 two-pass | online, 8 partitions merged | f128 two-pass reference, population covariance. |
| Sigmoid | scalar `1/(1+exp(-x))` | stable sigmoid | Only finite `[-16,16]` inputs; neither version claims superiority outside benchmark domain. |
| Softplus | scalar `log1p(exp(x))` | stable softplus | Only finite `[-16,16]` inputs; numerically stable outside this interval is not being benchmarked. |

**Use `--size` values divisible by 8** in the range 8–1,048,576. Default is
32,768 values, 30 measured iterations, five warmups. A single benchmark run
may be affected by CPU frequency, thermal throttling and memory caches.
Run both versions on the same CPU/OS/Zig version and the same parameters;
repeat independent runs or interleave revisions before claiming gains.

`bytes` in the raw CSV denotes total four-array input footprint, **not** exact
bytes read by the individual kernel. `checksum` encodes the independent f128
reference result; the aggregate error is printed only in the human-readable
mode. For speed comparisons:

```sh
python3 tools/bench_compare.py m19-baseline.csv m19-candidate.csv \
  --bootstrap 5000 --confidence 0.95 --min-effect-pct 3
```

`baseline.*` case labels are scalar reference implementations **in the
benchmark**, not specialized standard-library APIs. The manifest identifies
them explicitly as benchmark scalar baselines.

## 4. Acceptance gates

1. `zig build test` and `zig build test -Doptimize=ReleaseSafe` succeed.
2. `zig build math-accuracy -Doptimize=ReleaseSafe` completes: regression
   threshold **<=16 ULP** for regular cases; tiny softmax cases must meet
   both the 512-ULP and 1e-12 relative-error gates, as documented above.
3. The optional Python mpmath corpus-check matches byte-for-byte.
4. `zig build math-bench -Doptimize=ReleaseFast` checks numeric error outside
   timed regions. It does **not** fail on the intentionally inaccurate naive
   sum baseline (which is reported as an error).
5. Record the host CPU and Zig version with `bench_manifest.py`; don't compare
   different sizes or checksums.

References: Chan, Golub & LeVeque (1983), *Algorithms for Computing the Sample
Variance: Analysis and Recommendations*; Zig 0.17.1 language reference,
*Floating Point Operations*. No claimed speedup is made until measured.
