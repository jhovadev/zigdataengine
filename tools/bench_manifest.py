#!/usr/bin/env python3
"""Record hardware/compiler/kernel information for existing --samples benchmarks.

This does not change CSV layout, so tools/bench_compare.py remains compatible.
The kernel field describes EXPLICIT ZDE choices; std/LLVM kernels are unknown.
"""
from __future__ import annotations
import argparse
import csv
import datetime as dt
import hashlib
import json
import os
import platform
import subprocess
from pathlib import Path


def kernel_for_case(name: str) -> str:
    if name == "zdata.vector16":
        return "explicit-vector-16"
    if name == "zdata.vector32":
        return "explicit-vector-32"
    if name == "zdata.structural.scalar/newline":
        return "scalar-64-byte-block"
    if name.startswith("baseline."):
        return "explicit-benchmark-scalar (not std API)"
    if name.startswith("std."):
        return "compiler-or-stdlib-selected (not introspected)"
    return "ZDE-default (not runtime dispatched)"


def cpu_model() -> str:
    try:
        with open("/proc/cpuinfo", encoding="utf-8") as handle:
            for line in handle:
                if line.startswith("model name") or line.startswith("Hardware"):
                    return line.partition(":")[2].strip()
    except OSError:
        pass
    return platform.processor() or "unknown"


def compiler_version() -> str:
    try:
        result = subprocess.run(["zig", "version"], capture_output=True, text=True,
                                check=True, timeout=5)
        return result.stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return "unavailable"


def make_manifest(path: Path) -> dict:
    content = path.read_bytes()
    reader = csv.DictReader(content.decode("utf-8").splitlines())
    if reader.fieldnames != ["case", "bytes", "iteration", "ns", "checksum"]:
        raise ValueError("expected M1.5/M1.7 --samples CSV")
    cases: dict[str, str] = {}
    row_count = 0
    for row in reader:
        name = row["case"]
        if not name:
            raise ValueError("blank case name")
        int(row["bytes"])
        int(row["iteration"])
        int(row["ns"])
        int(row["checksum"])
        cases[name] = kernel_for_case(name)
        row_count += 1
    if not row_count:
        raise ValueError("empty samples file")
    return {
        "schema_version": 1,
        "samples_file": path.name,
        "samples_sha256": hashlib.sha256(content).hexdigest(),
        "created_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
        "platform": platform.platform(),
        "machine": platform.machine(),
        "cpu_model": cpu_model(),
        "logical_cpus": os.cpu_count(),
        "zig_version": compiler_version(),
        "note": "CPU model from host; compiler-generated std kernels are not introspected.",
        "kernels": cases,
        "sample_rows": row_count,
    }


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("samples", type=Path)
    p.add_argument("--out", type=Path, required=True)
    args = p.parse_args()
    try:
        result = make_manifest(args.samples)
    except (OSError, ValueError, UnicodeError) as exc:
        p.error(str(exc))
    args.out.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"Wrote {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
