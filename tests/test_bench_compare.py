"""Run with python3 -m unittest discover -s tests -v (no extra dependencies)."""
import tempfile
import unittest
from pathlib import Path

from tools.bench_compare import bootstrap_delta_ci, compare, load_samples


class BenchCompareTests(unittest.TestCase):
    def test_bootstrap_detects_large_gain_and_regression(self):
        old = [1_000_000 + i * 2000 for i in range(30)]
        faster = [n // 2 for n in old]
        slower = [n * 2 for n in old]
        _, _, high = bootstrap_delta_ci(old, faster, repetitions=1000, confidence=.95, seed=42)
        self.assertLess(high, -3)
        _, low, _ = bootstrap_delta_ci(old, slower, repetitions=1000, confidence=.95, seed=42)
        self.assertGreater(low, 3)

    def test_bootstrap_stable_data_inconclusive(self):
        times = [1_000_000 + i * 100 for i in range(30)]
        _, low, high = bootstrap_delta_ci(times, times, repetitions=1000, confidence=.95, seed=42)
        self.assertLess(low, 3)
        self.assertGreater(high, -3)

    def test_rejects_aggregate_csv(self):
        with tempfile.TemporaryDirectory() as td:
            p = Path(td) / "summary.csv"
            p.write_text("case,bytes,iterations,warmup,min_ns,median_ns,p95_ns,max_ns,mib_per_s,checksum\n")
            with self.assertRaisesRegex(ValueError, "raw"):
                load_samples(p)

    def test_rejects_duplicate_or_missing_iterations(self):
        with tempfile.TemporaryDirectory() as td:
            p = Path(td) / "samples.csv"
            p.write_text("case,bytes,iteration,ns,checksum\n"
                         "scan,1024,0,10000,23\nscan,1024,0,15000,23\n")
            with self.assertRaisesRegex(ValueError, "repeated iteration"):
                load_samples(p)
            p.write_text("case,bytes,iteration,ns,checksum\n"
                         "scan,1024,0,10000,23\nscan,1024,2,15000,23\n")
            with self.assertRaisesRegex(ValueError, "missing or noncontiguous"):
                load_samples(p)

    def test_rejects_different_checksum(self):
        with tempfile.TemporaryDirectory() as td:
            old = Path(td) / "old.csv"
            new = Path(td) / "new.csv"
            content = "case,bytes,iteration,ns,checksum\n" + "".join(
                f"scan,1024,{i},10000,23\n" for i in range(20))
            old.write_text(content)
            new.write_text(content.replace(",10000,23", ",10000,24"))
            with self.assertRaisesRegex(ValueError, "checksum differs"):
                compare(old, new, 100, .95, 3, 1)

    def test_rejects_different_dataset(self):
        with tempfile.TemporaryDirectory() as td:
            old = Path(td) / "old.csv"
            new = Path(td) / "new.csv"
            content = "case,bytes,iteration,ns,checksum\n" + "".join(
                f"scan,1024,{i},10000,23\n" for i in range(20))
            old.write_text(content)
            new.write_text(content.replace(",1024,", ",4096,"))
            with self.assertRaisesRegex(ValueError, "sizes differ"):
                compare(old, new, 100, .95, 3, 1)


if __name__ == "__main__":
    unittest.main()
