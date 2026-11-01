"""`babysit_verify_evidence.capped_close`: the pr-merge lane closes a lanes App
pull request the verifier refuses for good (the FAIL cap, too old) for a fresh
attempt at its issue, or parks the issue once `merge.verify-cap-attempts` are
spent, never adding a person's label (owner decision 2026-10-29). The expected
writes follow the GitHub REST endpoints the function names: issue comments,
issue labels and the pull request update."""

from __future__ import annotations

import contextlib
import io
import json
import pathlib
import subprocess
import sys
import unittest
from typing import Any
from unittest import mock

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import babysit_verify_evidence as ve  # noqa: E402

REPO = "melodic-software/claude-code-plugins"
BOT = "melodic-automation-lanes[bot]"
HEAD = "a" * 40
FAILED = ["1" * 40, "2" * 40, "3" * 40]
PR = 50
ISSUE = 7


class StubReader:
    """The reader answers `capped_close` reads: the judgment, the FAIL
    findings and the issue link."""

    def __init__(
        self,
        refusal: str = ve.REPEATED_FAIL,
        issues: tuple[int, ...] = (ISSUE,),
        link: str | None = None,
        issue_labels: tuple[str, ...] = ("agent-ready",),
    ) -> None:
        self.repo = REPO
        self.agent_identity = BOT
        self.refusal = refusal
        self.issues = issues
        self.link = link
        self.issue_labels = issue_labels

    def link_refusal(self, number: int) -> str | None:
        return self.link

    def evidence(self, number: int, head: str) -> ve.Evidence:
        return ve.Evidence(self.refusal, head, (), 0, "fails at 3 heads, the cap is 3")

    def fail_findings(self, number: int) -> list[dict[str, Any]]:
        return [
            {
                "head": FAILED[0],
                "run": 11,
                "summary": "misses the error path",
                "notes": ["a.py:3 ```rm -rf```"],
            },
            {"head": FAILED[1], "run": 12, "unreadable": "artifact x of run 12"},
        ]

    def _closing_issues(self, number: int) -> dict[int, Any]:
        labels = [{"name": name} for name in self.issue_labels]
        return {
            n: {"number": n, "labels": {"totalCount": len(labels), "nodes": labels}}
            for n in self.issues
        }


RECORDED = "2026-10-29T10:00:00Z"
LATER = "2026-10-29T11:00:00Z"
EARLIER = "2026-10-29T09:00:00Z"


def comment(body: str, login: str = BOT, at: str = RECORDED) -> dict[str, Any]:
    return {"user": {"login": login}, "body": body, "created_at": at}


def event(kind: str, login: str, at: str, label: str = "agent-ready") -> dict[str, Any]:
    return {
        "event": kind,
        "actor": {"login": login},
        "created_at": at,
        "label": {"name": label},
    }


class World:
    """The REST reads `capped_close` makes and the writes it sends, in order."""

    def __init__(
        self,
        *,
        labels: list[str] | None = None,
        author: str = BOT,
        state: str = "open",
        head: str = HEAD,
    ) -> None:
        self.pr = {
            "state": state,
            "head": {"sha": head},
            "user": {"login": author},
            "labels": [{"name": n} for n in labels or []],
        }
        self.comments: dict[int, list[dict[str, Any]]] = {PR: [], ISSUE: []}
        self.events: dict[int, list[dict[str, Any]]] = {PR: [], ISSUE: []}
        self.writes: list[list[str]] = []
        self.fail_once: set[str] = set()

    def paginated(self, endpoint: str, label: str) -> list[dict[str, Any]]:
        number = int(endpoint.split("/issues/")[1].split("/")[0])
        if "/events" in endpoint:
            return self.events[number]
        return self.comments[number]

    def gh(self, args: list[str], **kwargs: Any) -> subprocess.CompletedProcess[str]:
        self.writes.append(args)
        key = " ".join(args[2:4])
        if key in self.fail_once:
            self.fail_once.discard(key)
            return subprocess.CompletedProcess(args, 1, "", "HTTP 502")
        return subprocess.CompletedProcess(args, 0, "{}", "")

    def run(
        self,
        reader: StubReader | None = None,
        attempts: int = 1,
        holds: tuple[str, ...] = (),
        issue_holds: tuple[str, ...] = ("needs-human",),
        reason: str = ve.CLOSE_VERIFY,
    ) -> dict[str, Any]:
        with (
            mock.patch.object(ve.merge_policy, "pull_request", return_value=self.pr),
            mock.patch.object(ve.postmerge, "_paginated", side_effect=self.paginated),
            mock.patch.object(ve.postmerge, "gh_capture", side_effect=self.gh),
        ):
            return ve.capped_close(
                reader or StubReader(),
                PR,
                HEAD,
                attempts=attempts,
                holds=holds,
                issue_holds=issue_holds,
                reason=reason,
            )

    def calls(self) -> list[str]:
        return [" ".join(a[2:4]) for a in self.writes]

    def body(self, index: int) -> str:
        return self.writes[index][-1].removeprefix("body=")


class ClosesForAFreshAttempt(unittest.TestCase):
    def test_below_the_attempts_it_records_closes_and_restarts_the_issue(self) -> None:
        world = World()
        result = world.run()
        self.assertEqual(
            result,
            {
                "closed": True,
                "refusal": ve.REPEATED_FAIL,
                "restarted": [ISSUE],
                "parked": [],
                "unrestarted": [],
            },
        )
        # The records first, then agent-ready off and back on, all before the
        # close, so a failed write leaves the pull request open for the next
        # run and a closed one never leaves its issue without agent-ready.
        self.assertEqual(
            world.calls(),
            [
                f"POST repos/{REPO}/issues/{PR}/comments",
                f"POST repos/{REPO}/issues/{ISSUE}/comments",
                f"DELETE repos/{REPO}/issues/{ISSUE}/labels/agent-ready",
                f"POST repos/{REPO}/issues/{ISSUE}/labels",
                f"PATCH repos/{REPO}/pulls/{PR}",
            ],
        )
        self.assertIn("labels[]=agent-ready", world.writes[-2])
        heads = f"{FAILED[0]},{FAILED[1]}"
        self.assertEqual(
            world.body(0).split("\n")[0],
            f"<!-- verify-capped-close pr={PR} heads={heads} -->",
        )
        issue = world.body(1)
        self.assertEqual(
            issue.split("\n")[0],
            f"<!-- verify-capped-close pr={PR} heads={heads} attempt=1 of=1 -->",
        )
        self.assertIn("fresh attempt 1 of 1", issue)
        # The findings, quoted as data: one fence, none of the model's own.
        self.assertIn("summary: misses the error path", issue)
        self.assertIn("a.py:3 '''rm -rf'''", issue)
        self.assertIn("unreadable: artifact x of run 12", issue)
        self.assertEqual(issue.count("```"), 2)
        # No person's label anywhere on this path.
        self.assertFalse(
            any(
                "needs-human" in " ".join(w) or "needs-decision" in " ".join(w)
                for w in world.writes
            )
        )

    def test_at_the_attempts_it_parks_the_issue_and_starts_nothing(self) -> None:
        world = World()
        world.comments[ISSUE] = [
            comment(
                f"<!-- verify-capped-close pr=40 heads={FAILED[2]} attempt=1 of=1 -->\nearlier"
            )
        ]
        result = world.run()
        self.assertEqual(result["parked"], [ISSUE])
        self.assertEqual(result["restarted"], [])
        self.assertEqual(
            world.calls(),
            [
                f"POST repos/{REPO}/issues/{PR}/comments",
                f"POST repos/{REPO}/issues/{ISSUE}/comments",
                f"POST repos/{REPO}/issues/{ISSUE}/labels",
                f"DELETE repos/{REPO}/issues/{ISSUE}/labels/status%3A%20ready",
                f"DELETE repos/{REPO}/issues/{ISSUE}/labels/agent-ready",
                f"PATCH repos/{REPO}/pulls/{PR}",
            ],
        )
        self.assertIn("labels[]=status: confirmed", world.writes[2])
        self.assertTrue(
            world.body(1).split("\n")[0].endswith("attempt=1 of=1 parked -->")
        )
        self.assertIn("parked", world.body(1))

    def test_zero_attempts_parks_at_the_first_close(self) -> None:
        self.assertEqual(World().run(attempts=0)["parked"], [ISSUE])

    def test_only_the_lanes_apps_records_spend_attempts(self) -> None:
        world = World()
        world.comments[ISSUE] = [
            comment(
                "<!-- verify-capped-close pr=40 heads= attempt=1 of=1 -->",
                login="someone",
            )
        ]
        self.assertEqual(world.run()["restarted"], [ISSUE])

    def test_only_records_that_started_an_attempt_spend_one(self) -> None:
        # The records `capped_closed` excuses nothing for spend nothing: one
        # written while a person had taken agent-ready off, and a parked one.
        world = World()
        world.comments[ISSUE] = [
            comment(f"<!-- verify-capped-close pr=40 heads={FAILED[2]} -->"),
            comment("<!-- verify-capped-close pr=41 heads= attempt=0 of=0 parked -->"),
        ]
        result = world.run()
        self.assertEqual(result["restarted"], [ISSUE])
        self.assertTrue(world.body(1).split("\n")[0].endswith("attempt=1 of=1 -->"))

    def test_a_rerun_after_a_failed_close_writes_only_what_is_left(self) -> None:
        world = World()
        world.fail_once.add(f"PATCH repos/{REPO}/pulls/{PR}")
        with self.assertRaises(RuntimeError):
            world.run()
        # The next run finds both records (the reads return what was posted).
        world.comments[PR] = [comment(world.body(0))]
        world.comments[ISSUE] = [comment(world.body(1))]
        # Its removal landed in the record's second (1 s resolution).
        world.events[ISSUE] = [event("unlabeled", BOT, RECORDED)]
        world.writes.clear()
        result = world.run()
        # The issue still carries the agent-ready the first run put back, so
        # the rerun only closes: no second toggle starts a second work run.
        self.assertEqual(result["restarted"], [])
        self.assertEqual(world.calls(), [f"PATCH repos/{REPO}/pulls/{PR}"])

    def test_a_rerun_after_a_record_with_no_removal_toggles(self) -> None:
        # The record went on but the run stopped before agent-ready came off:
        # no labeled event ever started the attempt, so the rerun toggles.
        for name, events in (
            ("no removal", []),
            ("only a person's", [event("unlabeled", "kyle-sexton", LATER)]),
            ("the App's before the record", [event("unlabeled", BOT, EARLIER)]),
        ):
            with self.subTest(name):
                world = World()
                world.comments[PR] = [
                    comment(f"<!-- verify-capped-close pr={PR} heads= -->")
                ]
                world.comments[ISSUE] = [
                    comment(
                        f"<!-- verify-capped-close pr={PR} heads= attempt=1 of=1 -->"
                    )
                ]
                world.events[ISSUE] = events
                result = world.run()
                self.assertEqual(result["restarted"], [ISSUE])
                self.assertEqual(
                    world.calls(),
                    [
                        f"DELETE repos/{REPO}/issues/{ISSUE}/labels/agent-ready",
                        f"POST repos/{REPO}/issues/{ISSUE}/labels",
                        f"PATCH repos/{REPO}/pulls/{PR}",
                    ],
                )

    def test_a_rerun_after_a_record_with_no_attempt_writes_no_label(self) -> None:
        # A person may have added agent-ready since: that started its run.
        world = World()
        world.comments[PR] = [comment(f"<!-- verify-capped-close pr={PR} heads= -->")]
        world.comments[ISSUE] = [
            comment(f"<!-- verify-capped-close pr={PR} heads= -->")
        ]
        result = world.run()
        self.assertEqual(result["unrestarted"], [ISSUE])
        self.assertEqual(world.calls(), [f"PATCH repos/{REPO}/pulls/{PR}"])

    def test_a_parked_rerun_writes_park_labels_only_while_unfinished(self) -> None:
        parked = f"<!-- verify-capped-close pr={PR} heads= attempt=1 of=1 parked -->"
        for labels, writes in (
            (("status: confirmed",), [f"PATCH repos/{REPO}/pulls/{PR}"]),
            (
                ("status: confirmed", "agent-ready"),
                [
                    f"POST repos/{REPO}/issues/{ISSUE}/labels",
                    f"DELETE repos/{REPO}/issues/{ISSUE}/labels/status%3A%20ready",
                    f"DELETE repos/{REPO}/issues/{ISSUE}/labels/agent-ready",
                    f"PATCH repos/{REPO}/pulls/{PR}",
                ],
            ),
        ):
            with self.subTest(labels):
                world = World()
                world.comments[PR] = [
                    comment(f"<!-- verify-capped-close pr={PR} heads= -->")
                ]
                world.comments[ISSUE] = [comment(parked)]
                result = world.run(StubReader(issue_labels=labels))
                self.assertEqual(result["parked"], [ISSUE])
                self.assertEqual(world.calls(), writes)

    def test_a_pull_request_reopened_after_its_record_is_left_alone(self) -> None:
        world = World()
        world.comments[PR] = [comment(f"<!-- verify-capped-close pr={PR} heads= -->")]
        world.events[PR] = [event("reopened", "kyle-sexton", LATER, label="")]
        result = world.run()
        self.assertEqual(
            result,
            {"closed": False, "reason": "reopened after its capped-close record"},
        )
        self.assertEqual(world.writes, [])

    def test_a_rerun_restarts_nothing_a_person_took_off(self) -> None:
        for name, unlabeled in (
            ("a person's removal", event("unlabeled", "kyle-sexton", LATER)),
            ("the App's removal before the record", event("unlabeled", BOT, EARLIER)),
            ("no removal", None),
        ):
            with self.subTest(name):
                world = World()
                world.comments[PR] = [
                    comment(f"<!-- verify-capped-close pr={PR} heads= -->")
                ]
                world.comments[ISSUE] = [
                    comment(
                        f"<!-- verify-capped-close pr={PR} heads= attempt=1 of=1 -->"
                    )
                ]
                world.events[ISSUE] = [unlabeled] if unlabeled else []
                result = world.run(StubReader(issue_labels=()))
                self.assertEqual(result["restarted"], [])
                self.assertEqual(result["unrestarted"], [ISSUE])
                self.assertEqual(world.calls(), [f"PATCH repos/{REPO}/pulls/{PR}"])

    def test_the_re_add_is_tried_twice(self) -> None:
        world = World()
        world.fail_once.add(f"POST repos/{REPO}/issues/{ISSUE}/labels")
        self.assertEqual(world.run()["restarted"], [ISSUE])
        self.assertEqual(
            world.calls()[-3:-1], [f"POST repos/{REPO}/issues/{ISSUE}/labels"] * 2
        )

    def test_a_re_add_that_fails_twice_leaves_the_pull_request_open(self) -> None:
        # Closed with agent-ready off, the issue would be stranded: the closed
        # pull request is never revisited, and label-unblocked.mjs skips the
        # hand-off for a pull request its capped-close record names.
        world = World()

        def gh(args: list[str], **kwargs: Any) -> subprocess.CompletedProcess[str]:
            world.writes.append(args)
            if " ".join(args[2:4]) == f"POST repos/{REPO}/issues/{ISSUE}/labels":
                return subprocess.CompletedProcess(args, 1, "", "HTTP 502")
            return subprocess.CompletedProcess(args, 0, "{}", "")

        world.gh = gh  # type: ignore[method-assign]
        with self.assertRaises(RuntimeError):
            world.run()
        self.assertNotIn(f"PATCH repos/{REPO}/pulls/{PR}", world.calls())

    def test_a_label_already_off_is_no_failure(self) -> None:
        world = World()

        def gh(args: list[str], **kwargs: Any) -> subprocess.CompletedProcess[str]:
            world.writes.append(args)
            if args[2] == "DELETE":
                return subprocess.CompletedProcess(
                    args, 1, "", "gh: Label does not exist (HTTP 404)"
                )
            return subprocess.CompletedProcess(args, 0, "{}", "")

        world.gh = gh  # type: ignore[method-assign]
        self.assertTrue(world.run()["closed"])

    def test_an_issue_without_agent_ready_is_not_restarted(self) -> None:
        # A person may have taken agent-ready off: the App's re-add would
        # override them and admit the issue afresh, so it starts nothing.
        world = World()
        result = world.run(StubReader(issue_labels=()))
        self.assertEqual(result["restarted"], [])
        self.assertEqual(result["parked"], [])
        self.assertEqual(result["unrestarted"], [ISSUE])
        self.assertEqual(
            world.calls(),
            [
                f"POST repos/{REPO}/issues/{PR}/comments",
                f"POST repos/{REPO}/issues/{ISSUE}/comments",
                f"PATCH repos/{REPO}/pulls/{PR}",
            ],
        )
        issue = world.body(1)
        self.assertEqual(
            issue.split("\n")[0],
            f"<!-- verify-capped-close pr={PR} heads={FAILED[0]},{FAILED[1]} -->",
        )
        self.assertIn("did not carry `agent-ready`", issue)
        self.assertIn("no fresh attempt starts", world.body(0))

    def test_a_rerun_after_a_failed_re_add_still_restarts(self) -> None:
        # The first run took agent-ready off and could not put it back; its
        # record names the attempt, so the rerun restarts the issue.
        world = World()

        def gh(args: list[str], **kwargs: Any) -> subprocess.CompletedProcess[str]:
            world.writes.append(args)
            if " ".join(args[2:4]) == f"POST repos/{REPO}/issues/{ISSUE}/labels":
                return subprocess.CompletedProcess(args, 1, "", "HTTP 502")
            return subprocess.CompletedProcess(args, 0, "{}", "")

        world.gh = gh  # type: ignore[method-assign]
        with self.assertRaises(RuntimeError):
            world.run()
        world.comments[PR] = [comment(world.body(0))]
        world.comments[ISSUE] = [comment(world.body(1))]
        # Its own removal, in its record's second, is the one the rerun undoes.
        world.events[ISSUE] = [event("unlabeled", BOT, RECORDED)]
        del world.gh
        world.writes.clear()
        result = world.run(StubReader(issue_labels=()))
        self.assertEqual(result["restarted"], [ISSUE])
        self.assertEqual(
            world.calls(),
            [
                f"POST repos/{REPO}/issues/{ISSUE}/labels",
                f"PATCH repos/{REPO}/pulls/{PR}",
            ],
        )

    def test_too_old_closes_nothing(self) -> None:
        # Owner decision 2026-11-01: a fresh pass at the head
        # clears it, so the pull request stays open for that judgment.
        self.assertFalse(World().run(StubReader(refusal=ve.TOO_OLD))["closed"])

    def test_review_rounds_not_converging_close_for_a_fresh_attempt(self) -> None:
        world = World()
        url = f"https://github.com/{REPO}/pull/{PR}#issuecomment-1"
        world.comments[PR] = [{**comment(stopped_note()), "html_url": url}]
        # The verifier's answer plays no part.
        result = world.run(StubReader(refusal=None), reason=ve.NOT_CONVERGING)
        self.assertEqual(result["closed"], True)
        self.assertEqual(result["refusal"], ve.NOT_CONVERGING)
        self.assertEqual(result["restarted"], [ISSUE])
        self.assertEqual(world.calls()[-1], f"PATCH repos/{REPO}/pulls/{PR}")
        self.assertIn("review rounds as `feedback-not-converging`", world.body(0))
        issue_body = world.body(1)
        self.assertTrue(issue_body.startswith(f"<!-- verify-capped-close pr={PR} "))
        # The fresh attempt starts from the open threads the stop lists,
        # not from pr-verify FAIL findings it was not closed for.
        self.assertIn(f"lane-stopped comment lists ({url})", issue_body)
        self.assertNotIn("starts from these findings", issue_body)
        self.assertNotIn("No FAIL findings", issue_body)

    def test_not_converging_needs_the_lanes_apps_stop_at_the_head(self) -> None:
        for why, comments in {
            "none": [],
            "another head": [comment(stopped_note(head="b" * 40))],
            "another reason": [comment(stopped_note(reason="feedback-verifier-open"))],
            "another account": [comment(stopped_note(), login="github-actions[bot]")],
        }.items():
            with self.subTest(why):
                world = World()
                world.comments[PR] = comments
                result = world.run(StubReader(refusal=None), reason=ve.NOT_CONVERGING)
                self.assertFalse(result["closed"])
                self.assertEqual(world.writes, [])


def stopped_note(reason: str = ve.NOT_CONVERGING, head: str = HEAD) -> str:
    """report-escalation.sh's fail-route comment for address-feedback."""
    return "\n".join(
        [
            ve.LANE_STOPPED_FEEDBACK,
            "The pr-unblock lane stopped `address-feedback` on this pull request.",
            "",
            f"- Reason: `{reason}`",
            f"- Head: `{head}`",
        ]
    )


class LeavesItAlone(unittest.TestCase):
    def test_a_refusal_that_can_clear_is_no_close(self) -> None:
        for refusal in (None, ve.FAIL, ve.UNREADABLE, ve.UNTRUSTED_SPEC):
            with self.subTest(refusal):
                world = World()
                self.assertFalse(world.run(StubReader(refusal=refusal))["closed"])
                self.assertEqual(world.writes, [])

    def test_a_person_pull_request_a_moved_head_or_a_closed_one_is_no_close(
        self,
    ) -> None:
        for world in (
            World(author="kyle-sexton"),
            World(head="b" * 40),
            World(state="closed"),
        ):
            self.assertFalse(world.run()["closed"])
            self.assertEqual(world.writes, [])

    def test_a_link_the_pr_merge_lane_does_not_take_keeps_it_open(self) -> None:
        # One closing issue (or the `Refs:` one) clearing the trust hold, as
        # the arm path reads it (`Reader.link_refusal`): no issue, two
        # issues, or an untrusted-provenance label refuses.
        for link in ("linked-issues:0", "linked-issues:2", "untrusted-provenance"):
            with self.subTest(link):
                world = World()
                result = world.run(StubReader(link=link))
                self.assertEqual(result, {"closed": False, "reason": link})
                self.assertEqual(world.writes, [])

    def test_an_issue_hold_label_keeps_it_open(self) -> None:
        world = World()
        result = world.run(StubReader(issue_labels=("Needs-Human",)))
        self.assertEqual(
            result,
            {"closed": False, "reason": "closing-issue-held:needs-human"},
        )
        self.assertEqual(world.writes, [])

    def test_no_resolved_issue_hold_keeps_it_open(self) -> None:
        world = World()
        result = world.run(issue_holds=())
        self.assertEqual(
            result,
            {"closed": False, "reason": "closing-issue-holds-unresolved"},
        )
        self.assertEqual(world.writes, [])

    def test_a_hold_label_keeps_it_open(self) -> None:
        world = World(labels=["Do-Not-Merge"])
        result = world.run(holds=("do-not-merge", "needs-human"))
        self.assertEqual(result, {"closed": False, "reason": "it carries do-not-merge"})
        self.assertEqual(world.writes, [])


class TheCommand(unittest.TestCase):
    """`capped-close`, which enable-auto-merge.mjs pythonClose runs."""

    def main(self, *extra: str) -> tuple[int, dict[str, Any]]:
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = ve.main(
                [
                    "capped-close",
                    "--repo",
                    REPO,
                    "--base-sha",
                    "b" * 40,
                    *extra,
                    str(PR),
                    HEAD,
                ]
            )
        return code, json.loads(out.getvalue().strip().split("\n")[-1])

    def test_it_closes_under_the_lower_config_with_the_hold_labels(self) -> None:
        config = mock.Mock(
            error=None,
            max_verify_fails=3,
            agent_identity=BOT,
            verify_cap_attempts=2,
            issue_holds=(),
        )
        with (
            mock.patch.object(ve.merge_policy, "config_at", return_value=config),
            mock.patch.object(
                ve.merge_policy, "with_default_branch", return_value=config
            ),
            mock.patch.object(ve.postmerge, "_role_label", return_value="needs-human"),
            mock.patch.object(
                ve, "capped_close", return_value={"closed": True}
            ) as close,
        ):
            code, answer = self.main(
                "--hold-label", "do-not-merge", "--hold-label", "needs-human"
            )
        self.assertEqual((code, answer), (0, {"closed": True}))
        (reader, number, head), kwargs = close.call_args
        self.assertEqual((reader.agent_identity, number, head), (BOT, PR, HEAD))
        self.assertEqual(
            kwargs,
            {
                "attempts": 2,
                "holds": ("do-not-merge", "needs-human"),
                "issue_holds": ("needs-human",),
                "reason": ve.CLOSE_VERIFY,
            },
        )
        with (
            mock.patch.object(ve.merge_policy, "config_at", return_value=config),
            mock.patch.object(
                ve.merge_policy, "with_default_branch", return_value=config
            ),
            mock.patch.object(ve.postmerge, "_role_label", return_value="needs-human"),
            mock.patch.object(
                ve, "capped_close", return_value={"closed": True}
            ) as close,
        ):
            self.main("--reason", ve.NOT_CONVERGING)
        self.assertEqual(close.call_args.kwargs["reason"], ve.NOT_CONVERGING)

    def test_a_failed_read_or_write_exits_one_with_the_error(self) -> None:
        with mock.patch.object(
            ve.merge_policy,
            "config_at",
            side_effect=ve.merge_policy.PolicyReadError("config gone"),
        ):
            code, answer = self.main()
        self.assertEqual((code, answer), (1, {"closed": False, "error": "config gone"}))


class TheRecordMatchesItsReaders(unittest.TestCase):
    def test_the_marker_parses_as_label_unblocked_and_write_issue_read_it(self) -> None:
        line = ve.capped_close_marker(PR, FAILED[:2], (1, 1))
        self.assertIsNotNone(ve.CAPPED_CLOSE_RE.fullmatch(line))
        self.assertTrue(line.startswith(f"<!-- verify-capped-close pr={PR} "))
        self.assertIsNotNone(
            ve.CAPPED_CLOSE_RE.fullmatch(ve.capped_close_marker(PR, []))
        )
        self.assertIsNotNone(
            ve.CAPPED_CLOSE_RE.fullmatch(
                ve.capped_close_marker(PR, [], (0, 0), parked=True)
            )
        )


if __name__ == "__main__":
    unittest.main()
