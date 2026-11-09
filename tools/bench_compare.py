#!/usr/bin/env python3
"""Compare M1.5 --samples CSV files using non-parametric bootstrap.

No third-party dependencies. This is an *independent-samples* comparison;
run both revisions on the same host and compiler settings, interleaving runs
when possible. Percentile bootstrap is a screening tool, not a CI proof.
"""
from __future__ import annotations

import argparse
import csv
import math
import random
import statistics
import sys
from collections import defaultdict
from pathlib import Path


def load_samples(path: Path) -> dict[str, tuple[int, int, list[int]]]:
    groups: dict[str, list[int]] = defaultdict(list)
    shapes: dict[str, int] = {}
    expected: dict[str, int] = {}
    with path.open(newline="", encoding="utf-8") as file:
        reader = csv.DictReader(file)
        if reader.fieldnames != ["case", "bytes", "iteration", "ns", "checksum"]:
            raise ValueError(f"{path}: expected raw `--samples` CSV, not `--csv` summary")
        seen: set[tuple[str, int]] = set()
        indices: dict[str, list[int]] = defaultdict(list)
        for row in reader:
            name = row["case"]
            byte_count = int(row["bytes"])
            iteration = int(row["iteration"])
            ns = int(row["ns"])
            checksum = int(row["checksum"])
            if not name or ns <= 0 or byte_count <= 0 or iteration < 0:
                raise ValueError(f"{path}: invalid row {row!r}")
            if (name, iteration) in seen:
                raise ValueError(f"{path}: repeated iteration for {name}")
            seen.add((name, iteration))
            indices[name].append(iteration)
            if name in shapes and (shapes[name] != byte_count or expected[name] != checksum):
                raise ValueError(f"{path}: mixed dataset or checksum for {name}")
            shapes[name] = byte_count
            expected[name] = checksum
            groups[name].append(ns)
    if not groups:
        raise ValueError(f"{path}: empty file")
    for name, rows in indices.items():
        if sorted(rows) != list(range(len(rows))):
            raise ValueError(f"{path}: missing or noncontiguous iterations for {name}")
    return {name: (shapes[name], expected[name], times) for name, times in groups.items()}


def bootstrap_delta_ci(
    old: list[int], new: list[int], *, repetitions: int, confidence: float, seed: int
) -> tuple[float, float, float]:
    if len(old) < 10 or len(new) < 10:
        raise ValueError("at least 10 independent timed samples per case required")
    if not 0.50 <= confidence < 1.0:
        raise ValueError("confidence must be between .50 and 1")
    if repetitions < 100:
        raise ValueError("at least 100 bootstrap repetitions required")
    rng = random.Random(seed)
    # Negative delta = faster new implementation.
    observed = (statistics.median(new) / statistics.median(old) - 1.0) * 100.0
    distribution: list[float] = []
    for _ in range(repetitions):
        old_resample = rng.choices(old, k=len(old))
        new_resample = rng.choices(new, k=len(new))
        ratio = statistics.median(new_resample) / statistics.median(old_resample)
        distribution.append((ratio - 1.0) * 100.0)
    distribution.sort()
    alpha = (1.0 - confidence) / 2
    low = distribution[max(0, int(alpha * repetitions))]
    high = distribution[min(repetitions - 1, math.ceil((1 - alpha) * repetitions) - 1)]
    return observed, low, high


def compare(old_path: Path, new_path: Path, bootstrap: int, confidence: float,
            min_effect: float, seed: int) -> int:
    old = load_samples(old_path)
    new = load_samples(new_path)
    if set(old) != set(new):
        raise ValueError(f"cases differ: old-only={sorted(set(old)-set(new))}, "
                         f"new-only={sorted(set(new)-set(old))}")
    if min_effect < 0:
        raise ValueError("min-effect must be nonnegative")
    output_rows = []
    for name in sorted(old):
        old_bytes, old_checksum, old_ns = old[name]
        new_bytes, new_checksum, new_ns = new[name]
        if old_bytes != new_bytes:
            raise ValueError(f"{name}: dataset sizes differ ({old_bytes} vs {new_bytes})")
        if old_checksum != new_checksum:
            raise ValueError(f"{name}: checksum differs ({old_checksum} vs {new_checksum})")
        if len(old_ns) != len(new_ns):
            raise ValueError(f"{name}: sample counts differ")
        observed, low, high = bootstrap_delta_ci(old_ns, new_ns, repetitions=bootstrap,
                                                 confidence=confidence, seed=seed)
        if high < -min_effect:
            decision = "faster"
        elif low > min_effect:
            decision = "slower"
        else:
            decision = "inconclusive"
        output_rows.append(f"{name},{statistics.median(old_ns)/1000:.3f},"
                           f"{statistics.median(new_ns)/1000:.3f},{observed:+.2f},"
                           f"{low:+.2f},{high:+.2f},{decision}")
    # Do not produce a misleading partial report if a later case is invalid.
    print("case,old_median_us,new_median_us,delta_pct,ci_low_pct,ci_high_pct,decision")
    for row in output_rows:
        print(row)
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("old", type=Path)
    parser.add_argument("new", type=Path)
    parser.add_argument("--bootstrap", type=int, default=5000)
    parser.add_argument("--confidence", type=float, default=0.95)
    parser.add_argument("--min-effect-pct", type=float, default=3.0)
    parser.add_argument("--seed", type=int, default=20261109)
    args = parser.parse_args()
    try:
        return compare(args.old, args.new, args.bootstrap, args.confidence,
                       args.min_effect_pct, args.seed)
    except (OSError, ValueError, ZeroDivisionError) as exc:
        print(f"bench-compare: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
