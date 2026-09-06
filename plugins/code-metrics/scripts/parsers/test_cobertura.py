#!/usr/bin/env python3
"""Output-based tests for cobertura.py, driven at its command line.

The committed fixtures are `../fixtures/coverage/cobertura.xml`, written in
the shape kcov emits for a Bash script, and `cobertura-multi-root.xml`, the
shape a multi-root build emits. Drift cases (a missing attribute, a `.`
source, a report with no methods) are written into a temporary directory,
because the point of those cases is a file no well-behaved producer writes.

The multi-root cases set `CODE_METRICS_SCAN_ROOT` to this repository, which is
the tree the fixture's source roots name, because the parser resolves a class
filename by probing for it on disk.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
SCRIPT = SCRIPT_DIR / "cobertura.py"
FIXTURE = SCRIPT_DIR.parent / "fixtures" / "coverage" / "cobertura.xml"
MULTI_ROOT = SCRIPT_DIR.parent / "fixtures" / "coverage" / "cobertura-multi-root.xml"
BASH_FIXTURE = "plugins/code-metrics/scripts/fixtures/sources/cm-sample.sh"
REPO_ROOT = SCRIPT_DIR.parents[3]
SOURCES = "plugins/code-metrics/scripts/fixtures/sources"
ALPHA = SOURCES + "/cluster/alpha"
BETA = SOURCES + "/cluster/beta"


def run(*args: str, scan_root: str | None = None) -> subprocess.CompletedProcess:
    env = dict(os.environ)
    env.pop("CODE_METRICS_SCAN_ROOT", None)
    if scan_root is not None:
        env["CODE_METRICS_SCAN_ROOT"] = scan_root
    return subprocess.run(
        [sys.executable, str(SCRIPT), *args],
        capture_output=True,
        text=True,
        check=False,
        env=env,
    )


def parsed(*args: str, scan_root: str | None = None) -> dict:
    result = run(*args, scan_root=scan_root)
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


class MultiRootTests(unittest.TestCase):
    """The three branches of the source-root resolution rule, plus its probe."""

    def document(self, scan_root: str) -> dict:
        return parsed(str(MULTI_ROOT), scan_root=scan_root)

    def test_a_class_relative_to_a_later_root_resolves_under_that_root(self) -> None:
        document = self.document(str(REPO_ROOT))
        self.assertIn(SOURCES + "/cm-sample.sh", document)
        self.assertNotIn(ALPHA + "/cm-sample.sh", document)
        self.assertEqual(
            document[SOURCES + "/cm-sample.sh"]["lines"],
            {"6": 1, "9": 1, "12": 0, "16": 1},
        )

    def test_two_roots_that_both_hold_the_file_take_the_first(self) -> None:
        document = self.document(str(REPO_ROOT))
        self.assertIn(ALPHA + "/shared/shared-utils.sh", document)
        self.assertNotIn(BETA + "/shared/shared-utils.sh", document)

    def test_a_filename_under_no_root_falls_back_to_the_first(self) -> None:
        self.assertIn(ALPHA + "/cm-absent.sh", self.document(str(REPO_ROOT)))

    def test_absolute_and_drive_qualified_filenames_are_never_prefixed(self) -> None:
        document = self.document(str(REPO_ROOT))
        self.assertIn("/workspace/repo/cm-absolute.sh", document)
        self.assertIn("C:/workspace/cm-drive.sh", document)

    def test_the_probe_reads_the_scan_root_it_is_given(self) -> None:
        # Pointed at an empty tree the probe finds no candidate anywhere, so
        # every relative filename falls back to the first root. The resolution
        # the other cases assert is therefore an observation of the measured
        # tree and not an accident of the order the roots are declared in.
        with tempfile.TemporaryDirectory() as tmp:
            document = self.document(tmp)
        self.assertIn(ALPHA + "/cm-sample.sh", document)
        self.assertNotIn(SOURCES + "/cm-sample.sh", document)

    def test_a_single_root_report_does_not_depend_on_the_scan_root(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            elsewhere = run(str(FIXTURE), scan_root=tmp)
        here = run(str(FIXTURE), scan_root=str(REPO_ROOT))
        self.assertEqual(elsewhere.stdout, here.stdout)
        self.assertEqual(
            list(json.loads(here.stdout)), ["/workspace/repo/" + BASH_FIXTURE]
        )


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
