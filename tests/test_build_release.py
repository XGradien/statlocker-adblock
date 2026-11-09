#!/usr/bin/env python3
"""Tests for the release build.

Run from the repo root:

    python -m unittest discover -s tests -v

The build script is exercised for real (as a subprocess, against a temporary
output directory) rather than mocked, so these tests would catch a zip that
shipped the wrong files or stopped being reproducible.
"""
import hashlib
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
TOOLS = REPO / "tools"

# Exactly what a user should get, and nothing else.
EXPECTED = [
    "Install AdBlock.bat",
    "Remove AdBlock.bat",
    "Check AdBlock Status.bat",
    "adblock.ps1",
    "domains.txt",
    "README.md",
    "assets/install-steps.svg",
    "assets/how-it-works.svg",
]

# Development files that must never reach a user.
FORBIDDEN = [
    "tools/refresh_domains.py",
    "tools/apply_new_domains.py",
    "tools/build-release.py",
    "tests/test_watcher.py",
    "tests/test-engine.ps1",
    ".github/workflows/ci.yml",
    "CONTRIBUTING.md",
    "CHANGELOG.md",
]


def build(out_dir, version="0.0.0-test"):
    return subprocess.run(
        [sys.executable, str(TOOLS / "build-release.py"),
         "--version", version, "--out-dir", str(out_dir)],
        capture_output=True, text=True, cwd=REPO,
    )


class TestBuildRelease(unittest.TestCase):
    def test_ships_only_user_facing_files(self):
        with tempfile.TemporaryDirectory() as tmp:
            result = build(tmp)
            self.assertEqual(result.returncode, 0, result.stderr)
            zip_path = Path(tmp) / "statlocker-adblock-v0.0.0-test.zip"
            self.assertTrue(zip_path.exists(), "the build did not write a zip")
            with zipfile.ZipFile(zip_path) as z:
                names = sorted(n.split("/", 1)[1] for n in z.namelist())
            self.assertEqual(names, sorted(EXPECTED))
            for leaked in FORBIDDEN:
                self.assertNotIn(leaked, names, f"{leaked} should not ship")

    def test_every_shipped_file_exists(self):
        with tempfile.TemporaryDirectory() as tmp:
            build(tmp)
            zip_path = Path(tmp) / "statlocker-adblock-v0.0.0-test.zip"
            with zipfile.ZipFile(zip_path) as z:
                for name in z.namelist():
                    self.assertGreater(z.getinfo(name).file_size, 0, f"{name} is empty")

    def test_build_is_reproducible(self):
        # Two builds from the same commit must be byte-identical, otherwise the
        # SHA-256 published with a release cannot be reproduced by anyone.
        with tempfile.TemporaryDirectory() as tmp:
            build(tmp)
            first = hashlib.sha256((Path(tmp) / "statlocker-adblock-v0.0.0-test.zip").read_bytes()).hexdigest()
            build(tmp)
            second = hashlib.sha256((Path(tmp) / "statlocker-adblock-v0.0.0-test.zip").read_bytes()).hexdigest()
            self.assertEqual(first, second, "two builds of the same commit differ")


if __name__ == "__main__":
    unittest.main()
