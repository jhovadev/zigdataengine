# M1.8 — Math precision and reproducible reduction

## Scope

The library stays format-agnostic. M1.8 adds:

- `zdata.math.accuracy.compare` for f64 absolute/relative/ULP reporting;
- checked-in, hermetic f64 golden vectors for `sigmoid`, `softplus`,
  `logSumExp`, and `softmax` generated from **100-decimal-digit mpmath**;
- extreme inputs and algebraic properties, without adding `mpmath` to Zig;
- `zdata.stats.Covariance`: streaming bivariate covariance/correlation with
  independent partitions merged using Chan's identities;
- `zdata.stats.sumFixedTree`: a canonical binary-tree compensated reduction,
  independently of runtime scheduling;
- `zig build math-accuracy` to report worst observed ULP against the fixture.

## Commands

```sh
zig build test
zig build test -Doptimize=ReleaseSafe
zig build math-accuracy
python3 -m unittest discover -s tests -v
# Optional: pip install mpmath
python3 tools/generate_math_vectors.py --check
```

The Python reference generator is **not** part of the SDK's runtime. It is an
optional validation dependency. `--write` regenerates committed vectors;
review the diff before accepting changes.

## Numerical contracts

- For finite results tested by the golden set, a difference of **up to 16 ULP**
  is the present regression threshold. This is **not** a formal 16-ULP guarantee
  for all representable f64 inputs or every target. As more targets are tested,
  the bound may need refinement. Test different Zig optimization modes.
- ULP error, absolute error and relative error are **different measurements**.
  Near zero, relative error may be meaningless; this harness returns null for
  the relative error when the reference is zero. Signed zeros are considered
  numerically equal by `ulpDistance` but can be tested by comparing bit patterns.
- `sigmoid`/`softplus` use existing scalar functions. NaNs propagate; infinities
  have specific limits. `softmax` and `logSumExp` reject nonfinite arrays.
- `Covariance` accepts finite pairs only; returns null for missing correlation
  (fewer than two observations or a zero-variance column). Merge order impacts
  rounding. It does **not** promise that arbitrary parallel partitions produce
  identical floating-point bit patterns.
- `sumFixedTree` always partitions a given input recursively in half; it can
  be scheduled using the same canonical tree, but no parallel execution or CPU
  dispatch is implemented here. Bitwise equality is only expected for the same
  target/compiler/optimization mode with the same input and evaluation order.
- Covariance and compensated reduction reject nonfinite inputs and overflowed
  intermediate outputs instead of silently emitting nonsensical finite values.

## Deferred / no claims

Not included: `erf`, `erfc`, normal CDF, vector math, CPU dispatch, arbitrary
precision types, Arrow, Python bindings or a concurrency runtime. Existing
`std.math` capabilities are not duplicated. Target-specific accuracy evidence
and performance comparisons are required before promising portable error bounds
or speedups.
