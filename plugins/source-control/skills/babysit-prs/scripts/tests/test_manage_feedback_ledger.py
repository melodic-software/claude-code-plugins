"""Advisory-round classification in the durable feedback ledger.

`record-advisory-round` is the only durable record of what a fix round
contained, so what it persists is what a post-rollover worker can know. These
cover the write shape and the tripwire the helper reports back at record time;
the two `--finding-class` argument refusals are guard-contract rows, executed
by `test_guards.py`.
"""

from __future__ import annotations

import argparse
import pathlib
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import manage_feedback_ledger as ledger

HEAD = "a" * 40
OLDER = "b" * 40
LEDGER_CLI = (
    pathlib.Path(__file__).resolve().parent.parent / "manage_feedback_ledger.py"
)


def record(
    ledger_entry: dict[str, object],
    head_sha: str,
    classes: list[str],
    *,
    apply: bool = True,
) -> dict[str, object]:
    args = argparse.Namespace(finding_class=classes, fix_round_cap=100, apply=apply)
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

    def test_each_round_gets_the_next_monotonic_sequence(self) -> None:
        # The ledger serializes with sorted keys, so the persisted sequence is
        # the only write order a post-rollover reader can reconstruct.
        entry: dict[str, object] = {}
        record(entry, OLDER, ["c"])
        record(entry, HEAD, ["c"])
        rounds = entry["advisory_fix_rounds"]["rounds"]
        self.assertEqual(rounds[OLDER]["sequence"], 1)
        self.assertEqual(rounds[HEAD]["sequence"], 2)

    def test_the_sequence_continues_past_pre_sequence_rounds(self) -> None:
        # A legacy round without a sequence neither blocks recording nor
        # collides with the new numbering.
        entry: dict[str, object] = {
            "advisory_fix_rounds": {
                "count": 1,
                "rounds": {OLDER: {"recorded_at": "2026-07-10T01:00:00Z"}},
            }
        }
        record(entry, HEAD, ["c"])
        self.assertEqual(entry["advisory_fix_rounds"]["rounds"][HEAD]["sequence"], 1)

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
    """The one refusal outside `guard_contract.py`'s two `--finding-class` rows."""

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
