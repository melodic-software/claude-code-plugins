#!/usr/bin/env python3
"""Output-based tests for replica-collapse.py at its command line."""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
SCRIPT = SCRIPT_DIR / "replica-collapse.py"


def run(*args: str, stdin: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, str(SCRIPT), *args],
        capture_output=True,
        text=True,
        input=stdin,
        check=False,
    )


def row(file: str, function: str = "greet", **fields) -> dict:
    base = {
        "file": file,
        "function": function,
        "start_line": 8,
        "end_line": None,
        "lane": "bash",
        "values": {"cyclomatic": 22},
        "collector": "shellmetrics",
        "labels": ["start-line-only"],
        "over_reference": ["cyclomatic"],
    }
    base.update(fields)
    return base


def document(measures: list[dict]) -> str:
    return json.dumps(
        {
            "schema": "code-metrics/v1",
            "skill": "audit-complexity",
            "status": "complete",
            "scope": {"mode": "all", "files": len(measures)},
            "run": [],
            "thresholds": [],
            "measures": measures,
            "summary": {},
            "excluded": [],
            "unavailable": [],
        }
    )


class ReplicaCollapseTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.registry = Path(self.tmp.name) / "registry.txt"
        self.registry.write_text("# shared\n\nhooks/hook-utils.sh\n", encoding="utf-8")

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def test_copies_under_distinct_carriers_collapse_to_one_labelled_row(self) -> None:
        rows = [
            row("plugins/b/hooks/hook-utils.sh"),
            row("plugins/a/hooks/hook-utils.sh"),
            row("plugins/c/hooks/hook-utils.sh"),
            row(
                "lib/other.sh",
                function="main",
                values={"cyclomatic": 3},
                over_reference=[],
            ),
        ]
        result = run("--registry", str(self.registry), stdin=document(rows))
        self.assertEqual(result.returncode, 0, result.stderr)
        out = json.loads(result.stdout)["measures"]
        self.assertEqual(
            [r["file"] for r in out], ["plugins/a/hooks/hook-utils.sh", "lib/other.sh"]
        )
        survivor = out[0]
        self.assertIn("replicated", survivor["labels"])
        self.assertEqual(survivor["replicas"]["count"], 3)
        self.assertEqual(survivor["replicas"]["line"], 3)
        self.assertEqual(survivor["replicas"]["path"], "hooks/hook-utils.sh")
        self.assertEqual(
            survivor["replicas"]["files"],
            [
                "plugins/a/hooks/hook-utils.sh",
                "plugins/b/hooks/hook-utils.sh",
                "plugins/c/hooks/hook-utils.sh",
            ],
        )
        self.assertNotIn("replicas", out[1])

    def test_copies_whose_numbers_differ_stay_separate(self) -> None:
        rows = [
            row("plugins/a/hooks/hook-utils.sh"),
            row("plugins/b/hooks/hook-utils.sh", values={"cyclomatic": 23}),
        ]
        result = run("--registry", str(self.registry), stdin=document(rows))
        out = json.loads(result.stdout)["measures"]
        self.assertEqual(len(out), 2)
        self.assertTrue(all("replicas" not in r for r in out))

    def test_a_cluster_line_is_left_to_the_clone_group_reader(self) -> None:
        # `<canonical> -> <member>...` names a root canonical for the
        # duplication audit; it is never a path-within-plugin, so this pass
        # skips it and the plain line beside it still collapses.
        registry = Path(self.tmp.name) / "clusters.txt"
        registry.write_text(
            "lib/hook-utils.sh -> plugins/*/hooks/hook-utils.sh\nhooks/hook-utils.sh\n",
            encoding="utf-8",
        )
        rows = [
            row("lib/hook-utils.sh"),
            row("plugins/a/hooks/hook-utils.sh"),
            row("plugins/b/hooks/hook-utils.sh"),
        ]
        result = run("--registry", str(registry), stdin=document(rows))
        self.assertEqual(result.returncode, 0, result.stderr)
        out = json.loads(result.stdout)["measures"]
        self.assertEqual(
            [r["file"] for r in out],
            ["lib/hook-utils.sh", "plugins/a/hooks/hook-utils.sh"],
        )
        self.assertEqual(out[1]["replicas"]["count"], 2)
        self.assertEqual(out[1]["replicas"]["line"], 2)

    def test_a_single_copy_is_not_a_replica(self) -> None:
        rows = [row("plugins/a/hooks/hook-utils.sh")]
        result = run("--registry", str(self.registry), stdin=document(rows))
        out = json.loads(result.stdout)["measures"]
        self.assertEqual(len(out), 1)
        self.assertNotIn("replicas", out[0])

    def test_prefix_makes_a_subdirectory_run_match_root_relative_lines(self) -> None:
        rows = [row("a/hooks/hook-utils.sh"), row("b/hooks/hook-utils.sh")]
        result = run(
            "--prefix",
            "plugins/",
            "--registry",
            str(self.registry),
            stdin=document(rows),
        )
        out = json.loads(result.stdout)["measures"]
        self.assertEqual(len(out), 1)
        self.assertEqual(out[0]["replicas"]["count"], 2)

    def test_clone_group_rows_pass_through_untouched(self) -> None:
        clone = {
            "file": None,
            "function": None,
            "lane": "bash",
            "instances": [
                {
                    "file": "plugins/a/hooks/hook-utils.sh",
                    "start_line": 1,
                    "end_line": 5,
                },
                {
                    "file": "plugins/b/hooks/hook-utils.sh",
                    "start_line": 1,
                    "end_line": 5,
                },
            ],
            "values": {"lines": 5, "tokens": 20},
        }
        result = run("--registry", str(self.registry), stdin=document([clone, clone]))
        out = json.loads(result.stdout)["measures"]
        self.assertEqual(out, [clone, clone])

    def test_no_registry_changes_nothing(self) -> None:
        rows = [
            row("plugins/a/hooks/hook-utils.sh"),
            row("plugins/b/hooks/hook-utils.sh"),
        ]
        result = run(stdin=document(rows))
        self.assertEqual(json.loads(result.stdout)["measures"], rows)

    def test_missing_registry_and_bad_stdin_exit_2(self) -> None:
        self.assertEqual(run("--registry", "/nope/r.txt", stdin="{}").returncode, 2)
        self.assertEqual(run(stdin="not json").returncode, 2)


if __name__ == "__main__":
    unittest.main()
