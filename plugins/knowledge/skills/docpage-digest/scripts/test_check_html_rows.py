#!/usr/bin/env python3
"""Negative-control suite for check-html-rows.py.

PASS is not believed until the known-bad fixtures fail. The fixtures under
fixtures/html-rows/ are synthetic; cases that need no committed file write a
temp digest instead.

Run: python test_check_html_rows.py
"""

from __future__ import annotations

import os
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
GATE = os.path.join(HERE, "check-html-rows.py")
FIXTURES = os.path.join(HERE, "fixtures", "html-rows")
SOURCE = os.path.join(FIXTURES, "source.html")


def fixture(name: str) -> str:
    return os.path.join(FIXTURES, name)


def run(*args: str):
    return subprocess.run(
        [sys.executable, GATE, *args],
        capture_output=True,
        encoding="utf-8",
        check=False,
    )


class TempDigest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()

    def tearDown(self):
        self.tmp.cleanup()

    def digest(self, text: str) -> str:
        path = os.path.join(self.tmp.name, "digest.md")
        with open(path, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(text)
        return path


class TestGoodRows(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.proc = run(SOURCE, fixture("good-rows.md"))
        cls.lines = cls.proc.stdout.splitlines()

    def test_exits_zero(self):
        self.assertEqual(self.proc.returncode, 0, self.proc.stdout)

    def test_exact_row(self):
        self.assertIn("EXACT good-rows.md F1 (line 3)", self.lines)

    def test_join_row_counts_declared_truncations(self):
        self.assertIn(
            "JOIN good-rows.md F2 (line 9): 7 line(s), each a text node or "
            "attribute value; 2 declared truncation line(s)",
            self.lines,
        )

    def test_summary(self):
        self.assertEqual(self.lines[-1], "2 F row(s) checked, 0 failure(s)")


class TestBadRows(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.proc = run(SOURCE, fixture("bad-rows.md"))
        cls.lines = cls.proc.stdout.splitlines()

    def test_exits_one(self):
        self.assertEqual(self.proc.returncode, 1, self.proc.stdout)

    def test_fabricated_join_line_fails(self):
        self.assertIn(
            "FAIL bad-rows.md F1 (line 3): 1 line(s) not a text node or "
            "attribute value, first 'This line is not in source.html'",
            self.lines,
        )

    def test_label_with_no_fence_fails(self):
        self.assertIn("FAIL bad-rows.md F2 (line 10): no fence follows the label", self.lines)

    def test_trailing_space_line_fails(self):
        self.assertIn(
            "FAIL bad-rows.md F3 (line 14): 1 line(s) not a text node or "
            "attribute value, first 'Readings taken at dawn '",
            self.lines,
        )

    def test_summary(self):
        self.assertEqual(self.lines[-1], "3 F row(s) checked, 3 failure(s)")


class TestZeroRows(TempDigest):
    def test_zero_f_rows_fails(self):
        proc = run(SOURCE, fixture("zero-rows.md"))
        self.assertEqual(proc.returncode, 1)
        self.assertEqual(proc.stdout, "0 F row(s) checked, 0 failure(s)\n")

    def test_empty_digest_fails(self):
        proc = run(SOURCE, self.digest(""))
        self.assertEqual(proc.returncode, 1)
        self.assertEqual(proc.stdout, "0 F row(s) checked, 0 failure(s)\n")


class TestEmptyPayload(TempDigest):
    def assert_empty_fails(self, body: str):
        proc = run(SOURCE, self.digest(f"**F1.** empty\n\n```text\n{body}```\n"))
        self.assertEqual(proc.returncode, 1, proc.stdout)
        self.assertIn(
            "FAIL digest.md F1 (line 1): fence payload is empty or only truncation marks, not a quote",
            proc.stdout,
        )

    def test_immediately_closed_fence_fails(self):
        self.assert_empty_fails("")

    def test_blank_line_fence_fails(self):
        self.assert_empty_fails("\n")

    def test_ellipsis_only_fence_fails(self):
        self.assert_empty_fails("...\n")


class TestFenceShape(TempDigest):
    def test_indented_fence_is_no_fence(self):
        text = "**F1.** indented\n\n    ```text\n    North\n    ```\n"
        proc = run(SOURCE, self.digest(text))
        self.assertEqual(proc.returncode, 1)
        self.assertIn("FAIL digest.md F1 (line 1): no fence follows the label", proc.stdout)

    def test_c_label_stops_the_fence_search(self):
        text = "**F1.** no fence of its own\n\n**C1.** next row\n\n```text\nNorth\n```\n"
        proc = run(SOURCE, self.digest(text))
        self.assertEqual(proc.returncode, 1)
        self.assertIn("FAIL digest.md F1 (line 1): no fence follows the label", proc.stdout)


class TestCliSurface(TempDigest):
    def test_help_exits_zero(self):
        proc = run("--help")
        self.assertEqual(proc.returncode, 0)
        self.assertIn("exit codes:", proc.stdout)
        self.assertEqual(proc.stderr, "")

    def test_missing_digest_is_usage_error(self):
        proc = run(SOURCE)
        self.assertEqual(proc.returncode, 2)
        self.assertEqual(proc.stdout, "")

    def test_unreadable_source_exits_two_without_traceback(self):
        proc = run(os.path.join(self.tmp.name, "absent.html"), fixture("good-rows.md"))
        self.assertEqual(proc.returncode, 2)
        self.assertIn("cannot read", proc.stderr)
        self.assertNotIn("Traceback", proc.stderr)

    def test_unreadable_digest_exits_two_without_traceback(self):
        proc = run(SOURCE, os.path.join(self.tmp.name, "absent.md"))
        self.assertEqual(proc.returncode, 2)
        self.assertIn("cannot read", proc.stderr)
        self.assertNotIn("Traceback", proc.stderr)

    def test_non_utf8_digest_exits_two(self):
        path = os.path.join(self.tmp.name, "latin1.md")
        with open(path, "wb") as fh:
            fh.write(b"**F1.** na\xefve\n")
        proc = run(SOURCE, path)
        self.assertEqual(proc.returncode, 2)
        self.assertNotIn("Traceback", proc.stderr)


if __name__ == "__main__":
    unittest.main()
