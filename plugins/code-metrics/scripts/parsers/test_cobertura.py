#!/usr/bin/env python3
"""Output-based tests for cobertura.py, driven at its command line.

The committed fixture is `../fixtures/coverage/cobertura.xml`, written in the
shape kcov emits for a Bash script. Drift cases (a missing attribute, a `.`
source, a report with no methods) are written into a temporary directory,
because the point of those cases is a file no well-behaved producer writes.
"""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
SCRIPT = SCRIPT_DIR / "cobertura.py"
FIXTURE = SCRIPT_DIR.parent / "fixtures" / "coverage" / "cobertura.xml"
BASH_FIXTURE = "plugins/code-metrics/scripts/fixtures/sources/cm-sample.sh"


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
    def test_the_source_prefix_is_applied_to_the_class_filename(self) -> None:
        document = parsed(str(FIXTURE))
        self.assertEqual(list(document), ["/workspace/repo/" + BASH_FIXTURE])

    def test_line_hits_are_read_and_rates_are_not(self) -> None:
        document = parsed(str(FIXTURE))
        lines = document["/workspace/repo/" + BASH_FIXTURE]["lines"]
        self.assertEqual(lines, {"6": 1, "9": 1, "10": 1, "12": 0, "16": 1})

    def test_a_method_carries_its_own_region_and_hit_flag(self) -> None:
        document = parsed(str(FIXTURE))
        functions = document["/workspace/repo/" + BASH_FIXTURE]["functions"]
        self.assertEqual(len(functions), 1)
        self.assertEqual(functions[0]["name"], "greet")
        self.assertEqual(functions[0]["start_line"], 9)
        self.assertEqual(functions[0]["end_line"], 12)
        self.assertEqual(functions[0]["hit"], 1)
        self.assertEqual(functions[0]["lines"], {"9": 1, "10": 1, "12": 0})


class DriftTests(unittest.TestCase):
    def test_a_dot_source_is_not_prefixed(self) -> None:
        body = (
            "<coverage><sources><source>.</source></sources><packages><package>"
            '<classes><class filename="src/a.py"><lines>'
            '<line number="1" hits="1"/></lines></class></classes>'
            "</package></packages></coverage>"
        )
        with tempfile.TemporaryDirectory() as tmp:
            document = parsed(write(tmp, "dot-source.xml", body))
        self.assertEqual(list(document), ["src/a.py"])

    def test_a_line_without_hits_is_dropped_not_counted_as_zero(self) -> None:
        body = (
            "<coverage><packages><package><classes>"
            '<class filename="src/a.py"><lines>'
            '<line number="1" hits="2"/><line number="2"/><line hits="0"/>'
            "</lines></class></classes></package></packages></coverage>"
        )
        with tempfile.TemporaryDirectory() as tmp:
            document = parsed(write(tmp, "missing-attrs.xml", body))
        self.assertEqual(document["src/a.py"]["lines"], {"1": 2})
        self.assertIsNone(document["src/a.py"]["functions"])

    def test_two_class_elements_for_one_file_merge(self) -> None:
        body = (
            "<coverage><packages><package><classes>"
            '<class filename="src/a.py"><lines><line number="1" hits="1"/></lines></class>'
            '<class filename="src/a.py"><lines><line number="2" hits="0"/></lines></class>'
            "</classes></package></packages></coverage>"
        )
        with tempfile.TemporaryDirectory() as tmp:
            document = parsed(write(tmp, "split-class.xml", body))
        self.assertEqual(document["src/a.py"]["lines"], {"1": 1, "2": 0})

    def test_a_method_hits_attribute_wins_over_its_line_hits(self) -> None:
        body = (
            "<coverage><packages><package><classes>"
            '<class filename="src/a.py"><methods>'
            '<method name="handle" hits="0"><lines>'
            '<line number="1" hits="1"/></lines></method></methods>'
            '<lines><line number="1" hits="1"/></lines></class>'
            "</classes></package></packages></coverage>"
        )
        with tempfile.TemporaryDirectory() as tmp:
            document = parsed(write(tmp, "method-hits.xml", body))
        self.assertEqual(document["src/a.py"]["functions"][0]["hit"], 0)

    def test_malformed_xml_exits_2(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run(write(tmp, "broken.xml", "<coverage>"))
        self.assertEqual(result.returncode, 2)

    def test_usage_error_without_an_artifact(self) -> None:
        result = run()
        self.assertEqual(result.returncode, 2)
        self.assertIn("usage", result.stderr)


if __name__ == "__main__":
    unittest.main()
