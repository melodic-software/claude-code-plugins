#!/usr/bin/env python3
"""Output-based tests for text-files.py at its command line, plus the pure
predicate through the module loaded by path."""

from __future__ import annotations

import importlib.util
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
SCRIPT = SCRIPT_DIR / "text-files.py"

_spec = importlib.util.spec_from_file_location("text_files", SCRIPT)
assert _spec is not None and _spec.loader is not None
text_files = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(text_files)


def run(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, str(SCRIPT), *args],
        capture_output=True,
        text=True,
        check=False,
    )


class PredicateTests(unittest.TestCase):
    def test_text_binary_directory_and_missing(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            text = Path(tmp) / "a.py"
            text.write_bytes(b"x = 1\n")
            binary = Path(tmp) / "b.bin"
            binary.write_bytes(b"\x89PNG\0\0" + b"\0" * 10)
            late_nul = Path(tmp) / "c.txt"
            late_nul.write_bytes(b"a" * (text_files.SNIFF_BYTES + 5) + b"\0")
            self.assertTrue(text_files.is_text_file(str(text)))
            self.assertFalse(text_files.is_text_file(str(binary)))
            self.assertTrue(
                text_files.is_text_file(str(late_nul)),
                "a NUL after the sniff window is not seen, as with grep -I",
            )
            self.assertFalse(text_files.is_text_file(tmp), "a directory is not a file")
            self.assertFalse(text_files.is_text_file(str(Path(tmp) / "missing.py")))

    @unittest.skipIf(
        os.name != "posix" or os.geteuid() == 0, "needs a non-root POSIX user"
    )
    def test_an_unreadable_file_is_kept_for_the_collector_to_report(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            locked = Path(tmp) / "locked.py"
            locked.write_bytes(b"x = 1\n")
            locked.chmod(0)
            try:
                self.assertTrue(text_files.is_text_file(str(locked)))
            finally:
                locked.chmod(0o644)


class CommandLineTests(unittest.TestCase):
    def test_filters_a_listing_in_order_and_ignores_blank_lines(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            (Path(tmp) / "z.sh").write_bytes(b"echo\n")
            (Path(tmp) / "a.md").write_bytes(b"# t\n")
            (Path(tmp) / "img.png").write_bytes(b"\0\0")
            listing = Path(tmp) / "list"
            listing.write_text(
                f"{tmp}/z.sh\n\n{tmp}/img.png\n{tmp}/a.md\n{tmp}/gone.py\n",
                encoding="utf-8",
            )
            result = run("--paths-from", str(listing))
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout, f"{tmp}/z.sh\n{tmp}/a.md\n")

    def test_usage_and_missing_listing_exit_2(self) -> None:
        self.assertEqual(run().returncode, 2)
        self.assertEqual(run("a.py").returncode, 2)
        result = run("--paths-from", "/nonexistent/listing")
        self.assertEqual(result.returncode, 2)
        self.assertIn("text-files.py:", result.stderr)


if __name__ == "__main__":
    unittest.main()
