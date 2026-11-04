"""pr-merge's candidate prefilter: a held candidate never reaches the gate.

A candidate whose listed labels or body carry a hold the gate refuses on is
dropped with no API call, the gate still refuses the same inputs on its own,
and when every candidate is held one stays so a gate process still sweeps the
merge queue. Expected holds come from `PullRequestBodyHold`, the gate's own
cases. Kept candidates sweep CLEAN first, then oldest first.
"""

from __future__ import annotations

import io
import json
import pathlib
import subprocess
import sys
import unittest
from unittest import mock

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import babysit_merge as merge
import babysit_merge_prefilter as prefilter
import test_babysit_merge as fixtures


def _candidate(number: int, *, labels: list[str] | None = None, body: str = "") -> dict:
    return {
        "number": number,
        "head": f"{number:040x}",
        "updatedAt": "2026-10-18T00:00:00Z",
        "labels": labels or [],
        "body": body,
    }


HELD_BODIES = (
    "Refs: #1\r\n\r\nHold: a human merges this\r\n",
    "Superseded. Do not merge this draft.",
    "Refs: #1\rHold: a bare CR line break",
)
FREE_BODIES = (
    "",
    "Adds the do-not-merge label check to the merge lane.",
    "Threshold: 3 retries",
)


class HeldCandidatesNeverReachTheGate(unittest.TestCase):
    def _run(self, candidates: list[dict]) -> tuple[list[dict], list[dict]]:
        """Run the CLI as the workflow does, with every process and gh seam
        refusing, so any API call fails the test."""
        refuse = mock.Mock(side_effect=AssertionError("prefilter made a call"))
        out = io.StringIO()
        with (
            mock.patch.object(subprocess, "run", refuse),
            mock.patch.object(subprocess, "Popen", refuse),
            mock.patch.object(merge, "gh_json", refuse),
            mock.patch.object(merge, "gh_capture", refuse),
            mock.patch.object(sys, "stdin", io.StringIO(json.dumps(candidates))),
            mock.patch.object(sys, "stdout", out),
        ):
            self.assertEqual(prefilter.main([]), 0)
        refuse.assert_not_called()
        result = json.loads(out.getvalue())
        return result["candidates"], result["held"]

    def test_held_candidates_are_dropped_with_no_call(self) -> None:
        candidates = [
            _candidate(1),
            _candidate(2, body=HELD_BODIES[0]),
            _candidate(3, labels=["Do-Not-Merge"]),
            _candidate(4, labels=["needs-review"], body=FREE_BODIES[1]),
            _candidate(7, labels=["Needs-Human"]),
        ]
        kept, held = self._run(candidates)
        self.assertEqual([c["number"] for c in kept], [1, 4])
        self.assertEqual(
            [(h["number"], h["reason"]) for h in held],
            [(2, "body-hold"), (3, "do-not-merge"), (7, "needs-human")],
        )
        # The gate loop reads exactly the fields it read before.
        self.assertEqual(set(kept[0]), {"number", "head", "updatedAt"})
        self.assertEqual(held[0]["head"], candidates[1]["head"])

    def test_one_held_candidate_stays_when_every_candidate_is_held(self) -> None:
        # Its gate process sweeps the merge queue, so a held entry the
        # identity queued before the hold still leaves it.
        kept, held = self._run(
            [_candidate(5, body=HELD_BODIES[1]), _candidate(6, labels=["do-not-merge"])]
        )
        self.assertEqual(
            kept, [{k: _candidate(5)[k] for k in ("number", "head", "updatedAt")}]
        )
        self.assertEqual(
            [(h["number"], h["reason"]) for h in held], [(6, "do-not-merge")]
        )

    def test_no_candidates_stay_none(self) -> None:
        self.assertEqual(self._run([]), ([], []))


class CleanCandidatesSweepFirstOldestFirst(unittest.TestCase):
    """A sweep the job timeout cuts short has tried the clean candidates
    first, oldest first; a hold still keeps a clean candidate out."""

    @staticmethod
    def _numbers(candidates: list[dict]) -> list[int]:
        return [c["number"] for c in prefilter.split(candidates)["candidates"]]

    @staticmethod
    def _listed(number: int, state: str | None, created: str | None, **kw) -> dict:
        row = _candidate(number, **kw)
        if state is not None:
            row["mergeStateStatus"] = state
        if created is not None:
            row["createdAt"] = created
        return row

    def test_clean_first_then_oldest(self) -> None:
        candidates = [
            self._listed(1, "BLOCKED", "2026-10-01T00:00:00Z"),
            self._listed(2, "CLEAN", "2026-10-15T00:00:00Z"),
            self._listed(3, "DIRTY", "2026-09-20T00:00:00Z"),
            self._listed(4, "CLEAN", "2026-10-03T00:00:00Z"),
            self._listed(5, None, None),
            self._listed(6, "UNSTABLE", None),
            self._listed(7, "CLEAN", None),
        ]
        self.assertEqual(self._numbers(candidates), [4, 2, 7, 3, 1, 5, 6])

    def test_input_without_the_fields_keeps_its_order(self) -> None:
        candidates = [_candidate(9), _candidate(3), _candidate(7)]
        self.assertEqual(self._numbers(candidates), [9, 3, 7])

    def test_all_held_fallback_keeps_the_first_in_sweep_order(self) -> None:
        # Every candidate is held; the one kept for the queue sweep is the
        # CLEAN, older one, not the lowest number.
        candidates = [
            self._listed(1, "BLOCKED", "2026-10-10T00:00:00Z", labels=["do-not-merge"]),
            self._listed(2, "CLEAN", "2026-09-01T00:00:00Z", body=HELD_BODIES[0]),
        ]
        result = prefilter.split(candidates)
        self.assertEqual(
            result["candidates"],
            [{k: candidates[1][k] for k in ("number", "head", "updatedAt")}],
        )
        self.assertEqual(
            [(h["number"], h["reason"]) for h in result["held"]], [(1, "do-not-merge")]
        )

    def test_held_clean_candidate_never_sweeps_first(self) -> None:
        candidates = [
            self._listed(1, "BLOCKED", "2026-10-05T00:00:00Z"),
            self._listed(2, "CLEAN", "2026-09-01T00:00:00Z", labels=["do-not-merge"]),
            self._listed(3, "CLEAN", "2026-09-02T00:00:00Z", labels=["needs-human"]),
            self._listed(4, "CLEAN", "2026-09-03T00:00:00Z", body=HELD_BODIES[0]),
        ]
        result = prefilter.split(candidates)
        self.assertEqual([c["number"] for c in result["candidates"]], [1])
        self.assertEqual(
            [(h["number"], h["reason"]) for h in result["held"]],
            [(2, "do-not-merge"), (3, "needs-human"), (4, "body-hold")],
        )


class PrefilterDropsOnlyWhatTheGateRefuses(fixtures.TierEvaluateHarness):
    """The gate refuses each dropped input on its own, and passes each kept
    one. The prefilter judges for pr-merge, an autonomous run, so it agrees
    with the autonomous gate (here the autopilot tier); `needs-human` alone
    is lifted for an attended gate (no tier, no unattended policy)."""

    def test_agrees_with_the_gate(self) -> None:
        cases = [
            *({"body": b} for b in HELD_BODIES + FREE_BODIES),
            {"labels": ["do-not-merge"]},
            {"labels": ["needs-review"]},
            {"labels": ["needs-human"]},
        ]
        for case in cases:
            labels = case.get("labels", [])
            body = case.get("body", "")
            dropped = prefilter.hold(_candidate(1, labels=labels, body=body))
            for tier in (fixtures.TIER, None):
                with self.subTest(case=case, tier=tier is not None):
                    gate = self._evaluate(
                        fixtures._pr(body=body, labels=[{"name": n} for n in labels]),
                        tier=tier,
                    )
                    expected = dropped is not None and (
                        tier is not None or labels != ["needs-human"]
                    )
                    self.assertEqual(expected, not gate["ready"], gate["blockers"])


# The tracker's human-gated label read an autonomous gate makes: stubbed so
# no test reads GitHub.
_role_label = fixtures.role_label_stub()


def setUpModule() -> None:
    _role_label.start()


def tearDownModule() -> None:
    _role_label.stop()


if __name__ == "__main__":
    unittest.main()
