#!/usr/bin/env python3
"""Output-based tests for report.py at its command line."""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
SCRIPT = SCRIPT_DIR / "report.py"
DEFAULTS = SCRIPT_DIR / "config-defaults.json"


def run(*args: str, stdin: str | None = None) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, str(SCRIPT), *args],
        capture_output=True,
        text=True,
        input=stdin,
        check=False,
    )


def write(directory: Path, name: str, content: str) -> str:
    path = directory / name
    path.write_text(content, encoding="utf-8")
    return str(path)


def jsonl(rows: list[dict]) -> str:
    return "".join(json.dumps(row) + "\n" for row in rows)


class ThresholdsTests(unittest.TestCase):
    def test_reads_reference_and_provenance_from_the_bundled_defaults(self) -> None:
        result = run("thresholds", "--config", str(DEFAULTS), "--measures", "cyclomatic,file_lines")
        self.assertEqual(result.returncode, 0, result.stderr)
        entries = {e["measure"]: e for e in json.loads(result.stdout)}
        self.assertEqual(entries["cyclomatic"]["reference"], 20)
        self.assertIn("8.2.117", entries["cyclomatic"]["provenance"])
        self.assertEqual(entries["cyclomatic"]["layer"], "bundled default")
        self.assertEqual(entries["file_lines"]["reference"], 1000)
        self.assertEqual(entries["file_lines"]["value_key"], "lines_non_blank")
        self.assertIn("not normative", entries["file_lines"]["provenance"])

    def test_layer_comes_from_the_config_when_present(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            config = json.loads(DEFAULTS.read_text(encoding="utf-8"))
            config["size"]["file_lines"] = 500
            config["_layers"] = {"size.file_lines": "team"}
            path = write(Path(tmp), "c.json", json.dumps(config))
            result = run("thresholds", "--config", path, "--measures", "file_lines")
            entry = json.loads(result.stdout)[0]
            self.assertEqual((entry["reference"], entry["layer"]), (500, "team"))


class AssembleTests(unittest.TestCase):
    def assemble(self, run_rows, measure_rows, thresholds_, scope=None, excluded=None):
        with tempfile.TemporaryDirectory() as tmp:
            d = Path(tmp)
            args = [
                "assemble",
                "--skill", "audit-size",
                "--scope", write(d, "scope.json", json.dumps(scope or {"mode": "paths", "base": None, "files": 2, "excluded": 0})),
                "--run", write(d, "run.jsonl", jsonl(run_rows)),
                "--measures", write(d, "m.jsonl", jsonl(measure_rows)),
                "--thresholds", write(d, "t.json", json.dumps(thresholds_)),
            ]
            if excluded is not None:
                args += ["--excluded", write(d, "x.jsonl", jsonl(excluded))]
            result = run(*args)
            self.assertEqual(result.returncode, 0, result.stderr)
            return json.loads(result.stdout)

    THRESHOLD = {"measure": "file_lines", "value_key": "lines_non_blank", "direction": "at_or_above",
                 "reference": 10, "provenance": "test", "layer": "bundled default"}

    def test_complete_document_with_over_reference_counts(self) -> None:
        doc = self.assemble(
            [{"lane": "python", "measure": "file_lines", "collector": "scc 3.7.0", "status": "ok", "reason": None}],
            [
                {"file": "a.py", "function": None, "lane": "python", "values": {"lines_total": 12, "lines_non_blank": 11}},
                {"file": "b.py", "function": None, "lane": "python", "values": {"lines_total": 3, "lines_non_blank": 2}},
            ],
            [self.THRESHOLD],
        )
        self.assertEqual(doc["schema"], "code-metrics/v1")
        self.assertEqual(doc["status"], "complete")
        self.assertEqual(doc["measures"][0]["over_reference"], ["file_lines"])
        self.assertEqual(doc["measures"][1]["over_reference"], [])
        self.assertEqual(doc["summary"], {"files": 2, "functions": 0, "over_reference": {"file_lines": 1}})
        self.assertEqual(doc["unavailable"], [])
        self.assertNotIn("value_key", doc["thresholds"][0])

    def test_null_reference_counts_nothing_and_null_value_never_counts(self) -> None:
        threshold = dict(self.THRESHOLD, reference=None)
        doc = self.assemble(
            [{"lane": "python", "measure": "file_lines", "collector": "x", "status": "ok", "reason": None}],
            [{"file": "a.py", "function": None, "lane": "python", "values": {"lines_non_blank": None}}],
            [threshold],
        )
        self.assertEqual(doc["measures"][0]["over_reference"], [])
        doc = self.assemble(
            [{"lane": "python", "measure": "file_lines", "collector": "x", "status": "ok", "reason": None}],
            [{"file": "a.py", "function": None, "lane": "python", "values": {"lines_non_blank": None}}],
            [self.THRESHOLD],
        )
        self.assertEqual(doc["measures"][0]["over_reference"], [])

    def test_below_direction(self) -> None:
        threshold = {"measure": "coverage", "value_key": "coverage_pct", "direction": "below",
                     "reference": 80, "provenance": "t", "layer": "team"}
        doc = self.assemble(
            [{"lane": "python", "measure": "coverage", "collector": "lcov", "status": "ok", "reason": None}],
            [{"file": "a.py", "function": "f", "lane": "python", "values": {"coverage_pct": 50.0}},
             {"file": "a.py", "function": "g", "lane": "python", "values": {"coverage_pct": 90.0}}],
            [threshold],
        )
        self.assertEqual([r["over_reference"] for r in doc["measures"]], [["coverage"], []])
        self.assertEqual(doc["summary"]["functions"], 2)

    def test_partial_and_empty_status_and_unavailable_list(self) -> None:
        run_rows = [
            {"lane": "python", "measure": "file_lines", "collector": "x", "status": "ok", "reason": None},
            {"lane": "bash", "measure": "file_lines", "collector": None, "status": "unavailable", "reason": "no tool"},
            {"lane": "dotnet", "measure": "cyclomatic", "collector": None, "status": "deferred", "reason": "deferred"},
        ]
        doc = self.assemble(run_rows, [{"file": "a.py", "function": None, "lane": "python", "values": {"lines_non_blank": 1}}], [])
        self.assertEqual(doc["status"], "partial")
        self.assertEqual(doc["unavailable"], ["bash/file_lines"])
        doc = self.assemble(run_rows[1:], [], [])
        self.assertEqual(doc["status"], "empty")

    def test_non_ok_row_without_reason_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            d = Path(tmp)
            result = run(
                "assemble", "--skill", "s",
                "--scope", write(d, "s.json", "{}"),
                "--run", write(d, "r.jsonl", jsonl([{"lane": "x", "measure": "y", "status": "unavailable", "reason": None}])),
                "--measures", write(d, "m.jsonl", ""),
                "--thresholds", write(d, "t.json", "[]"),
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("without a reason", result.stderr)


class RenderTests(unittest.TestCase):
    def test_empty_status_headline_and_tables(self) -> None:
        doc = {
            "schema": "code-metrics/v1", "skill": "audit-size", "status": "empty",
            "scope": {"mode": "change", "base": "abc", "files": 0, "excluded": 0},
            "run": [{"lane": "*", "measure": "*", "collector": None, "status": "not-applicable", "reason": "no measurable files in scope"}],
            "thresholds": [], "measures": [], "summary": {"files": 0, "functions": 0, "over_reference": {}},
            "excluded": [], "unavailable": [],
        }
        result = run("render", stdin=json.dumps(doc))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Measured nothing", result.stdout)
        self.assertIn("## Coverage of this run", result.stdout)
        self.assertIn("| * | * |  | not-applicable | no measurable files in scope |", result.stdout)

    def test_measures_table_lists_value_keys_and_over_reference(self) -> None:
        doc = {
            "schema": "code-metrics/v1", "skill": "audit-size", "status": "complete",
            "scope": {"mode": "paths", "base": None, "files": 1, "excluded": 0},
            "run": [{"lane": "python", "measure": "file_lines", "collector": "scc 3.7.0", "status": "ok", "reason": None}],
            "thresholds": [{"measure": "file_lines", "reference": 10, "provenance": "p", "layer": "bundled default"}],
            "measures": [{"file": "a.py", "function": None, "lane": "python", "values": {"lines_total": 12, "lines_non_blank": 11}, "over_reference": ["file_lines"]}],
            "summary": {"files": 1, "functions": 0, "over_reference": {"file_lines": 1}},
            "excluded": [], "unavailable": [],
        }
        result = run("render", stdin=json.dumps(doc))
        self.assertIn("| File | Function | Lane | lines_total | lines_non_blank | Over reference |", result.stdout)
        self.assertIn("| a.py |  | python | 12 | 11 | file_lines |", result.stdout)
        self.assertIn("never a bar", result.stdout)
        self.assertIn("Over reference: file_lines 1.", result.stdout)


if __name__ == "__main__":
    unittest.main()
