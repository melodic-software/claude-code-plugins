#!/usr/bin/env python3
"""Output-based tests for go_cover.py, driven at its command line.

The committed fixture is `../fixtures/coverage/go-cover.out`, a `mode: set`
profile for the Go fixture source under the module path the compiler would
have seen. Count-mode and malformed profiles are written into a temporary
directory.
"""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
SCRIPT = SCRIPT_DIR / "go_cover.py"
FIXTURE = SCRIPT_DIR.parent / "fixtures" / "coverage" / "go-cover.out"
MODULE_PATH = "example.com/cmsample/cm-sample.go"


def run(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, str(SCRIPT), *args],
        capture_output=True,
        text=True,
        check=False,
    )


def parsed(*args: str) -> dict:
    result = run(*args)
    assert result.returncode == 0, result.stderr
    return json.loads(result.stdout)


def write(tmp: str, name: str, body: str) -> str:
    path = Path(tmp) / name
    path.write_text(body, encoding="utf-8")
    return str(path)


class FixtureTests(unittest.TestCase):
    def test_a_block_covers_every_line_of_its_range(self) -> None:
        document = parsed(str(FIXTURE))
        self.assertEqual(list(document), [MODULE_PATH])
        lines = document[MODULE_PATH]["lines"]
        self.assertEqual(lines["9"], 1)
        self.assertEqual(lines["12"], 0)
        self.assertEqual(sorted(int(k) for k in lines), [7, 8, 9, 10, 11, 12, 13, 14])

    def test_an_overlapping_block_keeps_the_larger_count(self) -> None:
        # Line 13 closes the uncovered block and opens the covered one.
        self.assertEqual(parsed(str(FIXTURE))[MODULE_PATH]["lines"]["13"], 1)

    def test_a_profile_names_no_functions(self) -> None:
        self.assertIsNone(parsed(str(FIXTURE))[MODULE_PATH]["functions"])


class ModeTests(unittest.TestCase):
    def test_count_mode_keeps_the_real_execution_count(self) -> None:
        body = "mode: count\nm/a.go:1.1,3.2 2 17\n"
        with tempfile.TemporaryDirectory() as tmp:
            document = parsed(write(tmp, "count.out", body))
        self.assertEqual(document["m/a.go"]["lines"], {"1": 17, "2": 17, "3": 17})

    def test_a_profile_without_a_mode_header_exits_2(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run(write(tmp, "headless.out", "m/a.go:1.1,2.2 1 1\n"))
        self.assertEqual(result.returncode, 2)
        self.assertIn("mode:", result.stderr)

    def test_an_unparsable_block_line_is_skipped_not_fatal(self) -> None:
        body = "mode: set\nnot a block line\nm/a.go:1.1,1.2 1 1\n"
        with tempfile.TemporaryDirectory() as tmp:
            document = parsed(write(tmp, "noise.out", body))
        self.assertEqual(document["m/a.go"]["lines"], {"1": 1})

    def test_usage_error_without_an_artifact(self) -> None:
        result = run()
        self.assertEqual(result.returncode, 2)
        self.assertIn("usage", result.stderr)


if __name__ == "__main__":
    unittest.main()
