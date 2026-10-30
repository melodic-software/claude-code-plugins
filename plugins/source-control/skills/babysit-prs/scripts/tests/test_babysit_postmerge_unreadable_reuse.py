"""An unreadable post-merge answer at main's head, checked once per pr-merge
run (`babysit_postmerge.reuse_unreadable`).

Each gate candidate is its own process reading the run's report file, so the
reuse goes through the file. Expected values: a check that came back
unreadable at the same main head, floor, identity and lane refuses every
later candidate with that same reason and is not run again; anything else
runs the check as before. An unreadable answer never reads as a pass.
"""

from __future__ import annotations

import json
import pathlib
import sys
import tempfile
import unittest
from datetime import UTC, datetime, timedelta
from typing import Any

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import babysit_merge_policy as policy
import babysit_postmerge as pm

HEAD = "a" * 40
MOVED = "b" * 40
CONFIG = "c" * 40
FLOOR = datetime(2026, 10, 21, 15, 40, 33, tzinfo=UTC)
IDENTITY = "agent-lanes[bot]"
REASON = (
    "unreadable: post-merge-detect-silent-revert.yml push runs: total_count "
    "1183, 1000 returned, at the 1000-run search cap"
)


def unreadable_report() -> dict[str, Any]:
    return {
        "ok": False,
        "readable": False,
        "reason": REASON,
        "hold": None,
        "autoMerges": [],
        "failures": [],
    }


class CountingCheck:
    """The full post-merge check, counted; it answers unreadable."""

    def __init__(self) -> None:
        self.runs = 0

    def __call__(self, floor: datetime, identity: str) -> policy.PostMergeGate:
        self.runs += 1
        return pm.gate_from_report(unreadable_report())


class UnreadableReuseTest(unittest.TestCase):
    def setUp(self) -> None:
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)
        self.path = str(pathlib.Path(self.dir.name) / "post-merge.json")
        self.check = CountingCheck()
        self.head = HEAD

    def write(self, payload: dict[str, Any]) -> None:
        pathlib.Path(self.path).write_text(json.dumps(payload), encoding="utf-8")

    def step_report(self, main_sha: str, computed_at: datetime) -> dict[str, Any]:
        """The merge job's own check, exit 3, as babysit_postmerge.py prints it."""
        return {
            **unreadable_report(),
            "since": FLOOR.isoformat(),
            "shared": {
                "mainSha": main_sha,
                "configSha": CONFIG,
                "demotion": {"active": True, "reason": "#1 open", "records": [1]},
                "identity": IDENTITY,
                "selfLogins": [],
                "laneMergesOnly": True,
                "computedAt": computed_at.isoformat(),
            },
        }

    def candidate(self) -> policy.PostMergeGate:
        """One gate process: a fresh reader over the run's report file."""
        gate = pm.reuse_unreadable(
            self.path, self.check, lambda: self.head, lane_merges_only=True
        )
        return gate(FLOOR, IDENTITY)

    def test_three_candidates_run_the_check_once(self) -> None:
        # The report the gate starts from binds no head (a malformed one),
        # so the first candidate checks; the next two reuse its answer.
        self.write({**unreadable_report(), "since": FLOOR.isoformat()})
        answers = [self.candidate() for _ in range(3)]
        self.assertEqual(self.check.runs, 1)
        self.assertEqual([a.refusal for a in answers], [REASON] * 3)
        self.assertEqual([a.report.get("readable") for a in answers], [False] * 3)

    def test_the_job_check_at_this_head_is_not_run_again(self) -> None:
        self.write(self.step_report(HEAD, datetime.now(UTC)))
        answers = [self.candidate() for _ in range(3)]
        self.assertEqual(self.check.runs, 0)
        self.assertEqual([a.refusal for a in answers], [REASON] * 3)

    def test_a_moved_head_checks_again(self) -> None:
        self.write(self.step_report(MOVED, datetime.now(UTC)))
        self.candidate()
        self.assertEqual(self.check.runs, 1)

    def test_an_old_answer_checks_again(self) -> None:
        old = datetime.now(UTC) - policy.SHARED_MAX_AGE - timedelta(minutes=1)
        self.write(self.step_report(HEAD, old))
        self.candidate()
        self.assertEqual(self.check.runs, 1)

    def test_an_unread_head_checks_every_time(self) -> None:
        self.head = None
        self.write(self.step_report(HEAD, datetime.now(UTC)))
        for _ in range(2):
            self.candidate()
        self.assertEqual(self.check.runs, 2)

    def test_a_stored_answer_marked_ok_is_never_reused(self) -> None:
        # Unreadable never reads as a pass: a stored report claiming `ok`
        # beside `readable: false` is not reused, so the check runs.
        report = self.step_report(HEAD, datetime.now(UTC))
        report["ok"] = True
        self.write(report)
        answer = self.candidate()
        self.assertEqual(self.check.runs, 1)
        self.assertEqual(answer.refusal, REASON)

    def test_a_readable_answer_is_never_recorded_as_unreadable(self) -> None:
        passing = {"ok": True, "readable": True, "reason": None, "autoMerges": []}
        checks = 0

        def check(floor: datetime, identity: str) -> policy.PostMergeGate:
            nonlocal checks
            checks += 1
            return pm.gate_from_report(passing)

        for _ in range(2):
            pm.reuse_unreadable(self.path, check, lambda: HEAD, lane_merges_only=True)(
                FLOOR, IDENTITY
            )
        self.assertEqual(checks, 2)


if __name__ == "__main__":
    unittest.main()
