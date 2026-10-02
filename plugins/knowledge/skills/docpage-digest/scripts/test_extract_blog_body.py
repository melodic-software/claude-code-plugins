#!/usr/bin/env python3
"""Fixture suite for extract_blog_body.py.

Runs the extractor as a subprocess over fixtures/blog-body.html, a hand-made
page in the claude.dev blog layout, and checks the markdown it writes.

Run: python test_extract_blog_body.py
"""

from __future__ import annotations

import importlib.util
import os
import re
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
EXTRACTOR = os.path.join(HERE, "extract_blog_body.py")
FIXTURE = os.path.join(HERE, "fixtures", "blog-body.html")

WIDGET_LABELS = ("Copy", "CODE", "Play video", "Pause")
SEPARATOR = re.compile(r"^\|( *:?-{3,}:? *\|)+$")


def extract() -> str:
    with tempfile.TemporaryDirectory() as tmp:
        out = os.path.join(tmp, "source.md")
        proc = subprocess.run(
            [sys.executable, EXTRACTOR, FIXTURE, out],
            capture_output=True,
            check=False,
        )
        if proc.returncode != 0:
            raise AssertionError(f"extractor exited {proc.returncode}: {proc.stderr.decode()}")
        with open(out, encoding="utf-8") as fh:
            return fh.read()


class TestExtractBlogBody(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.text = extract()
        cls.lines = cls.text.splitlines()

    def test_table_has_separator_row(self):
        header = self.lines.index("| Bed | Moisture |")
        self.assertRegex(self.lines[header + 1], SEPARATOR)
        self.assertEqual(self.lines[header + 2], "| North | 31% |")

    def test_paragraphs_inside_cells_stay_in_the_table(self):
        self.assertIn("| East | 24% |", self.lines)
        self.assertNotIn("East", [line for line in self.lines if not line.startswith("|")])

    def test_paragraphs_inside_list_items_keep_the_bullet(self):
        first = self.lines.index("- Check the rain gauge first.")
        self.assertIn("  Skip watering after rain.", self.lines[first + 1 :])
        self.assertIn("- Log every reading.", self.lines)

    def test_no_widget_or_video_label_text(self):
        for label in WIDGET_LABELS:
            with self.subTest(label=label):
                self.assertNotIn(label, self.text)

    def test_no_fence_opened_by_blank_line(self):
        opened = False
        fences = 0
        for i, line in enumerate(self.lines):
            if line.startswith("```"):
                if not opened:
                    fences += 1
                    self.assertNotEqual(self.lines[i + 1].strip(), "", f"fence at line {i + 1}")
                opened = not opened
        self.assertEqual(fences, 1)
        self.assertFalse(opened, "unclosed fence")

    def test_code_payload_is_exact(self):
        self.assertIn(
            "```python\ndef needs_water(reading):\n    return reading < 20\n```\n", self.text
        )

    def test_body_is_sliced(self):
        self.assertTrue(self.text.startswith("# Watering a garden with sensors\n"))
        self.assertIn("The last paragraph of the body.", self.text)
        self.assertNotIn("Site nav text", self.text)
        self.assertNotIn("Related", self.text)

    def test_inline_markup_lists_and_media(self):
        self.assertIn("**bold**, _italic_, `inline_code`", self.text)
        self.assertIn("[link to a soil page](https://example.com/soil)", self.text)
        self.assertIn("- Read each sensor once an hour.", self.lines)
        self.assertIn("  1. Open the valve.", self.lines)
        self.assertIn("[CAPTION] **VIDEO** The valve opening on the south bed.", self.lines)
        self.assertTrue(any(line.startswith("[VIDEO src='/media/valve.mp4'") for line in self.lines))

    def test_import_runs_nothing(self):
        spec = importlib.util.spec_from_file_location("extract_blog_body", EXTRACTOR)
        module = importlib.util.module_from_spec(spec)
        argv = sys.argv
        sys.argv = [EXTRACTOR]
        try:
            spec.loader.exec_module(module)
        finally:
            sys.argv = argv
        self.assertTrue(callable(module.main))


if __name__ == "__main__":
    unittest.main()
