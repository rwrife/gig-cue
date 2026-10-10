import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


class NetworkGateTests(unittest.TestCase):
    def run_gate(self, source="", grep_error=False):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "scripts").mkdir()
            (root / "App").mkdir()
            (root / "App" / "Probe.swift").write_text(source)
            shutil.copyfile(Path(__file__).resolve().parents[2] / "scripts/check_zero_network.sh",
                            root / "scripts/check_zero_network.sh")
            env = dict(os.environ)
            if grep_error:
                (root / "bin").mkdir()
                fake = root / "bin" / "grep"
                fake.write_text("#!/bin/sh\nexit 2\n")
                fake.chmod(0o700)
                env["PATH"] = str(root / "bin") + os.pathsep + env["PATH"]
            return subprocess.run(["bash", str(root / "scripts/check_zero_network.sh")],
                                  env=env, capture_output=True, text=True, timeout=15)

    def test_clean_source_passes(self):
        result = self.run_gate("import SwiftUI\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("PASS", result.stdout)

    def test_network_source_blocks(self):
        result = self.run_gate("let session = URLSession.shared\n")
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("PASS", result.stdout)

    def test_scanner_error_blocks(self):
        result = self.run_gate(grep_error=True)
        self.assertEqual(result.returncode, 2)
        self.assertNotIn("PASS", result.stdout)
