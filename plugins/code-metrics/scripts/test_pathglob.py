#!/usr/bin/env python3
"""Output-based tests for pathglob.py, driven at its command line and, for the
pure translator, through the module loaded by path (its name is importable,
but the subprocess seam is the contract every caller uses)."""

from __future__ import annotations

import importlib.util
import subprocess
import sys
import unittest
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
SCRIPT = SCRIPT_DIR / "pathglob.py"

_spec = importlib.util.spec_from_file_location("pathglob", SCRIPT)
assert _spec is not None and _spec.loader is not None
pathglob = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(pathglob)


def run(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, str(SCRIPT), *args],
        capture_output=True,
        text=True,
        check=False,
    )


class TranslateTests(unittest.TestCase):
    def test_bare_extension_matches_at_any_depth(self) -> None:
        self.assertTrue(pathglob.matches("*.sh", "a/b/c.sh"))
        self.assertTrue(pathglob.matches("*.sh", "c.sh"))
        self.assertFalse(pathglob.matches("*.sh", "a/b/c.bash"))

    def test_star_never_crosses_a_separator(self) -> None:
        self.assertTrue(pathglob.matches("src/*.ts", "src/a.ts"))
        self.assertFalse(pathglob.matches("src/*.ts", "src/sub/a.ts"))

    def test_double_star_matches_zero_or_more_segments(self) -> None:
        self.assertTrue(pathglob.matches("src/**/*.ts", "src/a.ts"))
        self.assertTrue(pathglob.matches("src/**/*.ts", "src/x/y/a.ts"))
        self.assertFalse(pathglob.matches("src/**/*.ts", "lib/a.ts"))
        self.assertTrue(pathglob.matches("**/vendor/**", "a/vendor/b/c.py"))
        self.assertTrue(pathglob.matches("**/*.sh", "deep/nested/x.sh"))

    def test_anchored_pattern_stays_at_the_root(self) -> None:
        self.assertTrue(pathglob.matches("/scripts/*.py", "scripts/a.py"))
        self.assertFalse(pathglob.matches("/scripts/*.py", "x/scripts/a.py"))

    def test_question_mark_and_classes(self) -> None:
        self.assertTrue(pathglob.matches("a?.go", "ab.go"))
        self.assertFalse(pathglob.matches("a?.go", "abc.go"))
        self.assertTrue(pathglob.matches("*.[ch]", "x/y.c"))
        self.assertFalse(pathglob.matches("*.[!ch]", "x/y.c"))

    def test_windows_separators_and_dot_slash_are_normalized(self) -> None:
        self.assertTrue(pathglob.matches("src/**/*.ts", "src\\a\\b.ts"))
        self.assertTrue(pathglob.matches("src/*.ts", "./src/a.ts"))


class CommandLineTests(unittest.TestCase):
    def test_prints_matching_paths_in_order(self) -> None:
        result = run("*.py", "a.py", "b.sh", "c/d.py")
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout.splitlines(), ["a.py", "c/d.py"])

    def test_any_mode_exit_codes(self) -> None:
        self.assertEqual(run("--any", "*.py", "a.py", "b.sh").returncode, 0)
        self.assertEqual(run("--any", "*.py", "b.sh").returncode, 1)

    def test_usage_error(self) -> None:
        result = run("*.py")
        self.assertEqual(result.returncode, 2)
        self.assertIn("usage", result.stderr)

    def test_an_unusable_glob_is_a_named_error_not_a_traceback(self) -> None:
        # A consumer writes these by hand in an ecosystem file. A traceback
        # would be unreadable, and a zero exit would let the caller read
        # "matched nothing" as an answer.
        result = run("[z-a]", "a.py")
        self.assertEqual(result.returncode, 2)
        self.assertIn("[z-a]", result.stderr)
        self.assertIn("not a usable glob", result.stderr)
        self.assertNotIn("Traceback", result.stderr)
        self.assertEqual(result.stdout, "")


if __name__ == "__main__":
    unittest.main()
