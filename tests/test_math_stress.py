"""Validate that the M1.9 high-precision corpus stays reproducible."""
import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "src" / "math" / "stress_golden.zig"
SCRIPT = ROOT / "tools" / "generate_math_stress.py"


class MathStressTests(unittest.TestCase):
    def test_fixture_has_expected_case_counts(self):
        text = FIXTURE.read_text(encoding="utf-8")
        self.assertEqual(text.count(".x_bits = "), 2048)
        self.assertEqual(text.count(".lse_bits = "), 256)

    def test_fixture_matches_mpmath_100_dps_when_available(self):
        try:
            import mpmath  # noqa: F401
        except ImportError:
            self.skipTest("mpmath optional: pip install mpmath")
        spec = importlib.util.spec_from_file_location("m19", SCRIPT)
        module = importlib.util.module_from_spec(spec)
        assert spec.loader is not None
        spec.loader.exec_module(module)
        self.assertEqual(FIXTURE.read_text(encoding="utf-8"), module.generate())


if __name__ == "__main__":
    unittest.main()
