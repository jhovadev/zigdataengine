#!/usr/bin/env python3
"""Deterministic MPFR-style *reference values* using mpmath (100 decimal digits).

The committed Zig fixture is the oracle: Zig tests never import Python. Running
--check verifies the fixture remains synchronized. mpmath is optional for SDK
users and required only when regenerating/auditing vectors.
"""
from __future__ import annotations

import argparse
import pathlib
import struct


ROOT = pathlib.Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "src" / "math" / "golden.zig"
INPUTS = [
    -1000.0, -745.0, -740.0, -710.0, -100.0, -40.0, -20.0,
    -5.0, -2.0, -1.0, -1e-12, -0.0, 0.0, 1e-12, 1.0, 2.0,
    5.0, 20.0, 40.0, 100.0, 709.0, 1000.0,
]
VECTORS = [
    [0.0, 0.0],
    [1.0, 2.0, 3.0],
    [1000.0, 1001.0, 1002.0],
    [-1000.0, -999.0, -998.0],
    [3.0, 3.0, 3.0, 3.0],
    [100.0, 0.0, -100.0],
    [1e-300, -1e-300],
    [709.0, -709.0],
    [1e6, 1e6-1.0, 1e6-2.0, 1e6-3.0],
]


def bits_int(x: float) -> str:
    return f"0x{struct.unpack('>Q', struct.pack('>d', float(x)))[0]:016x}"


def generate() -> str:
    try:
        from mpmath import mp
    except ImportError as exc:
        raise SystemExit("Install optional test dependency: python -m pip install mpmath") from exc
    mp.dps = 100
    lines = [
        "//! Generated with tools/generate_math_vectors.py using mpmath (100 dps).",
        "//! Golden f64 outputs are rounded from arbitrary-precision expressions.",
        "//! DO NOT EDIT: run `python3 tools/generate_math_vectors.py --check`.",
        "pub const Unary = struct { x_bits: u64, sigmoid_bits: u64, softplus_bits: u64 };",
        "pub const unary = [_]Unary{",
    ]
    for x in INPUTS:
        x_mp = mp.mpf(x)
        sigmoid = 1 / (1 + mp.exp(-x_mp))
        softplus = mp.log1p(mp.exp(x_mp))
        lines.append("    .{ .x_bits = %s, .sigmoid_bits = %s, .softplus_bits = %s }," % (
            bits_int(x), bits_int(float(sigmoid)), bits_int(float(softplus))
        ))
    lines += [
        "};", "pub const Vector = struct { len: usize, inputs: [4]u64, lse_bits: u64, probabilities: [4]u64 };",
        "pub const vectors = [_]Vector{",
    ]
    for values in VECTORS:
        ms = [mp.mpf(v) for v in values]
        m = max(ms)
        exps = [mp.exp(v - m) for v in ms]
        den = mp.fsum(exps)
        lse = m + mp.log(den)
        out = [float(e / den) for e in exps]
        inbits = [bits_int(x) for x in values] + [bits_int(0.0)] * (4-len(values))
        outbits = [bits_int(x) for x in out] + [bits_int(0.0)] * (4-len(values))
        lines.append("    .{ .len = %d, .inputs = .{ %s }, .lse_bits = %s, .probabilities = .{ %s } }," % (
            len(values), ", ".join(inbits), bits_int(float(lse)), ", ".join(outbits)
        ))
    lines += ["};", ""]
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser()
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument("--check", action="store_true")
    action.add_argument("--write", action="store_true")
    args = parser.parse_args()
    expected = generate()
    if args.check:
        if not OUTPUT.exists() or OUTPUT.read_text(encoding="utf-8") != expected:
            raise SystemExit("Golden reference vectors differ; rerun with --write and review the diff")
        print("Math references match mpmath (100 dps)")
    else:
        OUTPUT.write_text(expected, encoding="utf-8")
        print(f"Wrote {OUTPUT}")


if __name__ == "__main__":
    main()
