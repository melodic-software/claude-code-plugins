#!/usr/bin/env python3
"""Output-based tests for go_cover.py, driven at its command line.

The committed fixture is `../fixtures/coverage/go-cover.out`, a `mode: set`
profile for the Go fixture source under the module path the compiler would
have seen. Count-mode, malformed and statement-weighted profiles are written
into a temporary directory.

`JoinTests` drives the parser's output through the audit-coverage join, which
is where the profile's numbers become a reported percentage. The profile in
that test is the one `go test -coverprofile` writes for the function quoted in
`go_cover.py`, and `go tool cover -func` reports it as 28.6%.
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
JOIN = SCRIPT_DIR.parent.parent / "skills" / "audit-coverage" / "scripts" / "join.py"
MODULE_PATH = "example.com/cmsample/cm-sample.go"

# Three blocks, 7 statements, 2 of them hit: `go test -coverprofile` on
#
#     func F(x int) int {
#         if x > 0 {
#             return 1
#         }
#         a := 1; b := 2; c := 3; d := 4; return a + b + c + d
#     }
#
# exercised only by F(1). `go tool cover -func` reports 28.6%.
DENSE_PROFILE = (
    "mode: set\n"
    "example.com/m/r.go:3.19,4.11 1 1\n"
    "example.com/m/r.go:4.11,6.3 1 1\n"
    "example.com/m/r.go:7.2,7.54 5 0\n"
)

# Two shards of one suite over the same file, each entering the block the
# other missed. Each reports 2 statements with 1 hit; between them both
# statements ran, so the union is 2 of 2.
SHARD_A = (
    "mode: set\nexample.com/m/r.go:3.19,4.11 1 1\nexample.com/m/r.go:7.2,7.54 1 0\n"
)
SHARD_B = (
    "mode: set\nexample.com/m/r.go:3.19,4.11 1 0\nexample.com/m/r.go:7.2,7.54 1 1\n"
)


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


def totals(document: dict, path: str) -> dict:
    """A file's `total` and `hit`, read without the block table beside them."""
    statements = document[path]["statements"]
    return {"total": statements["total"], "hit": statements["hit"]}


class FixtureTests(unittest.TestCase):
    def test_a_profile_reports_no_per_line_coverage(self) -> None:
        # A block is a statement count over a line range and never says which
        # of those lines carry statements, so there is no honest line table.
        document = parsed(str(FIXTURE))
        self.assertEqual(list(document), [MODULE_PATH])
        self.assertEqual(document[MODULE_PATH]["lines"], {})

    def test_the_profiles_own_statement_weights_survive(self) -> None:
        # Five one-statement blocks, one of them never entered.
        self.assertEqual(
            totals(parsed(str(FIXTURE)), MODULE_PATH), {"total": 5, "hit": 4}
        )

    def test_a_profile_names_no_functions(self) -> None:
        self.assertIsNone(parsed(str(FIXTURE))[MODULE_PATH]["functions"])


class StatementWeightTests(unittest.TestCase):
    def test_the_weights_match_go_tool_cover_func(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            document = parsed(write(tmp, "dense.out", DENSE_PROFILE))
        weights = totals(document, "example.com/m/r.go")
        self.assertEqual(weights, {"total": 7, "hit": 2})
        self.assertEqual(round(100.0 * weights["hit"] / weights["total"], 1), 28.6)

    def test_a_wide_block_does_not_outweigh_a_dense_one(self) -> None:
        # Two hit statements over seven lines against five missed statements on
        # one line. Counting lines calls this 87.5% covered; the statements the
        # profile actually weighs make it 28.6%.
        body = (
            "mode: set\n"
            "example.com/m/r.go:2.10,8.4 2 1\n"
            "example.com/m/r.go:9.2,9.40 5 0\n"
        )
        with tempfile.TemporaryDirectory() as tmp:
            document = parsed(write(tmp, "wide.out", body))
        self.assertEqual(totals(document, "example.com/m/r.go"), {"total": 7, "hit": 2})

    def test_the_block_table_keeps_each_blocks_own_identity(self) -> None:
        # The aggregates cannot be unioned across two profiles of the same
        # file once they are summed, so each block travels to the join under
        # the profile's own `start.col,end.col` identity with its statement
        # count and its execution count.
        with tempfile.TemporaryDirectory() as tmp:
            document = parsed(write(tmp, "dense.out", DENSE_PROFILE))
        self.assertEqual(
            document["example.com/m/r.go"]["statements"]["blocks"],
            {
                "3.19,4.11": {"statements": 1, "count": 1},
                "4.11,6.3": {"statements": 1, "count": 1},
                "7.2,7.54": {"statements": 5, "count": 0},
            },
        )

    def test_a_repeated_block_is_weighed_once(self) -> None:
        # Two profiles concatenated list the same block twice. Its statements
        # count once, and the larger of the two counts wins.
        body = "mode: count\nm/a.go:1.1,3.2 2 0\nm/a.go:1.1,3.2 2 4\n"
        with tempfile.TemporaryDirectory() as tmp:
            document = parsed(write(tmp, "repeat.out", body))
        self.assertEqual(totals(document, "m/a.go"), {"total": 2, "hit": 2})
        self.assertEqual(
            document["m/a.go"]["statements"]["blocks"],
            {"1.1,3.2": {"statements": 2, "count": 4}},
        )

    def test_blocks_differing_only_in_column_are_separate(self) -> None:
        body = "mode: set\nm/a.go:1.1,3.2 1 1\nm/a.go:1.9,3.2 1 0\n"
        with tempfile.TemporaryDirectory() as tmp:
            document = parsed(write(tmp, "cols.out", body))
        self.assertEqual(totals(document, "m/a.go"), {"total": 2, "hit": 1})


class JoinTests(unittest.TestCase):
    def file_row(self, *profiles: str) -> dict:
        """The `r.go` file row of a join over each profile, parsed for real."""
        with tempfile.TemporaryDirectory() as tmp:
            artifacts = []
            for index, body in enumerate(profiles):
                document = parsed(write(tmp, f"profile-{index}.out", body))
                path = write(tmp, f"parsed-{index}.json", json.dumps(document))
                artifacts += ["--artifacts", f"go_cover:{path}"]
            write(tmp, "scope.txt", "r.go\n")
            write(
                tmp,
                "complexity.json",
                json.dumps(
                    {
                        "schema": "code-metrics/v1",
                        "skill": "audit-complexity",
                        "measures": [],
                        "run": [],
                    }
                ),
            )
            result = subprocess.run(
                [
                    sys.executable,
                    str(JOIN),
                    "--complexity",
                    str(Path(tmp) / "complexity.json"),
                    "--scope",
                    str(Path(tmp) / "scope.txt"),
                    "--root",
                    tmp,
                    *artifacts,
                ],
                capture_output=True,
                text=True,
                check=False,
            )
        self.assertEqual(result.returncode, 0, result.stderr)
        rows = json.loads(result.stdout)["measures"]
        return next(r for r in rows if r["file"] == "r.go" and r["function"] is None)

    def test_the_join_reports_the_ratio_go_tool_cover_func_prints(self) -> None:
        row = self.file_row(DENSE_PROFILE)
        # For this profile `go tool cover -func` says 28.6%: 7 statements, 2
        # of them hit. The percentage comes from the profile's own statement
        # counts, so it is the tool's own number; weighing each block by the
        # lines it spans would report 80% instead.
        self.assertEqual(row["values"]["coverage_pct"], 28.57)
        # Those counts are statements, not lines, and the profile never says
        # which lines carry them. Reporting 0 executable lines would claim the
        # artifact measured none; it measured 7 of something else.
        self.assertIsNone(row["values"]["lines_executable"])
        self.assertIsNone(row["values"]["lines_hit"])
        self.assertEqual(row["cov_source"], "statement-ratio")

    def test_two_shard_profiles_union_their_blocks(self) -> None:
        # Two test shards, each entering the block the other missed. Both
        # profiles report 2 statements with 1 hit, and both statements ran
        # between them, so the merged answer is 2 of 2. Any rule over the two
        # aggregates reports 1 of 2, because a maximum cannot union.
        self.assertEqual(self.file_row(SHARD_A)["values"]["coverage_pct"], 50.0)
        self.assertEqual(self.file_row(SHARD_B)["values"]["coverage_pct"], 50.0)
        self.assertEqual(
            self.file_row(SHARD_A, SHARD_B)["values"]["coverage_pct"], 100.0
        )

    def test_a_block_both_shards_list_is_weighed_once(self) -> None:
        # The union is over block identity, so the same file measured twice
        # is not twice the statements.
        self.assertEqual(
            self.file_row(DENSE_PROFILE, DENSE_PROFILE)["values"]["coverage_pct"], 28.57
        )


class ModeTests(unittest.TestCase):
    def test_count_mode_weighs_an_executed_block_as_hit(self) -> None:
        body = "mode: count\nm/a.go:1.1,3.2 2 17\n"
        with tempfile.TemporaryDirectory() as tmp:
            document = parsed(write(tmp, "count.out", body))
        self.assertEqual(totals(document, "m/a.go"), {"total": 2, "hit": 2})
        self.assertEqual(document["m/a.go"]["lines"], {})

    def test_a_profile_without_a_mode_header_exits_2(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run(write(tmp, "headless.out", "m/a.go:1.1,2.2 1 1\n"))
        self.assertEqual(result.returncode, 2)
        self.assertIn("mode:", result.stderr)

    def test_an_unparsable_block_line_is_skipped_not_fatal(self) -> None:
        body = "mode: set\nnot a block line\nm/a.go:1.1,1.2 1 1\n"
        with tempfile.TemporaryDirectory() as tmp:
            document = parsed(write(tmp, "noise.out", body))
        self.assertEqual(totals(document, "m/a.go"), {"total": 1, "hit": 1})

    def test_usage_error_without_an_artifact(self) -> None:
        result = run()
        self.assertEqual(result.returncode, 2)
        self.assertIn("usage", result.stderr)


if __name__ == "__main__":
    unittest.main()
