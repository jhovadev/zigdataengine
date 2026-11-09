"""Optional mpmath check for Zig's committed high-precision math fixtures."""
import pathlib
import subprocess
import sys
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
try:
    import mpmath  # noqa: F401
except ImportError:
    mpmath = None


class GoldenVectorTests(unittest.TestCase):
    def test_reference_fixture_exists(self):
        fixture = ROOT / "src" / "math" / "golden.zig"
        self.assertTrue(fixture.is_file())
        self.assertIn("pub const unary", fixture.read_text(encoding="utf8"))

    @unittest.skipUnless(mpmath, "mpmath is an optional precision-test dependency")
    def test_reference_fixture_matches_100_digit_mpmath(self):
        completed = subprocess.run(
            [sys.executable, str(ROOT / "tools" / "generate_math_vectors.py"), "--check"],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(completed.returncode, 0, completed.stderr + completed.stdout)


if __name__ == "__main__":
    unittest.main()
