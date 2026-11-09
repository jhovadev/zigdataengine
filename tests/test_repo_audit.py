import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

from tools.repo_audit import audit, generated_path


class RepoAuditTests(unittest.TestCase):
    def test_detects_generated_outputs_but_not_reference_vectors(self):
        for name in (
            "zig-out/bin/zdata-copy",
            "tests/__pycache__/unit.pyc",
            "copia-prueba.csv",
            "m17-baseline.meta.json",
        ):
            with self.subTest(name=name):
                self.assertTrue(generated_path(name))
        for name in (
            "src/math/golden.zig",
            "src/math/stress_golden.zig",
            "tests/fixtures/data.csv",
            "docs/results/published.csv",
        ):
            with self.subTest(name=name):
                self.assertFalse(generated_path(name))

    def test_audit_flags_large_file_without_deleting_it(self):
        import subprocess

        with TemporaryDirectory() as directory:
            root = Path(directory)
            subprocess.run(["git", "init", "-q"], cwd=root, check=True)
            target = root / "oversized.bin"
            target.write_bytes(b"X" * 64)
            subprocess.run(["git", "add", "--", "oversized.bin"], cwd=root, check=True)
            count, warnings = audit(root, 32)
            self.assertEqual(count, 1)
            self.assertEqual(len(warnings), 1)
            self.assertTrue(target.exists())


if __name__ == "__main__":
    unittest.main()
