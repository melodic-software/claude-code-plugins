#!/usr/bin/env python3
"""Output-based tests for size_check.py: the crossing test against a scratch repository."""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

for _leaked_git_var in ("GIT_DIR", "GIT_WORK_TREE", "GIT_CONFIG"):
    os.environ.pop(_leaked_git_var, None)

SCRIPT = Path(__file__).resolve().parent / "size_check.py"


def git(root: Path, *args: str) -> str:
    return subprocess.run(
        [
            "git",
            "-C",
            str(root),
            "-c",
            "user.name=t",
            "-c",
            "user.email=t@example.invalid",
            *args,
        ],
        capture_output=True,
        text=True,
        check=True,
    ).stdout.strip()


def lines(n: int) -> str:
    return "".join(f"line {i}\n\n" for i in range(n))


class SizeCheckTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)
        git(self.root, "init", "-q")
        (self.root / "grows.txt").write_text(lines(3), encoding="utf-8")
        (self.root / "over.txt").write_text(lines(6), encoding="utf-8")
        (self.root / "moved-from.txt").write_text(lines(7), encoding="utf-8")
        git(self.root, "add", ".")
        git(self.root, "commit", "-q", "-m", "base")
        self.base = git(self.root, "rev-parse", "--short=12", "HEAD")

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def run_check(
        self, rows, rule="crossing", mode="change", reference=5, run=(), replicas=None
    ):
        for f, n, fn in rows:
            if n is not None and fn is None:
                (self.root / f).write_text(lines(n), encoding="utf-8")
        document = {
            "root": {"kind": "repository", "path": str(self.root)},
            "scope": {"mode": mode, "base": self.base if mode == "change" else None},
            "thresholds": [
                {"measure": "file_lines", "reference": reference, "layer": "team"}
            ],
            "run": list(run),
            "measures": [
                {
                    "file": f,
                    "function": fn,
                    "values": {"lines_non_blank": 1000},
                    "replicas": replicas,
                }
                for f, n, fn in rows
            ],
        }
        config = {"size": {"check": rule}, "_layers": {"size.check": "team"}}
        report = self.root.parent / f"{self.root.name}-report.json"
        conf = self.root.parent / f"{self.root.name}-config.json"
        report.write_text(json.dumps(document), encoding="utf-8")
        conf.write_text(json.dumps(config), encoding="utf-8")
        try:
            result = subprocess.run(
                [
                    sys.executable,
                    str(SCRIPT),
                    "add",
                    "--config",
                    str(conf),
                    str(report),
                ],
                capture_output=True,
                text=True,
                check=False,
            )
            block = json.loads(report.read_text(encoding="utf-8"))["size_check"]
            rendered = subprocess.run(
                [sys.executable, str(SCRIPT), "render", str(report)],
                capture_output=True,
                text=True,
                check=False,
            ).stdout
        finally:
            report.unlink()
            conf.unlink()
        return result, block, rendered

    def test_a_crossing_fails_with_the_guidance(self) -> None:
        result, block, text = self.run_check([("grows.txt", 5, None)])
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertEqual(
            [
                (r["file"], r["base_lines"], r["head_lines"], r["kind"], r["fails"])
                for r in block["rows"]
            ],
            [("grows.txt", 3, 5, "crossed", True)],
        )
        self.assertIn("FAIL: 1 file(s)", text)
        self.assertIn("real responsibility boundary", text)
        self.assertIn("Do not delete code or squash lines", text)

    def test_below_the_reference_passes(self) -> None:
        result, block, text = self.run_check([("grows.txt", 4, None)])
        self.assertEqual(result.returncode, 0)
        self.assertEqual(block["rows"], [])
        self.assertIn("PASS", text)

    def test_already_over_and_not_grown_is_left_alone(self) -> None:
        result, block, _ = self.run_check(
            [("over.txt", 6, None)], rule="crossing-or-growth"
        )
        self.assertEqual(result.returncode, 0)
        self.assertEqual(block["rows"], [])

    def test_already_over_and_grown_reports_under_crossing(self) -> None:
        result, block, text = self.run_check([("over.txt", 9, None)])
        self.assertEqual(result.returncode, 0)
        self.assertEqual(
            [(r["kind"], r["fails"]) for r in block["rows"]], [("grew", False)]
        )
        self.assertIn("reported: already over, grew", text)

    def test_already_over_and_grown_fails_under_crossing_or_growth(self) -> None:
        result, block, _ = self.run_check(
            [("over.txt", 9, None)], rule="crossing-or-growth"
        )
        self.assertEqual(result.returncode, 1)
        self.assertEqual(block["failed"], 1)

    def test_a_new_file_at_the_reference_crosses_from_zero(self) -> None:
        (self.root / "new.txt").write_text(lines(5), encoding="utf-8")
        result, block, _ = self.run_check([("new.txt", 5, None)])
        self.assertEqual(result.returncode, 1)
        self.assertEqual(block["rows"][0]["base_lines"], 0)

    def test_a_renamed_file_is_counted_under_its_old_name(self) -> None:
        git(self.root, "mv", "moved-from.txt", "moved-to.txt")
        result, block, _ = self.run_check([("moved-to.txt", 7, None)])
        self.assertEqual(result.returncode, 0, block)
        self.assertEqual(block["rows"], [])

    def test_a_raised_reference_is_honored(self) -> None:
        result, _, _ = self.run_check([("grows.txt", 5, None)], reference=50)
        self.assertEqual(result.returncode, 0)

    def test_function_rows_are_ignored(self) -> None:
        result, block, _ = self.run_check([("grows.txt", 9, "f")])
        self.assertEqual(result.returncode, 0)
        self.assertEqual(block["rows"], [])

    def test_report_rule_passes_whatever_the_sizes(self) -> None:
        result, block, text = self.run_check([("grows.txt", 500, None)], rule="report")
        self.assertEqual(result.returncode, 0)
        self.assertEqual(block["rows"], [])
        self.assertIn("nothing fails", text)

    def test_no_change_scope_cannot_decide(self) -> None:
        result, _, _ = self.run_check([("grows.txt", 5, None)], mode="all")
        self.assertEqual(result.returncode, 2)
        self.assertIn("needs the change scope", result.stderr)

    def test_an_unmeasured_lane_cannot_decide(self) -> None:
        run = [
            {
                "lane": "other",
                "measure": "file_lines",
                "status": "unavailable",
                "reason": "no collector",
            }
        ]
        result, _, _ = self.run_check([("grows.txt", 5, None)], run=run)
        self.assertEqual(result.returncode, 2)
        self.assertIn("not measured", result.stderr)

    def test_an_empty_change_passes(self) -> None:
        run = [
            {
                "lane": "*",
                "measure": "*",
                "status": "not-applicable",
                "reason": "no measurable files in scope",
            }
        ]
        result, _, _ = self.run_check([], run=run)
        self.assertEqual(result.returncode, 0)

    def test_the_collector_figure_is_not_the_head_count(self) -> None:
        result, block, _ = self.run_check([("grows.txt", 3, None)])
        self.assertEqual(result.returncode, 0)
        self.assertEqual(block["rows"], [])

    def test_each_replica_is_checked_against_its_own_base(self) -> None:
        (self.root / "copy.txt").write_text(lines(7), encoding="utf-8")
        replicas = {"count": 2, "files": ["over.txt", "copy.txt"]}
        result, block, _ = self.run_check([("over.txt", 7, None)], replicas=replicas)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(
            [(r["file"], r["kind"], r["fails"]) for r in block["rows"]],
            [("copy.txt", "crossed", True), ("over.txt", "grew", False)],
        )

    def test_an_unreadable_file_cannot_decide(self) -> None:
        result, _, _ = self.run_check([("gone.txt", None, None)])
        self.assertEqual(result.returncode, 2)


if __name__ == "__main__":
    unittest.main()
