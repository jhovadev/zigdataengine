# Publication and release checklist

This checklist is for maintainers of the **GitHub source repository**. The
package uses `build.zig.zon` and exposes `b.dependency("zdata").module("zdata")`.
Do not alter the existing package `fingerprint` when merely renaming or
publishing the repository: it is part of its package identity.

## Before pushing a public repository

1. Check Git's tracked files and staged changes:

   ```sh
   git status --short
   git ls-files
   python3 tools/repo_audit.py --strict
   ```

2. Check **tracked** large or generated artifacts. `.gitignore` does not remove
   previously tracked files:

   ```sh
   git ls-files '*.csv' '*.meta.json' '*.pyc' 'zig-out/*'
   ```

   For an accidentally tracked file, untrack it **without deleting the local
   copy**, for example `git rm --cached -- copia-prueba.csv`. Do not run this on
   intentionally curated datasets or reference fixtures.

3. Run the checks:

   ```sh
   zig build test
   zig build test -Doptimize=ReleaseSafe
   zig build math-accuracy -Doptimize=ReleaseSafe
   python3 -m unittest discover -s tests -v
   uv run --with mpmath python -m unittest discover -s tests -v
   ```

4. Check the README, license, package name and Zig version. Avoid publishing
   local paths, benchmark results without hardware metadata, or unsupported
   claims about CPU dispatch, Arrow integration, concurrency or SIMD.
5. Push to a new repository and check the CI result. Only then consider a
   `v0.1.0` tag and a GitHub Release; do **not** tag a commit with failing CI.

## Keeping benchmark evidence

Root-level `*.csv` and `*.meta.json` files are local output and ignored.
Evidence intentionally published in `docs/results/` can be committed with
its command, hardware manifest and clear interpretation. Do not commit the
30 MB CSV copy used for the file-transfer smoke test.

## Package inclusion rules

`build.zig.zon` uses an explicit `.paths` list. A GitHub repository checkout
contains developer tools and GitHub CI, but a fetched Zig package contains
**only** the declared paths. Update `.paths` deliberately if a new file is
needed at consumer build time; avoid pulling benchmark output into the package.
