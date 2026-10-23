"""The review-lane hold enable-auto-merge reads (`lane_review_refusal`).

Expected values come from the gate's lane rule (babysit_risk.py, `LANES` and
`holding`): the security lane's open CRITICAL findings hold
(`security-finding`, HIGH), a lane whose evidence is not bound to the head
holds (`evidence-unbound:<lane>`), and claude-review's open findings are
reported and never hold. A read that fails holds.
"""

from __future__ import annotations

import contextlib
import io
import json
import pathlib
import sys
import unittest
from unittest import mock

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import babysit_merge  # noqa: E402
import babysit_merge_policy as policy  # noqa: E402
import babysit_verify_evidence as ve  # noqa: E402
from babysit_risk import LaneEvidence  # noqa: E402

REPO = "example-org/example-repo"
HEAD = "a" * 40
PR = {"number": 41, "head": {"sha": HEAD, "ref": "feat/x"}, "base": {"sha": "b" * 40}}
CONFIG = policy.PipelineConfig(
    "c" * 40, "C2", "pr-merge", "agent-lanes[bot]", None, (), None
)


def lanes(
    *, code: int = 0, critical: int = 0, security_bound: bool = True
) -> tuple[LaneEvidence, ...]:
    return (
        LaneEvidence("claude-review", True, None, code),
        LaneEvidence(
            "claude-security-review",
            security_bound,
            None if security_bound else "marker-missing",
            critical if security_bound else None,
            False,
            critical if security_bound else None,
        ),
    )


def refusal(evidence: object) -> str | None:
    effect = evidence if isinstance(evidence, Exception) else None
    with (
        mock.patch.object(policy, "_default_branch_config", return_value=CONFIG),
        mock.patch.object(policy, "changed_files", return_value=((), True)),
        mock.patch.object(policy, "permission_reader", return_value=lambda login: None),
        mock.patch.object(
            babysit_merge,
            "_lane_evidence",
            side_effect=effect,
            return_value=None if effect else (evidence, []),
        ),
    ):
        return ve.lane_review_refusal(REPO, 41, PR)


class LaneReviewRefusal(unittest.TestCase):
    def test_a_critical_security_finding_holds(self) -> None:
        self.assertEqual(refusal(lanes(critical=1)), "security-finding: 1 open")

    def test_clean_lanes_and_a_code_finding_hold_nothing(self) -> None:
        self.assertIsNone(refusal(lanes()))
        self.assertIsNone(refusal(lanes(code=3)))

    def test_an_unbound_security_review_holds(self) -> None:
        held = refusal(lanes(security_bound=False))
        self.assertTrue(
            str(held).startswith("evidence-unbound:claude-security-review"), held
        )

    def test_a_failed_read_holds(self) -> None:
        held = refusal(babysit_merge.HeadPusherUnproven("head-pusher-unproven:abc"))
        self.assertTrue(str(held).startswith("unreadable: "), held)


class EvidenceCommandReadsTheReviews(unittest.TestCase):
    def cli(
        self, evidence: ve.Evidence, reviews: str | None, head: str = HEAD
    ) -> dict[str, object]:
        out = io.StringIO()
        with (
            mock.patch.object(
                policy, "pull_request", return_value=PR | {"head": {"sha": head}}
            ),
            mock.patch.object(
                ve.Reader, "evidence", lambda self, n, h, pr=None: evidence
            ),
            mock.patch.object(ve, "lane_review_refusal", return_value=reviews) as read,
            contextlib.redirect_stdout(out),
        ):
            ve.main(["evidence", "--lane-reviews", "--repo", REPO, "41", HEAD])
        self.read = read
        return json.loads(out.getvalue())

    def test_a_pass_carries_the_review_hold(self) -> None:
        report = self.cli(ve.Evidence(None, HEAD, (), 0), "security-finding: 1 open")
        self.assertEqual(
            (report["refusal"], report["reviews"]), (None, "security-finding: 1 open")
        )
        self.assertIsNone(self.cli(ve.Evidence(None, HEAD, (), 0), None)["reviews"])

    def test_a_refused_verdict_reads_no_reviews(self) -> None:
        report = self.cli(ve.Evidence(ve.FAIL, HEAD, (), 0), None)
        self.assertNotIn("reviews", report)
        self.read.assert_not_called()

    def test_a_moved_head_holds(self) -> None:
        report = self.cli(ve.Evidence(None, HEAD, (), 0), None, head="d" * 40)
        self.assertTrue(str(report["reviews"]).startswith("unreadable: the head is"))
        self.read.assert_not_called()


if __name__ == "__main__":
    unittest.main()
