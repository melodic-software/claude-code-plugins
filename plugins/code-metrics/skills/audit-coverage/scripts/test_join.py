#!/usr/bin/env python3
"""Output-based tests for join.py at its command line.

Each case writes a small complexity document and one or more parsed-artifact
documents into a temporary directory, so the shapes under test (an absolute
`SF:` path, a lane with no function end lines, a function with no executable
lines) are visible in the test rather than buried in a fixture tree. The
end-to-end join over the committed fixtures is the shell suite's job.
"""

from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
SCRIPT = SCRIPT_DIR / "join.py"
PLUGIN_ROOT = SCRIPT_DIR.parents[2]
LCOV_PARSER = PLUGIN_ROOT / "scripts" / "parsers" / "lcov.py"
SHORT_NAME_FIXTURE = (
    PLUGIN_ROOT / "scripts" / "fixtures" / "coverage" / "lcov-short-names.info"
)

# The suite drives the script at its command line; this import is only for the
# few cases that pin a helper's signature directly, such as the default value
# of an optional parameter that no command-line path can leave unset.
_spec = importlib.util.spec_from_file_location("join_module", SCRIPT)
assert _spec is not None and _spec.loader is not None
join = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(join)


def run(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, str(SCRIPT), *args],
        capture_output=True,
        text=True,
        check=False,
    )


def complexity_row(
    file: str, function: str, start: int, end: int | None, lane: str, comp: int
) -> dict:
    return {
        "file": file,
        "function": function,
        "start_line": start,
        "end_line": end,
        "lane": lane,
        "values": {"cyclomatic": comp},
    }


class JoinCase:
    """One temporary directory holding a complexity document, the parsed
    artifacts, and the scope file list the entry script writes."""

    def __init__(self, tmp: str) -> None:
        self.dir = Path(tmp)
        self.artifacts: list[str] = []

    def complexity(self, rows: list[dict]) -> "JoinCase":
        (self.dir / "complexity.json").write_text(
            json.dumps({"measures": rows}), encoding="utf-8"
        )
        scope: list[str] = []
        for row in rows:
            if row["file"] not in scope:
                scope.append(row["file"])
        (self.dir / "scope.txt").write_text("\n".join(scope) + "\n", encoding="utf-8")
        return self

    def scope(self, paths: list[str]) -> "JoinCase":
        """The scope on its own, for a case with no complexity rows at all."""
        (self.dir / "scope.txt").write_text("\n".join(paths) + "\n", encoding="utf-8")
        document = self.dir / "complexity.json"
        if not document.exists():
            document.write_text(
                json.dumps({"measures": [], "run": []}), encoding="utf-8"
            )
        return self

    def artifact(self, fmt: str, payload: dict) -> "JoinCase":
        path = self.dir / f"parsed-{len(self.artifacts)}.json"
        path.write_text(json.dumps(payload), encoding="utf-8")
        self.artifacts.append(f"{fmt}:{path}")
        return self

    def join(self, *extra: str) -> dict:
        args = [
            "--complexity",
            str(self.dir / "complexity.json"),
            "--scope",
            str(self.dir / "scope.txt"),
        ]
        for spec in self.artifacts:
            args += ["--artifacts", spec]
        result = run(*args, *extra)
        assert result.returncode == 0, result.stderr
        return json.loads(result.stdout)


class ArtifactMergeTests(unittest.TestCase):
    def test_two_artifacts_covering_one_function_are_folded_not_stacked(self) -> None:
        # Two suites each report `classify`: the first never entered it, the
        # second did. Kept as two records, the lookup returns whichever landed
        # first, so the function reads 0 percent (and maximal CRAP) beside a
        # file row the merged line table already shows as covered.
        with tempfile.TemporaryDirectory() as tmp:
            case = JoinCase(tmp).complexity(
                [complexity_row("src/a.py", "classify", 1, 4, "python", 3)]
            )
            for hit, lines in ((0, {"1": 0, "2": 0}), (1, {"1": 1, "2": 1})):
                case.artifact(
                    "lcov",
                    {
                        "src/a.py": {
                            "lines": lines,
                            "functions": [
                                {
                                    "name": "classify",
                                    "start_line": 1,
                                    "end_line": 4,
                                    "hit": hit,
                                    "lines": lines,
                                }
                            ],
                        }
                    },
                )
            document = case.join()
        function = next(
            row for row in document["measures"] if row["function"] == "classify"
        )
        self.assertEqual(function["hit"], 1)
        self.assertEqual(function["values"]["coverage_pct"], 100.0)
        # A fully covered function's CRAP is its complexity, not comp^2 + comp.
        self.assertEqual(function["values"]["crap"], function["values"]["cyclomatic"])

    def test_two_methods_sharing_a_name_in_one_file_stay_separate(self) -> None:
        # One file, two classes, both with a `render` the artifact names
        # unqualified. Folding them on the name alone would let the covered
        # one stand in for the uncovered one.
        with tempfile.TemporaryDirectory() as tmp:
            case = JoinCase(tmp).complexity(
                [
                    complexity_row("src/a.py", "A.render", 1, 4, "python", 2),
                    complexity_row("src/a.py", "B.render", 10, 14, "python", 2),
                ]
            )
            case.artifact(
                "cobertura",
                {
                    "src/a.py": {
                        "lines": {"1": 1, "2": 1, "10": 0, "11": 0},
                        "functions": [
                            {
                                "name": "render",
                                "start_line": 1,
                                "end_line": 4,
                                "hit": 1,
                                "lines": {"1": 1, "2": 1},
                            },
                            {
                                "name": "render",
                                "start_line": 10,
                                "end_line": 14,
                                "hit": 0,
                                "lines": {"10": 0, "11": 0},
                            },
                        ],
                    }
                },
            )
            document = case.join()
        rows = {
            row["function"]: row
            for row in document["measures"]
            if row["function"] is not None
        }
        self.assertEqual(rows["A.render"]["values"]["coverage_pct"], 100.0)
        self.assertEqual(rows["B.render"]["values"]["coverage_pct"], 0.0)
        # The uncovered method keeps the CRAP its own coverage earns.
        self.assertGreater(
            rows["B.render"]["values"]["crap"], rows["A.render"]["values"]["crap"]
        )

    def test_two_methods_sharing_an_exact_name_bind_by_position(self) -> None:
        # Keeping the two records separate is only half the fix: the lookup
        # must not then hand both complexity rows the first record. The
        # artifact names both methods `render` exactly, so the start line the
        # complexity collector reported is what separates them.
        with tempfile.TemporaryDirectory() as tmp:
            case = JoinCase(tmp).complexity(
                [
                    complexity_row("src/a.py", "render", 1, 4, "python", 2),
                    complexity_row("src/a.py", "render", 10, 14, "python", 2),
                ]
            )
            case.artifact(
                "cobertura",
                {
                    "src/a.py": {
                        "lines": {"1": 1, "2": 1, "10": 0, "11": 0},
                        "functions": [
                            {
                                "name": "render",
                                "start_line": 1,
                                "end_line": 4,
                                "hit": 1,
                                "lines": {"1": 1, "2": 1},
                            },
                            {
                                "name": "render",
                                "start_line": 10,
                                "end_line": 14,
                                "hit": 0,
                                "lines": {"10": 0, "11": 0},
                            },
                        ],
                    }
                },
            )
            document = case.join()
        rows = [
            row
            for row in document["measures"]
            if row["function"] == "render" and row["start_line"] is not None
        ]
        by_start = {row["start_line"]: row for row in rows}
        self.assertEqual(sorted(by_start), [1, 10])
        self.assertEqual(by_start[1]["values"]["coverage_pct"], 100.0)
        self.assertEqual(by_start[10]["values"]["coverage_pct"], 0.0)

    def test_one_functions_start_is_not_a_neighbours_start(self) -> None:
        # The two formats mean different things by "start": lcov reports the
        # `FN:` declaration line while the coverage.py JSON report gives the
        # first body line. In `cm_sample.py` that makes lcov's start for
        # `classify` (line 9, the `def`) equal coverage.py's start for the
        # nested `classify.inner` (line 12, its first body line). Folding on a
        # start line alone therefore hands the nested helper the outer
        # function's region, leaves `classify` holding only lcov's `FNDA:0`,
        # and reports it at 0 percent and maximal CRAP beside a file row that
        # says 62.5. A Python repository that emits both artifacts hits this
        # with no configuration, because both names are discovered by default.
        with tempfile.TemporaryDirectory() as tmp:
            case = JoinCase(tmp).complexity(
                [
                    complexity_row("src/a.py", "classify", 9, 20, "python", 4),
                    complexity_row("src/a.py", "classify.inner", 12, 14, "python", 2),
                ]
            )
            case.artifact(
                "lcov",
                {
                    "src/a.py": {
                        "lines": {},
                        "functions": [
                            {
                                "name": "classify",
                                "start_line": 9,
                                "end_line": None,
                                "hit": 0,
                                "lines": None,
                            },
                            {
                                "name": "classify.inner",
                                "start_line": 12,
                                "end_line": None,
                                "hit": 0,
                                "lines": None,
                            },
                        ],
                    }
                },
            )
            case.artifact(
                "coverage_py_json",
                {
                    "src/a.py": {
                        "lines": {
                            "9": 1,
                            "12": 1,
                            "14": 1,
                            "16": 1,
                            "17": 1,
                            "18": 0,
                            "19": 0,
                            "20": 0,
                        },
                        "functions": [
                            {
                                "name": "classify",
                                "start_line": 12,
                                "end_line": 20,
                                "hit": 1,
                                "lines": {
                                    "12": 1,
                                    "16": 1,
                                    "17": 1,
                                    "18": 0,
                                    "19": 0,
                                    "20": 0,
                                },
                            },
                            {
                                "name": "classify.inner",
                                "start_line": 14,
                                "end_line": 14,
                                "hit": 1,
                                "lines": {"14": 1},
                            },
                        ],
                    }
                },
            )
            document = case.join()
        rows = {row["function"]: row for row in document["measures"]}
        self.assertEqual(rows[None]["values"]["coverage_pct"], 62.5)
        self.assertEqual(rows["classify"]["values"]["coverage_pct"], 50.0)
        self.assertEqual(rows["classify"]["values"]["crap"], 6.0)
        self.assertEqual(rows["classify"]["hit"], 1)
        self.assertEqual(rows["classify.inner"]["values"]["coverage_pct"], 100.0)
        self.assertEqual(rows["classify.inner"]["values"]["lines_executable"], 1)

    def test_two_formats_disagreeing_on_a_start_line_still_fold(self) -> None:
        # The same disagreement seen from the other side: one function, named
        # the same by both artifacts, whose start lcov reports as the `def`
        # line and Cobertura as the first body line. Refusing to fold two
        # records whose starts differ splits one function in two, and the
        # lookup then binds the complexity row to the record carrying the
        # declaration line and its `FNDA:0`, reporting a fully covered
        # function at 0 percent. The values must not depend on which artifact
        # discovery happened to read first either.
        lcov = {
            "src/a.py": {
                "lines": {},
                "functions": [
                    {
                        "name": "process",
                        "start_line": 10,
                        "end_line": None,
                        "hit": 0,
                        "lines": None,
                    }
                ],
            }
        }
        cobertura = {
            "src/a.py": {
                "lines": {"11": 4, "12": 4, "13": 4},
                "functions": [
                    {
                        "name": "process",
                        "start_line": 11,
                        "end_line": 13,
                        "hit": 4,
                        "lines": {"11": 4, "12": 4, "13": 4},
                    }
                ],
            }
        }
        for order in (("lcov", "cobertura"), ("cobertura", "lcov")):
            with self.subTest(order=order), tempfile.TemporaryDirectory() as tmp:
                case = JoinCase(tmp).complexity(
                    [complexity_row("src/a.py", "process", 10, 13, "python", 5)]
                )
                for fmt in order:
                    case.artifact(fmt, lcov if fmt == "lcov" else cobertura)
                document = case.join()
                row = next(
                    r for r in document["measures"] if r["function"] == "process"
                )
                self.assertEqual(row["values"]["coverage_pct"], 100.0)
                self.assertEqual(row["values"]["crap"], 5.0)

    def test_a_function_only_one_artifact_knows_the_end_of_keeps_that_range(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            case = JoinCase(tmp).complexity(
                [complexity_row("src/a.py", "classify", 1, 4, "python", 2)]
            )
            case.artifact(
                "lcov",
                {
                    "src/a.py": {
                        "lines": {"1": 1},
                        "functions": [
                            {
                                "name": "classify",
                                "start_line": 1,
                                "end_line": None,
                                "hit": 0,
                                "lines": None,
                            }
                        ],
                    }
                },
            )
            case.artifact(
                "cobertura",
                {
                    "src/a.py": {
                        "lines": {"2": 1},
                        "functions": [
                            {
                                "name": "classify",
                                "start_line": 1,
                                "end_line": 4,
                                "hit": 1,
                                "lines": {"1": 1, "2": 1},
                            }
                        ],
                    }
                },
            )
            document = case.join()
        function = next(
            row for row in document["measures"] if row["function"] == "classify"
        )
        self.assertEqual(function["cov_source"], "artifact-region")
        self.assertEqual(function["hit"], 1)


def go_section(blocks: dict[str, tuple[int, int]]) -> dict:
    """A parsed Go cover profile section: no line table, one block table.

    `blocks` maps the profile's own `start.col,end.col` identity to the
    block's statement count and its execution count, which is the shape
    `go_cover.py` prints. `total` and `hit` are this profile's own totals,
    and the join recomputes them from the merged blocks.
    """
    table = {
        key: {"statements": statements, "count": count}
        for key, (statements, count) in blocks.items()
    }
    return {
        "lines": {},
        "functions": None,
        "statements": {
            "total": sum(s for s, _ in blocks.values()),
            "hit": sum(s for s, count in blocks.values() if count > 0),
            "blocks": table,
        },
    }


class StatementWeightTests(unittest.TestCase):
    """A Go cover profile weighs statements over line ranges, not lines."""

    def test_two_shards_union_their_blocks_rather_than_taking_a_maximum(self) -> None:
        # Two profiles from separate test shards, each entering the block the
        # other missed. Each says 2 statements with 1 hit, so any rule over
        # those aggregates reports 1 of 2 = 50 percent, while the two runs
        # between them covered both statements. The union of the blocks is
        # what makes that 100.
        shards = [
            {"3.19,4.11": (1, 1), "7.2,7.54": (1, 0)},
            {"3.19,4.11": (1, 0), "7.2,7.54": (1, 1)},
        ]
        with tempfile.TemporaryDirectory() as tmp:
            case = JoinCase(tmp).scope(["r.go"])
            for blocks in shards:
                case.artifact("go_cover", {"r.go": go_section(blocks)})
            document = case.join()
        row = next(r for r in document["measures"] if r["function"] is None)
        self.assertEqual(row["values"]["coverage_pct"], 100.0)
        self.assertEqual(row["cov_source"], "statement-ratio")

    def test_a_block_two_profiles_both_list_is_weighed_once(self) -> None:
        blocks = {"3.19,4.11": (1, 1), "7.2,7.54": (5, 0)}
        with tempfile.TemporaryDirectory() as tmp:
            case = JoinCase(tmp).scope(["r.go"])
            for _ in range(2):
                case.artifact("go_cover", {"r.go": go_section(blocks)})
            document = case.join()
        row = next(r for r in document["measures"] if r["function"] is None)
        self.assertEqual(row["values"]["coverage_pct"], 16.67)

    def test_the_statement_ratio_outranks_a_line_table_for_the_same_file(self) -> None:
        # The profile's 7 statements with 2 hit are 28.57 percent, the number
        # `go tool cover -func` prints for this file. A line artifact naming
        # the same `.go` file measures something else, here 1 of 4 lines, and
        # a partial or stale one must not replace the exact native measure.
        profile = go_section(
            {"3.19,4.11": (1, 1), "4.11,6.3": (1, 1), "7.2,7.54": (5, 0)}
        )
        lines = {"lines": {"3": 1, "4": 0, "7": 0, "9": 0}, "functions": None}
        with tempfile.TemporaryDirectory() as tmp:
            line_only = (
                JoinCase(tmp).scope(["r.go"]).artifact("lcov", {"r.go": lines}).join()
            )
        line_row = next(r for r in line_only["measures"] if r["function"] is None)
        self.assertEqual(line_row["values"]["coverage_pct"], 25.0)
        with tempfile.TemporaryDirectory() as tmp:
            document = (
                JoinCase(tmp)
                .scope(["r.go"])
                .artifact("go_cover", {"r.go": profile})
                .artifact("lcov", {"r.go": lines})
                .join()
            )
        row = next(r for r in document["measures"] if r["function"] is None)
        self.assertEqual(row["values"]["coverage_pct"], 28.57)
        # The basis is in the row, so the reader sees which measure produced
        # the number rather than a percentage that silently changed meaning.
        self.assertEqual(row["cov_source"], "statement-ratio")
        # The line counts came from a real line table, but 1 of 4 lines is not
        # 28.57 percent: printed beside a statement ratio they would read as
        # the counts behind it. The file row states one measure only.
        self.assertIsNone(row["values"]["lines_executable"])
        self.assertIsNone(row["values"]["lines_hit"])
        # Both artifacts are still named as read, so nothing is invisible.
        collector = next(
            r["collector"] for r in document["run"] if r["measure"] == "coverage"
        )
        self.assertIn("lcov", collector)
        self.assertIn("go_cover", collector)

    def test_a_line_measured_file_keeps_its_line_counts(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            document = (
                JoinCase(tmp)
                .scope(["a.ts"])
                .artifact(
                    "lcov", {"a.ts": {"lines": {"1": 1, "2": 0}, "functions": None}}
                )
                .join()
            )
        row = next(r for r in document["measures"] if r["function"] is None)
        self.assertEqual(row["cov_source"], "artifact-region")
        self.assertEqual(row["values"]["lines_executable"], 2)

    def test_a_parser_reporting_totals_only_still_reports_its_ratio(self) -> None:
        # The aggregates stay in the parser's output, so a document produced
        # without a block table still joins, folded by the most that shape
        # supports: the larger total and the larger hit count.
        section = {"lines": {}, "functions": None, "statements": {"total": 5, "hit": 4}}
        with tempfile.TemporaryDirectory() as tmp:
            document = (
                JoinCase(tmp)
                .scope(["r.go"])
                .artifact("go_cover", {"r.go": section})
                .join()
            )
        row = next(r for r in document["measures"] if r["function"] is None)
        self.assertEqual(row["values"]["coverage_pct"], 80.0)
        self.assertEqual(row["cov_source"], "statement-ratio")

    def test_a_go_function_reports_null_line_counts_not_zero(self) -> None:
        # The profile never measured lines, so the function's line counts are
        # not 0: reporting 0 executable and 0 hit claims the artifact looked
        # at the range and found nothing runnable in it.
        with tempfile.TemporaryDirectory() as tmp:
            document = (
                JoinCase(tmp)
                .complexity([complexity_row("r.go", "F", 3, 7, "go", 2)])
                .artifact(
                    "go_cover",
                    {"r.go": go_section({"3.19,4.11": (1, 1), "7.2,7.54": (5, 0)})},
                )
                .join()
            )
        row = next(r for r in document["measures"] if r["function"] == "F")
        self.assertIsNone(row["values"]["lines_executable"])
        self.assertIsNone(row["values"]["lines_hit"])
        # A profile names no functions, so coverage and CRAP stay null too.
        self.assertIsNone(row["values"]["coverage_pct"])
        self.assertIsNone(row["values"]["crap"])

    def test_a_line_measured_function_with_no_lines_in_range_reports_zero(self) -> None:
        # The other side of the same rule: this artifact does measure lines
        # and carries none in the function's range, so 0 is what it found.
        with tempfile.TemporaryDirectory() as tmp:
            document = (
                JoinCase(tmp)
                .complexity(
                    [complexity_row("a.ts", "classify", 4, 12, "typescript", 3)]
                )
                .artifact("lcov", {"a.ts": {"lines": {"1": 1}, "functions": None}})
                .join()
            )
        row = next(r for r in document["measures"] if r["function"] == "classify")
        self.assertEqual(row["values"]["lines_executable"], 0)
        self.assertEqual(row["values"]["lines_hit"], 0)
        self.assertIsNone(row["values"]["coverage_pct"])

    def test_an_empty_line_section_still_counts_as_having_measured_lines(self) -> None:
        # A line artifact covered this `.go` file and carried no executable
        # line, which is a measurement of zero. A Go profile covers it too, so
        # the merged line table is empty either way: reading the table after
        # the fact cannot tell "measured, found none" from "never measured
        # lines", and only the first is a 0. Whether a line-measuring section
        # was merged has to be recorded as it happens.
        with tempfile.TemporaryDirectory() as tmp:
            document = (
                JoinCase(tmp)
                .complexity([complexity_row("r.go", "F", 3, 7, "go", 2)])
                .artifact(
                    "go_cover",
                    {"r.go": go_section({"1.1,2.2": (1, 1), "3.1,3.9": (1, 0)})},
                )
                .artifact("lcov", {"r.go": {"lines": {}, "functions": None}})
                .join()
            )
        row = next(r for r in document["measures"] if r["function"] == "F")
        self.assertEqual(row["values"]["lines_executable"], 0)
        self.assertEqual(row["values"]["lines_hit"], 0)
        # The file row still takes its percentage from the statement ratio.
        file_row = next(r for r in document["measures"] if r["function"] is None)
        self.assertEqual(file_row["values"]["coverage_pct"], 50.0)
        self.assertEqual(file_row["cov_source"], "statement-ratio")


class PathNormalizationTests(unittest.TestCase):
    def test_an_absolute_artifact_path_joins_to_the_relative_scope_path(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            document = (
                JoinCase(tmp)
                .complexity(
                    [complexity_row("src/a.ts", "classify", 4, 12, "typescript", 3)]
                )
                .artifact(
                    "lcov",
                    {
                        "/workspace/repo/src/a.ts": {
                            "lines": {"4": 1, "5": 0},
                            "functions": None,
                        }
                    },
                )
                .join()
            )
        files = [row for row in document["measures"] if row["function"] is None]
        self.assertEqual([row["file"] for row in files], ["src/a.ts"])
        self.assertEqual(files[0]["values"]["coverage_pct"], 50.0)

    def test_a_configured_prefix_is_stripped_before_the_join(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            document = (
                JoinCase(tmp)
                .complexity(
                    [complexity_row("src/a.ts", "classify", 1, 2, "typescript", 2)]
                )
                .artifact(
                    "lcov", {"dist/src/a.ts": {"lines": {"1": 1}, "functions": None}}
                )
                .join("--prefix-strip", "dist")
            )
        self.assertEqual(document["measures"][0]["file"], "src/a.ts")

    def test_a_module_path_joins_by_a_unique_basename(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            document = (
                JoinCase(tmp)
                .complexity(
                    [complexity_row("pkg/sample.go", "Classify", 7, 15, "go", 3)]
                )
                .artifact(
                    "go_cover",
                    {
                        "example.com/mod/sample.go": {
                            "lines": {"7": 1},
                            "functions": None,
                        }
                    },
                )
                .join()
            )
        self.assertEqual(document["measures"][0]["file"], "pkg/sample.go")

    def test_an_ambiguous_suffix_joins_to_nothing(self) -> None:
        # Two services vendor the same `pkg/a.py`; an artifact naming only the
        # shared suffix must not credit whichever service came first.
        with tempfile.TemporaryDirectory() as tmp:
            document = (
                JoinCase(tmp)
                .complexity(
                    [
                        complexity_row("service-one/pkg/a.py", "f", 1, 3, "python", 1),
                        complexity_row("service-two/pkg/a.py", "f", 1, 3, "python", 1),
                    ]
                )
                .artifact(
                    "lcov",
                    {
                        "pkg/a.py": {
                            "lines": {"1": 1, "2": 1, "3": 1},
                            "functions": None,
                        }
                    },
                )
                .join()
            )
        self.assertEqual(document["measures"], [])
        coverage_row = next(r for r in document["run"] if r["measure"] == "coverage")
        self.assertEqual(coverage_row["status"], "unavailable")
        self.assertIn("0 of 2", coverage_row["reason"])

    def test_a_basename_two_artifact_paths_share_joins_to_nothing(self) -> None:
        # One profile lists `service-a/handler.go` and `service-b/handler.go`
        # and only the first is in scope. The second matches no suffix, so it
        # reaches the basename fallback, where the scope alone is unambiguous:
        # taking it would union an unrelated package's covered block into the
        # scoped file and report a file that never ran as half covered.
        with tempfile.TemporaryDirectory() as tmp:
            document = (
                JoinCase(tmp)
                .complexity(
                    [complexity_row("service-a/handler.go", "H", 1, 2, "go", 1)]
                )
                .artifact(
                    "go_cover",
                    {
                        "example.com/mod/service-a/handler.go": {
                            "lines": {},
                            "functions": None,
                            "statements": {
                                "total": 1,
                                "hit": 0,
                                "blocks": {"1.1,2.2": {"statements": 1, "count": 0}},
                            },
                        },
                        "example.com/mod/service-b/handler.go": {
                            "lines": {},
                            "functions": None,
                            "statements": {
                                "total": 1,
                                "hit": 1,
                                "blocks": {"9.1,9.9": {"statements": 1, "count": 1}},
                            },
                        },
                    },
                )
                .join()
            )
        file_row = next(r for r in document["measures"] if r["function"] is None)
        self.assertEqual(file_row["file"], "service-a/handler.go")
        self.assertEqual(file_row["values"]["coverage_pct"], 0.0)

    def test_the_collision_is_seen_across_artifacts_not_just_within_one(self) -> None:
        # The coverage skill discovers one artifact per coverage file, so two
        # services each shipping a `handler.go` arrive as two documents. A
        # count that stopped at one artifact would not see the collision at
        # all, and the out-of-scope service would credit the scoped one exactly
        # as it does inside a single profile.
        with tempfile.TemporaryDirectory() as tmp:
            document = (
                JoinCase(tmp)
                .complexity(
                    [complexity_row("service-a/handler.go", "H", 1, 2, "go", 1)]
                )
                .artifact(
                    "go_cover",
                    {
                        "example.com/mod/service-a/handler.go": go_section(
                            {"1.1,2.2": (1, 0)}
                        )
                    },
                )
                .artifact(
                    "go_cover",
                    {
                        "example.com/mod/service-b/handler.go": go_section(
                            {"9.1,9.9": (1, 1)}
                        )
                    },
                )
                .join()
            )
        file_row = next(r for r in document["measures"] if r["function"] is None)
        self.assertEqual(file_row["values"]["coverage_pct"], 0.0)

    def test_one_file_listed_under_two_spellings_is_not_a_collision(self) -> None:
        # `//` is a spelling the parsers' own normalization does not collapse.
        # Both keys name one file, so counting spellings rather than distinct
        # paths would reject the basename and drop coverage that was measured.
        with tempfile.TemporaryDirectory() as tmp:
            document = (
                JoinCase(tmp)
                .complexity([complexity_row("pkg/handler.go", "H", 1, 2, "go", 1)])
                .artifact(
                    "go_cover",
                    {
                        "example.com/mod/x/handler.go": go_section({"1.1,2.2": (1, 1)}),
                        "example.com/mod//x/handler.go": go_section(
                            {"3.1,3.9": (1, 0)}
                        ),
                    },
                )
                .join()
            )
        file_row = next(r for r in document["measures"] if r["function"] is None)
        self.assertEqual(file_row["file"], "pkg/handler.go")
        self.assertEqual(file_row["values"]["coverage_pct"], 50.0)

    def test_two_formats_naming_one_file_are_not_a_collision(self) -> None:
        # A Go profile writes the module path the compiler saw and an lcov
        # tracefile writes the repository path, so one file reaches the join
        # under two spellings that do not normalize to each other. Counting
        # basenames across formats would read that as two competing files and
        # refuse the profile, losing the statement ratio that outranks the line
        # table for exactly this file.
        with tempfile.TemporaryDirectory() as tmp:
            document = (
                JoinCase(tmp)
                .complexity([complexity_row("pkg/handler.go", "H", 1, 2, "go", 1)])
                .artifact(
                    "go_cover",
                    {
                        "example.com/mod/handler.go": go_section(
                            {"1.1,2.2": (1, 1), "3.1,3.9": (1, 0)}
                        )
                    },
                )
                .artifact(
                    "lcov",
                    {"pkg/handler.go": {"lines": {"1": 1}, "functions": None}},
                )
                .join()
            )
        file_row = next(r for r in document["measures"] if r["function"] is None)
        self.assertEqual(file_row["values"]["coverage_pct"], 50.0)
        self.assertEqual(file_row["cov_source"], "statement-ratio")

    def test_one_formats_ambiguity_does_not_refuse_another_formats_path(
        self,
    ) -> None:
        # Two `go_cover` paths share `handler.go`, so that basename is
        # ambiguous for that format. A single lcov path carrying the same
        # basename is not ambiguous for lcov and still has to reach the scoped
        # file: flattening the two formats into one set of basenames would
        # refuse it and drop line coverage the artifact really did measure.
        with tempfile.TemporaryDirectory() as tmp:
            document = (
                JoinCase(tmp)
                .complexity([complexity_row("pkg/handler.go", "H", 1, 2, "go", 1)])
                .artifact(
                    "go_cover",
                    {
                        "example.com/a/service-x/handler.go": go_section(
                            {"1.1,2.2": (1, 0)}
                        ),
                        "example.com/a/service-y/handler.go": go_section(
                            {"9.1,9.9": (1, 1)}
                        ),
                    },
                )
                .artifact(
                    "lcov",
                    {
                        "generated/handler.go": {
                            "lines": {"1": 1, "2": 0},
                            "functions": None,
                        }
                    },
                )
                .join()
            )
        file_row = next(r for r in document["measures"] if r["function"] is None)
        self.assertEqual(file_row["file"], "pkg/handler.go")
        # Line-measured, because the two statement-weighted paths were refused.
        self.assertEqual(file_row["values"]["coverage_pct"], 50.0)
        self.assertEqual(file_row["values"]["lines_executable"], 2)

    def test_resolve_without_the_ambiguous_set_keeps_the_basename_fallback(
        self,
    ) -> None:
        # The parameter is optional, and any caller that omits it gets the
        # behaviour the fallback had before the guard existed.
        self.assertEqual(
            join.resolve("example.com/mod/sample.go", ["pkg/sample.go"], "", []),
            "pkg/sample.go",
        )


class RunRowTests(unittest.TestCase):
    def test_a_lane_matched_in_part_carries_the_partial_reason(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            case = JoinCase(tmp).complexity(
                [
                    complexity_row("src/a.ts", "classify", 1, 3, "typescript", 2),
                    complexity_row("src/b.ts", "other", 1, 3, "typescript", 2),
                ]
            )
            document = case.artifact(
                "lcov", {"src/a.ts": {"lines": {"1": 1}, "functions": None}}
            ).join()
        row = [r for r in document["run"] if r["measure"] == "coverage"][0]
        # Half the lane was measured and half was not, so the row is neither
        # ok nor unavailable; reporting it ok let the assembler call the whole
        # document complete while this row said 1 of 2.
        self.assertEqual(row["status"], "partial")
        self.assertIn(
            "partial, 1 of 2 scope files present in the artifacts", row["reason"]
        )

    def test_a_lane_matched_by_nothing_is_unavailable_with_its_count(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            document = (
                JoinCase(tmp)
                .complexity(
                    [complexity_row("src/a.ts", "classify", 1, 3, "typescript", 2)]
                )
                .artifact(
                    "lcov", {"other/z.ts": {"lines": {"1": 1}, "functions": None}}
                )
                .join()
            )
        row = [r for r in document["run"] if r["measure"] == "coverage"][0]
        self.assertEqual(row["status"], "unavailable")
        self.assertIn(
            "partial, 0 of 1 scope files present in the artifacts", row["reason"]
        )

    def test_no_artifact_at_all_lists_the_paths_searched(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            document = (
                JoinCase(tmp)
                .complexity(
                    [complexity_row("src/a.ts", "classify", 1, 3, "typescript", 2)]
                )
                .join("--searched", "coverage/lcov.info", "--searched", "coverage.xml")
            )
        row = [r for r in document["run"] if r["measure"] == "coverage"][0]
        self.assertEqual(row["status"], "unavailable")
        self.assertIn("coverage/lcov.info, coverage.xml", row["reason"])
        self.assertEqual(document["measures"], [])

    def test_a_lane_without_function_end_lines_reports_crap_not_applicable(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            document = (
                JoinCase(tmp)
                .complexity(
                    [complexity_row("cm-greet.sh", "greet", 8, None, "bash", 3)]
                )
                .artifact(
                    "cobertura", {"cm-greet.sh": {"lines": {"9": 1}, "functions": None}}
                )
                .join()
            )
        rows = {row["measure"]: row for row in document["run"] if row["lane"] == "bash"}
        self.assertEqual(rows["coverage"]["status"], "ok")
        self.assertEqual(rows["crap"]["status"], "not-applicable")
        self.assertIn("no function end lines", rows["crap"]["reason"])
        self.assertEqual([r for r in document["measures"] if r["function"]], [])


class FunctionRowTests(unittest.TestCase):
    def test_an_artifact_region_wins_over_the_line_range(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            document = (
                JoinCase(tmp)
                .complexity([complexity_row("a.py", "classify", 9, 20, "python", 3)])
                .artifact(
                    "coverage_py_json",
                    {
                        "a.py": {
                            "lines": {
                                "9": 1,
                                "12": 1,
                                "16": 1,
                                "17": 1,
                                "18": 0,
                                "19": 0,
                                "20": 0,
                            },
                            "functions": [
                                {
                                    "name": "classify",
                                    "start_line": 12,
                                    "end_line": 20,
                                    "hit": 1,
                                    "lines": {
                                        "12": 1,
                                        "16": 1,
                                        "17": 1,
                                        "18": 0,
                                        "19": 0,
                                        "20": 0,
                                    },
                                }
                            ],
                        }
                    },
                )
                .join()
            )
        row = [r for r in document["measures"] if r["function"] == "classify"][0]
        self.assertEqual(row["cov_source"], "artifact-region")
        self.assertEqual(row["values"]["coverage_pct"], 50.0)
        self.assertEqual(row["values"]["crap"], 4.125)
        self.assertEqual(row["hit"], 1)

    def test_a_nested_range_is_subtracted_from_the_parent(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            document = (
                JoinCase(tmp)
                .complexity(
                    [
                        complexity_row("a.py", "classify", 9, 20, "python", 3),
                        complexity_row("a.py", "classify.inner", 12, 14, "python", 2),
                    ]
                )
                .artifact(
                    "lcov",
                    {
                        "a.py": {
                            "lines": {"9": 1, "12": 1, "14": 1, "16": 0, "20": 0},
                            "functions": None,
                        }
                    },
                )
                .join()
            )
        outer = [r for r in document["measures"] if r["function"] == "classify"][0]
        inner = [r for r in document["measures"] if r["function"] == "classify.inner"][
            0
        ]
        self.assertEqual(outer["cov_source"], "line-range")
        self.assertEqual(outer["values"]["lines_executable"], 3)
        self.assertEqual(outer["values"]["lines_hit"], 1)
        self.assertEqual(inner["values"]["lines_executable"], 2)

    def test_a_function_hit_flag_of_zero_forces_zero_percent(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            document = (
                JoinCase(tmp)
                .complexity(
                    [complexity_row("a.ts", "classify", 4, 12, "typescript", 3)]
                )
                .artifact(
                    "lcov",
                    {
                        "a.ts": {
                            "lines": {"4": 1, "5": 0, "6": 0},
                            "functions": [
                                {
                                    "name": "classify",
                                    "start_line": 4,
                                    "end_line": None,
                                    "hit": 0,
                                    "lines": None,
                                }
                            ],
                        }
                    },
                )
                .join()
            )
        row = [r for r in document["measures"] if r["function"] == "classify"][0]
        self.assertEqual(row["values"]["coverage_pct"], 0)
        self.assertEqual(row["values"]["crap"], 12)
        self.assertEqual(row["hit"], 0)

    def test_no_executable_lines_reports_null_not_zero(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            document = (
                JoinCase(tmp)
                .complexity(
                    [complexity_row("a.ts", "classify", 4, 12, "typescript", 3)]
                )
                .artifact("lcov", {"a.ts": {"lines": {"1": 1}, "functions": None}})
                .join()
            )
        row = [r for r in document["measures"] if r["function"] == "classify"][0]
        self.assertIsNone(row["values"]["coverage_pct"])
        self.assertIsNone(row["values"]["crap"])

    def test_every_coverage_row_carries_a_cov_source(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            document = (
                JoinCase(tmp)
                .complexity(
                    [complexity_row("a.ts", "classify", 4, 12, "typescript", 3)]
                )
                .artifact("lcov", {"a.ts": {"lines": {"4": 1}, "functions": None}})
                .join()
            )
        self.assertTrue(document["measures"])
        for row in document["measures"]:
            self.assertIn(row["cov_source"], ("artifact-region", "line-range"))


class ShortNameJoinTests(unittest.TestCase):
    """The trailing-name fallback, tie-broken by line range.

    An artifact that records a method as `run` rather than as `Alpha.run`
    matches every function in the file whose name ends in `run`, so the name
    alone cannot say which one it measured. The committed fixture
    `../../../scripts/fixtures/coverage/lcov-short-names.info` holds the four
    shapes that decide it: `src/dispatch.py`, where the record sits in the
    second function's range; `src/handler.py`, the same shape with the record
    moved into the first function's range; `src/router.py`, where an `FNDA`
    with no `FN` declaration names the function and places it nowhere; and
    `src/relay.py`, where two records named `run` sit inside the first
    function's range and neither one starts where it does. Every section
    declares the same two functions,
    `Alpha.run` at 3-6 and `Beta.run` at 11-14, so what changes between them is
    only where the coverage sits.
    """

    PATHS = ("src/dispatch.py", "src/handler.py", "src/router.py", "src/relay.py")

    def _document(self) -> dict:
        parsed = subprocess.run(
            [sys.executable, str(LCOV_PARSER), str(SHORT_NAME_FIXTURE)],
            capture_output=True,
            text=True,
            check=False,
        )
        assert parsed.returncode == 0, parsed.stderr
        with tempfile.TemporaryDirectory() as tmp:
            case = JoinCase(tmp).complexity(
                [
                    complexity_row(path, name, start, end, "python", 3)
                    for path in self.PATHS
                    for name, start, end in (("Alpha.run", 3, 6), ("Beta.run", 11, 14))
                ]
            )
            case.artifact("lcov", json.loads(parsed.stdout))
            return case.join()

    @staticmethod
    def _rows(document: dict, path: str) -> dict:
        return {
            row["function"]: row
            for row in document["measures"]
            if row["file"] == path and row["function"]
        }

    def test_a_short_name_binds_to_the_function_whose_range_holds_it(self) -> None:
        # The record is placed at 11-14, which is `Beta.run`. Bound by the
        # trailing name alone it also reached `Alpha.run`, which never ran, and
        # reported it at 100 percent out of the other method's region.
        rows = self._rows(self._document(), "src/dispatch.py")
        self.assertEqual(rows["Beta.run"]["values"]["coverage_pct"], 100.0)
        self.assertEqual(rows["Beta.run"]["cov_source"], "artifact-region")
        self.assertEqual(rows["Beta.run"]["hit"], 4)
        self.assertEqual(rows["Alpha.run"]["values"]["coverage_pct"], 0.0)
        self.assertEqual(rows["Alpha.run"]["cov_source"], "line-range")
        self.assertIsNone(rows["Alpha.run"]["hit"])

    def test_moving_the_record_moves_the_binding(self) -> None:
        # The same two functions with the record at 3-6 instead. The binding
        # follows the range rather than the order the functions were measured
        # in, so this is the mirror of the case above and not a repeat of it.
        rows = self._rows(self._document(), "src/handler.py")
        self.assertEqual(rows["Alpha.run"]["values"]["coverage_pct"], 100.0)
        self.assertEqual(rows["Alpha.run"]["cov_source"], "artifact-region")
        self.assertEqual(rows["Alpha.run"]["hit"], 4)
        self.assertEqual(rows["Beta.run"]["values"]["coverage_pct"], 0.0)
        self.assertEqual(rows["Beta.run"]["cov_source"], "line-range")
        self.assertIsNone(rows["Beta.run"]["hit"])

    def test_an_unplaceable_record_leaves_both_functions_unjoined(self) -> None:
        # `FNDA:4,run` with no `FN` declaration names a function and places it
        # at no line at all, so nothing separates the two `run` methods. Both
        # rows are withheld rather than one of them taking the count.
        rows = self._rows(self._document(), "src/router.py")
        for name in ("Alpha.run", "Beta.run"):
            row = rows[name]
            self.assertEqual(row["cov_source"], "ambiguous")
            self.assertIn("coverage-ambiguous", row["labels"])
            self.assertIsNone(row["values"]["coverage_pct"])
            self.assertIsNone(row["values"]["crap"])
            self.assertIsNone(row["hit"])
            self.assertEqual(row["values"]["cyclomatic"], 3)

    def test_two_records_inside_one_range_leave_that_function_unjoined(self) -> None:
        # `src/relay.py` declares `run` twice, at 4-4 and at 5-6, two nested
        # closures the artifact also recorded short, and both sit inside
        # `Alpha.run` at 3-6. The range narrows the candidates without
        # separating them, so taking the first would hand `Alpha.run` a hit
        # count that is one of the two records and no way to tell which. The
        # row is withheld and says why. `Beta.run` at 11-14 holds neither
        # record, so it keeps the line-range fallback over its own lines.
        rows = self._rows(self._document(), "src/relay.py")
        alpha = rows["Alpha.run"]
        self.assertEqual(alpha["cov_source"], "ambiguous")
        self.assertIn("coverage-ambiguous", alpha["labels"])
        self.assertIsNone(alpha["values"]["coverage_pct"])
        self.assertIsNone(alpha["values"]["crap"])
        self.assertIsNone(alpha["hit"])
        self.assertIn("fall inside this function's line range", alpha["reason"])
        self.assertEqual(rows["Beta.run"]["cov_source"], "line-range")
        self.assertEqual(rows["Beta.run"]["values"]["coverage_pct"], 0.0)

    def test_the_lane_run_row_reports_the_functions_it_left_unjoined(self) -> None:
        # The refusal has to be visible without reading the JSON row by row:
        # the lane says it measured only part of itself and names what it could
        # not place, so the document cannot then settle as complete.
        document = self._document()
        row = next(
            entry
            for entry in document["run"]
            if entry["lane"] == "python" and entry["measure"] == "coverage"
        )
        self.assertEqual(row["status"], "partial")
        # Both refusals reach the row: the two unplaced records in
        # `src/router.py` and the two in-range records in `src/relay.py`.
        self.assertIn("3 function(s) left unjoined", row["reason"])
        self.assertIn("Alpha.run", row["reason"])
        self.assertIn("Beta.run", row["reason"])
        self.assertIn("carries no line range", row["reason"])
        self.assertIn("fall inside this function's line range", row["reason"])

    def test_a_lone_short_name_still_binds_where_nothing_contests_it(self) -> None:
        # The single-candidate trailing-name match is unchanged: one record,
        # one function that could own it, no tie to break. Its start line is
        # nowhere near the measured range on purpose, which is what an artifact
        # built from compiled output looks like.
        with tempfile.TemporaryDirectory() as tmp:
            document = (
                JoinCase(tmp)
                .complexity(
                    [complexity_row("src/only.py", "Alpha.run", 3, 6, "python", 3)]
                )
                .artifact(
                    "lcov",
                    {
                        "src/only.py": {
                            "lines": {"4": 2, "5": 2},
                            "functions": [
                                {
                                    "name": "run",
                                    "start_line": 40,
                                    "end_line": None,
                                    "hit": 2,
                                    "lines": None,
                                }
                            ],
                        }
                    },
                )
                .join()
            )
        row = self._rows(document, "src/only.py")["Alpha.run"]
        self.assertEqual(row["hit"], 2)
        self.assertEqual(row["values"]["coverage_pct"], 100.0)
        self.assertEqual(
            next(entry for entry in document["run"] if entry["measure"] == "coverage")[
                "status"
            ],
            "ok",
        )


class OutputTests(unittest.TestCase):
    def test_the_jsonl_outputs_match_the_printed_document(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            case = JoinCase(tmp).complexity(
                [complexity_row("a.ts", "classify", 4, 12, "typescript", 3)]
            )
            case.artifact("lcov", {"a.ts": {"lines": {"4": 1}, "functions": None}})
            rows_out = Path(tmp) / "rows.jsonl"
            run_out = Path(tmp) / "run.jsonl"
            document = case.join(
                "--measures-out", str(rows_out), "--run-out", str(run_out)
            )
            rows = [json.loads(line) for line in rows_out.read_text().splitlines()]
            runs = [json.loads(line) for line in run_out.read_text().splitlines()]
        self.assertEqual(rows, document["measures"])
        self.assertEqual(runs, document["run"])

    def test_the_self_test_exits_zero(self) -> None:
        result = run("--self-test")
        self.assertEqual(result.returncode, 0)
        self.assertIn("ok", result.stdout)

    def test_a_missing_complexity_document_is_a_usage_error(self) -> None:
        self.assertEqual(run("--scope", "nowhere.txt").returncode, 2)


if __name__ == "__main__":
    unittest.main()
