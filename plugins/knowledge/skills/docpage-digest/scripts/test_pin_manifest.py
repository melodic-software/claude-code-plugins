#!/usr/bin/env python3
"""Suite for pin-manifest.py over a temporary slice.

Run: python test_pin_manifest.py
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "pin-manifest.py")


class PinManifestCase(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp(prefix="pin-manifest-")
        self.addCleanup(shutil.rmtree, self.root, True)
        self.put("source.md", "# Page\n")
        self.put("source.html", "<p>Page</p>\n")
        self.put("SOURCES.md", "---\nabstract: one page\n---\n")
        self.put("digests/01-intro.md", "# Intro\n")
        self.put("digests/02-usage.md", "# Usage\n")
        self.put("digests/notes.txt", "not frozen\n")
        self.put("checklist.md", "not frozen\n")

    def put(self, rel, text):
        path = os.path.join(self.root, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(text)

    def run_script(self, *extra):
        return subprocess.run(
            [sys.executable, SCRIPT, self.root, *extra], capture_output=True, text=True, check=False
        )

    def manifest(self):
        with open(os.path.join(self.root, "verification", "pin-manifest.json"), encoding="utf-8") as fh:
            return json.load(fh)


class TestWrite(PinManifestCase):
    def test_writes_schema_and_frozen_set(self):
        proc = self.run_script()
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("PINNED 5 files", proc.stdout)
        data = self.manifest()
        self.assertEqual(data["schema"], "docpage-pin/v1")
        self.assertEqual(data["pinned_on"], "agent-reported-completion")
        self.assertRegex(data["pinned_at"], r"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$")
        paths = [entry["path"] for entry in data["files"]]
        self.assertEqual(
            paths,
            ["source.html", "source.md", "SOURCES.md", "digests/01-intro.md", "digests/02-usage.md"],
        )

    def test_hashes_are_sha256_of_bytes(self):
        self.run_script()
        expected = hashlib.sha256(b"# Intro\n").hexdigest()
        entry = next(e for e in self.manifest()["files"] if e["path"] == "digests/01-intro.md")
        self.assertEqual(entry["sha256"], expected)
        self.assertTrue(all(re.fullmatch(r"[0-9a-f]{64}", e["sha256"]) for e in self.manifest()["files"]))

    def test_refuses_slice_without_digests(self):
        shutil.rmtree(os.path.join(self.root, "digests"))
        proc = self.run_script()
        self.assertEqual(proc.returncode, 2)
        self.assertIn("digests/*.md", proc.stderr)
        self.assertFalse(os.path.exists(os.path.join(self.root, "verification")))

    def test_refuses_missing_inventory_and_source(self):
        os.remove(os.path.join(self.root, "SOURCES.md"))
        os.remove(os.path.join(self.root, "source.md"))
        os.remove(os.path.join(self.root, "source.html"))
        proc = self.run_script()
        self.assertEqual(proc.returncode, 2)
        self.assertIn("source.*", proc.stderr)
        self.assertIn("SOURCES.md", proc.stderr)

    def test_usage_errors(self):
        self.assertEqual(self.run_script("--bogus").returncode, 2)
        missing = subprocess.run(
            [sys.executable, SCRIPT, os.path.join(self.root, "absent")],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(missing.returncode, 2)


class TestCheck(PinManifestCase):
    def test_match_after_write(self):
        self.run_script()
        proc = self.run_script("--check")
        self.assertEqual(proc.returncode, 0, proc.stdout)
        self.assertIn("MATCH 5 files", proc.stdout)

    def test_blocks_on_changed_new_and_missing(self):
        self.run_script()
        self.put("digests/01-intro.md", "# Intro, edited mid-audit\n")
        self.put("digests/03-late.md", "# Late\n")
        os.remove(os.path.join(self.root, "source.html"))
        proc = self.run_script("--check")
        self.assertEqual(proc.returncode, 1)
        self.assertIn("BLOCKED: changed digests/01-intro.md", proc.stdout)
        self.assertIn("BLOCKED: new digests/03-late.md", proc.stdout)
        self.assertIn("BLOCKED: missing source.html", proc.stdout)

    def test_check_without_manifest_is_an_error(self):
        proc = self.run_script("--check")
        self.assertEqual(proc.returncode, 2)
        self.assertIn("cannot read", proc.stderr)


if __name__ == "__main__":
    unittest.main()
