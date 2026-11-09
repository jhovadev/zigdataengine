import tempfile
import unittest
from pathlib import Path

from tools.bench_manifest import kernel_for_case, make_manifest


class BenchManifestTests(unittest.TestCase):
    def test_kernel_labels_are_explicit_not_guessed(self):
        self.assertEqual(kernel_for_case("zdata.vector32"), "explicit-vector-32")
        self.assertIn("not introspected", kernel_for_case("std.mem.count(byte)"))
        self.assertEqual(kernel_for_case("baseline.scalar.sigmoid"), "explicit-benchmark-scalar (not std API)")

    def test_samples_have_sha256_and_cpu_metadata(self):
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / "sample.csv"
            path.write_text("case,bytes,iteration,ns,checksum\nzdata.vector16,32,0,42,1\n")
            manifest = make_manifest(path)
            self.assertEqual(manifest["sample_rows"], 1)
            self.assertEqual(len(manifest["samples_sha256"]), 64)
            self.assertEqual(manifest["kernels"]["zdata.vector16"], "explicit-vector-16")
            self.assertTrue(manifest["machine"])

    def test_summary_csv_is_rejected(self):
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / "summary.csv"
            path.write_text("case,bytes,median_ns\na,32,1\n")
            with self.assertRaises(ValueError):
                make_manifest(path)


if __name__ == "__main__":
    unittest.main()
