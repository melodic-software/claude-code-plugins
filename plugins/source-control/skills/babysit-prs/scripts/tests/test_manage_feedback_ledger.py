"""Advisory-round classification in the durable feedback ledger.

`record-advisory-round` is the only durable record of what a fix round
contained, so what it persists is what a post-rollover worker can know. These
cover the write shape, the argument-layer refusals that keep an unclassified
round out of the ledger, and the tripwire the helper reports back at record
time.
"""

from __future__ import annotations

import argparse
import pathlib
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import manage_feedback_ledger as ledger  # noqa: E402

HEAD = "a" * 40
OLDER = "b" * 40
LEDGER_CLI = pathlib.Path(__file__).resolve().parent.parent / "manage_feedback_ledger.py"


def record(
    ledger_entry: dict[str, object],
    head_sha: str,
    classes: list[str],
    *,
    apply: bool = True,
) -> dict[str, object]:
    args = argparse.Namespace(
        finding_class=classes, fix_round_cap=100, apply=apply
    )
    return ledger.record_advisory_round(args, "owner/repo#1", ledger_entry, head_sha)


class RecordAdvisoryRoundTests(unittest.TestCase):
    def test_per_finding_classes_are_persisted(self) -> None:
        entry: dict[str, object] = {}
        result = record(entry, HEAD, ["c", "c", "b"])
        self.assertEqual(result["finding_classes"], {"a": 0, "b": 1, "c": 2})
        self.assertEqual(result["composition"], "mixed")
        self.assertEqual(
            entry["advisory_fix_rounds"]["rounds"][HEAD]["finding_classes"],
            {"a": 0, "b": 1, "c": 2},
        )

    def test_a_dry_run_persists_nothing_but_still_reports_the_tripwire(self) -> None:
        entry: dict[str, object] = {}
        result = record(entry, HEAD, ["c"], apply=False)
        self.assertNotIn("advisory_fix_rounds", entry)
        self.assertIn("non_convergence_tripwire", result)

    def test_the_recorded_round_arms_the_tripwire_at_record_time(self) -> None:
        # The worker recording round N learns immediately that N-1 was also
        # all-(c) -- it does not have to wait for the next snapshot to find out.
        entry: dict[str, object] = {}
        record(entry, OLDER, ["c"])
        result = record(entry, HEAD, ["c", "c"])
        self.assertTrue(result["non_convergence_tripwire"]["armed"])

    def test_a_mixed_round_clears_the_tripwire(self) -> None:
        entry: dict[str, object] = {}
        record(entry, OLDER, ["c"])
        result = record(entry, HEAD, ["b", "c"])
        self.assertFalse(result["non_convergence_tripwire"]["armed"])


def invoke(*argv: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(LEDGER_CLI), *argv],
        capture_output=True,
        text=True,
        check=False,
    )


class ArgumentRefusalTests(unittest.TestCase):
    """`--finding-class` is required where it is meaningful and rejected elsewhere."""

    def test_an_unclassified_advisory_round_is_refused(self) -> None:
        with tempfile.TemporaryDirectory() as state_dir:
            result = invoke(
                "record-advisory-round",
                "--pr",
                "owner/repo#1",
                "--expected-head-sha",
                HEAD,
                "--state-dir",
                state_dir,
                "--lease-token",
                "token",
                "--apply",
            )
        self.assertEqual(result.returncode, 2)
        self.assertIn("--finding-class", result.stderr)

    def test_a_finding_class_outside_an_advisory_round_is_refused(self) -> None:
        with tempfile.TemporaryDirectory() as state_dir:
            result = invoke(
                "record-worker-checkin",
                "--pr",
                "owner/repo#1",
                "--expected-head-sha",
                HEAD,
                "--state-dir",
                state_dir,
                "--finding-class",
                "c",
            )
        self.assertEqual(result.returncode, 2)
        self.assertIn("--finding-class", result.stderr)

    def test_an_unknown_class_is_refused(self) -> None:
        with tempfile.TemporaryDirectory() as state_dir:
            result = invoke(
                "record-advisory-round",
                "--pr",
                "owner/repo#1",
                "--expected-head-sha",
                HEAD,
                "--state-dir",
                state_dir,
                "--finding-class",
                "d",
            )
        self.assertEqual(result.returncode, 2)


if __name__ == "__main__":
    unittest.main()
