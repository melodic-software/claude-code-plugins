"""The merge gate's trust in github-actions[bot] lane comments: a footed
comment is its lane's only when the lane-binding check accepts it, a legacy
one (no binding) by the legacy rule, and every parser reads the body without
its binding line. Claude App comments keep their handling."""

from __future__ import annotations

import pathlib
import sys
import unittest
from typing import Any
from unittest import mock

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import babysit_lane_binding as lb
import babysit_merge as merge
import babysit_review_evidence as ev
import test_babysit_lane_binding as lb_tests
import test_babysit_review_evidence as ev_tests
from test_babysit_review_evidence import S, UNEDITED, Base, thread, whole

SEC = "claude-security-review"
ACTIONS = {"__typename": "Bot", "login": "github-actions"}


def binding(text: str, lane: str = SEC) -> str:
    return lb_tests.bound(text, sha=S, lane=lane)


def verdict(item: dict[str, Any], value: bool | None) -> dict[str, Any]:
    if value is not None:
        item[lb.VERDICT] = value
    return item


def summary(body: str, at: str = "2026-01-01T00:30:00Z") -> dict[str, Any]:
    return {
        "id": 77,
        "user": {"login": "github-actions[bot]", "type": "Bot"},
        "created_at": at,
        "updated_at": at,
        "body": body,
        "edit": UNEDITED,
    }


class EvidenceTests(Base):
    def test_a_bound_finding_counts_only_when_accepted_and_reads_its_severity(self) -> None:
        # The `severity:` line sits directly above the binding.
        body = binding("finding\nseverity: IMPORTANT")
        runs = [whole("claude-review", S), whole(SEC, S, n=1, k=1)]
        for value, blocking in ((True, 0), (False, 1), (None, 1)):
            with self.subTest(verdict=value):
                item = thread(body, author=ACTIONS)
                verdict(item["comments"][0], value)
                result = self.bind(runs, threads=[item])[SEC]
                self.assertEqual(result.open_findings, 1)
                self.assertEqual(result.blocking_findings, blocking)

    def test_a_legacy_finding_still_counts(self) -> None:
        runs = [whole("claude-review", S), whole(SEC, S, n=1, k=1)]
        item = thread(f"finding\nseverity: IMPORTANT\n\nclaude-lane: {SEC}", author=ACTIONS)
        self.assertEqual(self.bind(runs, threads=[item])[SEC].blocking_findings, 0)

    def test_a_bound_summary_counts_only_when_accepted_and_reads_its_line(self) -> None:
        runs = [whole("claude-review", S), whole(SEC, S, n=2, k=0)]
        body = binding("summary\n\ncritical-findings: 0")
        for value, blocking in ((True, 0), (False, 2), (None, 2)):
            with self.subTest(verdict=value):
                comments = [*ev_tests.both_markers(), verdict(summary(body), value)]
                self.assertEqual(self.bind(runs, comments=comments)[SEC].blocking_findings, blocking)

    def test_a_claude_app_comment_is_unchanged(self) -> None:
        # The App's own comments never carry a verdict and need none.
        runs = [whole("claude-review", S), whole(SEC, S, n=1, k=1)]
        item = thread(f"finding\nseverity: IMPORTANT\n\nclaude-lane: {SEC}")
        self.assertEqual(self.bind(runs, threads=[item])[SEC].blocking_findings, 0)


class LanePostedTests(unittest.TestCase):
    """Whether the lane may have posted reads the footer alone: a run lost
    before it uploaded its records leaves its comments unproven, and reading
    them as not posted would let a re-run trade that run's verdict away."""

    def posted(self, comments: list[dict[str, Any]], threads: Any = ()) -> bool:
        return ev.lane_posted("claude-review", S, "2026-01-01T00:00:00Z", None, comments, list(threads))

    def test_a_footed_comment_reads_as_posted_whatever_its_verdict(self) -> None:
        body = binding("summary", lane="claude-review")
        for value in (True, False, None):
            with self.subTest(verdict=value):
                self.assertTrue(self.posted([verdict(summary(body), value)]))
        self.assertTrue(self.posted([summary("summary\n\nclaude-lane: claude-review")]))

    def test_a_footed_thread_reads_as_posted_whatever_its_verdict(self) -> None:
        for value in (True, False, None):
            with self.subTest(verdict=value):
                item = thread(binding("finding", lane="claude-review"), author=ACTIONS)
                verdict(item["comments"][0], value)
                self.assertTrue(self.posted([], [item]))

    def test_a_lost_first_attempts_rejected_post_still_holds_the_rerun(self) -> None:
        item = thread(binding("finding", lane="claude-review"), author=ACTIONS, created="2026-01-01T00:50:00Z")
        verdict(item["comments"][0], False)
        lane_run = ev_tests.run("claude-review", S, attempts=[ev_tests.lost(), ev_tests.rerun_ok()])
        result = ev_tests.by_lane(
            ev.bind(
                S,
                [lane_run, whole(SEC, S)],
                ev_tests.both_markers(),
                [item],
                is_human=ev_tests.is_human,
                head_file=ev_tests.fixed_head,
                changed_paths=(),
                floor=ev_tests.risk.floor_for(),
            )
        )
        self.assertFalse(result["claude-review"].bound)
        self.assertEqual(result["claude-review"].unbound_reason, "rerun-not-allowed")


class AttachTests(unittest.TestCase):
    """`_attach_lane_bindings` checks each footed, bound github-actions[bot]
    comment once and reads nothing for any other."""

    def setUp(self) -> None:
        self.issue_body = lb_tests.bound("summary")
        self.thread_body = lb_tests.bound("finding")
        entries = [
            lb_tests.record_entry(self.issue_body, kind="issue_comment", id=5),
            lb_tests.record_entry(self.thread_body, kind="review_comment", id=6),
        ]
        self.api = lb_tests.FakeActions({lb_tests.RUN: lb_tests.lane_run(entries)})

    def attach(self, comments: list[dict[str, Any]], threads: Any = ()) -> None:
        merge._attach_lane_bindings(self.api.checker(), comments, threads)

    def test_a_listed_comment_is_accepted_and_an_unlisted_one_rejected(self) -> None:
        comments = [
            {"id": 5, "user": {"login": "github-actions[bot]"}, "body": self.issue_body},
            {"id": 9, "user": {"login": "github-actions[bot]"}, "body": self.issue_body},
        ]
        first = {"databaseId": 6, "author": ACTIONS, "body": self.thread_body}
        self.attach(comments, [{"comments": [first]}])
        self.assertIs(comments[0][lb.VERDICT], True)
        self.assertIs(comments[1][lb.VERDICT], False)
        self.assertIs(first[lb.VERDICT], True)
        self.assertEqual(self.api.calls.count(("run", lb_tests.RUN)), 1)

    def test_other_comments_get_no_verdict_and_cost_no_read(self) -> None:
        comments = [
            {"id": 1, "user": {"login": "github-actions[bot]"}, "body": "x\n\nclaude-lane: claude-review"},
            {"id": 2, "user": {"login": "claude[bot]"}, "body": self.issue_body},
            {"id": 3, "user": {"login": "someone"}, "body": self.issue_body},
            {"id": 4, "user": {"login": "github-actions[bot]"}, "body": "no footer"},
        ]
        later = {"databaseId": 6, "author": ACTIONS, "body": self.thread_body}
        self.attach(comments, [{"comments": [{"author": ACTIONS, "body": "x"}, later]}])
        self.assertFalse(any(lb.VERDICT in c for c in comments))
        self.assertNotIn(lb.VERDICT, later)
        self.assertEqual(self.api.calls, [])

    def test_a_failed_read_raises(self) -> None:
        comment = {"id": 5, "user": {"login": "github-actions[bot]"}, "body": lb_tests.bound("x", run=999)}
        with self.assertRaises(RuntimeError):
            self.attach([comment])


class LaneEvidenceReadTests(unittest.TestCase):
    """`_lane_evidence` checks the comments before `bind()`, with the verdict
    reader's token, and a failed check read raises out of it, which the gate
    reads as `evidence-missing`."""

    def read(self, comments: list[dict[str, Any]], checker: Any) -> Any:
        pr = {"head": {"ref": "feat", "sha": S}, "user": {"login": "agent"}, "commits": 0}

        def paginated(endpoint: str, label: str, **_: Any) -> list[dict[str, Any]]:
            return comments if "/comments?" in endpoint else []

        with (
            mock.patch.dict("os.environ", {merge.verify_evidence.TOKEN_ENV: "job-token"}),
            mock.patch.object(merge, "fetch_paginated_api", side_effect=paginated),
            mock.patch.object(merge, "fetch_review_threads", return_value=[]),
            mock.patch.object(merge, "collect_lane_runs", return_value=[]),
            mock.patch.object(merge, "lane_binding_checker", checker),
        ):
            return merge._lane_evidence(
                "owner/repo",
                7,
                pr,
                "agent",
                frozenset(),
                lambda login: "write",
                (),
                merge.babysit_risk.floor_for(),
            )

    def test_a_failed_check_read_raises_before_bind(self) -> None:
        comment = summary(binding("summary"))

        def failing(*_: Any) -> Any:
            def check(view: Any) -> bool:
                raise RuntimeError("artifact download failed")

            return check

        with mock.patch.object(ev, "bind") as bind, self.assertRaises(RuntimeError):
            self.read([comment], failing)
        bind.assert_not_called()

    def test_the_checker_reads_with_the_verdict_readers_token(self) -> None:
        factory = mock.Mock(return_value=lambda view: True)
        comment = summary(binding("summary"))
        _, comments = self.read([comment], factory)
        repo, number, workflows, env = factory.call_args.args
        self.assertEqual((repo, number, env), ("owner/repo", 7, {"GH_TOKEN": "job-token"}))
        self.assertEqual(workflows, {lane: path for lane, (path, _) in ev.LANES.items()})
        self.assertIs(comments[0][lb.VERDICT], True)


if __name__ == "__main__":
    unittest.main()
