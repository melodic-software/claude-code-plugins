#!/usr/bin/env python3
"""Output-based tests for join.py at its command line.

Each case writes a small complexity document and one or more parsed-artifact
documents into a temporary directory, so the shapes under test (an absolute
`SF:` path, a lane with no function end lines, a function with no executable
lines) are visible in the test rather than buried in a fixture tree. The
end-to-end join over the committed fixtures is the shell suite's job.
"""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
SCRIPT = SCRIPT_DIR / "join.py"


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
        (self.dir / "scope.txt").write_text("\n".join(paths) + "\n", encoding="utf-8")
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
