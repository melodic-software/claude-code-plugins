"""The merge gate's async merge path, merge-queue enqueue, and stacked PRs.

Expected request fields, statuses, and HTTP semantics come from GitHub's
"Merge a pull request asynchronously" and "Get the result of an asynchronous
merge" REST docs: `sha` pins the head, `merge_method` is direct-only,
`merge_action` is `direct_merge` or `merge_queue`, 409 returns the pending
request's UUID, and `enqueued` means queued, not merged. A merge-queue base is
enqueued through GraphQL `enqueuePullRequest` (`pullRequestId`,
`expectedHeadOid`), per GitHub's GraphQL "Pulls" reference. Stack membership and
the trunk rule come from "About stacked pull requests" and the stacks REST
endpoints. Every gh seam is stubbed; no real gh process is spawned.
"""

from __future__ import annotations

import contextlib
import io
import json
import pathlib
import subprocess
import sys
import tempfile
import unittest
from datetime import timedelta
from typing import Any, ClassVar
from unittest import mock
from urllib.parse import unquote

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

from repo_config_fake import RepoConfigFake
import babysit_merge as merge

HEAD = "c" * 40
# The base compare the freshness hold reads for an otherwise-ready PR.
UP_TO_DATE = {"status": "ahead", "ahead_by": 1, "behind_by": 0}
LAYER1 = "1" * 40
LAYER2 = "2" * 40
UUID = "3f2c9a1e-0000-4000-8000-000000000001"
SELF = "solo-owner"
APPROVED_RULES = [
    {"type": "pull_request", "parameters": {"required_approving_review_count": 1}}
]
QUEUE_RULES = [*APPROVED_RULES, {"type": "merge_queue", "parameters": {}}]


def _proc(payload: Any = None, *, returncode: int = 0, stderr: str = "") -> mock.Mock:
    stdout = "" if payload is None else json.dumps(payload)
    return mock.Mock(returncode=returncode, stdout=stdout, stderr=stderr)


def _async(status: str, message: str = "") -> dict[str, Any]:
    return {"status": status, "details": {"message": message, "uuid": UUID}}


def _queue(
    *,
    position: int | None = None,
    state: str = "QUEUED",
    required: bool = True,
    merged: bool = False,
    armed: bool = False,
    timeline: list[Any] | None = None,
) -> dict[str, Any]:
    """A GraphQL `PullRequest` merge-queue read; a position puts the PR in the queue."""
    in_queue = position is not None
    pull_request = {
        "merged": merged,
        "isInMergeQueue": in_queue,
        "isMergeQueueEnabled": required,
        "mergeQueueEntry": {"state": state, "position": position} if in_queue else None,
        "autoMergeRequest": {"enabledAt": "2026-10-04T00:00:00Z"} if armed else None,
        "timelineItems": {"nodes": timeline or []},
    }
    return {"data": {"repository": {"pullRequest": pull_request}}}


LIMIT = merge.merge_policy.MAX_QUEUE_EJECTIONS_LIMIT
COMMIT = {"__typename": "PullRequestCommit"}
FORCE_PUSH = {"__typename": "HeadRefForcePushedEvent"}


def _removed(reason: str = "failed_checks") -> dict[str, Any]:
    return {"__typename": "RemovedFromMergeQueueEvent", "reason": reason}


NO_QUEUE = _queue(required=False, merged=True)
NODE_ID = "PR_kwDOnode0001"


def _enqueued(state: str = "QUEUED", position: int = 1) -> dict[str, Any]:
    """An `enqueuePullRequest` answer carrying the new `MergeQueueEntry`."""
    entry = {"state": state, "position": position}
    return {"data": {"enqueuePullRequest": {"mergeQueueEntry": entry}}}


def _graphql_error(message: str) -> dict[str, Any]:
    return {"data": {"enqueuePullRequest": None}, "errors": [{"message": message}]}


class AsyncMergeHarness(unittest.TestCase):
    """Runs `main --merge` over a stubbed ready verdict and records gh calls."""

    def setUp(self) -> None:
        RepoConfigFake().install(self)
        self.enterContext(
            mock.patch.object(
                merge.merge_policy,
                "resolve",
                return_value=merge.merge_policy.UnattendedPolicy(
                    reason="authority-unconfigured"
                ),
            )
        )
        self.captures: list[list[str]] = []
        self.polls: list[list[str]] = []
        self.sleeps: list[float] = []

    def _run(
        self,
        put: mock.Mock | list[mock.Mock],
        polls: list[dict[str, Any]] | None = None,
        *,
        merged: bool | None = True,
        landed_head: str = HEAD,
        base: str = "main",
        default_branch: str | None = "main",
        merge_action: str = "direct_merge",
        stack_lands: bool = False,
        stack_listings: list[list[dict[str, Any]] | Exception] | None = None,
        extra: tuple[str, ...] = (),
        clock: list[float] | None = None,
        ready: bool = True,
        merge_flag: bool = True,
        pinned: bool = True,
        head: str | None = HEAD,
        blockers: list[str] | None = None,
        stack_member: bool = False,
        queue: list[dict[str, Any] | Exception] | None = None,
        report: dict[str, Any] | None = None,
        node: dict[str, Any] | Exception | None = None,
    ) -> int:
        if blockers is not None:
            ready = not blockers
        verdict = {
            "ready": ready,
            "blockers": (
                blockers
                if blockers is not None
                else []
                if ready
                else ["1 unresolved review thread(s) [reviewer]"]
            ),
            "headRefOid": head,
            "baseRef": base,
            "mergeAction": merge_action,
            "stack": {
                "enabled": True,
                "member": stack_lands or stack_member,
                "landsLowerLayers": stack_lands,
                "number": 7,
                "layers": (
                    [{"pr": "owner/repo#2", "number": 2, "headRefOid": LAYER2}]
                    if stack_lands
                    else []
                ),
            },
            "autoMerge": {"ready": ready, "blockers": []},
            **(report or {}),
        }
        puts = list(put) if isinstance(put, list) else [put]
        poll_answers = list(polls or [])
        listings = list(stack_listings or [])
        queue_answers = list(queue or [NO_QUEUE])

        def capture(cmd: list[str]) -> Any:
            self.captures.append(cmd)
            joined = " ".join(cmd)
            if "merge-async" in joined or "enqueuePullRequest" in joined:
                return puts.pop(0)
            return _proc()

        def gh_json(args: list[str]) -> Any:
            if args[0] == "api" and "/compare/" in args[1]:
                return UP_TO_DATE
            if "merge-async/" in args[1]:
                self.polls.append(args)
                answer = poll_answers.pop(0)
                if isinstance(answer, Exception):
                    raise answer
                return answer
            if args[1] == "repos/owner/repo/pulls/1":
                self.node_reads += 1
                answer = {"id": NODE_ID} if node is None else node
                if isinstance(answer, Exception):
                    raise answer
                return answer
            if args[1] == "repos/owner/repo/stacks/7":
                self.stack_reads += 1
                listing = listings.pop(0)
                if isinstance(listing, Exception):
                    raise listing
                return {"number": 7, "pull_requests": listing}
            if args[1] == "graphql":
                self.queue_reads += 1
                answer = queue_answers.pop(0)
                if isinstance(answer, Exception):
                    raise answer
                return answer
            raise AssertionError(f"unexpected gh_json call: {args}")

        self.stack_reads = 0
        self.queue_reads = 0
        self.node_reads = 0
        ticks = iter(clock or [0.0] * 50)
        argv = [
            "babysit_merge.py",
            "owner/repo#1",
            "--allowed-owners",
            "owner",
            *(("--merge",) if merge_flag else ()),
            *(
                ("--expected-head", HEAD)
                if merge_flag and pinned
                else ("--allow-unpinned-head",)
                if merge_flag
                else ()
            ),
            *extra,
        ]
        out = io.StringIO()
        with (
            mock.patch.object(sys, "argv", argv),
            mock.patch.object(merge, "evaluate", return_value=verdict),
            mock.patch.object(merge, "allowed_method", return_value="squash"),
            mock.patch.object(merge, "gh_capture", side_effect=capture),
            mock.patch.object(merge, "gh_json", side_effect=gh_json),
            mock.patch.object(
                merge, "repository_default_branch", return_value=default_branch
            ),
            mock.patch.object(
                merge,
                "pull_request_landed",
                return_value={
                    "merged": merged,
                    "head": None if merged is None else landed_head,
                },
            ),
            mock.patch.object(merge, "_poll_sleep", side_effect=self.sleeps.append),
            mock.patch.object(merge, "_poll_clock", side_effect=lambda: next(ticks)),
            contextlib.redirect_stdout(out),
        ):
            code = merge.main()
        self.output = json.loads(out.getvalue())
        return code

    def _put(self) -> list[str]:
        [cmd] = [c for c in self.captures if "merge-async" in " ".join(c)]
        return cmd

    def _enqueue_commands(self) -> list[list[str]]:
        return [c for c in self.captures if "enqueuePullRequest" in " ".join(c)]

    def _fields(self, cmd: list[str]) -> dict[str, str]:
        pairs = [cmd[i + 1] for i, arg in enumerate(cmd) if arg in ("-f", "-F")]
        return dict(pair.split("=", 1) for pair in pairs)


class DirectMergeGoesThroughTheAsyncApi(AsyncMergeHarness):
    def test_accepted_request_is_polled_to_merged(self) -> None:
        code = self._run(
            _proc(_async("pending")), [_async("pending"), _async("merged")]
        )
        self.assertEqual(code, 0)
        self.assertTrue(self.output["merged"])
        self.assertEqual(self.output["action"], "merge")
        cmd = self._put()
        self.assertEqual(
            cmd[:4], ["api", "-X", "PUT", "repos/owner/repo/pulls/1/merge-async"]
        )
        self.assertEqual(
            self._fields(cmd),
            {
                "merge_action": "direct_merge",
                "bypass_rules": "false",
                "sha": HEAD,
                "merge_method": "squash",
            },
        )
        self.assertEqual(len(self.polls), 2)
        self.assertTrue(self.polls[0][1].endswith(f"/merge-async/{UUID}"))
        self.assertEqual(self.sleeps, [merge.ASYNC_MERGE_POLL_INTERVAL_SECONDS])
        self.assertFalse(any(c[:2] == ["pr", "merge"] for c in self.captures))

    def test_already_merged_answer_needs_no_poll(self) -> None:
        code = self._run(
            _proc({"status": "merged", "details": {"message": "m", "sha": "d" * 40}})
        )
        self.assertEqual(code, 0)
        self.assertTrue(self.output["merged"])
        self.assertEqual(self.polls, [])

    def test_conflict_polls_the_pending_request_it_names(self) -> None:
        conflict = _proc(
            _async("pending"), returncode=1, stderr="gh: Conflict (HTTP 409)"
        )
        code = self._run(conflict, [_async("merged")])
        self.assertEqual(code, 0)
        self.assertEqual(self.output["merge"]["httpStatus"], 409)
        self.assertTrue(self.polls[0][1].endswith(UUID))

    def test_already_merged_answer_at_another_head_is_not_a_success(self) -> None:
        code = self._run(
            _proc({"status": "merged", "details": {"message": "m", "sha": "d" * 40}}),
            landed_head="f" * 40,
        )
        self.assertEqual(code, 10)
        self.assertTrue(self.output["merged"])
        self.assertFalse(self.output["merge"]["success"])
        self.assertEqual(self.output["merge"]["mergedHead"], "f" * 40)
        self.assertIn("escalate", self.output["merge"]["message"])

    def test_failed_request_is_not_a_merge(self) -> None:
        code = self._run(_proc(_async("pending")), [_async("failed", "head moved")])
        self.assertEqual(code, 10)
        self.assertFalse(self.output["merged"])
        self.assertEqual(self.output["merge"]["status"], "failed")
        self.assertEqual(self.output["merge"]["message"], "head moved")

    def test_request_still_pending_at_the_bound_is_left_pending(self) -> None:
        bound = merge.ASYNC_MERGE_POLL_TIMEOUT_SECONDS
        code = self._run(
            _proc(_async("pending")),
            [_async("pending"), _async("pending")],
            clock=[0.0, 1.0, bound + 1],
        )
        self.assertEqual(code, 10)
        self.assertFalse(self.output["merged"])
        self.assertEqual(self.output["merge"]["status"], "pending")
        self.assertEqual(len(self.polls), 2)

    def test_reported_merge_the_pull_request_contradicts_is_not_counted(self) -> None:
        code = self._run(
            _proc({"status": "merged", "details": {"message": "m", "sha": "d" * 40}}),
            merged=False,
        )
        self.assertEqual(code, 10)
        self.assertFalse(self.output["merged"])
        self.assertFalse(self.output["merge"]["verifiedMerged"])

    def test_a_merge_that_cannot_be_read_back_is_unconfirmed(self) -> None:
        code = self._run(
            _proc({"status": "merged", "details": {"message": "m", "sha": "d" * 40}}),
            merged=None,
        )
        self.assertEqual(code, 10)
        self.assertFalse(self.output["merged"])
        self.assertTrue(self.output["mergeUnconfirmed"])
        self.assertIsNone(self.output["merge"]["verifiedMerged"])

    def test_unready_pull_request_answer_does_not_fall_back(self) -> None:
        code = self._run(
            _proc(
                {"message": "Pull request is a draft"},
                returncode=1,
                stderr="gh: (HTTP 400)",
            )
        )
        self.assertEqual(code, 10)
        self.assertEqual(self.output["merge"]["httpStatus"], 400)
        self.assertFalse(any(c[:2] == ["pr", "merge"] for c in self.captures))

    def test_missing_endpoint_falls_back_to_gh_pr_merge_with_the_pin(self) -> None:
        code = self._run(
            _proc(
                {"message": "Not Found"},
                returncode=1,
                stderr="gh: Not Found (HTTP 404)",
            )
        )
        self.assertEqual(code, 0)
        self.assertTrue(self.output["merged"])
        self.assertIn("asyncFallback", self.output)
        [legacy] = [c for c in self.captures if c[:2] == ["pr", "merge"]]
        self.assertEqual(legacy[legacy.index("--match-head-commit") + 1], HEAD)

    def test_non_default_base_keeps_gh_pr_merge(self) -> None:
        code = self._run(_proc(), base="release")
        self.assertEqual(code, 0)
        self.assertFalse(any("merge-async" in " ".join(c) for c in self.captures))
        [legacy] = self.captures
        self.assertEqual(legacy[:2], ["pr", "merge"])
        self.assertEqual(
            (self.output["action"], self.output["merged"]), ("merge", True)
        )
        self.assertNotIn("enqueued", self.output)
        self.assertNotIn("mergeQueue", self.output)

    def test_unreadable_default_branch_keeps_gh_pr_merge(self) -> None:
        self._run(_proc(), default_branch=None)
        self.assertEqual(self.captures[0][:2], ["pr", "merge"])


def _conflict(body: dict[str, Any]) -> mock.Mock:
    return _proc(body, returncode=1, stderr="gh: Conflict (HTTP 409)")


def _pending_with_options(
    head: str = HEAD, action: str = "direct_merge"
) -> dict[str, Any]:
    """A 409 body naming the pending request's options, per GitHub's pending
    `details` schema (`expected_head_sha`, `merge_action`)."""
    details = {"message": "", "uuid": UUID}
    details |= {"expected_head_sha": head, "merge_action": action}
    return {"status": "pending", "details": details}


class ConflictAdoptsOnlyTheVettedRequest(AsyncMergeHarness):
    """A 409 names a request this run did not send; it is reported as this
    run's merge only when it is pinned to the vetted head and action, or the
    PR is read back merged at the vetted head."""

    def test_a_pending_request_for_another_head_is_not_adopted(self) -> None:
        code = self._run(_conflict(_pending_with_options(head="f" * 40)))
        self.assertEqual(code, 10)
        self.assertFalse(self.output["merged"])
        self.assertFalse(self.output["merge"]["success"])
        self.assertEqual(self.polls, [])
        self.assertEqual(
            self.output["merge"]["conflictingRequest"]["expected_head_sha"], "f" * 40
        )

    def test_a_pending_request_for_another_action_is_not_adopted(self) -> None:
        code = self._run(_conflict(_pending_with_options(action="merge_queue")))
        self.assertEqual(code, 10)
        self.assertFalse(self.output["merge"]["success"])
        self.assertEqual(self.polls, [])

    def test_a_request_pinned_to_the_vetted_head_is_polled_to_merged(self) -> None:
        code = self._run(_conflict(_pending_with_options()), [_async("merged")])
        self.assertEqual(code, 0)
        self.assertTrue(self.output["merged"])

    def test_an_unpinned_request_that_merged_another_head_is_not_a_success(
        self,
    ) -> None:
        code = self._run(
            _conflict(_async("pending")), [_async("merged")], landed_head="f" * 40
        )
        self.assertEqual(code, 10)
        self.assertFalse(self.output["merge"]["success"])
        self.assertEqual(self.output["merge"]["mergedHead"], "f" * 40)

    def test_an_unpinned_request_whose_merge_cannot_be_read_is_unconfirmed(
        self,
    ) -> None:
        code = self._run(_conflict(_async("pending")), [_async("merged")], merged=None)
        self.assertEqual(code, 10)
        self.assertFalse(self.output["merged"])
        self.assertTrue(self.output["mergeUnconfirmed"])

    def test_a_request_not_adopted_is_still_recorded_as_live(self) -> None:
        state = tempfile.TemporaryDirectory()
        self.addCleanup(state.cleanup)
        self._run(
            _conflict(_pending_with_options(head="f" * 40)),
            extra=("--state-dir", state.name),
        )
        path = pathlib.Path(state.name) / merge.PENDING_MERGES_FILE
        records = json.loads(path.read_text(encoding="utf-8"))["requests"]
        self.assertEqual(records["owner/repo#1"]["uuid"], UUID)


class PullRequestReadBack(unittest.TestCase):
    def _landed(self, payload: Any) -> dict[str, Any]:
        with mock.patch.object(merge, "gh_json", return_value=payload):
            return merge.pull_request_landed("owner/repo", 1)

    def test_a_merged_pull_request_reports_its_head(self) -> None:
        self.assertEqual(
            self._landed({"merged": True, "head": HEAD}),
            {"merged": True, "head": HEAD},
        )

    def test_a_merge_with_no_readable_head_is_unconfirmed(self) -> None:
        self.assertEqual(
            self._landed({"merged": True, "head": None}),
            {"merged": None, "head": None},
        )

    def test_a_failed_read_is_unconfirmed(self) -> None:
        with mock.patch.object(
            merge, "gh_json", side_effect=RuntimeError("gh: (HTTP 502)")
        ):
            landed = merge.pull_request_landed("owner/repo", 1)
        self.assertEqual(landed, {"merged": None, "head": None})


class UnpinnedMergeStillPinsTheEvaluatedHead(AsyncMergeHarness):
    """`--allow-unpinned-head` waives only the `--expected-head` argument: the
    request still pins the head the gate just evaluated."""

    def test_async_request_carries_the_evaluated_head(self) -> None:
        code = self._run(_proc(_async("merged")), pinned=False)
        self.assertEqual(code, 0)
        self.assertEqual(self._fields(self._put())["sha"], HEAD)

    def test_gh_pr_merge_carries_the_evaluated_head(self) -> None:
        code = self._run(_proc(), base="release", pinned=False)
        self.assertEqual(code, 0)
        [legacy] = self.captures
        self.assertEqual(legacy[legacy.index("--match-head-commit") + 1], HEAD)

    def test_no_evaluated_head_sends_no_request(self) -> None:
        code = self._run(_proc(_async("merged")), pinned=False, head=None)
        self.assertEqual(code, 10)
        self.assertFalse(self.output["merge"]["attempted"])
        self.assertEqual(self.captures, [])


class MergeQueueIsEnqueued(AsyncMergeHarness):
    """A merge-queue base is enqueued through GraphQL `enqueuePullRequest`,
    never REST `merge-async`."""

    def test_queue_branch_enqueues_through_graphql_at_the_vetted_head(self) -> None:
        code = self._run(_proc(_enqueued(position=2)), merge_action="merge_queue")
        self.assertEqual(code, 0)
        self.assertEqual(self.output["action"], "enqueue")
        self.assertFalse(self.output["merged"])
        self.assertTrue(self.output["enqueued"])
        self.assertFalse(any("merge-async" in " ".join(c) for c in self.captures))
        [cmd] = self._enqueue_commands()
        self.assertEqual(cmd[:2], ["api", "graphql"])
        fields = self._fields(cmd)
        self.assertEqual((fields["id"], fields["head"]), (NODE_ID, HEAD))
        self.assertIn("pullRequestId:$id", fields["query"])
        self.assertIn("expectedHeadOid:$head", fields["query"])
        self.assertNotIn("jump", fields["query"])
        self.assertEqual(self.output["merge"]["api"], "graphql")
        self.assertEqual(
            self.output["merge"]["mergeQueue"], {"state": "QUEUED", "position": 2}
        )
        self.assertEqual(self.polls, [])

    def test_a_refused_enqueue_is_held_and_tries_no_other_api(self) -> None:
        refusal = "Enqueuer is not authorized to merge"
        code = self._run(
            _proc(_graphql_error(refusal), returncode=1, stderr=f"gh: {refusal}"),
            merge_action="merge_queue",
        )
        self.assertEqual(code, 10)
        self.assertFalse(self.output["enqueued"])
        self.assertIn(refusal, self.output["merge"]["message"])
        self.assertEqual(len(self._enqueue_commands()), 1)
        self.assertFalse(any("merge-async" in " ".join(c) for c in self.captures))
        self.assertFalse(any(c[:2] == ["pr", "merge"] for c in self.captures))

    def test_an_entry_returned_beside_errors_is_still_enqueued_and_recorded(
        self,
    ) -> None:
        state = tempfile.TemporaryDirectory()
        self.addCleanup(state.cleanup)
        answer = {**_enqueued(), "errors": [{"message": "partial"}]}
        code = self._run(
            _proc(answer, returncode=1, stderr="gh: partial"),
            merge_action="merge_queue",
            extra=("--state-dir", state.name),
        )
        self.assertEqual(code, 0)
        self.assertTrue(self.output["enqueued"])
        path = pathlib.Path(state.name) / merge.PENDING_MERGES_FILE
        record = json.loads(path.read_text(encoding="utf-8"))["requests"][
            "owner/repo#1"
        ]
        self.assertEqual((record["queued"], record["head"]), (True, HEAD))

    def test_an_answer_without_a_queue_entry_is_not_enqueued(self) -> None:
        answer = {"data": {"enqueuePullRequest": {"mergeQueueEntry": None}}}
        code = self._run(_proc(answer), merge_action="merge_queue")
        self.assertEqual(code, 10)
        self.assertFalse(self.output["enqueued"])

    def test_an_unreadable_pull_request_id_sends_no_enqueue(self) -> None:
        code = self._run(
            [],
            merge_action="merge_queue",
            node=RuntimeError("gh: Server Error (HTTP 502)"),
        )
        self.assertEqual(code, 10)
        self.assertFalse(self.output["enqueued"])
        self.assertEqual(self._enqueue_commands(), [])
        self.assertFalse(any(c[:2] == ["pr", "merge"] for c in self.captures))

    def test_a_refused_enqueue_records_nothing_for_later_runs(self) -> None:
        state = tempfile.TemporaryDirectory()
        self.addCleanup(state.cleanup)
        self._run(
            _proc(_graphql_error("refused"), returncode=1, stderr="gh: refused"),
            merge_action="merge_queue",
            extra=("--state-dir", state.name),
        )
        path = pathlib.Path(state.name) / merge.PENDING_MERGES_FILE
        records = (
            json.loads(path.read_text(encoding="utf-8"))["requests"]
            if path.exists()
            else {}
        )
        self.assertEqual(records, {})


class GhPrMergeOntoAQueueIsReportedQueued(AsyncMergeHarness):
    """`gh pr merge` routes a merge on any base that has a merge queue into the
    queue and exits 0, so a queue the rules read missed shows only in the PR's
    own `isInMergeQueue` / `mergeQueueEntry` read back afterward."""

    def test_a_merge_github_put_in_the_queue_is_queued_not_merged(self) -> None:
        code = self._run(_proc(), base="release", queue=[_queue(position=2)])
        self.assertEqual(code, 0)
        self.assertEqual(self.output["action"], "enqueue")
        self.assertFalse(self.output["merged"])
        self.assertTrue(self.output["enqueued"])
        self.assertEqual(self.output["mergeQueue"], {"state": "QUEUED", "position": 2})

    def test_an_unreadable_queue_keeps_the_merge_report_and_names_the_failure(
        self,
    ) -> None:
        code = self._run(
            _proc(), base="release", queue=[RuntimeError("gh: (HTTP 502)")]
        )
        self.assertEqual((code, self.output["merged"]), (0, True))
        self.assertIn("merge queue", self.output["merge"]["queueReadError"])

    def test_a_queued_merge_is_recorded_for_later_runs(self) -> None:
        state = tempfile.TemporaryDirectory()
        self.addCleanup(state.cleanup)
        self._run(
            _proc(),
            base="release",
            queue=[_queue(position=1)],
            extra=("--state-dir", state.name),
        )
        path = pathlib.Path(state.name) / merge.PENDING_MERGES_FILE
        record = json.loads(path.read_text(encoding="utf-8"))["requests"][
            "owner/repo#1"
        ]
        self.assertEqual((record["queued"], record["head"]), (True, HEAD))


class AnUnseenQueueResultIsHeldUntilConfirmed(AsyncMergeHarness):
    """A `gh pr merge` the queue base took can read back, for a moment, as
    neither queued, armed, nor merged. That success is re-read, then recorded
    unconfirmed, and later runs confirm it without sending another merge."""

    def setUp(self) -> None:
        super().setUp()
        self.state = tempfile.TemporaryDirectory()
        self.addCleanup(self.state.cleanup)

    def _merge(self, answers: list[dict[str, Any] | Exception]) -> int:
        return self._run(
            _proc(),
            base="release",
            queue=answers,
            extra=("--state-dir", self.state.name),
        )

    def _unseen_merge(self) -> None:
        code = self._merge([_queue()])
        self.assertEqual((code, self.output["action"]), (10, "merge-pending"))
        self.captures.clear()
        self.sleeps.clear()

    def _later_run(self, answer: dict[str, Any] | Exception, **kwargs: Any) -> int:
        return self._run(
            _proc(),
            base="release",
            queue=[answer],
            extra=("--state-dir", self.state.name),
            **kwargs,
        )

    def _records(self) -> dict[str, Any]:
        path = pathlib.Path(self.state.name) / merge.PENDING_MERGES_FILE
        return json.loads(path.read_text(encoding="utf-8"))["requests"]

    def _merge_commands(self) -> list[list[str]]:
        return [c for c in self.captures if c[:2] == ["pr", "merge"]]

    def test_an_unseen_result_is_read_once_then_held_and_recorded(self) -> None:
        code = self._merge([_queue()])
        self.assertEqual((code, self.output["action"]), (10, "merge-pending"))
        self.assertFalse(self.output["ready"])
        self.assertFalse(self.output["merged"])
        self.assertNotIn("enqueued", self.output)
        self.assertTrue(self.output["mergeQueue"]["unconfirmed"])
        self.assertIn("merge pending, unconfirmed", self.output["blockers"][0])
        self.assertEqual(self.queue_reads, 1)
        self.assertEqual(self.sleeps, [])
        record = self._records()["owner/repo#1"]
        self.assertEqual(
            (record["queued"], record["unconfirmed"], record["head"]),
            (True, True, HEAD),
        )

    def test_the_next_run_holds_without_sending_another_merge(self) -> None:
        self._unseen_merge()
        code = self._later_run(_queue())
        self.assertEqual((code, self.output["action"]), (10, "merge-pending"))
        self.assertFalse(self.output["ready"])
        self.assertTrue(self.output["mergeQueue"]["unconfirmed"])
        self.assertIn("merge pending, unconfirmed", self.output["blockers"][0])
        self.assertEqual(self._merge_commands(), [])
        self.assertEqual(self._records()["owner/repo#1"]["unseenReads"], 1)

    def test_an_entry_that_appears_later_is_reported_queued_and_confirmed(
        self,
    ) -> None:
        self._unseen_merge()
        code = self._later_run(_queue(position=2, state="AWAITING_CHECKS"))
        self.assertEqual((code, self.output["action"]), (10, "merge-pending"))
        self.assertTrue(self.output["enqueued"])
        self.assertEqual(
            self.output["mergeQueue"], {"state": "AWAITING_CHECKS", "position": 2}
        )
        self.assertEqual(self._merge_commands(), [])
        record = self._records()["owner/repo#1"]
        self.assertNotIn("unconfirmed", record)
        # Confirmed, it follows the queued-entry rule: leaving the queue unmerged
        # is a dequeue on the very next read.
        code = self._later_run(_queue())
        self.assertEqual(code, 10)
        self.assertTrue(self.output["dequeued"])
        self.assertEqual(self._records(), {})

    def test_an_arm_that_appears_later_holds_without_sending_another_merge(
        self,
    ) -> None:
        self._unseen_merge()
        code = self._later_run(_queue(armed=True))
        self.assertEqual((code, self.output["action"]), (10, "merge-pending"))
        self.assertFalse(self.output["enqueued"])
        self.assertTrue(self.output["mergeQueue"]["entersWhenReady"])
        self.assertIn("armed", self.output["blockers"][0])
        self.assertEqual(self._merge_commands(), [])
        self.assertNotIn("unconfirmed", self._records()["owner/repo#1"])

    def test_a_merge_that_appears_later_reports_merged(self) -> None:
        self._unseen_merge()
        code = self._later_run(
            _queue(merged=True), ready=False, blockers=["state=MERGED (not OPEN)"]
        )
        self.assertEqual(code, 0)
        self.assertTrue(self.output["merged"])
        self.assertEqual(self.output["pendingMergeRequest"]["status"], "merged")
        self.assertEqual(self._merge_commands(), [])
        self.assertEqual(self._records(), {})

    def test_a_result_never_seen_is_dequeued_and_gated_again(self) -> None:
        self._unseen_merge()
        for _ in range(merge.QUEUE_UNCONFIRMED_LATER_READS - 1):
            code = self._later_run(_queue())
            self.assertEqual((code, self.output["action"]), (10, "merge-pending"))
        code = self._later_run(_queue())
        self.assertEqual(code, 10)
        self.assertTrue(self.output["dequeued"])
        self.assertNotEqual(self.output["action"], "merge-pending")
        self.assertIn("dequeued", self.output["blockers"][0])
        self.assertEqual(self._merge_commands(), [])
        self.assertEqual(self._records(), {})
        self._later_run(_queue(position=1))
        self.assertEqual(len(self._merge_commands()), 1)
        self.assertEqual(self.output["action"], "enqueue")


class QueuedPullRequestIsConfirmedLater(AsyncMergeHarness):
    """An enqueue is not a merge: a later run reads the queue entry back and
    reports it still queued, merged at the vetted head, or dequeued."""

    def setUp(self) -> None:
        super().setUp()
        self.state = tempfile.TemporaryDirectory()
        self.addCleanup(self.state.cleanup)

    def _enqueue(self) -> None:
        code = self._run(
            _proc(_enqueued()),
            merge_action="merge_queue",
            extra=("--state-dir", self.state.name),
        )
        self.assertEqual((code, self.output["enqueued"]), (0, True))
        self.captures.clear()

    def _later_run(self, answer: dict[str, Any] | Exception, **kwargs: Any) -> int:
        return self._run(
            _proc(_enqueued()),
            merge_action="merge_queue",
            queue=[answer],
            extra=("--state-dir", self.state.name),
            **kwargs,
        )

    def _records(self) -> dict[str, Any]:
        path = pathlib.Path(self.state.name) / merge.PENDING_MERGES_FILE
        return json.loads(path.read_text(encoding="utf-8"))["requests"]

    def test_an_enqueue_is_recorded(self) -> None:
        self._enqueue()
        record = self._records()["owner/repo#1"]
        self.assertEqual((record["queued"], record["head"]), (True, HEAD))

    def test_a_pr_still_in_the_queue_reports_its_position_and_sends_nothing(
        self,
    ) -> None:
        self._enqueue()
        code = self._later_run(_queue(position=3, state="AWAITING_CHECKS"))
        self.assertEqual((code, self.output["action"]), (10, "merge-pending"))
        self.assertTrue(self.output["enqueued"])
        self.assertFalse(self.output["merged"])
        self.assertEqual(
            self.output["mergeQueue"], {"state": "AWAITING_CHECKS", "position": 3}
        )
        self.assertIn("position 3", self.output["blockers"][0])
        self.assertEqual(self.captures, [])
        self.assertIn("owner/repo#1", self._records())

    def test_a_pr_that_left_the_queue_merged_reports_the_merge(self) -> None:
        self._enqueue()
        code = self._later_run(
            _queue(merged=True), ready=False, blockers=["state=MERGED (not OPEN)"]
        )
        self.assertEqual(code, 0)
        self.assertTrue(self.output["merged"])
        self.assertEqual(self.output["blockers"], [])
        self.assertEqual(self.output["pendingMergeRequest"]["status"], "merged")
        self.assertEqual(self._records(), {})

    def test_a_queue_merge_at_another_head_escalates(self) -> None:
        self._enqueue()
        code = self._later_run(_queue(merged=True), landed_head="f" * 40)
        self.assertEqual(code, 10)
        self.assertIn("escalate", self.output["blockers"][0])
        self.assertFalse(self.output["merged"])

    def test_a_pr_that_left_the_queue_unmerged_is_reported_dequeued(self) -> None:
        self._enqueue()
        code = self._later_run(_queue())
        self.assertEqual(code, 10)
        self.assertTrue(self.output["dequeued"])
        self.assertFalse(self.output["merged"])
        self.assertNotEqual(self.output["action"], "merge-pending")
        self.assertIn("dequeued", self.output["blockers"][0])
        self.assertEqual(self.captures, [])
        self.assertEqual(self._records(), {})

    def test_a_dequeue_names_the_queue_removal_reason(self) -> None:
        self._enqueue()
        code = self._later_run(_queue(timeline=[COMMIT, _removed("failed_checks")]))
        self.assertEqual(code, 10)
        self.assertTrue(self.output["dequeued"])
        self.assertIn("removed it as 'failed_checks'", self.output["blockers"][0])
        self.assertNotIn("signature", self.output["blockers"][0])

    def test_a_branch_protection_dequeue_names_the_squash_signature_cause(
        self,
    ) -> None:
        self._enqueue()
        code = self._later_run(_queue(timeline=[_removed("branch_protection_failure")]))
        self.assertEqual(code, 10)
        blocker = self.output["blockers"][0]
        self.assertIn("removed it as 'branch_protection_failure'", blocker)
        self.assertIn("committer", blocker)
        self.assertIn("reword the body", blocker)

    def test_an_unreadable_queue_keeps_the_record_and_holds(self) -> None:
        self._enqueue()
        code = self._later_run(RuntimeError("gh: Server Error (HTTP 502)"))
        self.assertEqual((code, self.output["action"]), (10, "merge-pending"))
        self.assertIn("could not be read", self.output["blockers"][0])
        self.assertEqual(self.captures, [])
        self.assertIn("owner/repo#1", self._records())


class MergeQueueReadBack(unittest.TestCase):
    def _read(self, payload: Any) -> dict[str, Any]:
        with mock.patch.object(merge, "gh_json", return_value=payload) as gh_json:
            result = merge.read_merge_queue("owner/repo", 5)
        [args] = gh_json.call_args.args
        self.assertEqual(args[:2], ["api", "graphql"])
        self.assertIn("n=5", args)
        return result

    def test_a_queued_pull_request_reports_its_entry(self) -> None:
        result = self._read(_queue(position=4, state="MERGEABLE"))
        self.assertEqual(
            (
                result["readError"],
                result["inQueue"],
                result["position"],
                result["state"],
            ),
            (None, True, 4, "MERGEABLE"),
        )

    def test_a_pull_request_armed_to_enter_the_queue_is_not_in_it(self) -> None:
        result = self._read(_queue(armed=True))
        self.assertEqual(
            (result["inQueue"], result["queueRequired"], result["autoMergeArmed"]),
            (False, True, True),
        )

    def test_a_response_without_the_pull_request_is_a_read_error(self) -> None:
        self.assertIsNotNone(self._read({"data": {"repository": None}})["readError"])

    def test_a_failed_read_is_a_read_error(self) -> None:
        with mock.patch.object(
            merge, "gh_json", side_effect=RuntimeError("gh: boom (HTTP 500)")
        ):
            result = merge.read_merge_queue("owner/repo", 5)
        self.assertIn("gh: boom", result["readError"])

    def test_failed_check_removals_count_since_the_newest_head_change(self) -> None:
        for timeline, expected in (
            ([], 0),
            ([COMMIT, _removed(), _removed()], 2),
            ([_removed(), _removed(), _removed()], 3),
            # A head change inside a full window still bounds the count.
            ([COMMIT] + [_removed("manually_removed")] * (LIMIT - 1), 0),
            ([_removed(), _removed(), COMMIT], 0),
            ([_removed(), _removed(), FORCE_PUSH, _removed()], 1),
            ([COMMIT, _removed("manually_removed"), _removed()], 1),
        ):
            with self.subTest(timeline=timeline):
                result = self._read(_queue(timeline=timeline))
                self.assertEqual(result["failedEjections"], expected)

    def test_the_newest_removal_reason_is_read_until_a_head_change(self) -> None:
        for timeline, expected in (
            ([], None),
            (
                [_removed("failed_checks"), _removed("branch_protection_failure")],
                "branch_protection_failure",
            ),
            ([_removed("branch_protection_failure"), COMMIT], None),
            ([FORCE_PUSH, _removed("manually_removed")], "manually_removed"),
            ([_removed("")], None),
        ):
            with self.subTest(timeline=timeline):
                result = self._read(_queue(timeline=timeline))
                self.assertEqual(result["lastRemovalReason"], expected)

    def test_the_enqueue_a_failed_checks_removal_ended_is_read(self) -> None:
        added = {
            "__typename": "AddedToMergeQueueEvent",
            "createdAt": "2026-10-25T16:59:28Z",
            "actor": {"__typename": "User", "databaseId": 5},
            "enqueuer": {"databaseId": 5},
        }
        lane = {**added, "actor": {"__typename": "Bot", "databaseId": 9}}
        at = "2026-10-25T17:03:28Z"
        out = {**_removed(), "createdAt": at}

        def found(enqueue: dict[str, Any], requeued: bool = False) -> dict[str, Any]:
            return {"enqueue": enqueue, "removedAt": at, "requeued": requeued}

        for events, expected in (
            ([COMMIT, added, out], found(added)),
            ([added, out, lane], found(added, True)),
            ([added, _removed("merge_conflict")], None),
            ([added, _removed("manually_removed")], None),
            ([_removed(), added, _removed("merged")], None),
            ([added, _removed(), COMMIT], None),
            ([added, _removed(), FORCE_PUSH], None),
            ([added, COMMIT, _removed()], None),
            # The lane's retry ejected: its own enqueue, which no person made.
            (
                [added, _removed(), lane, out],
                found(lane),
            ),
            ([_removed()], None),
            ([added], None),
            ([], None),
            ([None, added, out], found(added)),
            ([added, None, _removed()], None),
            (None, None),
        ):
            with self.subTest(events=events):
                payload = _queue()
                pr = payload["data"]["repository"]["pullRequest"]
                pr["queueEvents"] = None if events is None else {"nodes": events}
                result = self._read(payload)
                self.assertEqual(result["ejectedEnqueue"], expected)
        # The extra read leaves the ejection count and removal reason alone.
        payload = _queue(timeline=[COMMIT, _removed()])
        payload["data"]["repository"]["pullRequest"]["queueEvents"] = {
            "nodes": [added, _removed()]
        }
        result = self._read(payload)
        self.assertEqual(
            (result["failedEjections"], result["lastRemovalReason"]),
            (1, "failed_checks"),
        )
        self.assertIn("ADDED_TO_MERGE_QUEUE_EVENT", merge.MERGE_QUEUE_QUERY)
        queue_events = merge.MERGE_QUEUE_QUERY.split("queueEvents:", 1)[1]
        self.assertIn("RemovedFromMergeQueueEvent{reason createdAt}", queue_events)

    def test_failed_merge_group_runs_are_the_pull_requests_own(self) -> None:
        runs = {
            "workflow_runs": [
                {"head_branch": "gh-readonly-queue/main/pr-5-abc", "html_url": "u1"},
                {"head_branch": "gh-readonly-queue/main/pr-55-abc", "html_url": "u2"},
                {"head_branch": "gh-readonly-queue/main/pr-5-def", "html_url": "u3"},
            ]
        }
        ok = subprocess.CompletedProcess([], 0, json.dumps(runs), "")
        with mock.patch.object(merge, "gh_capture", return_value=ok) as gh:
            self.assertEqual(
                merge._failed_merge_group_runs("owner/repo", "main", 5), ["u1", "u3"]
            )
        self.assertIn("event=merge_group&status=failure", gh.call_args.args[0][1])
        failed = subprocess.CompletedProcess([], 1, "", "HTTP 403")
        with mock.patch.object(merge, "gh_capture", return_value=failed):
            self.assertIsNone(merge._failed_merge_group_runs("owner/repo", "main", 5))

    def test_failed_check_removal_times_are_read_since_the_newest_head_change(
        self,
    ) -> None:
        at = "2026-11-12T04:40:05Z"
        out = {**_removed(), "createdAt": at}
        for timeline, expected in (
            ([], []),
            ([out, COMMIT, out], [at]),
            ([COMMIT, _removed("manually_removed"), out, _removed()], [at, ""]),
            ([{"__typename": "IssueComment"}, out], None),
        ):
            with self.subTest(timeline=timeline):
                result = self._read(_queue(timeline=timeline))
                self.assertEqual(result["failedRemovals"], expected)
        timeline = merge.MERGE_QUEUE_QUERY.split("queueEvents:", 1)[0]
        self.assertIn("RemovedFromMergeQueueEvent{reason createdAt}", timeline)

    def test_an_unreadable_timeline_counts_nothing(self) -> None:
        # A full window with no head change in it: older failed-check
        # removals may lie beyond it, so the count is unreadable.
        full = [_removed("manually_removed")] * (LIMIT - 1) + [_removed()]
        for timeline in (
            None,
            [{"__typename": "IssueComment"}, _removed()],
            [None],
            full,
        ):
            with self.subTest(timeline=timeline):
                payload = _queue()
                pr = payload["data"]["repository"]["pullRequest"]
                pr["timelineItems"] = None if timeline is None else {"nodes": timeline}
                result = self._read(payload)
                self.assertIsNone(result["readError"])
                self.assertIsNone(result["failedEjections"])


def _annotation(level: str, message: str) -> dict[str, str]:
    return {"annotation_level": level, "message": message}


# The failure and warning annotations of run 43155083740's CI Status job
# (check run 130976739440, the merge group of #15535 on 2026-11-12), as GitHub
# returned them; the notices, one repeated pair and the long request-id warning
# are left out, and the jobs read's jq filter is cut from its command.
RATE_LIMITED_GATE = [
    _annotation("failure", "Process completed with exit code 1."),
    _annotation(
        "failure",
        "could not record ci-lanes on 58fe3155b5d6e48a08a0d999deb5f1cb68f4f3bc "
        "(HTTP 403): rate limited past rate-limit-wait-seconds; re-run this job "
        "after the limit resets",
    ),
    _annotation(
        "warning",
        "POST repos/melodic-software/claude-code-plugins/statuses/"
        "58fe3155b5d6e48a08a0d999deb5f1cb68f4f3bc is rate limited and needs a "
        "831s wait, more than the 60s left of rate-limit-wait-seconds (60); not "
        "waiting. The limit resets at 1794459224 (2026-11-12T04:53:44Z).",
    ),
    _annotation("failure", "could not read #15535; re-run this run."),
    _annotation(
        "failure",
        "GitHub's core API rate limit blocks 'gh api repos/melodic-software/"
        "claude-code-plugins/pulls/15535' until 2026-11-12T04:53:44Z, past the "
        "2026-11-12T04:53:27Z ci-status can wait to inside its timeout; a re-run "
        "after 2026-11-12T04:53:44Z is needed.",
    ),
    _annotation(
        "failure",
        "'gh api repos/melodic-software/claude-code-plugins/pulls/15535' was not "
        "sent: GitHub's core API rate limit holds until 2026-11-12T04:53:44Z",
    ),
    _annotation(
        "warning",
        "the run cache was not carried: GET https://api.github.com/repos/"
        "melodic-software/claude-code-plugins/actions/workflows/pr-merge.yml/runs"
        " was not sent: GitHub's core API rate limit holds until "
        "2026-11-12T04:53:44Z",
    ),
    _annotation(
        "failure",
        "GET https://api.github.com/repos/melodic-software/claude-code-plugins/"
        "actions/workflows/pr-merge.yml/runs?branch=main&exclude_pull_requests=true"
        "&per_page=100&page=1 was not sent: GitHub's core API rate limit holds "
        "until 2026-11-12T04:53:44Z",
    ),
    _annotation(
        "failure",
        "'gh api repos/melodic-software/claude-code-plugins/actions/runs/"
        "43155083740/attempts/1/jobs?per_page=100' hit GitHub's core API rate "
        "limit: no call to it before 2026-11-12T04:53:44Z (x-ratelimit-reset); "
        "the call returns 1",
    ),
]
REMOVED_AT = "2026-11-12T04:40:05Z"
AFTER_RESET = merge.parse_github_timestamp("2026-11-12T05:00:00Z")
ENTRY_SHA = "5" * 40


def _job(job_id: int, name: str, conclusion: str = "failure") -> dict[str, Any]:
    return {"id": job_id, "name": name, "conclusion": conclusion}


GATE_JOBS = [
    _job(1, "test-python", "success"),
    _job(2, merge.merge_policy.GATE_CHECK),
    _job(3, merge.merge_policy.GATE_ALIAS),
]


class RateLimitedQueueRemovalsAreNotCounted(unittest.TestCase):
    """A merge-queue removal whose merge-group run failed only its gate, on a
    GitHub rate limit that has since reset, does not count toward
    `merge.max-queue-ejections`; every other failed-check removal does."""

    def setUp(self) -> None:
        self.runs: list[dict[str, Any]] | Exception = [self._run(9, ENTRY_SHA)]
        self.jobs: dict[int, Any] = {9: GATE_JOBS}
        self.annotations: dict[int, Any] = {2: RATE_LIMITED_GATE}
        self.now = AFTER_RESET
        self.paths: list[str] = []

    @staticmethod
    def _run(
        run_id: int,
        sha: str,
        created: str = "2026-11-12T04:28:59Z",
        updated: str = REMOVED_AT,
    ) -> dict[str, Any]:
        return {
            "id": run_id,
            "run_attempt": 1,
            "status": "completed",
            "head_branch": f"gh-readonly-queue/main/pr-5-{sha}",
            "head_sha": sha,
            "html_url": f"https://github.com/owner/repo/actions/runs/{run_id}",
            "created_at": created,
            "updated_at": updated,
        }

    def _read(self, path: str) -> Any:
        self.paths.append(path)
        if "actions/runs?" in path:
            if isinstance(self.runs, Exception):
                raise self.runs
            return {"workflow_runs": self.runs}
        if "/jobs" in path:
            jobs = self.jobs[int(path.split("/actions/runs/")[1].split("/")[0])]
            if isinstance(jobs, Exception):
                raise jobs
            return {"total_count": len(jobs), "jobs": jobs}
        found = self.annotations[int(path.split("/check-runs/")[1].split("/")[0])]
        if isinstance(found, Exception):
            raise found
        return found

    def hold(
        self, removals: list[str], ejections: int | None = None
    ) -> tuple[str | None, str | None, str | None]:
        count = len(removals) if ejections is None else ejections
        with (
            mock.patch.object(merge, "_verdict_read", side_effect=self._read),
            mock.patch.object(merge, "_now", return_value=self.now),
        ):
            return merge.queue_ejection_hold(
                "owner/repo", "main", 5, HEAD, count, 2, removals
            )

    def assert_counted(self, removals: list[str]) -> None:
        refusal = self.hold(removals)[0]
        self.assertTrue(
            refusal and refusal.startswith(f"queue-ejected:{len(removals)} "), refusal
        )

    def test_a_removal_the_gate_failed_on_a_reset_rate_limit_is_not_counted(
        self,
    ) -> None:
        # The earlier removal failed a lane; only the rate-limited one drops.
        self.runs.append(
            self._run(8, "4" * 40, "2026-11-12T02:00:00Z", "2026-11-12T02:10:00Z")
        )
        self.jobs[8] = [*GATE_JOBS[1:], _job(4, "test-node")]
        refusal, body, error = self.hold(["2026-11-12T02:10:00Z", REMOVED_AT])
        self.assertEqual((refusal, body, error), (None, None, None))

    def test_a_removal_for_a_failed_lane_is_counted(self) -> None:
        self.jobs[9] = [*GATE_JOBS, _job(4, "test-node")]
        self.assert_counted([REMOVED_AT, REMOVED_AT])

    def test_a_gate_that_failed_on_its_own_hold_beside_the_limit_is_counted(
        self,
    ) -> None:
        held = _annotation(
            "failure",
            "#5 carries 'needs-human'. Removing the label approves this pull "
            "request; ci-status re-runs on the unlabel.",
        )
        self.annotations[2] = [*RATE_LIMITED_GATE, held]
        self.assert_counted([REMOVED_AT, REMOVED_AT])

    def test_a_gate_failure_with_no_rate_limit_line_is_counted(self) -> None:
        self.annotations[2] = [
            a for a in RATE_LIMITED_GATE if "rate limit" not in a["message"]
        ]
        self.assert_counted([REMOVED_AT, REMOVED_AT])

    def test_a_removal_before_the_limit_resets_is_counted(self) -> None:
        self.now = merge.parse_github_timestamp("2026-11-12T04:50:00Z")
        self.assert_counted([REMOVED_AT, REMOVED_AT])

    # A server error hold (a 5xx whose only signal was Retry-After) is held
    # like a rate limit and is infrastructure too: a gate that failed on its
    # lines alone is not counted once the hold has passed, and is before.
    SERVER_ERROR_GATE: ClassVar[list[dict[str, Any]]] = [
        _annotation("failure", "Process completed with exit code 75."),
        _annotation(
            "failure",
            "GitHub answered HTTP 503 with a Retry-After; no GitHub call is sent "
            "before 2026-11-12T04:53:44Z",
        ),
        _annotation(
            "failure",
            "GET https://api.github.com/repos/o/r/pulls/5 got a GitHub server "
            "error, HTTP 502 with a Retry-After: no call to it before "
            "2026-11-12T04:52:00Z (retry-after); this step fails",
        ),
        _annotation(
            "failure",
            "GET https://api.github.com/repos/o/r/issues/5 was not sent: GitHub "
            "answered HTTP 502 with a Retry-After; no call to it before "
            "2026-11-12T04:52:00Z",
        ),
    ]

    def test_a_removal_the_gate_failed_on_a_passed_server_error_hold_is_not_counted(
        self,
    ) -> None:
        self.annotations[2] = self.SERVER_ERROR_GATE
        self.assertEqual(self.hold([REMOVED_AT, REMOVED_AT]), (None, None, None))

    def test_a_removal_before_a_server_error_hold_passes_is_counted(self) -> None:
        self.annotations[2] = self.SERVER_ERROR_GATE
        self.now = merge.parse_github_timestamp("2026-11-12T04:53:00Z")
        self.assert_counted([REMOVED_AT, REMOVED_AT])

    def test_unreadable_evidence_counts_the_removal(self) -> None:
        cases = {
            "runs listing": lambda: setattr(self, "runs", RuntimeError("HTTP 403")),
            "jobs": lambda: self.jobs.__setitem__(9, RuntimeError("HTTP 403")),
            "annotations": lambda: self.annotations.__setitem__(
                2, RuntimeError("HTTP 403")
            ),
            "no run ended at the removal": lambda: self.runs.__setitem__(
                0, self._run(9, ENTRY_SHA, updated="2026-11-12T04:30:00Z")
            ),
            "two queue entries ended at the removal": lambda: self.runs.append(
                self._run(7, "6" * 40)
            ),
        }
        for name, break_it in cases.items():
            with self.subTest(name):
                self.setUp()
                break_it()
                self.assert_counted([REMOVED_AT, REMOVED_AT])
        with self.subTest("removal with no time"):
            self.setUp()
            self.assert_counted(["", ""])

    def test_under_the_cap_nothing_is_read(self) -> None:
        self.assertEqual(self.hold([REMOVED_AT]), (None, None, None))
        self.assertEqual(self.paths, [])

    def test_a_certain_refusal_stops_reading(self) -> None:
        # The two newest removals failed a lane: a third changes nothing.
        self.jobs[9] = [*GATE_JOBS, _job(4, "test-node")]
        self.hold([REMOVED_AT] * 3)
        self.assertEqual(sum("/jobs" in p for p in self.paths), 2)


def _listed(number: int, sha: str, *, merged: bool = False) -> dict[str, Any]:
    return {
        "number": number,
        "state": "closed" if merged else "open",
        "draft": False,
        "merged_at": "2026-10-02T00:00:00Z" if merged else None,
        "head": {"ref": f"layer-{number}", "sha": sha},
    }


# The harness PR is #1; #2 is the open layer below it, evaluated at LAYER2.
AS_EVALUATED = [_listed(2, LAYER2), _listed(1, HEAD)]
LANDED = [_listed(2, LAYER2, merged=True), _listed(1, HEAD, merged=True)]


class StackLandsThroughTheAsyncApi(AsyncMergeHarness):
    def _stack(self, put: mock.Mock, listings: list[list[dict[str, Any]]]) -> int:
        return self._run(
            put,
            base="feat/b",
            stack_lands=True,
            stack_listings=listings,
            extra=("--stacked-prs",),
        )

    def test_stack_merge_never_falls_back_to_gh_pr_merge(self) -> None:
        missing = _proc(
            {"message": "Not Found"}, returncode=1, stderr="gh: Not Found (HTTP 404)"
        )
        code = self._stack(missing, [AS_EVALUATED])
        self.assertEqual(code, 10)
        self.assertFalse(any(c[:2] == ["pr", "merge"] for c in self.captures))

    def test_stack_merge_is_a_direct_async_merge_verified_layer_by_layer(self) -> None:
        code = self._stack(_proc(_async("merged")), [AS_EVALUATED, LANDED])
        self.assertEqual(code, 0)
        self.assertEqual(self._fields(self._put())["merge_action"], "direct_merge")
        self.assertEqual(self.output["stackVerification"]["verified"], True)

    def test_a_lower_layer_pushed_after_evaluation_is_never_requested(self) -> None:
        moved = [_listed(2, "f" * 40), _listed(1, HEAD)]
        code = self._stack(_proc(_async("merged")), [moved])
        self.assertEqual(code, 10)
        self.assertFalse(self.output["merge"]["attempted"])
        self.assertFalse(any("merge-async" in " ".join(c) for c in self.captures))

    def test_a_layer_added_below_after_evaluation_is_never_requested(self) -> None:
        grown = [_listed(3, "9" * 40), _listed(2, LAYER2), _listed(1, HEAD)]
        code = self._stack(_proc(_async("merged")), [grown])
        self.assertEqual(code, 10)
        self.assertFalse(any("merge-async" in " ".join(c) for c in self.captures))

    def test_a_layer_landing_at_another_head_is_reported(self) -> None:
        other = [_listed(2, "e" * 40, merged=True), _listed(1, HEAD, merged=True)]
        code = self._stack(_proc(_async("merged")), [AS_EVALUATED, other])
        self.assertEqual(code, 10)
        self.assertTrue(self.output["merged"])
        [mismatch] = self.output["stackVerification"]["mismatches"]
        self.assertEqual(
            (mismatch["pr"], mismatch["evaluatedHead"], mismatch["reportedHead"]),
            ("owner/repo#2", LAYER2, "e" * 40),
        )


class BottomStackMemberMergesThroughTheAsyncApi(AsyncMergeHarness):
    """GitHub documents the async API as the required API for merging a
    stacked pull request, so the bottom layer (base == trunk) uses it even on
    a trunk that is not the default branch."""

    def _bottom(self, put: mock.Mock) -> int:
        return self._run(
            put,
            base="release",
            default_branch="main",
            stack_member=True,
            extra=("--stacked-prs",),
        )

    def test_bottom_member_on_a_non_default_trunk_merges_async(self) -> None:
        code = self._bottom(_proc(_async("merged")))
        self.assertEqual(code, 0)
        self.assertEqual(
            len([c for c in self.captures if "merge-async" in " ".join(c)]), 1
        )
        self.assertFalse(any(c[:2] == ["pr", "merge"] for c in self.captures))
        self.assertEqual(self.stack_reads, 0)

    def test_bottom_member_without_the_endpoint_is_held(self) -> None:
        missing = _proc(
            {"message": "Not Found"}, returncode=1, stderr="gh: Not Found (HTTP 404)"
        )
        code = self._bottom(missing)
        self.assertEqual(code, 10)
        self.assertFalse(any(c[:2] == ["pr", "merge"] for c in self.captures))


class PendingRequestOutlivesTheRun(AsyncMergeHarness):
    """GitHub documents no route to cancel an async merge request, so a request
    left pending is recorded and every later run reports it."""

    def setUp(self) -> None:
        super().setUp()
        self.state = tempfile.TemporaryDirectory()
        self.addCleanup(self.state.cleanup)

    def _leave_pending(self) -> None:
        bound = merge.ASYNC_MERGE_POLL_TIMEOUT_SECONDS
        code = self._run(
            _proc(_async("pending")),
            [_async("pending")],
            clock=[0.0, bound + 1],
            extra=("--state-dir", self.state.name),
        )
        self.assertEqual((code, self.output["merge"]["status"]), (10, "pending"))

    def _records(self) -> dict[str, Any]:
        path = pathlib.Path(self.state.name) / merge.PENDING_MERGES_FILE
        return json.loads(path.read_text(encoding="utf-8"))["requests"]

    def test_a_pending_request_is_recorded(self) -> None:
        self._leave_pending()
        record = self._records()["owner/repo#1"]
        self.assertEqual((record["uuid"], record["head"]), (UUID, HEAD))

    def test_a_later_held_run_reports_merge_pending_and_sends_nothing(self) -> None:
        self._leave_pending()
        self.captures.clear()
        code = self._run(
            _proc(),
            [_async("pending")],
            ready=False,
            merge_flag=False,
            extra=("--state-dir", self.state.name),
        )
        self.assertEqual(code, 10)
        self.assertEqual(self.output["action"], "merge-pending")
        self.assertIn(UUID, self.output["blockers"][0])
        self.assertEqual(self.captures, [])

    def test_a_later_ready_run_does_not_request_again(self) -> None:
        self._leave_pending()
        self.captures.clear()
        code = self._run(
            _proc(_async("merged")),
            [_async("pending")],
            extra=("--state-dir", self.state.name),
        )
        self.assertEqual((code, self.output["action"]), (10, "merge-pending"))
        self.assertEqual(self.captures, [])

    def test_an_unreadable_request_still_counts_as_pending(self) -> None:
        self._leave_pending()
        self._run(
            _proc(),
            [RuntimeError("gh: Server Error (HTTP 502)")],
            merge_flag=False,
            extra=("--state-dir", self.state.name),
        )
        self.assertEqual(self.output["action"], "merge-pending")
        self.assertIn("owner/repo#1", self._records())

    def test_a_finished_request_clears_the_record(self) -> None:
        self._leave_pending()
        code = self._run(
            _proc(),
            [_async("merged")],
            ready=False,
            merge_flag=False,
            extra=("--state-dir", self.state.name),
        )
        self.assertEqual((code, self.output["merged"]), (0, True))
        self.assertEqual(self.output["pendingMergeRequest"]["status"], "merged")
        self.assertEqual(self._records(), {})

    def test_a_record_older_than_a_day_is_still_polled(self) -> None:
        self._corrupt_record(UUID, age_hours=30)
        self._run(
            _proc(),
            [_async("merged")],
            merge_flag=False,
            extra=("--state-dir", self.state.name),
        )
        self.assertEqual(len(self.polls), 1)
        prior = self.output["pendingMergeRequest"]
        self.assertEqual(prior["status"], "merged")
        self.assertIn("verification", prior)

    def test_an_expired_request_clears_the_record(self) -> None:
        self._leave_pending()
        self._run(
            _proc(),
            [RuntimeError("gh: Not Found (HTTP 404)")],
            merge_flag=False,
            extra=("--state-dir", self.state.name),
        )
        self.assertEqual(self.output["pendingMergeRequest"]["status"], "expired")
        self.assertEqual(self._records(), {})

    def _corrupt_record(self, uuid: str, *, age_hours: float = 0) -> None:
        path = pathlib.Path(self.state.name) / merge.PENDING_MERGES_FILE
        requested = merge.datetime.now(merge.UTC) - timedelta(hours=age_hours)
        entry = {
            "uuid": uuid,
            "head": HEAD,
            "mergeAction": "direct_merge",
            "requestedAt": requested.isoformat(),
        }
        merge.write_state(
            path, {"schema_version": 1, "requests": {"owner/repo#1": entry}}
        )

    def test_a_record_with_an_unusable_request_id_is_held_and_never_read(
        self,
    ) -> None:
        self._corrupt_record("../../../user")
        self._assert_corrupt_hold()

    def test_a_corrupt_record_is_held_however_old(self) -> None:
        self._corrupt_record("../../../user", age_hours=48)
        self._assert_corrupt_hold()

    def test_an_id_with_a_trailing_newline_is_corrupt(self) -> None:
        self._corrupt_record(UUID + "\n")
        self._assert_corrupt_hold()

    def _assert_corrupt_hold(self) -> None:
        code = self._run(_proc(), [], extra=("--state-dir", self.state.name))
        self.assertEqual((code, self.output["action"]), (10, "merge-pending"))
        self.assertIn("corrupt", self.output["blockers"][0])
        self.assertEqual(self.polls, [])
        self.assertEqual(self.captures, [])
        self.assertIn("owner/repo#1", self._records())


class PendingRequestIsVerifiedWhenItLands(AsyncMergeHarness):
    """The request's `sha` pins only the top PR, so a request that finishes in
    a later run is checked against every head the gate evaluated."""

    def setUp(self) -> None:
        super().setUp()
        self.state = tempfile.TemporaryDirectory()
        self.addCleanup(self.state.cleanup)

    def _leave_pending(self, *, stack: bool = True) -> None:
        code = self._run(
            _proc(_async("pending")),
            [_async("pending")],
            clock=[0.0, merge.ASYNC_MERGE_POLL_TIMEOUT_SECONDS + 1],
            base="feat/b" if stack else "main",
            stack_lands=stack,
            stack_listings=[AS_EVALUATED] if stack else None,
            extra=("--state-dir", self.state.name)
            + (("--stacked-prs",) if stack else ()),
        )
        self.assertEqual((code, self.output["merge"]["status"]), (10, "pending"))

    def _later_run(self, listing: Any = None, **kwargs: Any) -> int:
        self.captures.clear()
        return self._run(
            _proc(),
            [_async("merged")],
            merge_flag=False,
            stack_listings=None if listing is None else [listing],
            extra=("--state-dir", self.state.name),
            **kwargs,
        )

    def _records(self) -> dict[str, Any]:
        path = pathlib.Path(self.state.name) / merge.PENDING_MERGES_FILE
        return json.loads(path.read_text(encoding="utf-8"))["requests"]

    def test_the_record_keeps_the_evaluated_lower_layers(self) -> None:
        self._leave_pending()
        stack = self._records()["owner/repo#1"]["stack"]
        self.assertEqual(stack["number"], 7)
        self.assertEqual(
            [(layer["number"], layer["headRefOid"]) for layer in stack["layers"]],
            [(2, LAYER2)],
        )

    def test_a_layer_that_landed_at_another_head_escalates(self) -> None:
        self._leave_pending()
        other = [_listed(2, "e" * 40, merged=True), _listed(1, HEAD, merged=True)]
        code = self._later_run(other)
        self.assertEqual(code, 10)
        self.assertIn("escalate", self.output["blockers"][0])
        verification = self.output["pendingMergeRequest"]["verification"]
        self.assertFalse(verification["verified"])
        [mismatch] = verification["mismatches"]
        self.assertEqual(
            (mismatch["pr"], mismatch["evaluatedHead"], mismatch["reportedHead"]),
            ("owner/repo#2", LAYER2, "e" * 40),
        )

    def test_a_stack_that_landed_as_evaluated_clears_the_record(self) -> None:
        self._leave_pending()
        code = self._later_run(LANDED)
        self.assertEqual(code, 0)
        self.assertTrue(self.output["pendingMergeRequest"]["verification"]["verified"])
        self.assertEqual(self._records(), {})

    def test_a_landed_request_reports_merged_even_though_the_gate_sees_a_closed_pr(
        self,
    ) -> None:
        self._leave_pending()
        code = self._later_run(LANDED, blockers=["state=MERGED (not OPEN)"])
        self.assertEqual(code, 0)
        self.assertTrue(self.output["merged"])
        self.assertTrue(self.output["ready"])
        self.assertEqual(self.output["blockers"], [])
        self.assertEqual(self.output["action"], "check")
        self.assertEqual(
            (self.output["merge"]["attempted"], self.output["merge"]["source"]),
            (False, "pendingMergeRequest"),
        )
        self.assertEqual(self.output["merge"]["uuid"], UUID)
        self.assertEqual(self._records(), {})

    def test_an_unreadable_stack_keeps_the_record_and_holds(self) -> None:
        self._leave_pending()
        code = self._later_run(RuntimeError("gh: Server Error (HTTP 502)"))
        self.assertEqual(code, 10)
        self.assertIsNone(
            self.output["pendingMergeRequest"]["verification"]["verified"]
        )
        self.assertIn("owner/repo#1", self._records())

    def test_a_top_pull_request_that_merged_another_head_escalates(self) -> None:
        self._leave_pending(stack=False)
        code = self._later_run(landed_head="f" * 40)
        self.assertEqual(code, 10)
        self.assertIn("escalate", self.output["blockers"][0])
        [mismatch] = self.output["pendingMergeRequest"]["verification"]["mismatches"]
        self.assertEqual(mismatch["reportedHead"], "f" * 40)


class GateEvaluation(unittest.TestCase):
    """`evaluate` over a three-layer native stack: #1 (base main, head feat/a),
    #2 (base feat/a, head feat/b), and #3 (base feat/b), the PR under test."""

    def setUp(self) -> None:
        RepoConfigFake().install(self)
        self.views = {
            1: self._view(LAYER1, "main"),
            2: self._view(LAYER2, "feat/a"),
            3: self._view(HEAD, "feat/b"),
        }
        self.members = [
            self._member(1, "feat/a", LAYER1),
            self._member(2, "feat/b", LAYER2),
            self._member(3, "feat/c", HEAD),
        ]
        self.stack: Any = {
            "base": {"ref": "main", "sha": "e" * 40},
            "number": 7,
            "position": 3,
        }
        self.stack_error = False
        self.rules: dict[str, list[dict[str, Any]]] = {"main": APPROVED_RULES}
        self.calls: list[list[str]] = []

    @staticmethod
    def _view(head: str, base: str, **overrides: Any) -> dict[str, Any]:
        view = {
            "state": "OPEN",
            "isDraft": False,
            "mergeable": "MERGEABLE",
            "mergeStateStatus": "CLEAN",
            "reviewDecision": "APPROVED",
            "headRefOid": head,
            "baseRefName": base,
            "author": {"login": SELF},
            "url": "u",
            "title": "t",
            "labels": [],
            "body": "",
            "statusCheckRollup": [],
        }
        view.update(overrides)
        return view

    @staticmethod
    def _member(
        number: int, head_ref: str, sha: str, **overrides: Any
    ) -> dict[str, Any]:
        member = {
            "number": number,
            "state": "open",
            "draft": False,
            "merged_at": None,
            "head": {"ref": head_ref, "sha": sha},
        }
        member.update(overrides)
        return member

    def _evaluate(self, *, stacked: bool = True, number: int = 3) -> dict[str, Any]:
        def gh_json(args: list[str]) -> Any:
            self.calls.append(args)
            if args[0] == "api" and "/compare/" in args[1]:
                return UP_TO_DATE
            if args[:2] == ["pr", "view"]:
                return self.views[int(args[2])]
            path = args[1]
            if path.startswith("repos/owner/repo/rules/branches/"):
                # The gate percent-encodes the branch. GitHub decodes that
                # segment back to the branch name before matching rules.
                branch = unquote(path.split("/rules/branches/", 1)[1])
                return self.rules.get(branch, [])
            if path == "repos/owner/repo":
                return {"name": "main"}
            if path.startswith("repos/owner/repo/pulls/") and "{stack: .stack}" in args:
                if self.stack_error:
                    raise RuntimeError("gh: Server Error (HTTP 502)")
                return {"stack": self.stack}
            if path == "repos/owner/repo/stacks/7":
                return {
                    "number": 7,
                    "base": {"ref": "main"},
                    "pull_requests": self.members,
                }
            raise AssertionError(f"unexpected gh_json call: {args}")

        with (
            mock.patch.object(merge, "gh_json", side_effect=gh_json),
            mock.patch.object(merge, "fetch_review_threads", return_value=[]),
        ):
            return merge.evaluate(
                "owner/repo",
                number,
                self.views[number]["headRefOid"],
                {"owner"},
                frozenset({SELF}),
                False,
                False,
                stacked=stacked,
            )

    def _stack_reads(self) -> list[list[str]]:
        return [c for c in self.calls if "{stack: .stack}" in c or "stacks/" in c[1]]

    def test_flag_off_holds_a_stack_layer_and_reads_no_stack(self) -> None:
        result = self._evaluate(stacked=False)
        self.assertFalse(result["ready"])
        self.assertTrue(
            any("'feat/b' is unprotected" in b for b in result["blockers"]),
            result["blockers"],
        )
        self.assertEqual(self._stack_reads(), [])

    def test_flag_on_judges_the_layer_against_the_trunk_and_gates_every_layer(
        self,
    ) -> None:
        result = self._evaluate()
        self.assertTrue(result["ready"], result["blockers"])
        self.assertEqual(result["landingBase"], "main")
        self.assertTrue(result["stack"]["landsLowerLayers"])
        self.assertEqual(
            [layer["pr"] for layer in result["stack"]["layers"]],
            ["owner/repo#1", "owner/repo#2"],
        )
        rule_reads = {c[1] for c in self.calls if "/rules/branches/" in c[1]}
        self.assertEqual(rule_reads, {"repos/owner/repo/rules/branches/main"})

    def test_a_lower_layer_missing_an_ai_review_holds_the_auto_merge(self) -> None:
        reviewed = [
            {
                "__typename": "CheckRun",
                "name": name,
                "status": "COMPLETED",
                "conclusion": "SUCCESS",
            }
            for name in merge.AI_REVIEW_CHECKS
        ]
        for number in (2, 3):
            self.views[number]["statusCheckRollup"] = reviewed
        self.views[1]["statusCheckRollup"] = reviewed[1:]  # claude-review-status absent
        result = self._evaluate()
        self.assertTrue(result["ready"], result["blockers"])
        self.assertFalse(result["autoMerge"]["ready"])
        self.assertEqual(
            result["autoMerge"]["blockers"],
            [
                "stack layer owner/repo#1: AI review check 'claude-review-status' "
                "has not succeeded on the live head"
            ],
        )

    def test_a_lower_layer_blocker_holds_the_stack(self) -> None:
        self.views[1]["isDraft"] = True
        result = self._evaluate()
        self.assertIn(
            "stack layer owner/repo#1: PR is a draft -- mark ready first",
            result["blockers"],
        )

    def test_a_lower_layer_whose_head_moved_holds_the_stack(self) -> None:
        self.views[2]["headRefOid"] = "f" * 40
        result = self._evaluate()
        self.assertTrue(
            any(
                b.startswith("stack layer owner/repo#2: head moved")
                for b in result["blockers"]
            ),
            result["blockers"],
        )

    def test_a_broken_chain_holds(self) -> None:
        self.views[2]["baseRefName"] = "elsewhere"
        result = self._evaluate()
        self.assertTrue(
            any("#2 targets 'elsewhere'" in b for b in result["blockers"]),
            result["blockers"],
        )

    def test_merged_lower_layers_are_skipped(self) -> None:
        self.members[0]["merged_at"] = "2026-10-01T00:00:00Z"
        self.members[0]["state"] = "closed"
        self.views[2]["baseRefName"] = "main"
        result = self._evaluate()
        self.assertTrue(result["ready"], result["blockers"])
        self.assertEqual(
            [layer["pr"] for layer in result["stack"]["layers"]], ["owner/repo#2"]
        )

    def test_a_closed_unmerged_layer_holds(self) -> None:
        self.members[1]["state"] = "closed"
        result = self._evaluate()
        self.assertIn(
            "stack layer owner/repo#2 is closed without merging -- held",
            result["blockers"],
        )

    def test_unreadable_membership_holds(self) -> None:
        self.stack_error = True
        result = self._evaluate()
        self.assertTrue(
            any(
                b.startswith("stack membership could not be read")
                for b in result["blockers"]
            )
        )

    def test_a_pr_outside_any_stack_keeps_the_non_default_hold(self) -> None:
        self.stack = None
        result = self._evaluate()
        self.assertTrue(
            any("'feat/b' is unprotected" in b for b in result["blockers"]),
            result["blockers"],
        )
        self.assertFalse(result["stack"]["landsLowerLayers"])

    def test_a_queue_trunk_holds_the_stack(self) -> None:
        self.rules["main"] = QUEUE_RULES
        result = self._evaluate()
        self.assertTrue(
            any("requires a merge queue" in b for b in result["blockers"]),
            result["blockers"],
        )

    def test_queue_on_the_default_branch_is_ready_to_enqueue(self) -> None:
        self.rules["main"] = QUEUE_RULES
        result = self._evaluate(stacked=False, number=1)
        self.assertTrue(result["ready"], result["blockers"])
        self.assertEqual(result["mergeAction"], "merge_queue")

    def test_queue_on_a_non_default_base_is_held(self) -> None:
        self.rules["feat/a"] = QUEUE_RULES
        result = self._evaluate(stacked=False, number=2)
        self.assertTrue(
            any(
                "not the default branch -- a direct merge is not allowed" in b
                for b in result["blockers"]
            ),
            result["blockers"],
        )

    def test_auto_merge_is_not_armed_over_a_queue(self) -> None:
        self.rules["main"] = QUEUE_RULES
        self.views[1]["isDraft"] = True
        result = self._evaluate(stacked=False, number=1)
        self.assertIn(merge.MERGE_QUEUE_AUTO_HOLD, result["autoMerge"]["blockers"])


if __name__ == "__main__":
    unittest.main()
