#!/usr/bin/env python3
"""Output-based tests for crap.py at its command line, plus the imported
function the join calls directly."""

from __future__ import annotations

import importlib.util
import subprocess
import sys
import unittest
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
SCRIPT = SCRIPT_DIR / "crap.py"

_spec = importlib.util.spec_from_file_location("crap", SCRIPT)
assert _spec is not None and _spec.loader is not None
crap_module = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(crap_module)


def run(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, str(SCRIPT), *args],
        capture_output=True,
        text=True,
        check=False,
    )


class CommandLineTests(unittest.TestCase):
    def test_uncovered_complexity_five_is_thirty(self) -> None:
        result = run("--comp", "5", "--cov", "0")
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout.strip(), "30")

    def test_fully_covered_complexity_five_is_five(self) -> None:
        self.assertEqual(run("--comp", "5", "--cov", "100").stdout.strip(), "5")

    def test_null_coverage_is_null_never_zero(self) -> None:
        result = run("--comp", "5", "--cov", "null")
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout.strip(), "null")

    def test_uncovered_complexity_thirty_is_nine_hundred_and_thirty(self) -> None:
        self.assertEqual(run("--comp", "30", "--cov", "0").stdout.strip(), "930")

    def test_half_covered_complexity_five_keeps_its_decimals(self) -> None:
        self.assertEqual(run("--comp", "5", "--cov", "50").stdout.strip(), "8.125")

    def test_zero_complexity_is_zero_at_any_coverage(self) -> None:
        self.assertEqual(run("--comp", "0", "--cov", "0").stdout.strip(), "0")


class UsageTests(unittest.TestCase):
    def test_a_missing_option_is_a_usage_error(self) -> None:
        self.assertEqual(run("--comp", "5").returncode, 2)
        self.assertEqual(run().returncode, 2)

    def test_a_coverage_above_one_hundred_is_a_usage_error(self) -> None:
        result = run("--comp", "5", "--cov", "101")
        self.assertEqual(result.returncode, 2)
        self.assertIn("percentage", result.stderr)

    def test_a_negative_coverage_is_a_usage_error(self) -> None:
        self.assertEqual(run("--comp", "5", "--cov", "-1").returncode, 2)

    def test_a_negative_complexity_is_a_usage_error(self) -> None:
        result = run("--comp", "-3", "--cov", "0")
        self.assertEqual(result.returncode, 2)
        self.assertIn("negative", result.stderr)

    def test_a_coverage_that_is_not_a_number_is_a_usage_error(self) -> None:
        self.assertEqual(run("--comp", "5", "--cov", "most of it").returncode, 2)


class ImportedFunctionTests(unittest.TestCase):
    def test_the_function_matches_the_command_line(self) -> None:
        self.assertEqual(crap_module.crap(5, 0), 30)
        self.assertEqual(crap_module.crap(5, 100), 5)
        self.assertIsNone(crap_module.crap(5, None))
        self.assertAlmostEqual(crap_module.crap(3, 50), 4.125)

    def test_render_matches_the_printed_form(self) -> None:
        self.assertEqual(crap_module.render(None), "null")
        self.assertEqual(crap_module.render(12.0), "12")
        self.assertEqual(crap_module.render(8.125), "8.125")
        self.assertEqual(crap_module.render(4.1256), "4.126")


if __name__ == "__main__":
    unittest.main()
