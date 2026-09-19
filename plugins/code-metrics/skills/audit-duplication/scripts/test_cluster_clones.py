#!/usr/bin/env python3
"""Output-based tests for cluster-clones.py at its command line.

The post-pass is a pure function from a document to a document, so every case
drives the script through subprocess with a small document on stdin (design
T13, the one seam per script). The committed captures
scripts/fixtures/tool-output/jscpd-aligned3.json and jscpd-offset3.json cover
the shapes jscpd itself reports for three copies; these cases cover the rule.
"""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent / "cluster-clones.py"


def instance(path: str, start: int, end: int) -> dict:
    return {"file": path, "start_line": start, "end_line": end}


def pair(
    first: tuple[str, int, int],
    second: tuple[str, int, int],
    lines: int = 41,
    collector: str = "jscpd",
    labels: list[str] | None = None,
) -> dict:
    return {
        "file": None,
        "function": None,
        "lane": "bash",
        "instances": [instance(*first), instance(*second)],
        "values": {"lines": lines, "tokens": 110},
        "collector": collector,
        "labels": ["token-based"] if labels is None else labels,
    }


def document(*rows: dict) -> dict:
    return {
        "schema": "code-metrics/v1",
        "skill": "audit-duplication",
        "measures": list(rows),
        "excluded": [],
        "summary": {"files": 0, "functions": 0, "over_reference": {}},
    }


def run(doc: dict | str, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, str(SCRIPT), *args],
        input=doc if isinstance(doc, str) else json.dumps(doc),
        capture_output=True,
        text=True,
        check=False,
    )


def measures(result: subprocess.CompletedProcess) -> list[dict]:
    return json.loads(result.stdout)["measures"]


A = "plugins/x/a/shared/shared-utils.sh"
B = "plugins/x/b/shared/shared-utils.sh"
C = "plugins/x/c/shared/shared-utils.sh"


class ClusterClonesTests(unittest.TestCase):
    def test_three_aligned_copies_collapse_to_one_class(self) -> None:
        # jscpd pairs every later copy with the first, so two rows name the
        # same instance of the first copy.
        result = run(
            document(pair((A, 1, 41), (B, 1, 41)), pair((A, 1, 41), (C, 1, 41)))
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        rows = measures(result)
        self.assertEqual(len(rows), 1)
        self.assertEqual([i["file"] for i in rows[0]["instances"]], [A, B, C])
        self.assertEqual(rows[0]["values"], {"lines": 41, "tokens": 110})
        self.assertEqual(rows[0]["labels"], ["token-based", "clustered"])

    def test_the_lines_of_a_merged_class_count_once(self) -> None:
        result = run(
            document(pair((A, 1, 41), (B, 1, 41)), pair((A, 1, 41), (C, 1, 41)))
        )
        rows = measures(result)
        self.assertEqual(sum(row["values"]["lines"] for row in rows), 41)

    def test_overlap_without_an_identical_range_stays_two_groups(self) -> None:
        # The third copy carries only part of the fragment, so its pair names
        # the first copy with a shorter range.
        result = run(
            document(
                pair(("c1.sh", 3, 36), ("c2.sh", 4, 37), lines=34),
                pair(("c1.sh", 3, 26), ("c3.sh", 5, 28), lines=24),
            )
        )
        rows = measures(result)
        self.assertEqual(len(rows), 2)
        self.assertTrue(all(len(row["instances"]) == 2 for row in rows))
        self.assertTrue(all("clustered" not in row["labels"] for row in rows))

    def test_an_identical_range_with_different_lines_does_not_join(self) -> None:
        result = run(
            document(
                pair((A, 1, 41), (B, 1, 41), lines=41),
                pair((A, 1, 41), (C, 1, 41), lines=40),
            )
        )
        self.assertEqual(len(measures(result)), 2)

    def test_a_three_instance_row_passes_through_unchanged(self) -> None:
        row = pair((A, 1, 41), (B, 1, 41))
        row["instances"].append(instance(C, 1, 41))
        other = pair((A, 1, 41), ("plugins/x/d/shared/shared-utils.sh", 1, 41))
        result = run(document(row, other))
        rows = measures(result)
        self.assertEqual(rows[0], row)
        self.assertEqual(rows[1], other)

    def test_a_pair_from_another_collector_joins_on_an_identical_instance(
        self,
    ) -> None:
        result = run(
            document(
                pair((A, 1, 41), (B, 1, 41)),
                pair((A, 1, 41), (C, 1, 41), collector="cpd", labels=["cpd"]),
            )
        )
        rows = measures(result)
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["collector"], "jscpd")
        self.assertEqual([i["file"] for i in rows[0]["instances"]], [A, B, C])

    def test_merged_instances_are_sorted_by_path_then_start_line(self) -> None:
        result = run(
            document(pair((C, 1, 41), (B, 1, 41)), pair((A, 1, 41), (B, 1, 41)))
        )
        rows = measures(result)
        self.assertEqual(len(rows), 1)
        self.assertEqual([i["file"] for i in rows[0]["instances"]], [A, B, C])

    def test_a_chain_of_pairs_closes_into_one_class(self) -> None:
        result = run(
            document(pair((A, 1, 41), (B, 1, 41)), pair((B, 1, 41), (C, 1, 41)))
        )
        rows = measures(result)
        self.assertEqual(len(rows), 1)
        self.assertEqual([i["file"] for i in rows[0]["instances"]], [A, B, C])

    def test_the_class_is_emitted_where_its_first_pair_stood(self) -> None:
        unrelated = pair(("y.sh", 1, 10), ("z.sh", 1, 10), lines=10)
        result = run(
            document(
                pair((A, 1, 41), (B, 1, 41)), unrelated, pair((A, 1, 41), (C, 1, 41))
            )
        )
        rows = measures(result)
        self.assertEqual(len(rows), 2)
        self.assertEqual(len(rows[0]["instances"]), 3)
        self.assertEqual(rows[1], unrelated)

    def test_rows_without_instances_and_the_summary_pass_through(self) -> None:
        file_row = {
            "file": "a.sh",
            "function": None,
            "lane": "bash",
            "values": {"lines": 3},
            "collector": "scc",
        }
        doc = document(file_row, pair((A, 1, 41), (B, 1, 41)))
        doc["summary"] = {"files": 9, "functions": 0, "over_reference": {}}
        result = run(doc)
        out = json.loads(result.stdout)
        self.assertEqual(out["measures"][0], file_row)
        self.assertEqual(out["summary"], doc["summary"])
        self.assertEqual(out["excluded"], [])

    def test_stdin_that_is_not_json_is_a_usage_error(self) -> None:
        result = run("not json")
        self.assertEqual(result.returncode, 2)
        self.assertIn("not a JSON document", result.stderr)

    def test_an_unknown_argument_is_a_usage_error(self) -> None:
        self.assertEqual(run(document(), "--root").returncode, 2)
        self.assertEqual(run(document(), "--registry", "x").returncode, 2)

    def test_root_sorts_instances_by_their_root_relative_path(self) -> None:
        # From `lib/`, the dispatcher names the root copy `hook-utils.sh` and
        # a plugin copy `../plugins/a/hooks/hook-utils.sh`, which sorts first
        # as text; relative to the root the `lib/` copy comes first, so the
        # rollup attributes the class the same way a root run does.
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            lib = root / "lib"
            lib.mkdir()
            doc = document(
                pair(
                    ("../plugins/a/hooks/hook-utils.sh", 1, 41),
                    ("hook-utils.sh", 1, 41),
                ),
                pair(
                    ("../plugins/b/hooks/hook-utils.sh", 1, 41),
                    ("hook-utils.sh", 1, 41),
                ),
            )
            result = subprocess.run(
                [sys.executable, str(SCRIPT), "--root", tmp],
                input=json.dumps(doc),
                capture_output=True,
                text=True,
                cwd=lib,
                check=False,
            )
        self.assertEqual(result.returncode, 0, result.stderr)
        rows = measures(result)
        self.assertEqual(len(rows), 1)
        self.assertEqual(
            [i["file"] for i in rows[0]["instances"]],
            [
                "hook-utils.sh",
                "../plugins/a/hooks/hook-utils.sh",
                "../plugins/b/hooks/hook-utils.sh",
            ],
        )


if __name__ == "__main__":
    unittest.main()
