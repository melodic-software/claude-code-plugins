#!/usr/bin/env python3
"""Tests for the shared `--paths-from` transport every adapter's collect verb
reads, through the module loaded by path and through one adapter's command
line (the bundled line counter, which has no tool to stub)."""

from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
HELPER = SCRIPT_DIR / "adapter_paths.py"
LINE_COUNTER = SCRIPT_DIR / "line-counter.py"

_spec = importlib.util.spec_from_file_location("adapter_paths", HELPER)
assert _spec is not None and _spec.loader is not None
adapter_paths = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(adapter_paths)


class FilesFromTests(unittest.TestCase):
    def test_positional_paths_pass_through_unchanged(self) -> None:
        self.assertEqual(
            adapter_paths.files_from(["a.py", "b/c.sh"]), ["a.py", "b/c.sh"]
        )

    def test_the_listing_expands_in_place_and_combines_with_positionals(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            listing = Path(tmp) / "files"
            listing.write_text("one.md\n\ntwo.json\n", encoding="utf-8")
            self.assertEqual(
                adapter_paths.files_from(
                    ["zero.py", "--paths-from", str(listing), "three.sh"]
                ),
                ["zero.py", "one.md", "two.json", "three.sh"],
            )

    def test_a_non_utf8_filename_survives_the_listing(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            listing = Path(tmp) / "files"
            listing.write_bytes(b"latin1-\xe9.py\n")
            [path] = adapter_paths.files_from(["--paths-from", str(listing)])
            self.assertEqual(path.encode("utf-8", "surrogateescape"), b"latin1-\xe9.py")

    def test_a_missing_value_or_listing_exits_2(self) -> None:
        with self.assertRaises(SystemExit) as caught:
            adapter_paths.files_from(["--paths-from"])
        self.assertEqual(caught.exception.code, 2)
        with self.assertRaises(SystemExit) as caught:
            adapter_paths.files_from(["--paths-from", "/nonexistent/listing"])
        self.assertEqual(caught.exception.code, 2)


class AdapterCommandLineTests(unittest.TestCase):
    def test_the_line_counter_reads_its_files_from_the_listing(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            (Path(tmp) / "a.md").write_text("# a\n\nline\n", encoding="utf-8")
            (Path(tmp) / "b.txt").write_text("x\n", encoding="utf-8")
            listing = Path(tmp) / "files"
            listing.write_text(f"{tmp}/a.md\n{tmp}/b.txt\n", encoding="utf-8")
            result = subprocess.run(
                [
                    sys.executable,
                    str(LINE_COUNTER),
                    "collect",
                    "other",
                    "file_lines",
                    "--paths-from",
                    str(listing),
                ],
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            rows = [json.loads(line) for line in result.stdout.splitlines()]
            self.assertEqual(
                [
                    (r["file"].rsplit("/", 1)[1], r["values"]["lines_non_blank"])
                    for r in rows
                ],
                [("a.md", 2), ("b.txt", 1)],
            )


if __name__ == "__main__":
    unittest.main()
