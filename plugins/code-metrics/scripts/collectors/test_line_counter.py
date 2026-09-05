#!/usr/bin/env python3
"""Output-based tests for the bundled line counter at its command line."""

from __future__ import annotations

import json
import os
import subprocess
import sys
import unittest
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
SCRIPT = SCRIPT_DIR / "line-counter.py"
SOURCES = SCRIPT_DIR.parent / "fixtures" / "sources"


def run(*args: str, env: dict | None = None) -> subprocess.CompletedProcess:
    merged = dict(os.environ)
    merged.pop("CODE_METRICS_DISABLE_BUNDLED", None)
    if env:
        merged.update(env)
    return subprocess.run(
        [sys.executable, str(SCRIPT), *args],
        capture_output=True,
        text=True,
        env=merged,
        check=False,
    )


class LineCounterTests(unittest.TestCase):
    def test_probe_is_bundled_unless_disabled(self) -> None:
        result = run("probe")
        self.assertEqual((result.returncode, result.stdout.strip()), (0, "bundled"))
        result = run("probe", env={"CODE_METRICS_DISABLE_BUNDLED": "1"})
        self.assertEqual(result.returncode, 1)

    def test_measures_and_install_hint(self) -> None:
        self.assertEqual(run("measures").stdout.strip(), "*/file_lines")
        self.assertIn("bundled", run("install_hint").stdout)

    def test_collect_counts_total_and_blank_lines(self) -> None:
        sample = SOURCES / "cm-sample.sh"
        result = run("collect", "bash", "file_lines", str(sample))
        self.assertEqual(result.returncode, 0, result.stderr)
        row = json.loads(result.stdout.strip())
        expected_total = len(sample.read_bytes().splitlines())
        expected_blank = sum(
            1 for line in sample.read_bytes().splitlines() if not line.strip()
        )
        self.assertEqual(
            row["values"],
            {
                "lines_total": expected_total,
                "lines_blank": expected_blank,
                "lines_non_blank": expected_total - expected_blank,
            },
        )
        self.assertEqual(row["lane"], "bash")
        self.assertIsNone(row["function"])
        self.assertEqual(row["labels"], ["comment-agnostic"])
        self.assertEqual(row["collector"], "line-counter")

    def test_collect_rejects_other_measures_and_missing_files(self) -> None:
        self.assertEqual(
            run(
                "collect", "bash", "cyclomatic", str(SOURCES / "cm-sample.sh")
            ).returncode,
            2,
        )
        self.assertEqual(
            run("collect", "bash", "file_lines", str(SOURCES / "nope.sh")).returncode, 3
        )


if __name__ == "__main__":
    unittest.main()
