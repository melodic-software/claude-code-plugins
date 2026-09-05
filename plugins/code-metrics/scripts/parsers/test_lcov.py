#!/usr/bin/env python3
"""Output-based tests for lcov.py, driven at its command line.

The committed fixtures are `../fixtures/coverage/lcov-1x.info` (the classic
`FN`/`FNDA` pairing, an MC/DC record, a `DA` checksum field and a `BRDA` whose
taken field is `-`), `lcov-2.2.info` (the `FNL`/`FNA` pair and no `FN` record
at all) and `lcov-absolute-sf.info` (an absolute `SF:` path). Cases that need a
shape no fixture carries write a tracefile into a temporary directory.
"""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
SCRIPT = SCRIPT_DIR / "lcov.py"
FIXTURES = SCRIPT_DIR.parent / "fixtures" / "coverage"
TS_FIXTURE = "plugins/code-metrics/scripts/fixtures/sources/cm-sample.ts"
GO_FIXTURE = "plugins/code-metrics/scripts/fixtures/sources/cm-sample.go"


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


class ClassicRecordTests(unittest.TestCase):
    def test_lcov_1x_line_and_function_records(self) -> None:
        document = parsed(str(FIXTURES / "lcov-1x.info"))
        self.assertEqual(list(document), [TS_FIXTURE])
        lines = document[TS_FIXTURE]["lines"]
        self.assertEqual(lines["4"], 1)
        self.assertEqual(sorted(lines), ["11", "4", "5", "6", "8", "9"])
        functions = document[TS_FIXTURE]["functions"]
        self.assertEqual(len(functions), 1)
        self.assertEqual(functions[0]["name"], "classify")
        self.assertEqual(functions[0]["start_line"], 4)
        self.assertIsNone(functions[0]["end_line"])
        self.assertEqual(functions[0]["hit"], 0)

    def test_a_checksum_third_field_on_da_is_ignored(self) -> None:
        document = parsed(str(FIXTURES / "lcov-1x.info"))
        self.assertEqual(document[TS_FIXTURE]["lines"]["5"], 0)

    def test_branch_and_mcdc_records_are_skipped_without_error(self) -> None:
        document = parsed(str(FIXTURES / "lcov-1x.info"))
        self.assertNotIn("branches", document[TS_FIXTURE])
        self.assertEqual(len(document[TS_FIXTURE]["lines"]), 6)


class Lcov22RecordTests(unittest.TestCase):
    def test_fnl_and_fna_carry_the_function_when_fn_is_absent(self) -> None:
        text = (FIXTURES / "lcov-2.2.info").read_text(encoding="utf-8")
        self.assertNotIn("\nFN:", text)
        document = parsed(str(FIXTURES / "lcov-2.2.info"))
        functions = document[GO_FIXTURE]["functions"]
        self.assertEqual(len(functions), 1)
        self.assertEqual(functions[0]["name"], "Classify")
        self.assertEqual(functions[0]["start_line"], 7)
        self.assertEqual(functions[0]["end_line"], 15)
        self.assertEqual(functions[0]["hit"], 3)

    def test_a_leader_without_an_end_line_reports_none(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            artifact = Path(tmp) / "no-end.info"
            artifact.write_text(
                "SF:src/a.ts\nFNL:0,10\nFNA:0,4,handle\nDA:10,4\nend_of_record\n",
                encoding="utf-8",
            )
            document = parsed(str(artifact))
        function = document["src/a.ts"]["functions"][0]
        self.assertEqual(function["start_line"], 10)
        self.assertIsNone(function["end_line"])


class PathAndShapeTests(unittest.TestCase):
    def test_an_absolute_sf_path_is_returned_verbatim(self) -> None:
        document = parsed(str(FIXTURES / "lcov-absolute-sf.info"))
        self.assertEqual(list(document), ["/workspace/repo/" + TS_FIXTURE])

    def test_a_file_without_function_records_reports_functions_none(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            artifact = Path(tmp) / "lines-only.info"
            artifact.write_text(
                "SF:./src/b.ts\nDA:1,1\nDA:2,0\nend_of_record\n", encoding="utf-8"
            )
            document = parsed(str(artifact))
        self.assertIsNone(document["src/b.ts"]["functions"])
        self.assertEqual(document["src/b.ts"]["lines"], {"1": 1, "2": 0})

    def test_two_sections_are_two_files(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            artifact = Path(tmp) / "two.info"
            artifact.write_text(
                "SF:src/a.ts\nDA:1,1\nend_of_record\n"
                "SF:src\\b.ts\nDA:2,0\nend_of_record\n",
                encoding="utf-8",
            )
            document = parsed(str(artifact))
        self.assertEqual(sorted(document), ["src/a.ts", "src/b.ts"])

    def test_usage_error_without_an_artifact(self) -> None:
        result = run()
        self.assertEqual(result.returncode, 2)
        self.assertIn("usage", result.stderr)

    def test_a_missing_artifact_exits_2(self) -> None:
        result = run(str(FIXTURES / "does-not-exist.info"))
        self.assertEqual(result.returncode, 2)


if __name__ == "__main__":
    unittest.main()
