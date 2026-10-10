import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


class NativeOnlyGateTests(unittest.TestCase):
    def run_gate(self, scanner=None):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "scripts").mkdir()
            (root / "App").mkdir()
            shutil.copyfile(
                Path(__file__).resolve().parents[2] / "scripts/check_native_only.sh",
                root / "scripts/check_native_only.sh",
            )
            env = dict(os.environ)
            if scanner:
                bin_dir = root / "bin"
                bin_dir.mkdir()
                fake = bin_dir / scanner
                fake.write_text("#!/bin/sh\nexit 2\n")
                fake.chmod(0o700)
                env["PATH"] = str(bin_dir) + os.pathsep + env["PATH"]
            return subprocess.run(
                ["bash", str(root / "scripts/check_native_only.sh")],
                env=env, capture_output=True, text=True, timeout=15,
            )

    def test_clean_tree_passes(self):
        result = self.run_gate()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("PASS", result.stdout)

    def test_find_error_blocks(self):
        result = self.run_gate("find")
        self.assertEqual(result.returncode, 2)
        self.assertNotIn("PASS", result.stdout)

    def test_grep_error_blocks(self):
        result = self.run_gate("grep")
        self.assertEqual(result.returncode, 2)
        self.assertNotIn("PASS", result.stdout)
