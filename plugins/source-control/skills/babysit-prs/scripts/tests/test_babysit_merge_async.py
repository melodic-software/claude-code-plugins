"""The merge gate's async merge path, merge-queue enqueue, and stacked PRs.

Expected request fields, statuses, and HTTP semantics come from GitHub's
"Merge a pull request asynchronously" and "Get the result of an asynchronous
merge" REST docs: `sha` pins the head, `merge_method` is direct-only,
`merge_action` is `direct_merge` or `merge_queue`, 409 returns the pending
request's UUID, and `enqueued` means queued, not merged. Stack membership and
the trunk rule come from "About stacked pull requests" and the stacks REST
endpoints. Every gh seam is stubbed; no real gh process is spawned.
"""

from __future__ import annotations

import contextlib
import io
import json
import pathlib
import sys
import tempfile
import unittest
from typing import Any
from unittest import mock

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

from repo_config_fake import RepoConfigFake
import babysit_merge as merge

HEAD = "c" * 40
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


class AsyncMergeHarness(unittest.TestCase):
    """Runs `main --merge` over a stubbed ready verdict and records gh calls."""

    def setUp(self) -> None:
        RepoConfigFake().install(self)
        self.captures: list[list[str]] = []
        self.polls: list[list[str]] = []
        self.sleeps: list[float] = []

    def _run(
        self,
        put: mock.Mock | list[mock.Mock],
        polls: list[dict[str, Any]] | None = None,
        *,
        merged: bool | None = True,
        base: str = "main",
        default_branch: str | None = "main",
        merge_action: str = "direct_merge",
        stack_lands: bool = False,
        stack_listings: list[list[dict[str, Any]]] | None = None,
        extra: tuple[str, ...] = (),
        clock: list[float] | None = None,
        ready: bool = True,
        merge_flag: bool = True,
    ) -> int:
        verdict = {
            "ready": ready,
            "blockers": [] if ready else ["1 unresolved review thread(s) [reviewer]"],
            "headRefOid": HEAD,
            "baseRef": base,
            "mergeAction": merge_action,
            "stack": {
                "enabled": True,
                "member": stack_lands,
                "landsLowerLayers": stack_lands,
                "number": 7,
                "layers": (
                    [{"pr": "owner/repo#2", "number": 2, "headRefOid": LAYER2}]
                    if stack_lands
                    else []
                ),
            },
            "autoMerge": {"ready": ready, "blockers": []},
        }
        puts = list(put) if isinstance(put, list) else [put]
        poll_answers = list(polls or [])
        listings = list(stack_listings or [])

        def capture(cmd: list[str]) -> Any:
            self.captures.append(cmd)
            if "merge-async" in " ".join(cmd):
                return puts.pop(0)
            return _proc()

        def gh_json(args: list[str]) -> Any:
            if "merge-async/" in args[1]:
                self.polls.append(args)
                answer = poll_answers.pop(0)
                if isinstance(answer, Exception):
                    raise answer
                return answer
            if args[1] == "repos/owner/repo/stacks/7":
                self.stack_reads += 1
                return {"number": 7, "pull_requests": listings.pop(0)}
            raise AssertionError(f"unexpected gh_json call: {args}")

        self.stack_reads = 0
        ticks = iter(clock or [0.0] * 50)
        argv = [
            "babysit_merge.py",
            "owner/repo#1",
            "--allowed-owners",
            "owner",
            *(("--merge", "--expected-head", HEAD) if merge_flag else ()),
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
            mock.patch.object(merge, "pull_request_merged", return_value=merged),
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

    def test_unreadable_default_branch_keeps_gh_pr_merge(self) -> None:
        self._run(_proc(), default_branch=None)
        self.assertEqual(self.captures[0][:2], ["pr", "merge"])


class MergeQueueIsEnqueued(AsyncMergeHarness):
    def test_queue_branch_enqueues_without_a_merge_method(self) -> None:
        code = self._run(
            _proc(_async("pending")), [_async("enqueued")], merge_action="merge_queue"
        )
        self.assertEqual(code, 0)
        self.assertEqual(self.output["action"], "enqueue")
        self.assertFalse(self.output["merged"])
        self.assertTrue(self.output["enqueued"])
        self.assertEqual(
            self._fields(self._put()),
            {"merge_action": "merge_queue", "bypass_rules": "false", "sha": HEAD},
        )

    def test_already_queued_answer_is_still_queued(self) -> None:
        code = self._run(_proc(_async("enqueued")), merge_action="merge_queue")
        self.assertEqual(code, 0)
        self.assertTrue(self.output["enqueued"])
        self.assertEqual(self.polls, [])

    def test_queue_without_the_endpoint_is_held(self) -> None:
        code = self._run(
            _proc(
                {"message": "Not Found"},
                returncode=1,
                stderr="gh: Not Found (HTTP 404)",
            ),
            merge_action="merge_queue",
        )
        self.assertEqual(code, 10)
        self.assertFalse(any(c[:2] == ["pr", "merge"] for c in self.captures))


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
        self.assertEqual(code, 10)
        self.assertEqual(self.output["pendingMergeRequest"]["status"], "merged")
        self.assertEqual(self._records(), {})

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
            if args[:2] == ["pr", "view"]:
                return self.views[int(args[2])]
            path = args[1]
            if path.startswith("repos/owner/repo/rules/branches/"):
                return self.rules.get(path.split("/rules/branches/", 1)[1], [])
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
