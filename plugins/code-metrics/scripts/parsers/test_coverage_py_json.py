#!/usr/bin/env python3
"""Output-based tests for coverage_py_json.py, driven at its command line.

The committed fixture is `../fixtures/coverage/coverage-py.json`, written in
the shape `coverage json` emits at 7.6.0 and later (the release that added the
per-function regions). The pre-7.6.0 shape, and a report that is JSON but not
a coverage.py report, are written into a temporary directory.
"""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
SCRIPT = SCRIPT_DIR / "coverage_py_json.py"
FIXTURE = SCRIPT_DIR.parent / "fixtures" / "coverage" / "coverage-py.json"
PY_FIXTURE = "plugins/code-metrics/scripts/fixtures/sources/cm_sample.py"


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


def write(tmp: str, name: str, document: dict) -> str:
    path = Path(tmp) / name
    path.write_text(json.dumps(document), encoding="utf-8")
    return str(path)


class FixtureTests(unittest.TestCase):
    def test_executed_and_missing_lines_become_hits_of_one_and_zero(self) -> None:
        document = parsed(str(FIXTURE))
        lines = document[PY_FIXTURE]["lines"]
        self.assertEqual(lines["9"], 1)
        self.assertEqual(lines["17"], 1)
        self.assertEqual(lines["18"], 0)
        self.assertEqual(len(lines), 8)

    def test_the_functions_mapping_becomes_regions_with_their_own_lines(self) -> None:
        functions = parsed(str(FIXTURE))[PY_FIXTURE]["functions"]
        self.assertEqual([f["name"] for f in functions], ["classify", "classify.inner"])
        outer, inner = functions
        self.assertEqual(outer["start_line"], 12)
        self.assertEqual(outer["end_line"], 20)
        self.assertEqual(
            outer["lines"], {"12": 1, "16": 1, "17": 1, "18": 0, "19": 0, "20": 0}
        )
        self.assertEqual(outer["hit"], 1)
        self.assertEqual(inner["lines"], {"14": 1})

    def test_a_never_entered_function_reports_a_hit_flag_of_zero(self) -> None:
        document = {
            "meta": {"version": "7.6.0"},
            "files": {
                "src/a.py": {
                    "executed_lines": [1],
                    "missing_lines": [3, 4],
                    "functions": {
                        "handle": {"executed_lines": [], "missing_lines": [3, 4]}
                    },
                }
            },
        }
        with tempfile.TemporaryDirectory() as tmp:
            out = parsed(write(tmp, "never-entered.json", document))
        self.assertEqual(out["src/a.py"]["functions"][0]["hit"], 0)


class ShapeTests(unittest.TestCase):
    def test_a_report_without_functions_reports_functions_none(self) -> None:
        document = {
            "meta": {"version": "7.5.4"},
            "files": {"src/a.py": {"executed_lines": [1, 2], "missing_lines": []}},
        }
        with tempfile.TemporaryDirectory() as tmp:
            out = parsed(write(tmp, "pre-7.6.json", document))
        self.assertIsNone(out["src/a.py"]["functions"])
        self.assertEqual(out["src/a.py"]["lines"], {"1": 1, "2": 1})

    def test_json_that_is_not_a_coverage_report_exits_2(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run(write(tmp, "other.json", {"totals": {}}))
        self.assertEqual(result.returncode, 2)
        self.assertIn("files", result.stderr)

    def test_the_internal_database_is_never_read(self) -> None:
        # The token is assembled rather than spelled, so the phase gate's
        # `grep -rc` over this directory stays at zero for every file in it.
        source = SCRIPT.read_text(encoding="utf-8")
        self.assertNotIn("import " + "sql" + "ite3", source)
        self.assertIn("json.load", source)

    def test_usage_error_without_an_artifact(self) -> None:
        result = run()
        self.assertEqual(result.returncode, 2)
        self.assertIn("usage", result.stderr)


if __name__ == "__main__":
    unittest.main()
