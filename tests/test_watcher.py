#!/usr/bin/env python3
"""Tests for the domain watcher and the blocklist applier.

Run from the repo root:

    python -m unittest discover -s tests -v

No third-party dependencies: stdlib only.
"""
import hashlib
import importlib.util
import io
import os
import re
import shutil
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from unittest import mock

REPO = Path(__file__).resolve().parent.parent
TOOLS = REPO / "tools"


def load_module(name, path):
    """Import a script by path so its __main__ guard does not fire."""
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


# A stand-in for Statlocker's ad-surface page. It carries the two variables the
# watcher needs to reconstruct the ramp.js URL, one permanently-dead script it
# must skip, and one ordinary extra script it will follow.
FAKE_PAGE = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Statlocker</title>
<script src="/popup-guard.js"></script>
<script src='https://cdn.intergient.com/'></script>
<script>
  var PUB_ID = '1025810';
  var WEBSITE_ID = '78633';
  var rampScript = { src: 'https://cdn.intergient.com/' + PUB_ID + '/' + WEBSITE_ID + '/ramp.js' };
</script>
<script src="https://config.playwire.com/1025810/v2/pre_content.js"></script>
<script src="https://cdn.example.com/extra.js"></script>
</head>
<body></body>
</html>
"""

RAMP_URL = "https://cdn.intergient.com/1025810/78633/ramp.js"
DEAD_URL = "https://config.playwire.com/1025810/v2/pre_content.js"
EXTRA_URL = "https://cdn.example.com/extra.js"


class TestRefreshDomains(unittest.TestCase):
    def setUp(self):
        self._cwd = os.getcwd()
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.addCleanup(os.chdir, self._cwd)
        self.root = Path(self.tmp.name)
        os.chdir(self.root)
        (self.root / "domains.txt").write_text(
            "cdn.intergient.com\nplaywire.com\n", encoding="utf-8"
        )

    def _run(self, fetch):
        module = load_module("refresh_domains_under_test", TOOLS / "refresh_domains.py")
        out, err = io.StringIO(), io.StringIO()
        with mock.patch.object(module, "fetch", side_effect=fetch) as patched:
            with redirect_stdout(out), redirect_stderr(err):
                code = module.main()
        return code, out.getvalue(), err.getvalue(), [c.args[0] for c in patched.call_args_list]

    def test_dead_url_is_never_fetched(self):
        def fetch(url):
            return FAKE_PAGE.encode()

        code, out, err, called = self._run(fetch)
        self.assertNotIn(DEAD_URL, called, "a permanently 404ing URL should be skipped")
        self.assertIn(RAMP_URL, called)

    def test_slot_page_failure_is_fatal(self):
        def fetch(url):
            raise OSError("connection refused")

        code, out, err, called = self._run(fetch)
        self.assertEqual(code, 2, "losing the slot pages means the watcher cannot see anything")
        self.assertIn("primary", err.lower())

    def test_ramp_failure_is_fatal(self):
        def fetch(url):
            if url in ("https://dtapp.statlocker.gg/?slot=sky",
                       "https://dtapp.statlocker.gg/?slot=med_rect"):
                return FAKE_PAGE.encode()
            raise OSError("404")

        code, out, err, called = self._run(fetch)
        self.assertEqual(code, 2, "ramp.js is the primary ad-config source")
        self.assertIn(RAMP_URL, called)

    def test_extra_script_failure_is_reported_not_fatal(self):
        def fetch(url):
            if url in ("https://dtapp.statlocker.gg/?slot=sky",
                       "https://dtapp.statlocker.gg/?slot=med_rect"):
                return FAKE_PAGE.encode()
            if url == RAMP_URL:
                return b""
            raise OSError("404")

        code, out, err, called = self._run(fetch)
        self.assertIn(EXTRA_URL, called)
        self.assertIn("# fetch failures: 1", err)
        self.assertIn("WARN", err)
        self.assertIn(code, (0, 1), "one dead secondary script must not fail the run")

    def test_uppercase_blocklist_entry_is_recognised(self):
        (self.root / "domains.txt").write_text(
            "CDN.INTERGIENT.COM\nplaywire.com\n", encoding="utf-8"
        )

        def fetch(url):
            return FAKE_PAGE.encode()

        code, out, err, called = self._run(fetch)
        self.assertEqual(code, 0, "an uppercase blocklist entry must still cover its domain")
        self.assertNotIn("cdn.intergient.com", out)

    def test_page_structure_change_is_reported(self):
        # The pages load fine, but the ad-config script can no longer be
        # located. That is a change in Statlocker's pages, not a clean run.
        def fetch(url):
            return b"<html><body>the page looks completely different now</body></html>"

        code, out, err, called = self._run(fetch)
        self.assertEqual(code, 3, "a structure change must not look like a clean run")
        self.assertIn("structure", err.lower())


class TestApplyNewDomains(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        (self.root / "tools").mkdir()
        shutil.copy(TOOLS / "apply_new_domains.py", self.root / "tools" / "apply_new_domains.py")
        (self.root / "domains.txt").write_text("a.example.com\n", encoding="utf-8")
        self.module = load_module("apply_new_domains_under_test",
                                  self.root / "tools" / "apply_new_domains.py")

    def _run(self, domains):
        new = self.root / "new.txt"
        new.write_text("\n".join(domains) + "\n", encoding="utf-8")
        out = io.StringIO()
        with redirect_stdout(out):
            code = self.module.main([str(new)])
        return code

    def test_appends_new_domain(self):
        code = self._run(["b.example.com"])
        self.assertEqual(code, 1)
        self.assertIn("b.example.com", (self.root / "domains.txt").read_text())

    def test_writes_matching_sha256_sidecar(self):
        self._run(["b.example.com"])
        sidecar = self.root / "domains.txt.sha256"
        self.assertTrue(sidecar.exists(), "the blocklist must ship a checksum")
        raw = (self.root / "domains.txt").read_bytes().replace(b"\r\n", b"\n")
        expected = hashlib.sha256(raw).hexdigest()
        self.assertTrue(sidecar.read_text().startswith(expected),
                        "sidecar must hold the sha256 of domains.txt")

    def test_hash_is_updated_when_the_list_changes(self):
        self._run(["b.example.com"])
        first = (self.root / "domains.txt.sha256").read_text()
        self._run(["c.example.com"])
        second = (self.root / "domains.txt.sha256").read_text()
        self.assertNotEqual(first, second)
        raw = (self.root / "domains.txt").read_bytes().replace(b"\r\n", b"\n")
        expected = hashlib.sha256(raw).hexdigest()
        self.assertTrue(second.startswith(expected))

    def test_second_run_is_a_noop(self):
        self._run(["b.example.com"])
        before = (self.root / "domains.txt").read_bytes()
        code = self._run(["b.example.com"])
        self.assertEqual(code, 0)
        self.assertEqual((self.root / "domains.txt").read_bytes(), before)

    def test_malformed_lines_are_skipped(self):
        code = self._run(["b.example.com", "not a domain!!"])
        self.assertEqual(code, 1)
        text = (self.root / "domains.txt").read_text()
        self.assertIn("b.example.com", text)
        self.assertNotIn("not a domain", text)

    def test_only_malformed_lines_is_a_noop(self):
        code = self._run(["not a domain!!"])
        self.assertEqual(code, 0)
        self.assertEqual((self.root / "domains.txt").read_text(), "a.example.com\n")

    def test_sidecar_ignores_crlf(self):
        # A Windows checkout has CRLF in the working copy; GitHub still serves
        # LF. The sidecar has to match what the installer downloads.
        (self.root / "domains.txt").write_bytes(b"a.example.com\r\n")
        self._run(["b.example.com"])
        raw = (self.root / "domains.txt").read_bytes().replace(b"\r\n", b"\n")
        expected = hashlib.sha256(raw).hexdigest()
        self.assertTrue((self.root / "domains.txt.sha256").read_text().startswith(expected))

    def test_write_failure_returns_2(self):
        # The workflow treats exit 1 as "domains appended", so an I/O failure
        # must never look like a success.
        (self.root / "domains.txt").unlink()
        (self.root / "domains.txt").mkdir()
        code = self._run(["b.example.com"])
        self.assertEqual(code, 2)


class TestCommittedSidecar(unittest.TestCase):
    """The sidecar in the repo must match the list in the repo.

    GitHub serves domains.txt exactly as stored, so the check normalises line
    endings the way the installer's download does.
    """

    def test_committed_sidecar_matches_committed_list(self):
        blob = (REPO / "domains.txt").read_bytes().replace(b"\r\n", b"\n")
        expected = hashlib.sha256(blob).hexdigest()
        sidecar = REPO / "domains.txt.sha256"
        self.assertTrue(sidecar.exists(), "domains.txt.sha256 must be committed")
        self.assertTrue(
            sidecar.read_text(encoding="utf-8").startswith(expected),
            "domains.txt.sha256 does not match domains.txt",
        )


class TestCommittedList(unittest.TestCase):
    """The committed blocklist has to stay installable.

    `adblock.ps1` validates every line before it writes the section, so one
    malformed entry would make every install refuse the bundled list.
    """

    def test_every_committed_line_is_a_plain_domain(self):
        pattern = re.compile(r"^[a-z0-9][a-z0-9\-]*(\.[a-z0-9\-]+)+$")
        for line in (REPO / "domains.txt").read_text(encoding="utf-8").splitlines():
            entry = line.strip()
            if not entry or entry.startswith("#"):
                continue
            self.assertRegex(entry, pattern, "not a plain domain name: %r" % entry)
