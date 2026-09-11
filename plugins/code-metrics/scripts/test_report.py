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
        # The value the reference was applied to, and in which direction,
        # travel with the document: the renderer orders rows by them and a
        # consumer comparing two documents needs them.
        self.assertEqual(doc["thresholds"][0]["value_key"], "lines_non_blank")
        self.assertEqual(doc["thresholds"][0]["direction"], "at_or_above")

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
        # An empty change is the common empty run: the headline says how to
        # widen the scope, since the skill body is not in front of the reader.
        headline = result.stdout.splitlines()[2]
        self.assertIn("against `abc`", headline)
        self.assertIn("pass paths or `--all` to widen the scope", headline)
        self.assertNotIn("Functions:", result.stdout)

    def test_an_empty_all_scope_carries_no_widening_hint(self) -> None:
        doc = {
            "schema": "code-metrics/v1",
            "skill": "audit-size",
            "status": "empty",
            "scope": {"mode": "all", "base": None, "files": 0, "excluded": 0},
            "run": [],
            "thresholds": [],
            "measures": [],
            "summary": {"files": 0, "functions": 0, "over_reference": {}},
            "excluded": [],
            "unavailable": [],
        }
        result = run("render", stdin=json.dumps(doc))
        self.assertNotIn("widen the scope", result.stdout)

    def _size_doc(self, rows: list[dict]) -> dict:
        return {
            "schema": "code-metrics/v1",
            "skill": "audit-size",
            "status": "complete",
            "scope": {"mode": "all", "base": None, "files": len(rows), "excluded": 0},
            "run": [],
            "thresholds": [
                {
                    "measure": "file_lines",
                    "value_key": "lines_non_blank",
                    "direction": "at_or_above",
                    "reference": 10,
                    "provenance": "p",
                    "layer": "bundled default",
                }
            ],
            "measures": rows,
            "summary": {"files": len(rows), "functions": 0, "over_reference": {}},
            "excluded": [],
            "unavailable": [],
        }

    def test_rows_are_ordered_by_the_primary_value_largest_first(self) -> None:
        rows = [
            {
                "file": "a.py",
                "function": None,
                "lane": "python",
                "values": {"lines_non_blank": 5},
                "over_reference": [],
            },
            {
                "file": "b.md",
                "function": None,
                "lane": "other",
                "values": {"lines_non_blank": 12},
                "over_reference": ["file_lines"],
            },
            {
                "file": "c.py",
                "function": None,
                "lane": "python",
                "values": {"lines_non_blank": None},
                "over_reference": [],
            },
            {
                "file": "d.sh",
                "function": None,
                "lane": "bash",
                "values": {"lines_non_blank": 7},
                "over_reference": [],
            },
        ]
        result = run("render", stdin=json.dumps(self._size_doc(rows)))
        measures_section = result.stdout.split("## Measures", 1)[1]
        table = [
            line for line in measures_section.splitlines() if line.startswith("| ")
        ]
        files = [line.split(" | ")[0].lstrip("| ") for line in table[1:]]
        # Largest first, a null value after every number, the over-reference
        # row leading because it is the extreme rather than by a separate sort.
        self.assertEqual(files, ["b.md", "d.sh", "a.py", "c.py"])

    def test_a_below_reference_orders_smallest_first(self) -> None:
        doc = self._size_doc([])
        doc["thresholds"] = [
            {
                "measure": "coverage",
                "value_key": "coverage_pct",
                "direction": "below",
                "reference": None,
                "provenance": "p",
                "layer": "bundled default",
            }
        ]
        doc["measures"] = [
            {
                "file": "a.py",
                "function": "f",
                "lane": "python",
                "start_line": 1,
                "values": {"coverage_pct": 90.0},
                "over_reference": [],
            },
            {
                "file": "b.py",
                "function": "g",
                "lane": "python",
                "start_line": 1,
                "values": {"coverage_pct": 10.0},
                "over_reference": [],
            },
        ]
        doc["summary"] = {"files": 2, "functions": 2, "over_reference": {}}
        result = run("render", stdin=json.dumps(doc))
        self.assertLess(
            result.stdout.index("| b.py |"), result.stdout.index("| a.py |")
        )
        self.assertIn("Files: 2. Functions: 2. Over reference: none.", result.stdout)

    def test_the_row_cap_names_the_key_it_kept_the_top_rows_by(self) -> None:
        rows = [
            {
                "file": f"f{i:04d}.md",
                "function": None,
                "lane": "other",
                "values": {"lines_non_blank": i},
                "over_reference": [],
            }
            for i in range(250)
        ]
        result = run("render", stdin=json.dumps(self._size_doc(rows)))
        self.assertIn(
            "50 more rows; re-run with --json for the full document; the 200 shown "
            "are those over a reference first, then the top by lines_non_blank",
            result.stdout,
        )
        self.assertIn("| f0249.md |", result.stdout)
        self.assertNotIn("| f0049.md |", result.stdout)
        self.assertIn("Files: 250. Over reference: none.", result.stdout)

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
            "| File | Function | Lane | Labels | lines_total | lines_non_blank | Over reference |",
            result.stdout,
        )
        self.assertIn("| a.py |  | python |  | 12 | 11 | file_lines |", result.stdout)
        self.assertIn("never a bar", result.stdout)
        self.assertIn("Over reference: file_lines 1.", result.stdout)


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
            "| alpha/shared/u.sh:1-20, beta/shared/u.sh:1-20 |  | bash |  | 20 | 90 |",
            result.stdout,
        )
        self.assertIn("Duplicated lines: 20 in 1 clone group(s).", result.stdout)

    def test_resummarize_counts_every_file_a_replica_row_stands_for(self) -> None:
        doc = AssembleTests().assemble(
            [],
            [
                {
                    "file": "plugins/a/hooks/u.sh",
                    "function": "greet",
                    "start_line": 8,
                    "lane": "bash",
                    "values": {"cyclomatic": 3},
                    "replicas": {
                        "count": 3,
                        "files": [
                            "plugins/a/hooks/u.sh",
                            "plugins/b/hooks/u.sh",
                            "plugins/c/hooks/u.sh",
                        ],
                    },
                }
            ],
            [],
        )
        result = run("resummarize", stdin=json.dumps(doc))
        out = json.loads(result.stdout)
        self.assertEqual(out["summary"]["files"], 3)
        self.assertEqual(out["summary"]["functions"], 1)

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


def clone_row(lane: str, first: str, second: str, lines: int, tokens: int = 90) -> dict:
    return {
        "file": None,
        "function": None,
        "lane": lane,
        "instances": [
            {"file": first, "start_line": 1, "end_line": lines},
            {"file": second, "start_line": 1, "end_line": lines},
        ],
        "values": {"lines": lines, "tokens": tokens},
        "over_reference": [],
    }


def duplication_doc(measures: list[dict], **overrides: object) -> dict:
    doc = {
        "schema": "code-metrics/v1",
        "skill": "audit-duplication",
        "status": "complete",
        "scope": {"mode": "all", "base": None, "files": 4, "excluded": 0},
        "run": [
            {
                "lane": "bash",
                "measure": "duplication",
                "collector": "jscpd 5.2.0",
                "status": "ok",
                "reason": None,
                "hint": None,
            }
        ],
        "thresholds": [],
        "measures": measures,
        "summary": {"files": 0, "functions": 0, "over_reference": {}},
        "excluded": [],
        "unavailable": [],
    }
    doc.update(overrides)
    return doc


def resummarized(doc: dict, *args: str) -> dict:
    result = run("resummarize", *args, stdin=json.dumps(doc))
    assert result.returncode == 0, result.stderr
    return json.loads(result.stdout)


class DuplicationRollupTests(unittest.TestCase):
    ROWS = [
        clone_row("bash", "a/x/u.sh", "b/x/u.sh", 20),
        clone_row("python", "a/y/v.py", "c/y/v.py", 7, 30),
        clone_row("bash", "a/x/w.sh", "d/x/w.sh", 5, 12),
    ]

    def test_the_rollups_sum_to_the_totals_and_root_restates_them(self) -> None:
        summary = resummarized(duplication_doc(self.ROWS))["summary"]
        self.assertEqual(summary["duplicated_lines"], 32)
        self.assertEqual(
            summary["by_lane"],
            {
                "bash": {"groups": 2, "duplicated_lines": 25},
                "python": {"groups": 1, "duplicated_lines": 7},
            },
        )
        self.assertEqual(
            sum(b["duplicated_lines"] for b in summary["by_lane"].values()),
            summary["duplicated_lines"],
        )
        self.assertEqual(
            summary["by_directory"]["."], {"groups": 3, "duplicated_lines": 32}
        )

    def test_directory_rollups_are_cumulative_over_the_first_instance(self) -> None:
        by_directory = resummarized(duplication_doc(self.ROWS))["summary"][
            "by_directory"
        ]
        # Every group's first instance sits under `a`, so `a` carries all three
        # while its children split them; the second instances count nowhere.
        self.assertEqual(by_directory["a"], {"groups": 3, "duplicated_lines": 32})
        self.assertEqual(by_directory["a/x"], {"groups": 2, "duplicated_lines": 25})
        self.assertEqual(by_directory["a/y"], {"groups": 1, "duplicated_lines": 7})
        self.assertNotIn("b", by_directory)
        self.assertEqual(
            set(by_directory), {".", "a", "a/x", "a/y"}, sorted(by_directory)
        )

    def test_root_makes_directory_keys_root_relative(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            rows = [
                clone_row(
                    "bash",
                    str(root / "plugins" / "p" / "u.sh"),
                    str(root / "plugins" / "q" / "u.sh"),
                    9,
                )
            ]
            by_directory = resummarized(duplication_doc(rows), "--root", tmp)[
                "summary"
            ]["by_directory"]
        self.assertEqual(set(by_directory), {".", "plugins", "plugins/p"})

    def test_a_document_without_clone_rows_carries_no_rollup_maps(self) -> None:
        summary = resummarized(duplication_doc([]))["summary"]
        self.assertNotIn("by_lane", summary)
        self.assertNotIn("by_directory", summary)


class DuplicationRenderTests(unittest.TestCase):
    def rendered(self, doc: dict, *args: str) -> str:
        result = run("render", *args, stdin=json.dumps(doc))
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout

    def test_clone_groups_render_largest_first(self) -> None:
        rows = [
            clone_row("bash", "a/small.sh", "b/small.sh", 5, 12),
            clone_row("bash", "a/big.sh", "b/big.sh", 20),
            clone_row("bash", "a/mid.sh", "b/mid.sh", 5, 40),
        ]
        out = self.rendered(resummarized(duplication_doc(rows)))
        self.assertLess(out.index("a/big.sh"), out.index("a/mid.sh"))
        self.assertLess(out.index("a/mid.sh"), out.index("a/small.sh"))

    def test_the_rollup_section_cuts_directories_at_the_depth(self) -> None:
        rows = [clone_row("bash", "a/x/z/u.sh", "b/u.sh", 20)]
        doc = resummarized(duplication_doc(rows))
        self.assertIn("a/x/z", doc["summary"]["by_directory"])
        out = self.rendered(doc)
        self.assertIn("## Rollup", out)
        self.assertIn("| bash | 1 | 20 |", out)
        self.assertIn("| . | 1 | 20 |", out)
        self.assertIn("| a/x | 1 | 20 |", out)
        self.assertNotIn("| a/x/z |", out)
        self.assertIn("| a/x/z | 1 | 20 |", self.rendered(doc, "--rollup-depth", "3"))

    def test_the_summary_line_counts_files_with_clones(self) -> None:
        rows = [clone_row("bash", "a/u.sh", "b/u.sh", 20)]
        out = self.rendered(resummarized(duplication_doc(rows)))
        self.assertIn("\nFiles with clones: 2.\n", out)
        self.assertNotIn("Functions:", out)

    def test_an_empty_excluded_list_is_stated_with_its_reason(self) -> None:
        rows = [clone_row("bash", "a/u.sh", "b/u.sh", 20)]
        out = self.rendered(resummarized(duplication_doc(rows)))
        self.assertIn(
            "Excluded by a sanctioned-replication registry: 0 (no registry configured, or "
            "none matched).",
            out,
        )
        doc = resummarized(duplication_doc(rows))
        doc["excluded"] = [{"registry": "r.txt", "line": 3, "path": "u.sh"}]
        self.assertIn(
            "Excluded by a sanctioned-replication registry: 1.", self.rendered(doc)
        )

    def test_no_detector_prints_one_headline_with_the_hint(self) -> None:
        hint = "jscpd: https://github.com/kucherenko/jscpd (npm install -g jscpd)"
        doc = duplication_doc(
            [],
            status="empty",
            run=[
                {
                    "lane": lane,
                    "measure": "duplication",
                    "collector": None,
                    "status": "unavailable",
                    "reason": "jscpd: not on PATH",
                    "hint": hint,
                }
                for lane in ("bash", "python")
            ],
            unavailable=["bash/duplication", "python/duplication"],
        )
        out = self.rendered(doc)
        self.assertEqual(out.count("No clone detector ran in any lane"), 1)
        self.assertEqual(out.count("npm install -g jscpd"), 1)
        self.assertIn("/code-metrics:setup", out)
        self.assertEqual(out.count("| unavailable | jscpd: not on PATH |"), 2)
        self.assertLess(out.index("No clone detector"), out.index("## Coverage"))

    def test_a_lane_that_skipped_every_file_is_partial_not_empty(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            d = Path(tmp)
            result = run(
                "assemble",
                "--skill",
                "audit-duplication",
                "--scope",
                write(d, "s.json", json.dumps({"mode": "all", "files": 1})),
                "--run",
                write(
                    d,
                    "r.jsonl",
                    jsonl(
                        [
                            {
                                "lane": "bash",
                                "measure": "duplication",
                                "collector": "jscpd 5.2.0",
                                "status": "partial",
                                "reason": "1 of 1 files skipped by duplication.max_size 1mb / max_lines none",
                                "hint": None,
                            }
                        ]
                    ),
                ),
                "--measures",
                write(d, "m.jsonl", ""),
                "--thresholds",
                write(d, "t.json", "[]"),
            )
        self.assertEqual(result.returncode, 0, result.stderr)
        doc = json.loads(result.stdout)
        self.assertEqual(doc["status"], "partial")
        out = self.rendered(doc)
        self.assertNotIn("Measured nothing", out)
        self.assertIn("Status: partial", out)
        self.assertIn("\nPartial: bash/duplication.\n", out)

    def test_a_size_document_renders_as_before(self) -> None:
        doc = {
            "schema": "code-metrics/v1",
            "skill": "audit-size",
            "status": "partial",
            "scope": {"mode": "all", "base": None, "files": 1, "excluded": 0},
            "run": [
                {
                    "lane": "python",
                    "measure": "size",
                    "collector": "scc 3.4.0",
                    "status": "partial",
                    "reason": "1 of 2 files unreadable",
                    "hint": None,
                }
            ],
            "thresholds": [],
            "measures": [
                {
                    "file": "a.py",
                    "function": None,
                    "lane": "python",
                    "values": {"lines_non_blank": 12},
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
        out = self.rendered(doc)
        self.assertEqual(
            out,
            "# code-metrics: audit-size\n"
            "\n"
            "Status: partial. Scope: all, 1 file(s).\n"
            "\n"
            "## Coverage of this run\n"
            "\n"
            "| Lane | Measure | Collector | Status | Reason |\n"
            "|---|---|---|---|---|\n"
            "| python | size | scc 3.4.0 | partial | 1 of 2 files unreadable |\n"
            "\n"
            "## Measures\n"
            "\n"
            "| File | Function | Lane | Labels | lines_non_blank | Over reference |\n"
            "|---|---|---|---|---|---|\n"
            "| a.py |  | python |  | 12 | file_lines |\n"
            "\n"
            "## Summary\n"
            "\n"
            "Files: 1. Over reference: file_lines 1.\n",
        )


def render_doc(measures: list[dict], thresholds_: list[dict] | None = None, **scope):
    doc = {
        "schema": "code-metrics/v1",
        "skill": "audit-complexity",
        "status": "partial",
        "scope": {"mode": "paths", "base": None, "files": 1, "excluded": 0, **scope},
        "run": [],
        "thresholds": thresholds_
        or [
            {
                "measure": "cyclomatic",
                "reference": 20,
                "provenance": "p",
                "layer": "bundled default",
            }
        ],
        "measures": measures,
        "summary": {"files": 1, "functions": 0, "over_reference": {}},
        "excluded": [],
        "unavailable": [],
    }
    return doc


def function_row(**fields) -> dict:
    row = {
        "file": "a.py",
        "function": "f",
        "start_line": 3,
        "end_line": 9,
        "lane": "python",
        "values": {},
        "collector": "lizard",
        "labels": [],
        "over_reference": [],
    }
    row.update(fields)
    return row


class JoinedRenderTests(unittest.TestCase):
    """The table joins one function's rows; the JSON keeps one row per collector."""

    def test_a_cyclomatic_row_and_a_halstead_row_render_as_one_line(self) -> None:
        rows = [
            function_row(values={"cyclomatic": 4}),
            function_row(
                start_line=None,
                end_line=None,
                collector="radon",
                labels=["no-line-range"],
                values={"halstead_difficulty": 1.5},
            ),
        ]
        out = run("render", stdin=json.dumps(render_doc(rows))).stdout
        self.assertEqual(out.count("| a.py | f |"), 1)
        self.assertIn("| a.py | f | python | no-line-range | 4 | 1.5 |  |", out)

    def test_two_same_named_functions_keep_a_start_line_less_row_separate(
        self,
    ) -> None:
        rows = [
            function_row(values={"cyclomatic": 4}),
            function_row(start_line=30, end_line=40, values={"cyclomatic": 6}),
            function_row(
                start_line=None,
                end_line=None,
                collector="radon",
                values={"halstead_difficulty": 1.5},
            ),
        ]
        out = run("render", stdin=json.dumps(render_doc(rows))).stdout
        self.assertEqual(out.count("| a.py | f |"), 3)

    def test_disagreeing_values_are_never_merged(self) -> None:
        rows = [
            function_row(values={"cyclomatic": 4}),
            function_row(collector="radon", values={"cyclomatic": 5}),
        ]
        out = run("render", stdin=json.dumps(render_doc(rows))).stdout
        self.assertEqual(out.count("| a.py | f |"), 2)

    def test_over_reference_rows_come_first_furthest_past_the_reference(self) -> None:
        rows = [
            function_row(
                function="mild",
                values={"cyclomatic": 21},
                over_reference=["cyclomatic"],
            ),
            function_row(function="calm", values={"cyclomatic": 3}),
            function_row(
                function="wild",
                values={"cyclomatic": 48},
                over_reference=["cyclomatic"],
            ),
        ]
        out = run("render", stdin=json.dumps(render_doc(rows))).stdout
        self.assertLess(out.index("| wild |"), out.index("| mild |"))
        self.assertLess(out.index("| mild |"), out.index("| calm |"))

    def test_labels_column_carries_the_row_labels(self) -> None:
        rows = [
            function_row(
                function=None,
                start_line=None,
                end_line=None,
                collector="multimetric",
                labels=["file-level"],
                values={"halstead_difficulty": 12.5},
            )
        ]
        out = run("render", stdin=json.dumps(render_doc(rows))).stdout
        self.assertIn("| a.py |  | python | file-level | 12.5 |  |", out)

    def test_a_halstead_zero_gets_the_measurement_footnote(self) -> None:
        rows = [function_row(values={"halstead_difficulty": 0})]
        out = run("render", stdin=json.dumps(render_doc(rows))).stdout
        self.assertIn("A Halstead value of 0 is a measurement", out)
        rows = [function_row(values={"halstead_difficulty": 2})]
        out = run("render", stdin=json.dumps(render_doc(rows))).stdout
        self.assertNotIn("A Halstead value of 0", out)

    def test_the_cap_line_names_the_persisted_document_or_says_to_rerun(self) -> None:
        rows = [
            function_row(function=f"f{i}", start_line=i + 1, values={"cyclomatic": 1})
            for i in range(205)
        ]
        doc = render_doc(rows)
        out = run("render", stdin=json.dumps(doc)).stdout
        self.assertIn("5 more rows; re-run with --json for the full document", out)
        out = run("render", "--document", "/tmp/r.json", stdin=json.dumps(doc)).stdout
        self.assertIn("5 more rows in the JSON document at /tmp/r.json", out)
        self.assertIn("Full document: /tmp/r.json", out)

    def test_replicas_and_exclusions_are_stated(self) -> None:
        rows = [
            function_row(
                file="plugins/a/hooks/u.sh",
                lane="bash",
                values={"cyclomatic": 22},
                over_reference=["cyclomatic"],
                labels=["replicated"],
                replicas={
                    "count": 3,
                    "registry": "r.txt",
                    "line": 2,
                    "path": "hooks/u.sh",
                    "files": [
                        "plugins/a/hooks/u.sh",
                        "plugins/b/hooks/u.sh",
                        "plugins/c/hooks/u.sh",
                    ],
                },
            )
        ]
        doc = render_doc(
            rows,
            excluded=4,
            exclusions=[{"pattern": "**/build/**", "files": 4}],
        )
        out = run("render", stdin=json.dumps(doc)).stdout
        self.assertIn(
            "| plugins/a/hooks/u.sh (+2 replicas) | f | bash | replicated | 22 | cyclomatic |",
            out,
        )
        self.assertIn(
            "Replicated files collapsed by a sanctioned-replication registry: 1 row(s) standing for 3 files.",
            out,
        )
        self.assertIn("Excluded by scope.exclude: `**/build/**` 4.", out)


if __name__ == "__main__":
    unittest.main()
