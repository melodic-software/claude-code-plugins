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
        result = run(
            "thresholds",
            "--config",
            str(DEFAULTS),
            "--measures",
            "cyclomatic,file_lines",
        )
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
                "--skill",
                "audit-size",
                "--scope",
                write(
                    d,
                    "scope.json",
                    json.dumps(
                        scope
                        or {"mode": "paths", "base": None, "files": 2, "excluded": 0}
                    ),
                ),
                "--run",
                write(d, "run.jsonl", jsonl(run_rows)),
                "--measures",
                write(d, "m.jsonl", jsonl(measure_rows)),
                "--thresholds",
                write(d, "t.json", json.dumps(thresholds_)),
            ]
            if excluded is not None:
                args += ["--excluded", write(d, "x.jsonl", jsonl(excluded))]
            result = run(*args)
            self.assertEqual(result.returncode, 0, result.stderr)
            return json.loads(result.stdout)

    THRESHOLD = {
        "measure": "file_lines",
        "value_key": "lines_non_blank",
        "direction": "at_or_above",
        "reference": 10,
        "provenance": "test",
        "layer": "bundled default",
    }

    def test_complete_document_with_over_reference_counts(self) -> None:
        doc = self.assemble(
            [
                {
                    "lane": "python",
                    "measure": "file_lines",
                    "collector": "scc 3.7.0",
                    "status": "ok",
                    "reason": None,
                }
            ],
            [
                {
                    "file": "a.py",
                    "function": None,
                    "lane": "python",
                    "values": {"lines_total": 12, "lines_non_blank": 11},
                },
                {
                    "file": "b.py",
                    "function": None,
                    "lane": "python",
                    "values": {"lines_total": 3, "lines_non_blank": 2},
                },
            ],
            [self.THRESHOLD],
        )
        self.assertEqual(doc["schema"], "code-metrics/v1")
        self.assertEqual(doc["status"], "complete")
        self.assertEqual(doc["measures"][0]["over_reference"], ["file_lines"])
        self.assertEqual(doc["measures"][1]["over_reference"], [])
        self.assertEqual(
            doc["summary"],
            {"files": 2, "functions": 0, "over_reference": {"file_lines": 1}},
        )
        self.assertEqual(doc["unavailable"], [])
        self.assertNotIn("value_key", doc["thresholds"][0])

    def test_null_reference_counts_nothing_and_null_value_never_counts(self) -> None:
        threshold = dict(self.THRESHOLD, reference=None)
        doc = self.assemble(
            [
                {
                    "lane": "python",
                    "measure": "file_lines",
                    "collector": "x",
                    "status": "ok",
                    "reason": None,
                }
            ],
            [
                {
                    "file": "a.py",
                    "function": None,
                    "lane": "python",
                    "values": {"lines_non_blank": None},
                }
            ],
            [threshold],
        )
        self.assertEqual(doc["measures"][0]["over_reference"], [])
        doc = self.assemble(
            [
                {
                    "lane": "python",
                    "measure": "file_lines",
                    "collector": "x",
                    "status": "ok",
                    "reason": None,
                }
            ],
            [
                {
                    "file": "a.py",
                    "function": None,
                    "lane": "python",
                    "values": {"lines_non_blank": None},
                }
            ],
            [self.THRESHOLD],
        )
        self.assertEqual(doc["measures"][0]["over_reference"], [])

    def test_below_direction(self) -> None:
        threshold = {
            "measure": "coverage",
            "value_key": "coverage_pct",
            "direction": "below",
            "reference": 80,
            "provenance": "t",
            "layer": "team",
        }
        doc = self.assemble(
            [
                {
                    "lane": "python",
                    "measure": "coverage",
                    "collector": "lcov",
                    "status": "ok",
                    "reason": None,
                }
            ],
            [
                {
                    "file": "a.py",
                    "function": "f",
                    "lane": "python",
                    "values": {"coverage_pct": 50.0},
                },
                {
                    "file": "a.py",
                    "function": "g",
                    "lane": "python",
                    "values": {"coverage_pct": 90.0},
                },
            ],
            [threshold],
        )
        self.assertEqual(
            [r["over_reference"] for r in doc["measures"]], [["coverage"], []]
        )
        self.assertEqual(doc["summary"]["functions"], 2)

    def test_functions_counts_distinct_functions_not_rows(self) -> None:
        # The row shapes the committed Python fixture produces: lizard reports
        # cyclomatic for `classify` and `classify.inner`, radon reports
        # halstead for `classify`, so `classify` arrives twice. A same-named
        # function in another file is a different function, and a file row
        # (`function: null`) is not one at all.
        doc = self.assemble(
            [
                {
                    "lane": "python",
                    "measure": "cyclomatic",
                    "collector": "lizard 1.24.0",
                    "status": "ok",
                    "reason": None,
                }
            ],
            [
                {
                    "file": "cm_sample.py",
                    "function": "classify.inner",
                    "lane": "python",
                    "values": {"cyclomatic": 2},
                },
                {
                    "file": "cm_sample.py",
                    "function": "classify",
                    "lane": "python",
                    "values": {"cyclomatic": 3},
                },
                {
                    "file": "cm_sample.py",
                    "function": "classify",
                    "lane": "python",
                    "values": {"halstead_difficulty": 2.0},
                },
                {
                    "file": "other.py",
                    "function": "classify",
                    "lane": "python",
                    "values": {"cyclomatic": 1},
                },
                {
                    "file": "cm_sample.py",
                    "function": None,
                    "lane": "python",
                    "values": {"lines_non_blank": 11},
                },
            ],
            [],
        )
        self.assertEqual(len(doc["measures"]), 5)
        self.assertEqual(doc["summary"]["functions"], 3)
        self.assertEqual(doc["summary"]["files"], 2)

    def test_two_same_named_methods_count_as_two_functions(self) -> None:
        # One file, two `render` methods in two classes, which a collector that
        # reports unqualified names gives the same name. Folding on the name
        # alone counts them once, so the summary undercounts a file the
        # coverage join deliberately keeps apart by source position. The
        # Halstead row for the first carries no start line and must still fold
        # into it rather than becoming a third function.
        doc = self.assemble(
            [
                {
                    "lane": "python",
                    "measure": "cyclomatic",
                    "collector": "lizard 1.24.0",
                    "status": "ok",
                    "reason": None,
                }
            ],
            [
                {
                    "file": "a.py",
                    "function": "render",
                    "start_line": 1,
                    "lane": "python",
                    "values": {"cyclomatic": 3},
                },
                {
                    "file": "a.py",
                    "function": "render",
                    "start_line": 10,
                    "lane": "python",
                    "values": {"cyclomatic": 2},
                },
                {
                    "file": "a.py",
                    "function": "render",
                    "start_line": None,
                    "lane": "python",
                    "values": {"halstead_difficulty": 4.0},
                },
            ],
            [],
        )
        self.assertEqual(doc["summary"]["functions"], 2)

    def test_partial_and_empty_status_and_unavailable_list(self) -> None:
        run_rows = [
            {
                "lane": "python",
                "measure": "file_lines",
                "collector": "x",
                "status": "ok",
                "reason": None,
            },
            {
                "lane": "bash",
                "measure": "file_lines",
                "collector": None,
                "status": "unavailable",
                "reason": "no tool",
            },
            {
                "lane": "dotnet",
                "measure": "cyclomatic",
                "collector": None,
                "status": "deferred",
                "reason": "deferred",
            },
        ]
        doc = self.assemble(
            run_rows,
            [
                {
                    "file": "a.py",
                    "function": None,
                    "lane": "python",
                    "values": {"lines_non_blank": 1},
                }
            ],
            [],
        )
        self.assertEqual(doc["status"], "partial")
        self.assertEqual(doc["unavailable"], ["bash/file_lines"])
        doc = self.assemble(run_rows[1:], [], [])
        self.assertEqual(doc["status"], "empty")

    def test_a_run_whose_only_producing_row_is_partial_is_partial_not_empty(
        self,
    ) -> None:
        # `partial` says a row measured some of what it implied. It withholds
        # `complete`, but it did produce rows, so a run carrying nothing else
        # must not read as having measured nothing: `empty` prints the headline
        # "Measured nothing" over a table that names the files it did measure.
        run_rows = [
            {
                "lane": "python",
                "measure": "coverage",
                "collector": "lcov",
                "status": "partial",
                "reason": "partial, 1 of 2 scope files present in the artifacts",
            },
            {
                "lane": "python",
                "measure": "crap",
                "collector": None,
                "status": "not-applicable",
                "reason": "no function-level cyclomatic rows in scope for this lane",
            },
        ]
        doc = self.assemble(
            run_rows,
            [
                {
                    "file": "a.py",
                    "function": None,
                    "lane": "python",
                    "values": {"coverage_pct": 50.0},
                }
            ],
            [],
        )
        self.assertEqual(doc["status"], "partial")
        self.assertEqual(doc["summary"]["files"], 1)
        # A partial row is not an unavailable one; it produced what it names.
        self.assertEqual(doc["unavailable"], [])

    def test_a_non_numeric_reference_never_compares_and_never_crashes(self) -> None:
        # A string reference (a quoted number that slipped past the resolver)
        # is no threshold at all: the row is not over it, and the assembler
        # exits 0 with a document rather than a traceback.
        doc = self.assemble(
            [
                {
                    "lane": "python",
                    "measure": "file_lines",
                    "collector": "line-counter bundled",
                    "status": "ok",
                    "reason": None,
                }
            ],
            [
                {
                    "file": "a.py",
                    "function": None,
                    "lane": "python",
                    "values": {"lines_non_blank": 1200},
                }
            ],
            [
                {
                    "measure": "file_lines",
                    "value_key": "lines_non_blank",
                    "direction": "at_or_above",
                    "reference": "1000",
                    "provenance": "test",
                    "layer": "team",
                }
            ],
        )
        self.assertEqual(doc["status"], "complete")
        self.assertEqual(doc["measures"][0]["over_reference"], [])

    def test_not_applicable_rows_do_not_withhold_complete(self) -> None:
        doc = self.assemble(
            [
                {
                    "lane": "python",
                    "measure": "type_coverage",
                    "collector": "mypy-report 1.19.1",
                    "status": "ok",
                    "reason": None,
                },
                {
                    "lane": "bash",
                    "measure": "type_coverage",
                    "collector": None,
                    "status": "not-applicable",
                    "reason": "not applicable to shell",
                },
            ],
            [{"file": None, "function": None, "lane": "python", "values": {"x": 1}}],
            [],
        )
        self.assertEqual(doc["status"], "complete")
        doc = self.assemble(
            [
                {
                    "lane": "python",
                    "measure": "cyclomatic",
                    "collector": "radon 6.0.1",
                    "status": "ok",
                    "reason": None,
                },
                {
                    "lane": "dotnet",
                    "measure": "cyclomatic",
                    "collector": None,
                    "status": "deferred",
                    "reason": "C# lane deferred",
                },
            ],
            [{"file": "a.py", "function": "f", "lane": "python", "values": {"x": 1}}],
            [],
        )
        self.assertEqual(doc["status"], "partial")

    def test_non_ok_row_without_reason_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            d = Path(tmp)
            result = run(
                "assemble",
                "--skill",
                "s",
                "--scope",
                write(d, "s.json", "{}"),
                "--run",
                write(
                    d,
                    "r.jsonl",
                    jsonl(
                        [
                            {
                                "lane": "x",
                                "measure": "y",
                                "status": "unavailable",
                                "reason": None,
                            }
                        ]
                    ),
                ),
                "--measures",
                write(d, "m.jsonl", ""),
                "--thresholds",
                write(d, "t.json", "[]"),
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("without a reason", result.stderr)


class RenderTests(unittest.TestCase):
    def test_empty_status_headline_and_tables(self) -> None:
        doc = {
            "schema": "code-metrics/v1",
            "skill": "audit-size",
            "status": "empty",
            "scope": {"mode": "change", "base": "abc", "files": 0, "excluded": 0},
            "run": [
                {
                    "lane": "*",
                    "measure": "*",
                    "collector": None,
                    "status": "not-applicable",
                    "reason": "no measurable files in scope",
                }
            ],
            "thresholds": [],
            "measures": [],
            "summary": {"files": 0, "functions": 0, "over_reference": {}},
            "excluded": [],
            "unavailable": [],
        }
        result = run("render", stdin=json.dumps(doc))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Measured nothing", result.stdout)
        self.assertIn("## Coverage of this run", result.stdout)
        self.assertIn(
            "| * | * |  | not-applicable | no measurable files in scope |",
            result.stdout,
        )

    def test_measures_table_lists_value_keys_and_over_reference(self) -> None:
        doc = {
            "schema": "code-metrics/v1",
            "skill": "audit-size",
            "status": "complete",
            "scope": {"mode": "paths", "base": None, "files": 1, "excluded": 0},
            "run": [
                {
                    "lane": "python",
                    "measure": "file_lines",
                    "collector": "scc 3.7.0",
                    "status": "ok",
                    "reason": None,
                }
            ],
            "thresholds": [
                {
                    "measure": "file_lines",
                    "reference": 10,
                    "provenance": "p",
                    "layer": "bundled default",
                }
            ],
            "measures": [
                {
                    "file": "a.py",
                    "function": None,
                    "lane": "python",
                    "values": {"lines_total": 12, "lines_non_blank": 11},
                    "over_reference": ["file_lines"],
                }
            ],
            "summary": {
                "files": 1,
                "functions": 0,
                "over_reference": {"file_lines": 1},
            },
            "excluded": [],
            "unavailable": [],
        }
        result = run("render", stdin=json.dumps(doc))
        self.assertIn(
            "| File | Function | Lane | lines_total | lines_non_blank | Over reference |",
            result.stdout,
        )
        self.assertIn("| a.py |  | python | 12 | 11 | file_lines |", result.stdout)
        self.assertIn("never a bar", result.stdout)
        self.assertIn("Over reference: file_lines 1.", result.stdout)

    def test_capped_coverage_table_leads_with_the_highest_crap_function(self) -> None:
        """Under the 200-row cap the first function row is the highest CRAP in scope,
        function rows with a null CRAP follow, and file rows come after them, least
        covered first with a null percentage last, whatever the file names sort to."""

        def function_row(file: str, name: str, crap, cov, line: int = 1) -> dict:
            return {
                "file": file,
                "function": name,
                "lane": "python",
                "start_line": line,
                "values": {"coverage_pct": cov, "cyclomatic": 3, "crap": crap},
                "over_reference": [],
            }

        def file_row(file: str, cov) -> dict:
            return {
                "file": file,
                "function": None,
                "lane": "python",
                "start_line": None,
                "values": {"coverage_pct": cov, "lines_executable": 10, "lines_hit": 5},
                "over_reference": [],
            }

        # 250 alphabetically-early filler functions would fill the cap on their own.
        filler = [
            function_row(f"a/{i:03d}.py", f"f{i}", crap=3.0 + (i % 7), cov=50.0)
            for i in range(250)
        ]
        top = function_row("zzz/join.py", "join", crap=3192.0, cov=0.0)
        null_crap = function_row("zzz/join.py", "empty", crap=None, cov=None, line=90)
        files = [
            file_row("zzz/a.py", 100.0),
            file_row("zzz/b.py", None),
            file_row("zzz/c.py", 12.5),
        ]
        measures = filler + files + [null_crap, top]
        doc = {
            "schema": "code-metrics/v1",
            "skill": "audit-coverage",
            "status": "complete",
            "scope": {"mode": "paths", "base": None, "files": 253, "excluded": 0},
            "run": [
                {
                    "lane": "python",
                    "measure": "coverage",
                    "collector": "coverage-json",
                    "status": "ok",
                    "reason": None,
                }
            ],
            "thresholds": [],
            "measures": measures,
            "summary": {"files": 253, "functions": 252, "over_reference": {}},
            "excluded": [],
            "unavailable": [],
        }
        result = run("render", stdin=json.dumps(doc))
        self.assertEqual(result.returncode, 0, result.stderr)
        table = [
            line
            for line in result.stdout.splitlines()
            if line.startswith("| ") and not line.startswith("| File |")
        ]
        measure_rows = [
            line
            for line in table
            if line.startswith("| zzz/") or line.startswith("| a/")
        ]
        self.assertEqual(len(measure_rows), 200)
        self.assertTrue(
            measure_rows[0].startswith(
                "| zzz/join.py | join | python | 0 | 3 | 3192 |"
            ),
            measure_rows[0],
        )
        self.assertIn("| 55 more rows in the JSON |", result.stdout)
        # The filler outranks nothing above it: its rows follow the top function by
        # CRAP descending, so the second row is the highest filler CRAP (3 + 6).
        self.assertIn("| 9 |", measure_rows[1])
        self.assertNotIn("| zzz/join.py | empty |", result.stdout)
        self.assertNotIn("| zzz/c.py |", result.stdout)

        # With the cap lifted, the null-CRAP function precedes every file row and the
        # file rows read least covered first with the null percentage last.
        doc["measures"] = files + [null_crap, top]
        result = run("render", stdin=json.dumps(doc))
        rows = [
            line for line in result.stdout.splitlines() if line.startswith("| zzz/")
        ]
        self.assertEqual(
            [row.split(" | ")[0] + " | " + row.split(" | ")[1] for row in rows],
            [
                "| zzz/join.py | join",
                "| zzz/join.py | empty",
                "| zzz/c.py | ",
                "| zzz/a.py | ",
                "| zzz/b.py | ",
            ],
        )

    def test_a_collect_failed_row_puts_an_exit_3_line_in_the_summary(self) -> None:
        # The dispatcher writes `collect failed (exit 3)` on the run row of a
        # collector that ran and produced nothing parseable, and the entry script
        # exits 3 on it; the summary names that row so the exit has a visible
        # cause. A coverage document carries the reason forward on its crap row
        # with no collector column, so the label comes from the reason instead.
        base = {
            "schema": "code-metrics/v1",
            "scope": {"mode": "paths", "base": None, "files": 2, "excluded": 0},
            "thresholds": [],
            "measures": [],
            "summary": {"files": 0, "functions": 0, "over_reference": {}},
            "excluded": [],
        }
        complexity = dict(
            base,
            skill="audit-complexity",
            status="empty",
            run=[
                {
                    "lane": "typescript",
                    "measure": "cyclomatic",
                    "collector": "eslint-complexity 10.1.0",
                    "status": "unavailable",
                    "reason": "collect failed (exit 3): eslint-complexity.py: no "
                    "parseable eslint output",
                }
            ],
            unavailable=["typescript/cyclomatic"],
        )
        result = run("render", stdin=json.dumps(complexity))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(
            "Exit 3: a collector ran and produced nothing parseable: "
            "typescript/cyclomatic (eslint-complexity 10.1.0).",
            result.stdout,
        )
        coverage = dict(
            base,
            skill="audit-coverage",
            status="partial",
            run=[
                {
                    "lane": "typescript",
                    "measure": "coverage",
                    "collector": "lcov",
                    "status": "partial",
                    "reason": "partial, 1 of 2 scope files present in the artifacts",
                },
                {
                    "lane": "typescript",
                    "measure": "crap",
                    "collector": None,
                    "status": "unavailable",
                    "reason": "cyclomatic collector eslint-complexity 10.1.0 "
                    "unavailable: collect failed (exit 3): eslint-complexity.py: "
                    "no parseable eslint output",
                },
            ],
            unavailable=["typescript/crap"],
        )
        result = run("render", stdin=json.dumps(coverage))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(
            "Exit 3: a collector ran and produced nothing parseable: "
            "typescript/crap (cyclomatic collector eslint-complexity 10.1.0 "
            "unavailable).",
            result.stdout,
        )
        clean = dict(base, skill="audit-size", status="empty", run=[], unavailable=[])
        result = run("render", stdin=json.dumps(clean))
        self.assertNotIn("Exit 3", result.stdout)


CLONE_ROW = {
    "file": None,
    "function": None,
    "lane": "bash",
    "instances": [
        {"file": "alpha/shared/u.sh", "start_line": 1, "end_line": 20},
        {"file": "beta/shared/u.sh", "start_line": 1, "end_line": 20},
    ],
    "values": {"lines": 20, "tokens": 90},
    "over_reference": [],
}


class CloneGroupRowTests(unittest.TestCase):
    def test_assemble_sums_duplicated_lines_and_counts_instance_files(self) -> None:
        doc = AssembleTests().assemble(
            [
                {
                    "lane": "bash",
                    "measure": "duplication",
                    "collector": "jscpd 5.1.2",
                    "status": "ok",
                    "reason": None,
                }
            ],
            [CLONE_ROW, dict(CLONE_ROW, values={"lines": 7, "tokens": 30})],
            [],
        )
        self.assertEqual(doc["summary"]["duplicated_lines"], 27)
        self.assertEqual(doc["summary"]["clone_groups"], 2)
        self.assertEqual(doc["summary"]["files"], 2)

    def test_summary_has_no_duplication_keys_without_clone_rows(self) -> None:
        doc = AssembleTests().assemble([], [], [])
        self.assertNotIn("duplicated_lines", doc["summary"])

    def test_render_shows_instances_and_the_duplicated_total(self) -> None:
        doc = {
            "schema": "code-metrics/v1",
            "skill": "audit-duplication",
            "status": "complete",
            "scope": {"mode": "paths", "base": None, "files": 2, "excluded": 0},
            "run": [],
            "thresholds": [],
            "measures": [CLONE_ROW],
            "summary": {
                "files": 2,
                "functions": 0,
                "over_reference": {},
                "duplicated_lines": 20,
                "clone_groups": 1,
            },
            "excluded": [],
            "unavailable": [],
        }
        result = run("render", stdin=json.dumps(doc))
        self.assertIn(
            "| alpha/shared/u.sh:1-20, beta/shared/u.sh:1-20 |  | bash | 20 | 90 |",
            result.stdout,
        )
        self.assertIn("Duplicated lines: 20 in 1 clone group(s).", result.stdout)

    def test_resummarize_recomputes_the_summary_after_rows_are_dropped(self) -> None:
        doc = AssembleTests().assemble(
            [
                {
                    "lane": "bash",
                    "measure": "duplication",
                    "collector": "jscpd 5.1.2",
                    "status": "ok",
                    "reason": None,
                }
            ],
            [CLONE_ROW, dict(CLONE_ROW, values={"lines": 7, "tokens": 30})],
            [],
        )
        doc["measures"] = doc["measures"][1:]
        doc["excluded"] = [{"registry": "r.txt", "line": 3, "path": "shared/u.sh"}]
        result = run("resummarize", stdin=json.dumps(doc))
        self.assertEqual(result.returncode, 0, result.stderr)
        out = json.loads(result.stdout)
        self.assertEqual(out["summary"]["duplicated_lines"], 7)
        self.assertEqual(out["summary"]["clone_groups"], 1)
        self.assertEqual(out["excluded"], doc["excluded"])
        self.assertEqual(out["status"], "complete")
        self.assertEqual(out["run"], doc["run"])


if __name__ == "__main__":
    unittest.main()
