#!/usr/bin/env python3
"""Output-based tests for scope-filter.py at its command line."""

from __future__ import annotations

import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
SCRIPT = SCRIPT_DIR / "scope-filter.py"


def run(listing: str, cwd: Path) -> subprocess.CompletedProcess:
    paths = cwd / "paths.txt"
    paths.write_text(listing, encoding="utf-8")
    return subprocess.run(
        [sys.executable, str(SCRIPT), "--paths-from", str(paths)],
        capture_output=True,
        text=True,
        cwd=cwd,
        check=False,
    )


class ScopeFilterTests(unittest.TestCase):
    def test_normalizes_dedupes_and_keeps_regular_text_files_in_order(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "src").mkdir()
            (root / "src" / "a.py").write_text("print(1)\n", encoding="utf-8")
            (root / "b.sh").write_text("echo\n", encoding="utf-8")
            (root / "img.png").write_bytes(b"\x89PNG\0\0binary")
            listing = "./src/a.py\r\nsrc\\a.py\nb.sh\nsrc\nmissing.py\nimg.png\n\nb.sh\n"
            result = run(listing, root)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.split("\n"), ["src/a.py", "b.sh", ""])

    def test_a_dangling_symlink_is_dropped(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            try:
                os.symlink(root / "gone.py", root / "link.py")
            except (OSError, NotImplementedError):
                self.skipTest("symlinks are not available here")
            result = run("link.py\n", root)
            self.assertEqual(result.stdout, "")

    def test_usage_error_exits_2(self) -> None:
        result = subprocess.run(
            [sys.executable, str(SCRIPT)], capture_output=True, text=True, check=False
        )
        self.assertEqual(result.returncode, 2)
        self.assertIn("usage", result.stderr)


if __name__ == "__main__":
    unittest.main()
