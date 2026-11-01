"""The settled marker of the post-merge check (`babysit_postmerge`).

Expected values come from the marker contract the module documents: a merge
of the agent identity's whose pull request carries the identity's unedited
`<!-- babysit-merge-settled sha=<merge commit> -->` comment is verified with
none of its runs or records read; a marker anyone else wrote, an edited one,
or one naming another commit is no marker, and the merge is judged on its
runs as before. A merge is listed for a marker (`settle`) only when a
readable check judged it verified with no red run or running canary in its
window and no empty record listing behind it, and a failed post is a
warning. Each fixture states its marker by construction.
"""

from __future__ import annotations

import contextlib
import io
import json
import pathlib
import sys
import tempfile
import unittest
from datetime import UTC, datetime
from types import SimpleNamespace
from typing import Any

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

import babysit_postmerge as pm  # noqa: E402
from test_babysit_postmerge import (  # noqa: E402
    APP_ACTOR,
    HEAD_SHA,
    HUMAN,
    IDENTITY,
    LATER_SHA,
    MERGE_SHA,
    OTHER_SHA,
    REPO,
    SINCE,
    CheckCase,
    by,
    canary_run,
    dispatch_run,
    human,
    identity_merge,
    merged_pr,
)
from test_babysit_postmerge import pin as pin_comment  # noqa: E402

# Forty days after the merge: past the dispatch deadline and the 30-day
# retention of its pr-merge-dispatched record.
LATE = datetime(2026, 11, 21, 10, 0, tzinfo=UTC)
SOON = datetime(2026, 10, 12, 11, 0, tzinfo=UTC)
NUMBER = 7001
RECORD = "pr-merge-dispatched-11"
LANE_RUN = 500
BOT = by("github-actions[bot]")


def marker(
    sha: str = MERGE_SHA, *, author: Any = APP_ACTOR, edited: str | None = None
) -> dict[str, Any]:
    return {
        "author": author,
        "body": pm.settled_comment(sha),
        "createdAt": "2026-10-12T11:00:00Z",
        "lastEditedAt": edited,
    }


class SettledCase(CheckCase):
    """One lane merge (the identity enqueued it), pinned at its head."""

    def setUp(self) -> None:
        super().setUp()
        self.gh.merged = [identity_merge()]
        self.gh.pin_comments = [pin_comment(HEAD_SHA)]

    def lane_dispatch(self, *, recorded: bool = True) -> None:
        """A green full run pr-merge.yml dispatched, a green canary, and the
        run's record when `recorded` (else its artifact has expired)."""
        self.gh.add_runs(
            "pr-require-checks.yml",
            "workflow_dispatch",
            dispatch_run(11, actor=BOT, triggering_actor=BOT),
        )
        self.gh.add_runs("post-merge-detect-silent-revert.yml", "push", canary_run(21))
        if recorded:
            self.gh.artifacts[RECORD] = [
                {"id": 9, "name": RECORD, "workflow_run": {"id": LANE_RUN}}
            ]
        self.gh.run_records[LANE_RUN] = {
            "id": LANE_RUN,
            "path": ".github/workflows/pr-merge.yml",
            "event": "schedule",
            "head_branch": "main",
            "head_sha": LATER_SHA,
            "repository": {"full_name": REPO},
            "head_repository": {"full_name": REPO},
        }

    def settled_check(self, now: datetime = LATE) -> pm.PostMergeVerdict:
        reader = pm.pin_reader(REPO, IDENTITY)
        return pm.check(
            REPO,
            agent_identity=IDENTITY,
            is_human=human,
            merged_since=SINCE,
            now=now,
            pinned_sha=reader,
            lane_merges_only=True,
            settled=reader.settled,
        )

    def joined(self) -> list[str]:
        return [" ".join(c) for c in self.gh.calls]

    def record_reads(self) -> int:
        return sum("actions/artifacts?name=" in c for c in self.joined())

    def window_reads(self) -> int:
        """Reads that judge a merge's window: its canary listing, a read by
        head SHA, a run or its record. The lane's re-run probe
        (`_lane_reruns`) lists recent dispatches whatever is merged."""
        return sum(
            pm.CANARY_WORKFLOW in c
            or "head_sha=" in c
            or "actions/artifacts" in c
            or "/actions/runs/" in c
            for c in self.joined()
        )


class AMarkerSettlesTheMerge(SettledCase):
    def test_a_marker_keeps_the_merge_verified_after_its_record_expired(
        self,
    ) -> None:
        # Without the marker the same runs hold the lane as an unlisted
        # record; with it the merge is verified and nothing about it is read.
        self.lane_dispatch(recorded=False)
        unsettled = self.settled_check()
        self.assertFalse(unsettled.readable)
        self.assertEqual(unsettled.hold, pm.HOLD_UNLISTED_RECORD)

        self.gh.calls.clear()
        self.gh.pin_comments = [pin_comment(HEAD_SHA), marker()]
        verdict = self.settled_check()
        self.assertTrue(verdict.readable, verdict.reason)
        self.assertIsNone(verdict.hold)
        self.assertEqual(verdict.failures, ())
        self.assertTrue(verdict.is_verified(verdict.merges[0].merge))
        self.assertTrue(verdict.merges[0].settled)
        self.assertFalse(verdict.needs_dispatch)
        self.assertEqual(self.window_reads(), 0)
        self.assertEqual(unsettled.merges, ())
        self.assertEqual(verdict.report()["settle"], [])
        self.assertEqual(self.gh.writes(), [])

    def test_a_marker_with_no_dispatch_run_does_not_fail_as_dispatch(self) -> None:
        self.gh.pin_comments = [marker()]
        verdict = self.settled_check()
        self.assertTrue(verdict.ok, verdict.reason)
        self.assertTrue(verdict.merges[0].verified)

    def test_the_marker_is_read_with_the_pins_in_one_batch(self) -> None:
        self.gh.pin_comments = [pin_comment(HEAD_SHA), marker()]
        self.settled_check()
        reads = [
            c for c in self.joined() if "PostMergeHeadPins" in c or "PostMergePin(" in c
        ]
        self.assertEqual(len(reads), 1)

    def test_only_the_settled_merge_skips_its_runs(self) -> None:
        # A later merge with no marker is judged on its runs as before.
        later = identity_merge(
            number=7002,
            url=f"https://github.com/{REPO}/pull/7002",
            mergeCommit={"oid": LATER_SHA},
            mergedAt="2026-10-12T10:04:00Z",
            updatedAt="2026-10-12T10:04:05Z",
        )
        self.gh.merged = [identity_merge(), later]
        self.gh.pin_comments = [pin_comment(HEAD_SHA), marker()]
        self.gh.add_runs("pr-require-checks.yml", "workflow_dispatch", dispatch_run(11))
        self.gh.add_runs(
            "post-merge-detect-silent-revert.yml",
            "push",
            canary_run(21, head_sha=LATER_SHA, created_at="2026-10-12T10:04:30Z"),
        )
        verdict = self.settled_check(now=SOON)
        states = {s.merge.number: s for s in verdict.merges}
        self.assertTrue(states[NUMBER].settled)
        self.assertFalse(states[7002].settled)
        self.assertTrue(states[7002].verified, states[7002].pending)
        self.assertEqual(
            verdict.report()["settle"], [{"number": 7002, "mergeCommit": LATER_SHA}]
        )


class NoMarkerStands(SettledCase):
    """A marker that does not stand leaves the merge judged on its runs."""

    def test_a_marker_by_anyone_else_is_judged_by_its_artifact(self) -> None:
        for author in (HUMAN, {"__typename": "User", "login": "agent-lanes"}, BOT):
            with self.subTest(author=author):
                self.gh.calls.clear()
                self.gh.runs.clear()
                self.lane_dispatch()
                self.gh.pin_comments = [pin_comment(HEAD_SHA), marker(author=author)]
                verdict = self.settled_check(now=SOON)
                self.assertTrue(verdict.merges[0].verified, verdict.reason)
                self.assertFalse(verdict.merges[0].settled)
                self.assertGreaterEqual(self.record_reads(), 1)

    def test_an_unsettled_merge_whose_record_expired_is_not_verified(self) -> None:
        for comments in (
            [pin_comment(HEAD_SHA)],
            [pin_comment(HEAD_SHA), marker(edited="2026-10-13T09:00:00Z")],
            [pin_comment(HEAD_SHA), marker(OTHER_SHA)],
            [pin_comment(HEAD_SHA), marker(author=HUMAN)],
        ):
            with self.subTest(comments=comments):
                self.gh.runs.clear()
                self.lane_dispatch(recorded=False)
                self.gh.pin_comments = comments
                verdict = self.settled_check()
                self.assertFalse(verdict.readable)
                self.assertEqual(verdict.hold, pm.HOLD_UNLISTED_RECORD)
                self.assertFalse(verdict.is_verified(SimpleNamespace(number=NUMBER)))
                self.assertEqual(verdict.report()["settle"], [])

    def test_no_settled_callable_reads_no_marker(self) -> None:
        self.gh.pin_comments = [pin_comment(HEAD_SHA), marker()]
        self.lane_dispatch(recorded=False)
        verdict = pm.check(
            REPO,
            agent_identity=IDENTITY,
            is_human=human,
            merged_since=SINCE,
            now=LATE,
            pinned_sha=pm.pin_reader(REPO, IDENTITY),
            lane_merges_only=True,
        )
        self.assertEqual(verdict.hold, pm.HOLD_UNLISTED_RECORD)


class WhatGetsSettled(SettledCase):
    def test_a_merge_verified_from_a_complete_read_is_listed(self) -> None:
        self.lane_dispatch()
        verdict = self.settled_check(now=SOON)
        self.assertTrue(verdict.merges[0].verified)
        self.assertEqual(
            verdict.report()["settle"], [{"number": NUMBER, "mergeCommit": MERGE_SHA}]
        )
        self.assertEqual(self.gh.writes(), [])

    def test_a_merge_with_a_canary_still_running_is_not_listed(self) -> None:
        self.lane_dispatch()
        self.gh.add_runs(
            "post-merge-detect-silent-revert.yml",
            "push",
            canary_run(22, conclusion=None, status="in_progress"),
        )
        verdict = self.settled_check(now=SOON)
        self.assertTrue(verdict.merges[0].verified)
        self.assertFalse(verdict.merges[0].settleable)
        self.assertEqual(verdict.report()["settle"], [])

    def test_a_pending_merge_is_not_listed(self) -> None:
        self.gh.add_runs("post-merge-detect-silent-revert.yml", "push", canary_run(21))
        verdict = self.settled_check(now=SOON)
        self.assertFalse(verdict.merges[0].verified)
        self.assertEqual(verdict.report()["settle"], [])

    def test_a_merge_verified_past_an_empty_record_listing_is_not_listed(
        self,
    ) -> None:
        # The lane's run in time read empty twice; a later recorded lane run
        # verifies the merge, but the empty listing leaves it unsettled.
        self.lane_dispatch(recorded=False)
        late = dispatch_run(
            12, actor=BOT, triggering_actor=BOT, created_at="2026-10-12T17:00:00Z"
        )
        self.gh.add_runs("pr-require-checks.yml", "workflow_dispatch", late)
        self.gh.artifacts["pr-merge-dispatched-12"] = [
            {
                "id": 10,
                "name": "pr-merge-dispatched-12",
                "workflow_run": {"id": LANE_RUN},
            }
        ]
        verdict = self.settled_check(now=datetime(2026, 10, 12, 18, 0, tzinfo=UTC))
        self.assertTrue(verdict.readable, verdict.reason)
        self.assertTrue(verdict.merges[0].verified, verdict.merges[0].pending)
        self.assertEqual(verdict.report()["settle"], [])

    def test_a_merge_another_app_enqueued_is_neither_listed_nor_settled(
        self,
    ) -> None:
        # The fixture's merge: a sync App enqueued it.
        self.gh.merged = [merged_pr()]
        self.gh.pin_comments = [marker()]
        self.lane_dispatch()
        reader = pm.pin_reader(REPO, IDENTITY)
        verdict = pm.check(
            REPO,
            agent_identity=IDENTITY,
            is_human=human,
            merged_since=SINCE,
            now=SOON,
            pinned_sha=reader,
            settled=reader.settled,
        )
        self.assertTrue(verdict.merges[0].verified)
        self.assertFalse(verdict.merges[0].settled)
        self.assertEqual(verdict.report()["settle"], [])


class Settle(SettledCase):
    """`settle` and `--settle-from`: the only writes."""

    def comment_posts(self) -> list[list[str]]:
        return [
            c for c in self.gh.writes() if f"issues/{NUMBER}/comments" in " ".join(c)
        ]

    def test_settle_posts_the_marker_the_check_reads_back(self) -> None:
        posted, warnings = pm.settle(
            REPO, [{"number": NUMBER, "mergeCommit": MERGE_SHA}], IDENTITY
        )
        self.assertEqual((posted, warnings), ([NUMBER], []))
        body = next(a for a in self.comment_posts()[0] if a.startswith("body="))
        self.assertEqual(body, f"body={pm.settled_comment(MERGE_SHA)}")
        self.assertEqual(pm._settled_shas(IDENTITY, [marker()]), frozenset({MERGE_SHA}))

    def test_a_failed_post_is_a_warning(self) -> None:
        self.gh.fail_reads = {f"issues/{NUMBER}/comments"}
        posted, warnings = pm.settle(
            REPO, [{"number": NUMBER, "mergeCommit": MERGE_SHA}], IDENTITY
        )
        self.assertEqual(posted, [])
        self.assertEqual(len(warnings), 1)
        self.assertTrue(warnings[0].startswith("settle-unposted:"), warnings)

    def test_an_entry_of_another_shape_posts_nothing(self) -> None:
        posted, warnings = pm.settle(
            REPO,
            [{"number": "7001", "mergeCommit": MERGE_SHA}, {"number": 7001}],
            IDENTITY,
        )
        self.assertEqual((posted, len(warnings)), ([], 2))
        self.assertEqual(self.gh.writes(), [])

    def test_a_merge_already_marked_is_not_marked_again(self) -> None:
        # A reused report, or two runs at once, lists a merge whose marker
        # already stands: nothing is posted. A marker that does not stand
        # (another author, edited, another commit) still gets one.
        for comments, expected in (
            ([marker()], []),
            ([marker(author=HUMAN)], [NUMBER]),
            ([marker(edited="2026-10-13T09:00:00Z")], [NUMBER]),
            ([marker(OTHER_SHA)], [NUMBER]),
        ):
            with self.subTest(comments=comments):
                self.gh.calls.clear()
                self.gh.pin_comments = comments
                posted, warnings = pm.settle(
                    REPO, [{"number": NUMBER, "mergeCommit": MERGE_SHA}], IDENTITY
                )
                self.assertEqual((posted, warnings), (expected, []))
                self.assertEqual(len(self.comment_posts()), len(expected))

    def test_an_unread_thread_posts_nothing(self) -> None:
        self.gh.fail_reads = {"PostMergeHeadPins"}
        posted, warnings = pm.settle(
            REPO, [{"number": NUMBER, "mergeCommit": MERGE_SHA}], IDENTITY
        )
        self.assertEqual((posted, len(warnings)), ([], 1))
        self.assertEqual(self.gh.writes(), [])

    def run_settle_from(self, report: Any) -> tuple[int, dict[str, Any]]:
        with tempfile.TemporaryDirectory(prefix="settle-") as tmp:
            path = pathlib.Path(tmp) / "post-merge.json"
            path.write_text(json.dumps(report), encoding="utf-8")
            out = io.StringIO()
            with contextlib.redirect_stdout(out):
                code = pm.main(
                    [
                        "--repo",
                        REPO,
                        "--agent-identity",
                        IDENTITY,
                        "--settle-from",
                        str(path),
                    ]
                )
        return code, json.loads(out.getvalue())

    def test_settle_from_posts_each_listed_merge_and_exits_0(self) -> None:
        self.lane_dispatch()
        report = self.settled_check(now=SOON).report()
        code, out = self.run_settle_from(report)
        self.assertEqual((code, out["settled"], out["warnings"]), (0, [NUMBER], []))
        self.assertEqual(len(self.comment_posts()), 1)

    def test_settle_from_warns_and_exits_0_when_the_post_fails(self) -> None:
        self.gh.fail_reads = {f"issues/{NUMBER}/comments"}
        code, out = self.run_settle_from(
            {"readable": True, "settle": [{"number": NUMBER, "mergeCommit": MERGE_SHA}]}
        )
        self.assertEqual((code, out["settled"]), (0, []))
        self.assertTrue(out["warnings"][0].startswith("settle-unposted:"))

    def test_settle_from_an_unreadable_report_posts_nothing(self) -> None:
        code, out = self.run_settle_from(
            {
                "readable": False,
                "settle": [{"number": NUMBER, "mergeCommit": MERGE_SHA}],
            }
        )
        self.assertEqual((code, out["settled"], len(out["warnings"])), (0, [], 1))
        self.assertEqual(self.gh.writes(), [])

    def test_settle_from_under_another_login_is_refused(self) -> None:
        self.gh.viewer = "maintainer"
        code, out = self.run_settle_from(
            {"readable": True, "settle": [{"number": NUMBER, "mergeCommit": MERGE_SHA}]}
        )
        self.assertEqual((code, out["ok"]), (2, False))
        self.assertEqual(self.gh.writes(), [])


if __name__ == "__main__":
    unittest.main()
