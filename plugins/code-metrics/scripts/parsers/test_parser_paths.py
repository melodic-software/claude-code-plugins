#!/usr/bin/env python3
"""Tests for the readers every coverage parser in this directory shares, through
the module loaded by path and through one parser's command line (the lcov
parser, whose fixtures exercise both readers on the same run)."""

from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
HELPER = SCRIPT_DIR / "parser_paths.py"
LCOV = SCRIPT_DIR / "lcov.py"

_spec = importlib.util.spec_from_file_location("parser_paths", HELPER)
assert _spec is not None and _spec.loader is not None
parser_paths = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(parser_paths)


class NormTests(unittest.TestCase):
    def test_backslashes_fold_and_surrounding_whitespace_goes(self) -> None:
        self.assertEqual(parser_paths.norm("  src\\pkg\\a.py \n"), "src/pkg/a.py")

    def test_every_leading_dot_slash_is_removed(self) -> None:
        self.assertEqual(parser_paths.norm("././a.py"), "a.py")

    def test_an_absolute_path_and_a_dot_dot_component_are_left_alone(self) -> None:
        self.assertEqual(parser_paths.norm("/tmp/../a.py"), "/tmp/../a.py")


class ToIntTests(unittest.TestCase):
    def test_a_spelled_integer_is_read_with_its_whitespace_stripped(self) -> None:
        self.assertEqual(parser_paths.to_int(" 42 "), 42)

    def test_a_non_integer_and_an_absent_field_are_both_none(self) -> None:
        self.assertIsNone(parser_paths.to_int("1.5"))
        self.assertIsNone(parser_paths.to_int(""))
        self.assertIsNone(parser_paths.to_int(None))


class ParserCommandLineTests(unittest.TestCase):
    def test_a_parser_run_as_a_subprocess_resolves_the_shared_module(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tracefile = Path(tmp) / "coverage.info"
            tracefile.write_text(
                "SF:.\\src\\a.ts\nDA: 1 , 3 \nDA:2,0\nend_of_record\n",
                encoding="utf-8",
            )
            result = subprocess.run(
                [sys.executable, str(LCOV), str(tracefile)],
                capture_output=True,
                text=True,
                check=False,
                cwd=tmp,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(
                json.loads(result.stdout),
                {"src/a.ts": {"lines": {"1": 3, "2": 0}, "functions": None}},
            )


if __name__ == "__main__":
    unittest.main()
