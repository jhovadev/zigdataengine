#!/usr/bin/env python3
"""Read-only audit of accidentally tracked generated files and large assets.

Reads ``git ls-files`` and file sizes. Never changes or deletes files.
Use ``--strict`` in CI to fail when suspicious tracked files are found.
"""

from __future__ import annotations

import argparse
from pathlib import Path, PurePosixPath
import subprocess


def generated_path(relative: str) -> bool:
    """Return True for known generated outputs, not checked-in golden .zig files."""
    path = PurePosixPath(relative)
    parts = path.parts
    if any(part in {".zig-cache", "zig-out", "zig-pkg", "__pycache__", ".venv"} for part in parts):
        return True
    if path.suffix in {".pyc", ".pyo", ".o", ".obj", ".exe"}:
        return True
    # Only reject root-level data output; fixtures in testdata/ may be intentional.
    if len(parts) == 1 and (path.suffix == ".csv" or path.name.endswith(".meta.json")):
        return True
    return False


def tracked_files(root: Path) -> list[str]:
    result = subprocess.run(
        ["git", "ls-files", "-z"], cwd=root, check=True, stdout=subprocess.PIPE
    )
    return [value.decode("utf-8", "surrogateescape") for value in result.stdout.split(b"\0") if value]


def audit(root: Path, max_tracked_bytes: int) -> tuple[int, list[str]]:
    paths = tracked_files(root)
    warnings: list[str] = []
    for relative in paths:
        target = root / relative
        if generated_path(relative):
            warnings.append(f"generated output tracked: {relative}")
        if target.is_file() and target.stat().st_size > max_tracked_bytes:
            mib = target.stat().st_size / (1024 * 1024)
            warnings.append(f"large tracked file ({mib:.1f} MiB): {relative}")
    return len(paths), warnings


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--strict", action="store_true", help="exit nonzero if suspicious tracked files exist")
    parser.add_argument("--max-tracked-mib", type=int, default=5)
    args = parser.parse_args()
    if args.max_tracked_mib < 1:
        parser.error("--max-tracked-mib must be positive")
    root = Path(__file__).resolve().parent.parent
    try:
        count, warnings = audit(root, args.max_tracked_mib * 1024 * 1024)
    except (OSError, subprocess.CalledProcessError) as exc:
        parser.exit(2, f"repo audit: {exc}\n")
    print(f"Repository audit: {count} tracked files, {len(warnings)} warning(s)")
    for warning in warnings:
        print(f"  - {warning}")
    return int(args.strict and bool(warnings))


if __name__ == "__main__":
    raise SystemExit(main())
