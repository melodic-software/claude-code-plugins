"""The post-merge check and its remediation (`babysit_postmerge`).

Expected values come from the plan's Design: "Enqueuer" (a null or non-human
`actor` or `enqueuer` is an auto-merge; no queue event is `unqueued-merge`),
"Post-merge" (verified = a green identity dispatch run on a main SHA that
contains the merge, a green canary run, and a matching `headRefOid` read-back;
a red full run is attributed after one wrapper re-run; the issue carries
`git revert <merge-sha>`), T10 (six hours without a dispatch run is a
failure), and T11 (dequeue, then the demotion issue, then telemetry).

The response shapes come from the recorded fixtures in fixtures/postmerge/,
with identifying details changed. Network is stubbed at the `gh_capture`
seam; no real gh process runs.
"""

from __future__ import annotations

import contextlib
import io
import json
import pathlib
import subprocess
import sys
import unittest
from datetime import UTC, datetime
from typing import Any
from unittest import mock

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import babysit_postmerge as pm

FIXTURES = pathlib.Path(__file__).resolve().parent / "fixtures" / "postmerge"
REPO = "example-org/example-repo"
IDENTITY = "agent-lanes[bot]"
HUMAN = {"__typename": "User", "login": "maintainer"}
APP_ACTOR = {"__typename": "Bot", "login": "agent-lanes"}
SINCE = datetime(2026, 10, 12, 0, 0, tzinfo=UTC)
MERGED_AT = datetime(2026, 10, 12, 10, 0, tzinfo=UTC)
MERGE_SHA = "3" * 40
HEAD_SHA = "2" * 40
LATER_SHA = "4" * 40
OTHER_SHA = "5" * 40


def human(actor: Any) -> bool:
    """Design "Human", for a repository whose only writer is `maintainer`."""
    if not isinstance(actor, dict) or actor.get("__typename") != "User":
        return False
    login = str(actor.get("login") or "")
    if login.endswith("[bot]") or login in {"github-actions", "agent-lanes"}:
        return False
    return login == "maintainer"


def merged_pr(**overrides: Any) -> dict[str, Any]:
    pr = json.loads((FIXTURES / "merged-pr.json").read_text(encoding="utf-8"))
    pr.update(overrides)
    return pr


def enqueued_by(actor: Any, enqueuer: Any) -> dict[str, Any]:
    return {
        "nodes": [
            {"createdAt": "2026-10-12T09:50:00Z", "actor": actor, "enqueuer": enqueuer}
        ]
    }


def identity_merge(**overrides: Any) -> dict[str, Any]:
    """A merge the agent identity enqueued (an App `actor`, null `enqueuer`)."""
    return merged_pr(timelineItems=enqueued_by(APP_ACTOR, None), **overrides)


def run(**overrides: Any) -> dict[str, Any]:
    payload = json.loads((FIXTURES / "workflow-run.json").read_text(encoding="utf-8"))
    payload.update(overrides)
    payload["html_url"] = f"https://github.com/{REPO}/actions/runs/{payload['id']}"
    return payload


def by(login: str) -> dict[str, Any]:
    return {"login": login, "type": "Bot" if login.endswith("[bot]") else "User"}


def dispatch_run(
    run_id: int, conclusion: str = "success", **overrides: Any
) -> dict[str, Any]:
    fields = {
        "id": run_id,
        "event": "workflow_dispatch",
        "conclusion": conclusion,
        "head_sha": LATER_SHA,
        "created_at": "2026-10-12T10:05:00Z",
        "actor": by(IDENTITY),
        "triggering_actor": by(IDENTITY),
    }
    fields.update(overrides)
    return run(**fields)


def canary_run(
    run_id: int, conclusion: str = "success", **overrides: Any
) -> dict[str, Any]:
    fields = {
        "id": run_id,
        "name": "post-merge-detect-silent-revert",
        "path": ".github/workflows/post-merge-detect-silent-revert.yml",
        "event": "push",
        "conclusion": conclusion,
        "head_sha": MERGE_SHA,
        "created_at": "2026-10-12T10:00:30Z",
    }
    fields.update(overrides)
    return run(**fields)


def schedule_run(
    run_id: int, conclusion: str = "failure", **overrides: Any
) -> dict[str, Any]:
    fields = {
        "id": run_id,
        "conclusion": conclusion,
        "head_sha": LATER_SHA,
        "created_at": "2026-10-12T16:32:14Z",
    }
    fields.update(overrides)
    return run(**fields)


def completed(
    stdout: Any = None, *, returncode: int = 0, stderr: str = ""
) -> subprocess.CompletedProcess[str]:
    text = "" if stdout is None else json.dumps(stdout)
    return subprocess.CompletedProcess(["gh"], returncode, text, stderr)


class FakeGh:
    """Serves the GitHub reads and records every call, writes included."""

    def __init__(self) -> None:
        self.calls: list[list[str]] = []
        self.merged: list[dict[str, Any]] = [merged_pr()]
        self.runs: dict[tuple[str, str], list[dict[str, Any]]] = {}
        self.attempts: dict[tuple[int, int], dict[str, Any]] = {}
        # SHAs main reached at or after MERGE_SHA; anything else does not contain it.
        self.descendants = {MERGE_SHA, LATER_SHA}
        self.queue: list[dict[str, Any]] = []
        self.issues: list[dict[str, Any]] = []
        self.comments: dict[int, list[dict[str, Any]]] = {}
        self.fail_reads: set[str] = set()

    def add_runs(self, workflow: str, event: str, *runs: dict[str, Any]) -> None:
        self.runs.setdefault((workflow, event), []).extend(runs)

    def writes(self) -> list[list[str]]:
        return [c for c in self.calls if self._is_write(c)]

    @staticmethod
    def _is_write(args: list[str]) -> bool:
        if "-X" in args and args[args.index("-X") + 1] != "GET":
            return True
        return any("mutation" in a for a in args)

    def __call__(
        self, args: list[str], *, timeout_seconds: float | None = None
    ) -> subprocess.CompletedProcess[str]:
        self.calls.append(list(args))
        joined = " ".join(args)
        for key in self.fail_reads:
            if key in joined:
                return completed(returncode=1, stderr="gh: Server Error (HTTP 502)")
        if args[:2] == ["api", "graphql"]:
            return self._graphql(joined)
        endpoint = next(a for a in args if a.startswith("repos/"))
        if "/actions/workflows/" in endpoint and "/runs?" in endpoint:
            workflow = endpoint.split("/actions/workflows/")[1].split("/")[0]
            event = endpoint.split("event=")[1].split("&")[0]
            return completed(
                [
                    {
                        "total_count": 0,
                        "workflow_runs": self.runs.get((workflow, event), []),
                    }
                ]
            )
        if "/attempts/" in endpoint:
            run_id = int(endpoint.split("/actions/runs/")[1].split("/")[0])
            attempt = int(endpoint.rsplit("/", 1)[1])
            if (run_id, attempt) in self.attempts:
                return completed(self.attempts[(run_id, attempt)])
            for runs in self.runs.values():
                for item in runs:
                    if item["id"] == run_id and item["run_attempt"] == attempt:
                        return completed(item)
            return completed(returncode=1, stderr="gh: Not Found (HTTP 404)")
        if "/compare/" in endpoint:
            base, head = endpoint.split("/compare/")[1].split("...")
            if head == base:
                return completed({"status": "identical"})
            return completed(
                {"status": "ahead" if head in self.descendants else "diverged"}
            )
        if "/actions/runs/" in endpoint and endpoint.endswith("/rerun-failed-jobs"):
            return completed()
        if endpoint.endswith("/dispatches"):
            return completed()
        if "/issues/" in endpoint and endpoint.split("?")[0].endswith("/comments"):
            number = int(endpoint.split("/issues/")[1].split("/")[0])
            if "-X" in args:
                return completed({"id": 1})
            return completed([self.comments.get(number, [])])
        if endpoint.startswith(f"repos/{REPO}/issues?"):
            creator = endpoint.split("creator=")[1].split("&")[0]
            from urllib.parse import unquote

            return completed(
                [[i for i in self.issues if i["user"]["login"] == unquote(creator)]]
            )
        if endpoint == f"repos/{REPO}/issues":
            return completed({"number": 9001})
        if endpoint.startswith(f"repos/{REPO}/contents/"):
            return completed(returncode=1, stderr="gh: Not Found (HTTP 404)")
        raise AssertionError(f"unexpected gh call: {args}")

    def _graphql(self, joined: str) -> subprocess.CompletedProcess[str]:
        if "dequeuePullRequest" in joined:
            return completed(
                {"data": {"dequeuePullRequest": {"clientMutationId": None}}}
            )
        if "PostMergeQueue" in joined:
            entries = {"totalCount": len(self.queue), "nodes": self.queue}
            return completed(
                {"data": {"repository": {"mergeQueue": {"entries": entries}}}}
            )
        if "PostMergeMerged" in joined:
            page = {
                "pageInfo": {"hasNextPage": False, "endCursor": None},
                "nodes": self.merged,
            }
            return completed({"data": {"repository": {"pullRequests": page}}})
        raise AssertionError(f"unexpected graphql call: {joined}")


class CheckCase(unittest.TestCase):
    def setUp(self) -> None:
        self.gh = FakeGh()
        patcher = mock.patch.object(pm, "gh_capture", self.gh)
        patcher.start()
        self.addCleanup(patcher.stop)

    def check(
        self, *, now: datetime | None = None, pinned: str | None = HEAD_SHA
    ) -> pm.PostMergeVerdict:
        return pm.check(
            REPO,
            agent_identity=IDENTITY,
            is_human=human,
            merged_since=SINCE,
            now=now or datetime(2026, 10, 12, 11, 0, tzinfo=UTC),
            pinned_sha=lambda merge: pinned,
        )

    def all_green(self) -> None:
        self.gh.add_runs("pr-require-checks.yml", "workflow_dispatch", dispatch_run(11))
        self.gh.add_runs("post-merge-detect-silent-revert.yml", "push", canary_run(21))

    def numbers(self, verdict: pm.PostMergeVerdict) -> list[int]:
        return [m.merge.number for m in verdict.merges]


class AutoMergeDerivation(CheckCase):
    def test_app_actor_with_null_enqueuer_is_an_auto_merge(self) -> None:
        self.gh.merged = [merged_pr(timelineItems=enqueued_by(APP_ACTOR, None))]
        self.assertEqual(self.numbers(self.check()), [7001])

    def test_identity_typed_as_user_is_an_auto_merge(self) -> None:
        identity_user = {"__typename": "User", "login": IDENTITY}
        self.gh.merged = [
            merged_pr(timelineItems=enqueued_by(identity_user, identity_user))
        ]
        self.assertEqual(self.numbers(self.check()), [7001])

    def test_human_actor_with_non_human_enqueuer_is_an_auto_merge(self) -> None:
        self.gh.merged = [
            merged_pr(
                timelineItems=enqueued_by(
                    HUMAN, {"__typename": "User", "login": "x[bot]"}
                )
            )
        ]
        self.assertEqual(self.numbers(self.check()), [7001])

    def test_human_enqueue_is_not_an_auto_merge(self) -> None:
        self.gh.merged = [merged_pr(timelineItems=enqueued_by(HUMAN, HUMAN))]
        verdict = self.check()
        self.assertEqual(self.numbers(verdict), [])
        self.assertTrue(verdict.ok)

    def test_dependabot_merge_enqueued_by_github_actions_needs_verification(
        self,
    ) -> None:
        actions = {"__typename": "Bot", "login": "github-actions"}
        self.gh.merged = [merged_pr(timelineItems=enqueued_by(actions, None))]
        verdict = self.check()
        self.assertEqual(self.numbers(verdict), [7001])
        self.assertFalse(verdict.is_verified(verdict.merges[0].merge))

    def test_merge_without_a_queue_event_is_an_unqueued_merge_warning(self) -> None:
        self.gh.merged = [merged_pr(timelineItems={"nodes": []})]
        verdict = self.check()
        self.assertEqual(verdict.warnings, ("unqueued-merge:#7001",))
        self.assertEqual(self.numbers(verdict), [])
        self.assertTrue(verdict.ok)

    def test_merge_before_the_floor_is_not_read(self) -> None:
        self.gh.merged = [
            merged_pr(mergedAt="2026-10-11T23:00:00Z", updatedAt="2026-10-11T23:00:00Z")
        ]
        self.assertEqual(self.numbers(self.check()), [])

    def test_unreadable_history_is_not_ok(self) -> None:
        self.gh.fail_reads.add("PostMergeMerged")
        verdict = self.check()
        self.assertFalse(verdict.readable)
        self.assertFalse(verdict.ok)

    def test_naive_floor_is_unreadable(self) -> None:
        verdict = pm.check(
            REPO,
            agent_identity=IDENTITY,
            is_human=human,
            merged_since=datetime(2026, 10, 12),
        )
        self.assertFalse(verdict.ok)
        self.assertEqual(verdict.reason, "merged-since-not-timezone-aware")


class Verification(CheckCase):
    def test_green_dispatch_canary_and_read_back_verify(self) -> None:
        self.all_green()
        verdict = self.check()
        self.assertTrue(verdict.ok)
        self.assertTrue(verdict.is_verified(verdict.merges[0].merge))

    def test_in_flight_merge_object_is_judged_by_number(self) -> None:
        self.all_green()
        verdict = self.check()
        merge_like = mock.Mock(
            number=7001, merge_commit=MERGE_SHA, head_ref_oid=HEAD_SHA, merged_at="x"
        )
        self.assertTrue(verdict.is_verified(merge_like))
        self.assertFalse(verdict.is_verified(mock.Mock(number=7002)))

    def test_unrecorded_pin_leaves_the_merge_unverified_without_failing(self) -> None:
        self.gh.merged = [identity_merge()]
        self.all_green()
        verdict = self.check(pinned=None)
        self.assertFalse(verdict.merges[0].verified)
        self.assertEqual(verdict.failures, ())

    def test_non_identity_enqueue_verifies_on_dispatch_and_canary_alone(self) -> None:
        # The fixture's enqueue is a sync App's: the identity pinned nothing.
        self.all_green()
        verdict = self.check(pinned=None)
        self.assertTrue(verdict.merges[0].verified)
        self.assertTrue(verdict.ok)

    def test_non_identity_enqueue_with_no_dispatch_run_stays_unverified(self) -> None:
        self.gh.add_runs("post-merge-detect-silent-revert.yml", "push", canary_run(21))
        self.assertFalse(self.check(pinned=None).merges[0].verified)

    def test_read_back_mismatch_is_a_failure(self) -> None:
        self.gh.merged = [identity_merge()]
        self.all_green()
        verdict = self.check(pinned=OTHER_SHA)
        self.assertEqual([f.signal for f in verdict.failures], ["read-back"])
        self.assertFalse(verdict.ok)

    def test_dispatch_run_by_another_actor_does_not_verify(self) -> None:
        self.gh.add_runs(
            "pr-require-checks.yml",
            "workflow_dispatch",
            dispatch_run(11, actor=by("maintainer"), triggering_actor=by("maintainer")),
        )
        self.gh.add_runs("post-merge-detect-silent-revert.yml", "push", canary_run(21))
        self.assertFalse(self.check().merges[0].verified)

    def test_dispatch_run_on_a_sha_without_the_merge_does_not_verify(self) -> None:
        self.gh.add_runs(
            "pr-require-checks.yml",
            "workflow_dispatch",
            dispatch_run(11, head_sha=OTHER_SHA),
        )
        self.gh.add_runs("post-merge-detect-silent-revert.yml", "push", canary_run(21))
        self.assertFalse(self.check().merges[0].verified)

    def test_no_dispatch_run_within_six_hours_is_a_failure(self) -> None:
        self.gh.add_runs("post-merge-detect-silent-revert.yml", "push", canary_run(21))
        before = self.check(now=datetime(2026, 10, 12, 15, 59, tzinfo=UTC))
        self.assertEqual(before.failures, ())
        after = self.check(now=datetime(2026, 10, 12, 16, 1, tzinfo=UTC))
        self.assertEqual([f.signal for f in after.failures], ["dispatch"])

    def test_red_canary_is_a_failure(self) -> None:
        self.gh.add_runs("pr-require-checks.yml", "workflow_dispatch", dispatch_run(11))
        self.gh.add_runs(
            "post-merge-detect-silent-revert.yml",
            "push",
            canary_run(21, conclusion="failure"),
        )
        self.assertEqual([f.signal for f in self.check().failures], ["canary"])

    def test_red_run_after_verification_does_not_count_against_the_merge(self) -> None:
        self.all_green()
        self.gh.add_runs("pr-require-checks.yml", "schedule", schedule_run(31))
        verdict = self.check(now=datetime(2026, 10, 12, 17, 0, tzinfo=UTC))
        self.assertTrue(verdict.merges[0].verified)
        self.assertEqual(verdict.reruns, ())


class Attribution(CheckCase):
    def setUp(self) -> None:
        super().setUp()
        self.gh.add_runs("post-merge-detect-silent-revert.yml", "push", canary_run(21))

    def test_red_schedule_run_needs_one_rerun_before_it_demotes(self) -> None:
        self.gh.add_runs(
            "pr-require-checks.yml",
            "schedule",
            schedule_run(31, created_at="2026-10-12T10:30:00Z"),
        )
        verdict = self.check()
        self.assertEqual(verdict.failures, ())
        self.assertEqual([r.run_id for r in verdict.reruns], [31])
        self.assertFalse(verdict.merges[0].verified)

    def test_red_again_after_the_rerun_demotes(self) -> None:
        self.gh.add_runs(
            "pr-require-checks.yml",
            "schedule",
            schedule_run(
                31,
                run_attempt=2,
                triggering_actor=by(IDENTITY),
                created_at="2026-10-12T10:30:00Z",
            ),
        )
        self.gh.attempts[(31, 1)] = schedule_run(31, created_at="2026-10-12T10:30:00Z")
        verdict = self.check()
        self.assertEqual(
            [(f.signal, f.merge.number) for f in verdict.failures], [("schedule", 7001)]
        )

    def test_green_on_the_rerun_records_a_flake_and_no_failure(self) -> None:
        self.gh.add_runs(
            "pr-require-checks.yml",
            "workflow_dispatch",
            dispatch_run(11, run_attempt=2, conclusion="success"),
        )
        self.gh.attempts[(11, 1)] = dispatch_run(11, conclusion="failure")
        verdict = self.check()
        self.assertEqual(verdict.failures, ())
        self.assertEqual(
            verdict.flakes, (f"https://github.com/{REPO}/actions/runs/11",)
        )
        self.assertTrue(verdict.merges[0].verified)

    def test_a_rerun_the_wrapper_did_not_trigger_does_not_clear_a_red_run(self) -> None:
        self.gh.add_runs(
            "pr-require-checks.yml",
            "workflow_dispatch",
            dispatch_run(
                11,
                run_attempt=2,
                conclusion="success",
                triggering_actor=by("maintainer"),
            ),
        )
        self.gh.attempts[(11, 1)] = dispatch_run(11, conclusion="failure")
        self.assertEqual([f.signal for f in self.check().failures], ["dispatch"])


class DispatchCoverage(CheckCase):
    """Design "Post-merge" plus the accepted deadlock rule: an unverified
    auto-merge with no identity dispatch run on a SHA containing it needs one;
    one run on main's tip covers every earlier merge."""

    def setUp(self) -> None:
        super().setUp()
        self.gh.add_runs("post-merge-detect-silent-revert.yml", "push", canary_run(21))

    def test_unverified_merge_without_a_dispatch_run_needs_one(self) -> None:
        self.assertTrue(self.check().needs_dispatch)

    def test_dispatch_run_in_progress_covers_the_merge(self) -> None:
        self.gh.add_runs(
            "pr-require-checks.yml",
            "workflow_dispatch",
            dispatch_run(11, status="in_progress", conclusion=None),
        )
        verdict = self.check()
        self.assertFalse(verdict.needs_dispatch)
        self.assertFalse(verdict.merges[0].verified)

    def test_red_dispatch_run_covers_the_merge_and_leaves_it_unverified(self) -> None:
        self.gh.add_runs(
            "pr-require-checks.yml",
            "workflow_dispatch",
            dispatch_run(11, conclusion="failure"),
        )
        verdict = self.check()
        self.assertFalse(verdict.needs_dispatch)
        self.assertFalse(verdict.merges[0].verified)

    def test_dispatch_run_by_another_actor_does_not_cover(self) -> None:
        self.gh.add_runs(
            "pr-require-checks.yml",
            "workflow_dispatch",
            dispatch_run(11, actor=by("maintainer"), triggering_actor=by("maintainer")),
        )
        self.assertTrue(self.check().needs_dispatch)

    def test_dispatch_run_on_a_sha_without_the_merge_does_not_cover(self) -> None:
        self.gh.add_runs(
            "pr-require-checks.yml",
            "workflow_dispatch",
            dispatch_run(11, head_sha=OTHER_SHA),
        )
        self.assertTrue(self.check().needs_dispatch)

    def test_one_run_on_the_tip_covers_every_earlier_merge(self) -> None:
        self.gh.merged = [
            merged_pr(),
            merged_pr(
                number=7002,
                url=f"https://github.com/{REPO}/pull/7002",
                mergedAt="2026-10-12T10:02:00Z",
                updatedAt="2026-10-12T10:02:05Z",
                mergeCommit={"oid": LATER_SHA},
            ),
        ]
        self.gh.add_runs(
            "pr-require-checks.yml",
            "workflow_dispatch",
            dispatch_run(11, created_at="2026-10-12T10:05:00Z"),
        )
        verdict = self.check()
        self.assertEqual(self.numbers(verdict), [7001, 7002])
        self.assertFalse(verdict.needs_dispatch)

    def test_verified_merges_need_no_dispatch(self) -> None:
        self.gh.add_runs("pr-require-checks.yml", "workflow_dispatch", dispatch_run(11))
        self.assertFalse(self.check().needs_dispatch)

    def test_unreadable_verdict_never_needs_dispatch(self) -> None:
        self.gh.fail_reads.add("post-merge-detect-silent-revert.yml")
        verdict = self.check()
        self.assertFalse(verdict.readable)
        self.assertFalse(verdict.needs_dispatch)


class Remediation(CheckCase):
    def failing_verdict(self) -> pm.PostMergeVerdict:
        self.gh.merged = [identity_merge()]
        self.all_green()
        return self.check(pinned=OTHER_SHA)

    def test_remediate_dequeues_before_issue(self) -> None:
        verdict = self.failing_verdict()
        self.gh.queue = [
            {
                "enqueuer": {"__typename": "Bot", "login": "agent-lanes"},
                "pullRequest": {"id": "PR_a", "number": 7010},
            },
        ]
        events: list[int] = []
        report = pm.remediate(
            REPO, verdict, agent_identity=IDENTITY, record_telemetry=events.append
        )
        writes = self.gh.writes()
        self.assertIn("dequeuePullRequest", " ".join(writes[0]))
        self.assertIn(f"repos/{REPO}/issues", writes[1])
        self.assertEqual(len(writes), 2)
        self.assertEqual(events, [1])
        self.assertEqual(report["dequeued"], [7010])
        self.assertEqual(report["telemetry"], {"demotion_events": 1})

    def test_remediate_never_dequeues_another_actors_entry(self) -> None:
        verdict = self.failing_verdict()
        self.gh.queue = [
            {"enqueuer": HUMAN, "pullRequest": {"id": "PR_b", "number": 7011}}
        ]
        pm.remediate(REPO, verdict, agent_identity=IDENTITY)
        self.assertNotIn(
            "dequeuePullRequest", " ".join(" ".join(w) for w in self.gh.writes())
        )

    def test_issue_body_carries_marker_links_and_git_revert(self) -> None:
        verdict = self.failing_verdict()
        pm.remediate(REPO, verdict, agent_identity=IDENTITY)
        create = next(w for w in self.gh.writes() if f"repos/{REPO}/issues" in w)
        body = next(a for a in create if a.startswith("body="))[len("body=") :]
        self.assertEqual(
            body.splitlines()[0],
            f"<!-- babysit-merge-demotion sha={MERGE_SHA} signal=read-back -->",
        )
        self.assertIn(f"git revert {MERGE_SHA}", body)
        self.assertIn("https://github.com/example-org/example-repo/pull/7001", body)
        self.assertIn("labels[]=needs-human", create)

    def test_failing_run_link_is_in_the_body(self) -> None:
        self.gh.add_runs("pr-require-checks.yml", "workflow_dispatch", dispatch_run(11))
        self.gh.add_runs(
            "post-merge-detect-silent-revert.yml",
            "push",
            canary_run(21, conclusion="failure"),
        )
        pm.remediate(REPO, self.check(), agent_identity=IDENTITY)
        create = next(w for w in self.gh.writes() if f"repos/{REPO}/issues" in w)
        self.assertTrue(
            any(f"https://github.com/{REPO}/actions/runs/21" in a for a in create)
        )

    def test_existing_marker_issue_is_commented_not_duplicated(self) -> None:
        verdict = self.failing_verdict()
        marker = f"<!-- babysit-merge-demotion sha={MERGE_SHA} signal=read-back -->"
        self.gh.issues = [
            {"number": 8001, "body": f"{marker}\nold", "user": {"login": IDENTITY}}
        ]
        report = pm.remediate(REPO, verdict, agent_identity=IDENTITY)
        writes = self.gh.writes()
        self.assertEqual([w for w in writes if f"repos/{REPO}/issues" in w], [])
        self.assertTrue(any(f"repos/{REPO}/issues/8001/comments" in w for w in writes))
        self.assertEqual(report["telemetry"], {"demotion_events": 0})

    def test_marker_issue_filed_by_github_actions_is_found(self) -> None:
        verdict = self.failing_verdict()
        marker = f"<!-- babysit-merge-demotion sha={MERGE_SHA} signal=read-back -->"
        self.gh.issues = [
            {"number": 8002, "body": marker, "user": {"login": "github-actions[bot]"}}
        ]
        pm.remediate(REPO, verdict, agent_identity=IDENTITY)
        self.assertTrue(
            any(f"repos/{REPO}/issues/8002/comments" in w for w in self.gh.writes())
        )

    def test_a_sighting_already_commented_is_not_repeated(self) -> None:
        verdict = self.failing_verdict()
        marker = f"<!-- babysit-merge-demotion sha={MERGE_SHA} signal=read-back -->"
        self.gh.issues = [{"number": 8001, "body": marker, "user": {"login": IDENTITY}}]
        detail = verdict.failures[0].detail
        self.gh.comments[8001] = [{"body": f"seen: {detail}"}]
        pm.remediate(REPO, verdict, agent_identity=IDENTITY)
        self.assertEqual(self.gh.writes(), [])

    def test_no_failure_means_no_write(self) -> None:
        self.all_green()
        pm.remediate(REPO, self.check(), agent_identity=IDENTITY)
        self.assertEqual(self.gh.writes(), [])

    def test_attribute_triggers_one_rerun_failed_jobs(self) -> None:
        self.gh.add_runs("post-merge-detect-silent-revert.yml", "push", canary_run(21))
        self.gh.add_runs(
            "pr-require-checks.yml",
            "schedule",
            schedule_run(31, created_at="2026-10-12T10:30:00Z"),
        )
        pm.attribute(REPO, self.check())
        self.assertEqual(
            self.gh.writes(),
            [["api", "-X", "POST", f"repos/{REPO}/actions/runs/31/rerun-failed-jobs"]],
        )

    def test_dispatch_full_run_posts_the_workflow_dispatch(self) -> None:
        pm.dispatch_full_run(REPO)
        self.assertEqual(
            self.gh.writes(),
            [
                [
                    "api",
                    "-X",
                    "POST",
                    f"repos/{REPO}/actions/workflows/pr-require-checks.yml/dispatches",
                    "-f",
                    "ref=main",
                ]
            ],
        )


class Cli(CheckCase):
    def main(self, *argv: str) -> tuple[int, dict[str, Any]]:
        out = io.StringIO()
        with (
            contextlib.redirect_stdout(out),
            mock.patch.object(pm, "_default_is_human", return_value=(human, None)),
        ):
            code = pm.main(
                [
                    "--repo",
                    REPO,
                    "--agent-identity",
                    IDENTITY,
                    "--since",
                    SINCE.isoformat(),
                    *argv,
                ]
            )
        return code, json.loads(out.getvalue())

    def test_read_only_by_default_even_with_failures(self) -> None:
        self.gh.add_runs("pr-require-checks.yml", "workflow_dispatch", dispatch_run(11))
        self.gh.add_runs(
            "post-merge-detect-silent-revert.yml",
            "push",
            canary_run(21, conclusion="failure"),
        )
        self.gh.add_runs(
            "pr-require-checks.yml",
            "schedule",
            schedule_run(31, created_at="2026-10-12T10:30:00Z"),
        )
        code, report = self.main()
        self.assertEqual(code, 1)
        self.assertEqual(self.gh.writes(), [])
        self.assertEqual([f["signal"] for f in report["failures"]], ["canary"])
        self.assertNotIn("remediation", report)

    def test_remediate_flag_writes(self) -> None:
        self.gh.add_runs("pr-require-checks.yml", "workflow_dispatch", dispatch_run(11))
        self.gh.add_runs(
            "post-merge-detect-silent-revert.yml",
            "push",
            canary_run(21, conclusion="failure"),
        )
        code, report = self.main("--remediate")
        self.assertEqual(code, 1)
        self.assertTrue(self.gh.writes())
        self.assertEqual(report["remediation"]["telemetry"], {"demotion_events": 1})

    def dispatches(self) -> list[list[str]]:
        return [w for w in self.gh.writes() if w[3].endswith("/dispatches")]

    def test_remediate_dispatches_one_full_run_when_no_run_covers_a_merge(
        self,
    ) -> None:
        self.gh.add_runs("post-merge-detect-silent-revert.yml", "push", canary_run(21))
        code, report = self.main("--remediate")
        self.assertEqual(
            self.dispatches(),
            [
                [
                    "api",
                    "-X",
                    "POST",
                    f"repos/{REPO}/actions/workflows/pr-require-checks.yml/dispatches",
                    "-f",
                    "ref=main",
                ]
            ],
        )
        self.assertTrue(report["dispatched"])
        # The dispatch verifies nothing by itself: the merge stays unverified.
        self.assertFalse(report["autoMerges"][0]["verified"])
        self.assertNotEqual(code, 4)
        self.assertEqual(report["remediation"]["errors"], [])

    def test_check_without_remediate_never_dispatches(self) -> None:
        self.gh.add_runs("post-merge-detect-silent-revert.yml", "push", canary_run(21))
        code, report = self.main()
        self.assertEqual(self.gh.writes(), [])
        self.assertTrue(report["needsDispatch"])
        self.assertNotIn("dispatched", report)

    def test_remediate_does_not_dispatch_when_a_run_covers_the_merge(self) -> None:
        self.gh.add_runs("post-merge-detect-silent-revert.yml", "push", canary_run(21))
        self.gh.add_runs(
            "pr-require-checks.yml",
            "workflow_dispatch",
            dispatch_run(11, status="in_progress", conclusion=None),
        )
        _, report = self.main("--remediate")
        self.assertEqual(self.dispatches(), [])
        self.assertFalse(report["dispatched"])

    def test_failed_dispatch_exits_4_and_leaves_the_merge_unverified(self) -> None:
        self.gh.add_runs("post-merge-detect-silent-revert.yml", "push", canary_run(21))
        self.gh.fail_reads.add("/dispatches")
        code, report = self.main("--remediate")
        self.assertEqual(code, 4)
        self.assertFalse(report["dispatched"])
        self.assertFalse(report["autoMerges"][0]["verified"])
        self.assertTrue(any("dispatch" in e for e in report["remediation"]["errors"]))

    def test_unreadable_exits_3(self) -> None:
        self.gh.fail_reads.add("PostMergeMerged")
        code, report = self.main("--remediate")
        self.assertEqual(code, 3)
        self.assertEqual(self.gh.writes(), [])
        self.assertFalse(report["readable"])

    def test_clean_exits_0(self) -> None:
        self.gh.merged = [merged_pr(timelineItems=enqueued_by(HUMAN, HUMAN))]
        code, report = self.main()
        self.assertEqual(code, 0)
        self.assertTrue(report["ok"])


if __name__ == "__main__":
    unittest.main()
