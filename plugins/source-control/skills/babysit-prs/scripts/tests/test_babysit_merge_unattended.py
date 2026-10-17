"""The unattended merge path of `babysit_merge`, connected end to end.

`evaluate(..., unattended=None)` must leave every existing verdict unchanged,
and a refusing policy must add exactly its blocker and an `unattended` report.
`main()` runs the real composition (`assess_unattended`, `merge_policy.assess`,
the scorer, the writes and the enqueue) over fakes of each reader, so every
refusal the plan's Phase 13 names is driven by one input: it must never reach
the merge call. Expected values come from the plan's Design (Contracts, T8,
T10, T14, T15, T20, D3, D4, D15, D22). A token acting as the configured agent
identity must never use the plain `--merge` path.

Network is stubbed at the gh seams and the readers; no real gh process runs.
"""

from __future__ import annotations

import contextlib
import dataclasses
import io
import json
import pathlib
import subprocess
import sys
import tempfile
import unittest
from datetime import UTC, datetime
from typing import Any
from unittest import mock

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import babysit_dependabot as dependabot
import babysit_gh as gh
import babysit_merge as merge
import babysit_merge_policy as policy
import babysit_postmerge as postmerge
import test_babysit_merge as fixtures
import test_babysit_merge_async as async_fixtures
from babysit_risk import ChangedFile, LaneEvidence
from repo_config_fake import RepoConfigFake

HEAD = fixtures.HEAD
BASE = "c" * 40
PR = fixtures.PR_NUMBER
IDENTITY = "agent-lanes[bot]"
INERT = policy.UnattendedPolicy(reason="authority-unconfigured")
INERT_BLOCKER = "unattended merge refused: authority-unconfigured"

# The report keys `evaluate()` returned before the unattended path existed,
# copied from its return statement. A run without a policy must return exactly
# these, so no consumer of the report sees a new or missing key.
PRE_UNATTENDED_KEYS = frozenset(
    {
        "pr",
        "autopilotMergeTier",
        "reviewSettle",
        "stack",
        "landingBase",
        "mergeAction",
        "url",
        "title",
        "author",
        "owner",
        "inScope",
        "baseRef",
        "baseUnprotected",
        "state",
        "isDraft",
        "mergeable",
        "mergeStateStatus",
        "reviewDecision",
        "headRefOid",
        "labels",
        "expectedHead",
        "headMatches",
        "effectiveRules",
        "baseFreshness",
        "requiredSignatures",
        "requiredChecks",
        "graphqlAvailable",
        "unresolvedThreadCount",
        "unresolvedThreads",
        "threadResolutionProven",
        "failingChecks",
        "pendingChecks",
        "ready",
        "blockers",
        "autoMerge",
        "aiReviewHolds",
        "aiReviewChecks",
    }
)

# Fixtures from the existing gate suite: (name, PR view, expected head, tier).
FIXTURES: list[tuple[str, dict[str, Any], str, Any]] = [
    ("ready", fixtures._pr(), HEAD, None),
    ("ready under the tier", fixtures._pr(), HEAD, fixtures.TIER),
    ("draft", fixtures._pr(isDraft=True), HEAD, None),
    ("conflicting", fixtures._pr(mergeable="CONFLICTING"), HEAD, None),
    ("blocked", fixtures._pr(mergeStateStatus="BLOCKED"), HEAD, None),
    ("changes requested", fixtures._pr(reviewDecision="CHANGES_REQUESTED"), HEAD, None),
    ("body hold", fixtures._pr(body="Do not merge yet"), HEAD, None),
    ("hold label", fixtures._pr(labels=[{"name": "do-not-merge"}]), HEAD, None),
    (
        "dependency author",
        fixtures._pr(author={"login": "dependabot[bot]"}),
        HEAD,
        None,
    ),
    ("head moved", fixtures._pr(), fixtures.STALE, None),
    ("closed", fixtures._pr(state="CLOSED"), HEAD, None),
    (
        "tier without a linked issue",
        fixtures._pr(closingIssuesReferences=[]),
        HEAD,
        fixtures.TIER,
    ),
]

# The fixtures the base gate must call ready; every other fixture carries a hold.
READY_FIXTURES = frozenset({"ready", "ready under the tier"})
# A base compare showing the head three commits behind a base that does not
# require up-to-date branches: a hold the gate adds after every other one.
BEHIND = {"status": "behind", "ahead_by": 0, "behind_by": 3}
BEHIND_BLOCKER = (
    "head is 3 commit(s) behind base 'main', which does not require up-to-date "
    "branches -- refresh the branch before merging"
)


def _evaluate(
    pr: dict[str, Any],
    expected: str,
    tier: Any,
    unattended: Any = None,
    *,
    compare: dict[str, Any] = fixtures.UP_TO_DATE,
) -> dict[str, Any]:
    """Run `evaluate` over one fixture with every gh seam stubbed."""

    def gh_json(args: list[str]) -> Any:
        if args[0] == "api" and "/compare/" in args[1]:
            return compare
        if args[:2] == ["pr", "view"]:
            return pr
        if args[0] == "api":
            return fixtures.RULES
        raise AssertionError(f"unexpected gh_json call: {args}")

    kwargs = {"unattended": unattended}
    with (
        mock.patch.object(merge, "gh_json", side_effect=gh_json),
        mock.patch.object(merge, "fetch_review_threads", return_value=[]),
        mock.patch.object(
            merge, "fetch_pull_request_reviews", return_value=fixtures.CLEAN_APPROVAL
        ),
        mock.patch.object(merge, "fetch_issue_comments", return_value=[]),
        mock.patch.object(merge, "fetch_pull_request_review_comments", return_value=[]),
    ):
        return merge.evaluate(
            "owner/repo",
            fixtures.PR_NUMBER,
            expected,
            {"owner"},
            frozenset(),
            False,
            False,
            tier,
            **kwargs,
        )


class EvaluateWithoutPolicyIsUnchanged(unittest.TestCase):
    """`unattended=None` keeps each fixture's verdict and the report's key set.

    Comparing a run that omits the keyword with one passing None would compare
    the same call twice and could not fail. So each fixture is checked against
    its literal verdict and the pre-unattended key set, and the existing gate
    suites, which run unchanged, pin the blockers themselves.
    """

    def test_every_fixture_keeps_its_verdict_and_keys(self) -> None:
        for name, pr, expected, tier in FIXTURES:
            with self.subTest(name):
                result = _evaluate(pr, expected, tier, unattended=None)
                self.assertIs(
                    result["ready"], name in READY_FIXTURES, result["blockers"]
                )
                self.assertEqual(result["blockers"] == [], name in READY_FIXTURES)
                self.assertEqual(frozenset(result), PRE_UNATTENDED_KEYS)


class EvaluateWithARefusingPolicyHolds(unittest.TestCase):
    def test_every_fixture_gains_the_refusal_and_report(self) -> None:
        for name, pr, expected, tier in FIXTURES:
            with self.subTest(name):
                result = _evaluate(pr, expected, tier, unattended=INERT)
                self.assertFalse(result["ready"])
                self.assertIn(INERT_BLOCKER, result["blockers"])
                self.assertFalse(result["autoMerge"]["ready"])
                self.assertIn(INERT_BLOCKER, result["autoMerge"]["blockers"])
                self.assertIs(result["unattended"]["enabled"], False)
                self.assertEqual(
                    result["unattended"]["reason"], "authority-unconfigured"
                )

    def test_a_permitting_policy_adds_no_blocker(self) -> None:
        permits = policy.UnattendedPolicy(None, IDENTITY, enabled=True, promoted=True)
        result = _evaluate(fixtures._pr(), HEAD, None, unattended=permits)
        self.assertEqual(result["blockers"], [])
        self.assertIs(result["unattended"]["enabled"], True)

    def test_other_blockers_are_still_reported(self) -> None:
        # The freshness hold is evaluated only once no other hold stands, so a
        # refusal added before it would hide a behind head.
        plain = _evaluate(fixtures._pr(), HEAD, None, compare=BEHIND)
        result = _evaluate(fixtures._pr(), HEAD, None, INERT, compare=BEHIND)
        self.assertEqual(plain["blockers"], [BEHIND_BLOCKER])
        self.assertEqual(result["blockers"], [BEHIND_BLOCKER, INERT_BLOCKER])


class ResolveWithoutMergeBlockIsInert(unittest.TestCase):
    def test_no_merge_block_resolves_authority_unconfigured(self) -> None:
        # The default branch head, then the two config files at it: neither
        # exists in a readable tree, so there is no merge block.
        sha = "a" * 40
        answers = {
            "repos/owner/repo": {"default_branch": "main"},
            "repos/owner/repo/commits/main": {"sha": sha},
            f"repos/owner/repo/contents?ref={sha}": [],
        }
        calls: list[list[str]] = []

        def fake_gh(args: list[str], **_: Any) -> subprocess.CompletedProcess[str]:
            calls.append(args)
            if args[1] in answers:
                return subprocess.CompletedProcess(
                    [], 0, json.dumps(answers[args[1]]), ""
                )
            if args[1].startswith("repos/owner/repo/contents/"):
                return subprocess.CompletedProcess(
                    [], 1, "", "gh: Not Found (HTTP 404)"
                )
            raise AssertionError(f"unexpected gh call: {args}")

        # The process seams every real gh read reaches, whichever module makes it.
        with (
            mock.patch.object(policy, "gh_capture", side_effect=fake_gh),
            mock.patch.object(gh, "_run_gh", side_effect=AssertionError("gh call")),
            mock.patch.object(
                subprocess, "run", side_effect=AssertionError("subprocess")
            ),
        ):
            resolved = policy.resolve("owner/repo")
        config_read = [
            "api",
            f"repos/owner/repo/contents/{policy.CONFIG_PATH}?ref={sha}",
        ]
        self.assertIn(config_read, calls)
        self.assertIs(resolved.enabled, False)
        self.assertEqual(resolved.reason, "authority-unconfigured")
        self.assertIsNone(resolved.agent_identity)
        self.assertEqual(
            resolved.report(),
            {"enabled": False, "promoted": None, "reason": "authority-unconfigured"},
        )

    def test_a_policy_without_a_refusal_is_enabled(self) -> None:
        self.assertIs(policy.UnattendedPolicy(reason=None).enabled, True)


# --- main() end to end --------------------------------------------------------------------------

QUEUE_RULES = [*fixtures.RULES, {"type": "merge_queue", "parameters": {}}]
LOW_FILE = ChangedFile(
    "docs/guide.md", None, "modified", 3, 1, True, "100644", "100644"
)
BOUND = tuple(
    LaneEvidence(lane, True, None, 0)
    for lane in ("claude-review", "claude-security-review")
)
UNBOUND = tuple(
    LaneEvidence(lane, False, "no-marker", None)
    for lane in ("claude-review", "claude-security-review")
)
PROMOTED = policy.Promotion(dict.fromkeys(policy.PROMOTABLE_CELLS, "promoted"), None)
PROCEED = policy.KillSwitch(True, "proceed")
REAL_ASYNC_MERGE = merge.async_merge
ENQUEUED = {
    "attempted": True,
    "api": "merge-async",
    "mergeAction": "merge_queue",
    "status": "enqueued",
    "success": True,
    "uuid": "u1",
    "endpointMissing": False,
    "message": "",
}


def entry(
    number: int, at: str, node: str, login: str = "agent-lanes"
) -> dict[str, Any]:
    return {
        "enqueuedAt": at,
        "position": 1,
        "enqueuer": {"__typename": "Bot", "login": login},
        "pullRequest": {"id": node, "number": number},
    }


class Unattended(unittest.TestCase):
    """`main()` over the real composition, every reader a fake set per test."""

    def setUp(self) -> None:
        self.repo_config = RepoConfigFake().install(self)
        self.config = policy.PipelineConfig(
            BASE, "C2", "local-babysit", IDENTITY, 200, (), "c2-mechanical"
        )
        self.acting = IDENTITY
        self.credentials: str | None = None
        self.kill = [PROCEED, PROCEED]
        self.verdict = postmerge.PostMergeVerdict(True, branch="main")
        self.demotion = policy.Demotion(False, None, ())
        self.cap = policy.RungCap(None, "no-cap")
        self.flight = policy.InFlight(True, None)
        self.promotion = PROMOTED
        self.eligible = policy.Eligibility(True, None, "C2", 40)
        self.lanes = BOUND
        self.comments: list[dict[str, Any]] = []
        self.files = ((LOW_FILE,), True)
        self.pr_view = fixtures._pr()
        self.queue = fixtures._queue_read(required=True)
        self.entries = [entry(PR, "2026-10-12T10:00:00Z", "PR_self")]
        self.queued: list[int] = []
        self.holds: dict[int, str] = {}
        self.prior: dict[str, Any] | None = None
        self.log: list[str] = []
        self.rules = QUEUE_RULES
        # -1: the queue re-read is whole; any other count truncates it.
        self.entries_total: int | None = -1
        self.node_id = "PR_self"
        self.rerun = mock.Mock(return_value=[])
        self.dispatch_error: Exception | None = None
        self.scored_head = HEAD
        self.default_branch: str | None = "main"
        # The opt-in re-read beside the second kill-switch read.
        self.opt_in_recheck: str | None = None
        # Raised by the lane evidence read in place of its answer.
        self.lane_error: Exception | None = None
        # The pr-merge lane's eligibility and its re-read before the enqueue.
        self.lane_eligible = policy.Eligibility(True, None, "C2")
        self.lane_recheck: str | None = None
        self.lane_recheck_kwargs: list[dict[str, Any]] = []
        # The pull request's REST author, and the Dependabot class's reads:
        # the assessment's, then the re-read before the enqueue.
        self.pr_user = {"login": IDENTITY, "type": "Bot"}
        self.pr_labels: list[dict[str, Any]] = []
        self.dependabot_reads: list[policy.Eligibility] = []

    def _dependabot_eligibility(self, *args: Any, **kwargs: Any) -> Any:
        if not self.dependabot_reads:
            raise AssertionError("the Dependabot class was read for this pull request")
        return (
            self.dependabot_reads.pop(0)
            if len(self.dependabot_reads) > 1
            else self.dependabot_reads[0]
        )

    def _lane_evidence(self, *args: Any) -> Any:
        if self.lane_error is not None:
            raise self.lane_error
        return self.lanes, self.comments

    def _default_branch(self, repo: str) -> str:
        if self.default_branch is None:
            raise policy.PolicyReadError("the default branch could not be read")
        return self.default_branch

    def _dispatch(self, repo: str, ref: str) -> None:
        self.log.append("dispatch")
        if self.dispatch_error is not None:
            raise self.dispatch_error

    def run_main(
        self, *flags: str, merge_flag: bool = True
    ) -> tuple[int, dict[str, Any]]:
        pr_record = {
            "number": PR,
            "node_id": self.node_id,
            "base": {"ref": "main", "sha": BASE},
            "head": {"ref": "feat", "sha": self.scored_head},
            "user": self.pr_user,
            "labels": self.pr_labels,
        }
        kills = list(self.kill)
        self.capture = mock.Mock(side_effect=self._capture)
        self.async_merge = mock.Mock(side_effect=self._async_merge)
        self.dequeue = mock.Mock(side_effect=self._dequeue)
        self.dispatch = mock.Mock(side_effect=self._dispatch)
        self.post_check = mock.Mock(return_value=self.verdict)
        self.in_flight = mock.Mock(return_value=self.flight)
        self.read_cap = mock.Mock(return_value=self.cap)

        def gh_json(args: list[str]) -> Any:
            if args[:2] == ["pr", "view"]:
                return self.pr_view
            if args[:2] == ["api", "graphql"]:
                nodes = self.entries
                return {
                    "data": {
                        "repository": {
                            "mergeQueue": {
                                "entries": {
                                    "totalCount": len(nodes)
                                    if self.entries_total == -1
                                    else self.entries_total,
                                    "nodes": nodes,
                                }
                            }
                        }
                    }
                }
            if args[0] == "api" and "/compare/" in args[1]:
                return fixtures.UP_TO_DATE
            if args[:2] == ["api", f"repos/owner/repo/pulls/{PR}"]:
                return {"id": self.node_id}
            if args[0] == "api":
                return self.rules
            raise AssertionError(f"unexpected gh_json call: {args}")

        argv = ["babysit_merge.py", f"owner/repo#{PR}", "--allowed-owners", "owner"]
        argv += ["--unattended"]
        if merge_flag:
            argv += ["--merge", "--expected-head", HEAD]
        argv += list(flags)
        out = io.StringIO()
        patches = [
            mock.patch.object(sys, "argv", argv),
            mock.patch.object(policy, "pull_request", return_value=pr_record),
            mock.patch.object(
                policy, "_default_branch", side_effect=self._default_branch
            ),
            mock.patch.object(policy, "read_config_at", return_value=self.config),
            mock.patch.object(policy, "read_acting_login", return_value=self.acting),
            mock.patch.object(
                policy, "credential_refusal", return_value=self.credentials
            ),
            mock.patch.object(
                policy, "read_kill_switch", side_effect=lambda repo: kills.pop(0)
            ),
            mock.patch.object(
                policy, "permission_reader", return_value=lambda login: "write"
            ),
            mock.patch.object(policy, "read_demotion", return_value=self.demotion),
            mock.patch.object(
                policy,
                "enabled_since",
                return_value=datetime(2026, 10, 1, tzinfo=UTC),
            ),
            mock.patch.object(postmerge, "check", self.post_check),
            mock.patch.object(policy, "read_rung_cap", self.read_cap),
            mock.patch.object(policy, "in_flight", self.in_flight),
            mock.patch.object(policy, "read_promotion", return_value=self.promotion),
            mock.patch.object(policy, "eligibility", return_value=self.eligible),
            # None runs the real lane eligibility over the stubbed reads.
            *(
                [
                    mock.patch.object(
                        policy, "lane_eligibility", return_value=self.lane_eligible
                    )
                ]
                if self.lane_eligible is not None
                else []
            ),
            mock.patch.object(
                policy,
                "recheck_lane_class",
                side_effect=lambda *a, **k: (
                    self.lane_recheck_kwargs.append(k) or self.lane_recheck
                ),
            ),
            mock.patch.object(
                policy,
                "dependabot_eligibility",
                side_effect=self._dependabot_eligibility,
            ),
            mock.patch.object(policy, "changed_files", return_value=self.files),
            mock.patch.object(
                policy,
                "entry_hold",
                side_effect=lambda r, n, i, **_: self.holds.get(n),
            ),
            mock.patch.object(merge, "_lane_evidence", side_effect=self._lane_evidence),
            mock.patch.object(
                policy,
                "recheck_opt_in",
                side_effect=lambda *a, **k: self.opt_in_recheck,
            ),
            mock.patch.object(
                merge, "_checkout", return_value=pathlib.Path("/checkout")
            ),
            mock.patch.object(
                postmerge, "identity_queue", return_value=(self.queued, 0)
            ),
            mock.patch.object(postmerge, "dequeue_identity_entries", self.dequeue),
            mock.patch.object(postmerge, "dispatch_full_run", self.dispatch),
            mock.patch.object(merge, "gh_json", side_effect=gh_json),
            mock.patch.object(merge, "gh_capture", self.capture),
            mock.patch.object(merge, "fetch_review_threads", return_value=[]),
            mock.patch.object(
                merge,
                "fetch_pull_request_reviews",
                return_value=fixtures.CLEAN_APPROVAL,
            ),
            mock.patch.object(merge, "repository_default_branch", return_value="main"),
            mock.patch.object(merge, "read_merge_queue", return_value=self.queue),
            mock.patch.object(merge, "async_merge", self.async_merge),
            mock.patch.object(merge, "rerun_rate_limited_reviews", self.rerun),
            contextlib.redirect_stdout(out),
        ]
        if self.prior is not None:
            patches.append(
                mock.patch.object(
                    merge, "check_pending_request", return_value=self.prior
                )
            )
        with contextlib.ExitStack() as stack:
            for patcher in patches:
                stack.enter_context(patcher)
            code = merge.main()
        return code, json.loads(out.getvalue())

    def _capture(self, args: list[str]) -> Any:
        joined = " ".join(args)
        if "babysit-merge-pin" in joined:
            self.log.append("pin")
        elif "babysit-merge-risk" in joined:
            self.log.append("risk-comment:" + args[2])
        elif "disablePullRequestAutoMerge" in joined:
            self.log.append("disarm")
        elif "dequeuePullRequest" in joined:
            self.log.append("dequeue-self:" + args[-1])
        elif "enqueuePullRequest" in joined:
            self.log.append(f"graphql-enqueue:{args[-3]}:{args[-1]}")
            answer = async_fixtures._enqueued()
            return subprocess.CompletedProcess(args, 0, json.dumps(answer), "")
        else:
            self.log.append("write:" + joined)
        return subprocess.CompletedProcess(args, 0, "{}", "")

    def _async_merge(self, repo: str, number: int, **kwargs: Any) -> dict[str, Any]:
        self.log.append(f"enqueue:{kwargs['sha']}:{kwargs['merge_action']}")
        return dict(ENQUEUED)

    def _dequeue(self, repo: str, branch: str, identity: str, **kwargs: Any) -> int:
        numbers = kwargs.get("numbers")
        self.log.append(f"dequeue:{sorted(numbers) if numbers is not None else 'all'}")
        return 0

    def assert_no_merge(self, code: int) -> None:
        self.assertEqual(code, 10)
        self.async_merge.assert_not_called()
        self.assertNotIn("pin", self.log)


class LaneMode(Unattended):
    """`--authority pr-merge` (plan Phase 1): the CI lane's own authority, its
    class re-read before the enqueue, and report-only writing nothing (D16)."""

    def setUp(self) -> None:
        super().setUp()
        self.config = policy.PipelineConfig(
            BASE, "C2", "pr-merge", IDENTITY, 200, (".github/**",), "c2-mechanical"
        )
        # The local opt-in re-read is not a lane rule: reaching it would hold.
        self.opt_in_recheck = "not-lane-authored-or-opted-in"
        # D16 replaces the local promotion read: an unpromoted cell must not hold.
        self.promotion = policy.Promotion(None, "resolver-failed")
        # The lane never reads the variables kill switch: a read would pop
        # from an empty list and fail the test.
        self.kill = []

    def lane(self, *flags: str) -> tuple[int, dict[str, Any]]:
        return self.run_main(
            "--authority",
            "pr-merge",
            "--lane-kill-switch",
            "proceed",
            "--lane-rung-cap",
            "",
            *flags,
        )

    def test_the_lane_takes_the_rung_cap_from_the_workflow(self) -> None:
        code, out = self.lane()
        self.assertEqual(code, 0, out["blockers"])
        self.read_cap.assert_not_called()
        self.assertEqual(
            out["unattended"]["rungCap"], {"value": None, "reason": "no-cap"}
        )

    def test_a_workflow_cap_below_the_rung_refuses(self) -> None:
        code, out = self.run_main(
            "--authority", "pr-merge", "--lane-kill-switch", "proceed",
            "--lane-rung-cap", "off",
        )  # fmt: skip
        self.assert_no_merge(code)
        self.assertEqual(out["unattended"]["reason"], "rung-off:rungCap")
        self.read_cap.assert_not_called()

    def test_the_lane_enqueues_at_the_pinned_head(self) -> None:
        code, out = self.lane()
        self.assertEqual(code, 0, out["blockers"])
        self.assertIsNone(out["unattended"]["reason"])
        self.assertEqual(self.log, ["pin", f"enqueue:{HEAD}:merge_queue"])
        self.assertEqual(
            out["unattended"]["enqueue"]["killSwitch"],
            {"proceed": True, "reason": "proceed"},
        )

    def test_the_lane_enqueues_through_graphql_not_merge_async(self) -> None:
        self._async_merge = REAL_ASYNC_MERGE  # type: ignore[method-assign]
        code, out = self.lane()
        self.assertEqual(code, 0, out["blockers"])
        self.assertTrue(out["enqueued"])
        self.assertEqual(self.log, ["pin", f"graphql-enqueue:id=PR_self:head={HEAD}"])
        self.assertEqual(out["merge"]["api"], "graphql")

    def test_a_missing_workflow_kill_switch_stops_the_lane(self) -> None:
        # A stop like the switch itself: no enqueue, and the identity's own
        # queued entries leave the queue.
        code, out = self.run_main("--authority", "pr-merge")
        self.assert_no_merge(code)
        self.assertEqual(out["unattended"]["reason"], "kill-switch:lane-value-missing")
        self.assertEqual(self.log, ["dequeue:all"])

    def test_a_workflow_kill_switch_other_than_proceed_refuses(self) -> None:
        for value in ("true", "stop", "PROCEED"):
            with self.subTest(value=value):
                self.log = []
                code, out = self.run_main(
                    "--authority", "pr-merge", "--lane-kill-switch", value
                )
                self.assert_no_merge(code)
                self.assertEqual(
                    out["unattended"]["reason"], "kill-switch:lane-value-not-proceed"
                )

    def test_the_lane_judges_only_its_own_merges(self) -> None:
        # #7481: the post-merge check and the in-flight rule skip another
        # App's merge on main.
        self.lane()
        self.assertIs(self.post_check.call_args.kwargs["lane_merges_only"], True)
        self.assertIs(self.in_flight.call_args.kwargs["lane_merges_only"], True)

    def test_a_class_label_gone_before_the_enqueue_refuses(self) -> None:
        self.lane_recheck = "class-label-removed"
        code, out = self.lane()
        self.assert_no_merge(code)
        self.assertIn(
            "unattended merge refused: ineligible:class-label-removed", out["blockers"]
        )

    def test_the_enqueue_recheck_keeps_the_self_logins_and_permission(self) -> None:
        # A listed self login must not count as a human labeler at the
        # recheck either (#7507).
        self.lane("--self-logins", "lane-app[bot]")
        self.assertEqual(len(self.lane_recheck_kwargs), 1)
        kwargs = self.lane_recheck_kwargs[0]
        self.assertEqual(kwargs.get("self_logins"), frozenset({"lane-app[bot]"}))
        self.assertIsNotNone(kwargs.get("permission"))

    def test_an_ineligible_pr_is_refused(self) -> None:
        self.lane_eligible = policy.Eligibility(False, "denied-path:.github/x.yml")
        code, out = self.lane()
        self.assert_no_merge(code)
        self.assertEqual(
            out["unattended"]["reason"], "ineligible:denied-path:.github/x.yml"
        )

    def test_report_only_reports_the_decision_and_writes_nothing(self) -> None:
        self.config = dataclasses.replace(self.config, report_only=True)
        code, out = self.lane()
        self.assertEqual(code, 0, out["blockers"])
        self.assertEqual(out["action"], "check")
        self.assertIs(out["unattended"]["reportOnly"], True)
        self.assertEqual(self.log, [])
        self.capture.assert_not_called()
        self.dequeue.assert_not_called()
        self.async_merge.assert_not_called()

    def test_authority_without_unattended_is_a_usage_error(self) -> None:
        argv = ["babysit_merge.py", f"owner/repo#{PR}", "--allowed-owners", "owner"]
        out = io.StringIO()
        with (
            mock.patch.object(sys, "argv", [*argv, "--authority", "pr-merge"]),
            mock.patch.object(merge, "gh_capture", side_effect=AssertionError),
            mock.patch.object(merge, "gh_json", side_effect=AssertionError),
            contextlib.redirect_stdout(out),
        ):
            self.assertEqual(merge.main(), 2)

    def test_a_lane_kill_switch_outside_the_lane_is_a_usage_error(self) -> None:
        # Local babysit keeps its variables read; it never takes a passed value.
        for flags in (
            ["--unattended", "--lane-kill-switch", "proceed"],
            ["--unattended", "--authority", "local-babysit"]
            + ["--lane-kill-switch", "proceed"],
            ["--lane-kill-switch", "proceed"],
            ["--unattended", "--lane-rung-cap", ""],
            ["--unattended", "--authority", "local-babysit", "--lane-rung-cap", "C2"],
        ):
            with self.subTest(flags=flags):
                argv = ["babysit_merge.py", f"owner/repo#{PR}"]
                argv += ["--allowed-owners", "owner", *flags]
                out = io.StringIO()
                with (
                    mock.patch.object(sys, "argv", argv),
                    mock.patch.object(merge, "gh_capture", side_effect=AssertionError),
                    mock.patch.object(merge, "gh_json", side_effect=AssertionError),
                    contextlib.redirect_stdout(out),
                ):
                    self.assertEqual(merge.main(), 2)


AUTO_TIER = dependabot.Classification("auto")
DEPENDABOT_AUTO = policy.Eligibility(True, None, "C2", dependabot=AUTO_TIER)


class DependabotLane(Unattended):
    """A Dependabot pull request in the pr-merge lane: tier `auto` on a green
    `ci-status` merges under `merge.dependabot.mode: enforce` while the lane
    stays report-only, with no diff score; tier `review` and every hold
    refuse."""

    lane = LaneMode.lane

    def setUp(self) -> None:
        super().setUp()
        self.config = policy.PipelineConfig(
            BASE, "C2", "pr-merge", IDENTITY, 200, (".github/**",), "c2-mechanical",
            report_only=True, dependabot_mode="enforce",
        )  # fmt: skip
        self.opt_in_recheck = "not-lane-authored-or-opted-in"
        self.promotion = policy.Promotion(None, "resolver-failed")
        self.kill = []
        self.pr_user = {"login": "dependabot[bot]", "type": "Bot"}
        self.pr_view = fixtures._pr(author={"login": "app/dependabot"})
        self.dependabot_reads = [DEPENDABOT_AUTO]
        # The class is not scored: reading the review evidence would fail.
        self.lane_error = AssertionError("the Dependabot class was scored")
        self.lane_eligible = policy.Eligibility(False, "lane-eligibility-read")

    def test_tier_auto_enqueues_while_the_lane_is_report_only(self) -> None:
        code, out = self.lane()
        self.assertEqual(code, 0, out["blockers"])
        self.assertIs(out["unattended"]["reportOnly"], False)
        self.assertEqual(out["unattended"]["risk"]["reason"], "not-scored:dependabot")
        self.assertEqual(self.log, ["pin", f"enqueue:{HEAD}:merge_queue"])
        self.assertFalse(any("dependency manager" in b for b in out["blockers"]))

    def test_report_mode_writes_nothing(self) -> None:
        self.config = dataclasses.replace(self.config, dependabot_mode="report")
        code, out = self.lane()
        self.assertEqual(code, 0, out["blockers"])
        self.assertEqual(out["action"], "check")
        self.assertEqual(self.log, [])
        self.async_merge.assert_not_called()

    def test_off_refuses_and_keeps_the_dependency_hold(self) -> None:
        self.config = dataclasses.replace(self.config, dependabot_mode="off")
        code, out = self.lane()
        self.assert_no_merge(code)
        self.assertEqual(out["unattended"]["reason"], "ineligible:dependabot-merge-off")
        self.assertTrue(any("dependency manager" in b for b in out["blockers"]))

    def test_a_major_bump_without_a_merge_verdict_is_refused(self) -> None:
        tier = dependabot.Classification("review", ("major:x",))
        reason = "dependabot-review:major:x;review-verdict-missing"
        self.dependabot_reads = [policy.Eligibility(False, reason, dependabot=tier)]
        code, out = self.lane()
        self.assert_no_merge(code)
        self.assertEqual(out["unattended"]["reason"], f"ineligible:{reason}")
        self.assertTrue(any("dependency manager" in b for b in out["blockers"]))

    def test_a_major_bump_with_a_merge_verdict_enqueues(self) -> None:
        tier = dependabot.Classification("review", ("major:x",), approved="55-1")
        self.dependabot_reads = [policy.Eligibility(True, None, "C2", dependabot=tier)]
        code, out = self.lane()
        self.assertEqual(code, 0, out["blockers"])
        self.assertEqual(self.log, ["pin", f"enqueue:{HEAD}:merge_queue"])
        self.assertEqual(out["unattended"]["dependabot"]["approved"], "55-1")
        self.assertFalse(any("dependency manager" in b for b in out["blockers"]))

    def test_a_red_ci_status_is_refused(self) -> None:
        tier = dependabot.Classification("review", ("ci-status-red",))
        reason = "dependabot-review:ci-status-red;review-verdict-missing"
        self.dependabot_reads = [policy.Eligibility(False, reason, dependabot=tier)]
        code, out = self.lane()
        self.assert_no_merge(code)
        self.assertEqual(out["unattended"]["reason"], f"ineligible:{reason}")

    def test_the_hold_label_or_a_body_hold_refuses(self) -> None:
        for view in (
            fixtures._pr(
                author={"login": "app/dependabot"}, labels=[{"name": "do-not-merge"}]
            ),
            fixtures._pr(
                author={"login": "app/dependabot"}, body="Hold: a human merges this"
            ),
        ):
            with self.subTest(view=view.get("labels") or view.get("body")):
                self.log = []
                self.pr_view = view
                code, out = self.lane()
                self.assert_no_merge(code)
                self.assertFalse(out["ready"])

    def test_a_hold_comment_before_the_enqueue_refuses(self) -> None:
        self.dependabot_reads = [
            DEPENDABOT_AUTO,
            policy.Eligibility(False, "human-blocking-comment:maintainer", "C2"),
        ]
        code, out = self.lane()
        self.assert_no_merge(code)
        self.assertIn(
            "unattended merge refused: ineligible:human-blocking-comment:maintainer",
            out["blockers"],
        )

    def test_a_lane_authored_pr_still_reads_report_only(self) -> None:
        self.pr_user = {"login": IDENTITY, "type": "Bot"}
        self.pr_view = fixtures._pr()
        self.lane_eligible = policy.Eligibility(True, None, "C2")
        self.lane_error = None
        code, out = self.lane()
        self.assertEqual(code, 0, out["blockers"])
        self.assertIs(out["unattended"]["reportOnly"], True)
        self.assertEqual(self.log, [])


class LocalBabysitKeepsItsReads(Unattended):
    """Without `--authority pr-merge` the kill switch is read from the
    variables and every non-human merge is judged, as before."""

    def test_the_variables_kill_switch_and_every_merge_are_read(self) -> None:
        code, out = self.run_main()
        self.assertEqual(code, 0, out["blockers"])
        self.assertEqual(
            out["unattended"]["enqueue"]["killSwitch"],
            {"proceed": PROCEED.proceed, "reason": PROCEED.reason},
        )
        self.assertIs(self.post_check.call_args.kwargs["lane_merges_only"], False)
        self.assertIs(self.in_flight.call_args.kwargs["lane_merges_only"], False)


class AllInputsGood(Unattended):
    def test_scores_low_and_enqueues_at_the_pinned_head_after_the_pin(self) -> None:
        code, out = self.run_main()
        self.assertEqual(code, 0, out["blockers"])
        self.assertEqual(out["unattended"]["risk"]["score"], "LOW")
        self.assertIs(out["unattended"]["enabled"], True)
        self.assertIs(out["unattended"]["promoted"], True)
        self.assertIsNone(out["unattended"]["reason"])
        self.assertEqual(self.log, ["pin", f"enqueue:{HEAD}:merge_queue"])
        self.assertIs(out["enqueued"], True)

    def test_a_head_that_moved_after_scoring_is_not_enqueued(self) -> None:
        # The policy scored one head; the gate's later read sees another that
        # still matches the --expected-head prefix. That head was never scored.
        self.scored_head = HEAD[:12] + "d" * 28
        code, out = self.run_main()
        self.assertEqual(code, 10)
        self.assertEqual(self.log, [])
        self.assertTrue(any("scored" in b for b in out["blockers"]), out["blockers"])

    def test_check_only_reports_the_decision_and_writes_nothing(self) -> None:
        code, out = self.run_main(merge_flag=False)
        self.assertEqual(code, 0)
        self.assertEqual(out["unattended"]["risk"]["score"], "LOW")
        self.assertEqual(self.log, [])
        self.capture.assert_not_called()

    def test_a_landed_entry_read_back_at_its_pin_dispatches_the_full_run(self) -> None:
        # A later run: the recorded queue entry merged at the pinned head (the
        # read-back held). The merge is now an unverified auto-merge in flight.
        self.flight = policy.InFlight(False, f"unverified-auto-merge:#{PR}")
        self.pr_view = fixtures._pr(state="MERGED")
        self.prior = {
            "queued": True,
            "head": HEAD,
            "status": "merged",
            "verification": {"verified": True, "mismatches": []},
            "requestedAt": "2026-10-12T10:00:00Z",
        }
        with tempfile.TemporaryDirectory() as state:
            code, out = self.run_main("--state-dir", state)
        self.assertIs(out["merged"], True)
        self.assertEqual(self.log, ["dispatch"])
        self.dispatch.assert_called_once_with("owner/repo", ref="main")
        self.assertIs(out["unattended"]["dispatched"], True)
        self.assertEqual(code, 10)

    def test_a_failed_dispatch_is_reported_and_left_to_the_remediate_check(
        self,
    ) -> None:
        # The pending record is already cleared, so the next cycle's
        # `babysit-postmerge.sh --remediate` is what dispatches again.
        self.flight = policy.InFlight(False, f"unverified-auto-merge:#{PR}")
        self.pr_view = fixtures._pr(state="MERGED")
        self.prior = {
            "queued": True,
            "head": HEAD,
            "status": "merged",
            "verification": {"verified": True, "mismatches": []},
            "requestedAt": "2026-10-12T10:00:00Z",
        }
        self.dispatch_error = postmerge.PostMergeWriteError("HTTP 500")
        with tempfile.TemporaryDirectory() as state:
            code, out = self.run_main("--state-dir", state)
        self.assertIs(out["merged"], True)
        self.assertIs(out["unattended"]["dispatched"], False)
        self.assertEqual(out["unattended"]["dispatchError"], "HTTP 500")
        self.assertEqual(code, 10)

    def test_an_enqueue_is_recorded_at_the_pin_for_the_later_read_back(
        self,
    ) -> None:
        # The enqueue returns before the queue lands it: the merge and its
        # verifying dispatch come from a later run reading this record back.
        self._async_merge = REAL_ASYNC_MERGE  # type: ignore[method-assign]
        with tempfile.TemporaryDirectory() as state:
            code, out = self.run_main("--state-dir", state)
            path = pathlib.Path(state) / merge.PENDING_MERGES_FILE
            record = json.loads(path.read_text(encoding="utf-8"))["requests"][
                f"owner/repo#{PR}"
            ]
        self.assertEqual(code, 0, out["blockers"])
        self.assertEqual((record["queued"], record["head"]), (True, HEAD))
        self.dispatch.assert_not_called()

    def test_a_read_back_that_did_not_hold_dispatches_nothing(self) -> None:
        self.pr_view = fixtures._pr(state="MERGED")
        self.prior = {
            "queued": True,
            "head": HEAD,
            "status": "merged",
            "verification": {"verified": False, "mismatches": [{"pr": "x"}]},
            "requestedAt": "2026-10-12T10:00:00Z",
        }
        with tempfile.TemporaryDirectory() as state:
            code, _ = self.run_main("--state-dir", state)
        self.assertEqual(code, 10)
        self.dispatch.assert_not_called()


class EachRefusalMakesNoMergeCall(Unattended):
    """One input per case; the reason is the Design's refusal for it."""

    def test_identity_credentials_and_authority_refuse_before_any_write(self) -> None:
        cases = {
            "identity": ("acting", "operator", "acting-login-mismatch"),
            "credentials": (
                "credentials",
                "other-account-listed",
                "credentials:other-account-listed",
            ),
            "authority": (
                "config",
                policy.PipelineConfig(BASE, "C2", "pr-merge", IDENTITY, 200, (), None),
                "authority-unconfigured",
            ),
        }
        for name, (field, value, reason) in cases.items():
            with self.subTest(name):
                self.setUp()
                setattr(self, field, value)
                code, out = self.run_main()
                self.assert_no_merge(code)
                self.assertEqual(out["unattended"]["reason"], reason)
                self.assertIs(out["unattended"]["enabled"], False)
                self.assertEqual(self.log, [])

    def test_stop_refusals_dequeue_the_identitys_entries(self) -> None:
        failed = postmerge.PostMergeVerdict(
            True,
            failures=(
                postmerge.Failure(
                    "canary",
                    policy.AutoMerge(9, "d" * 40, "e" * 40, "2026-10-12T09:00:00Z"),
                    None,
                    "attempt 1 failure",
                ),
            ),
            branch="main",
        )
        cases = {
            "kill switch at cycle start": (
                "kill",
                [policy.KillSwitch(False, "org-switch-not-false")],
                "kill-switch:org-switch-not-false",
            ),
            "post-merge failure": ("verdict", failed, "post-merge:failure:canary#9"),
            "cap": ("cap", policy.RungCap("off", "cap-set"), "rung-off:rungCap"),
            "demotion issue": (
                "demotion",
                policy.Demotion(True, "#9 open", (9,)),
                "rung-off:demotion",
            ),
            # Local review of ed841af72: a doubtful default-branch read must
            # not skip the dequeue a hold or the kill switch would make.
            "default branch unreadable": (
                "default_branch",
                None,
                "default-branch-unreadable",
            ),
        }
        for name, (field, value, reason) in cases.items():
            with self.subTest(name):
                self.setUp()
                setattr(self, field, value)
                code, out = self.run_main()
                self.assert_no_merge(code)
                self.assertEqual(out["unattended"]["reason"], reason)
                self.assertEqual(self.log, ["dequeue:all"])

    def test_live_refusals_hold_the_merge_and_keep_the_path_enabled(self) -> None:
        cases = {
            "in flight": (
                "flight",
                policy.InFlight(False, "identity-entry-queued:#5"),
                "in-flight:identity-entry-queued:#5",
            ),
            "promotion unqualified": (
                "promotion",
                policy.Promotion(None, "options-unset:promotion_evidence_checker"),
                "promotion-unqualified:options-unset:promotion_evidence_checker",
            ),
            "ineligible": (
                "eligible",
                policy.Eligibility(False, "not-lane-authored-or-opted-in"),
                "ineligible:not-lane-authored-or-opted-in",
            ),
        }
        for name, (field, value, reason) in cases.items():
            with self.subTest(name):
                self.setUp()
                setattr(self, field, value)
                code, out = self.run_main()
                self.assert_no_merge(code)
                self.assertEqual(out["unattended"]["reason"], reason)
                self.assertIs(out["unattended"]["enabled"], True)
                self.assertEqual(self.log, [])

    def test_an_ineligible_pull_request_is_not_scored_or_commented(self) -> None:
        self.eligible = policy.Eligibility(False, "fork")
        self.lanes = UNBOUND
        _, out = self.run_main()
        self.assertNotIn("risk", out["unattended"])
        self.capture.assert_not_called()

    def test_a_required_check_not_green_makes_no_merge_call(self) -> None:
        self.pr_view = fixtures._pr(mergeStateStatus="BLOCKED")
        code, out = self.run_main()
        self.assert_no_merge(code)
        self.assertIsNone(out["unattended"]["reason"])

    def test_the_kill_switch_at_the_pre_enqueue_read_refuses_and_dequeues(self) -> None:
        self.kill = [PROCEED, policy.KillSwitch(False, "repo-switch-not-false")]
        code, out = self.run_main()
        self.assert_no_merge(code)
        self.assertEqual(self.log, ["dequeue:all"])
        self.assertIn(
            "unattended merge refused: kill-switch:repo-switch-not-false",
            out["blockers"],
        )

    def test_an_opt_in_gone_at_the_pre_enqueue_read_refuses(self) -> None:
        # #7339 comment 2: the opt-in is read again beside the kill switch.
        self.opt_in_recheck = "opt-in-label:labeler-not-human"
        code, out = self.run_main()
        self.assert_no_merge(code)
        self.assertEqual(self.log, [])
        self.assertIn(
            "unattended merge refused: ineligible:opt-in-label:labeler-not-human",
            out["blockers"],
        )

    def test_an_unproven_head_pusher_refuses(self) -> None:
        self.lane_error = merge.HeadPusherUnproven("head-pusher-unproven:aaaaaaaaaaaa")
        code, out = self.run_main()
        self.assert_no_merge(code)
        self.assertEqual(
            out["unattended"]["reason"], "head-pusher-unproven:aaaaaaaaaaaa"
        )

    def test_an_armed_auto_merge_is_disarmed_and_refused(self) -> None:
        self.queue = fixtures._queue_read(required=True, armed=True)
        code, out = self.run_main()
        self.assert_no_merge(code)
        self.assertEqual(self.log, ["disarm"])
        self.assertIs(out["unattended"]["enqueue"]["disarmed"], True)

    def test_a_base_without_a_merge_queue_is_refused(self) -> None:
        # C4: an unattended merge only ever enqueues.
        self.rules = fixtures.RULES
        code, out = self.run_main()
        self.assert_no_merge(code)
        self.assertTrue(
            any("merge queue" in b for b in out["blockers"]), out["blockers"]
        )

    def test_a_med_score_refuses(self) -> None:
        self.lanes = UNBOUND
        code, out = self.run_main()
        self.assert_no_merge(code)
        self.assertEqual(out["unattended"]["reason"], "risk:MED")


class OneUnattendedMergeInFlight(Unattended):
    def test_two_identity_entries_the_later_dequeues_itself(self) -> None:
        # Another host enqueued #5 first in the same window (D4).
        self.entries = [
            entry(5, "2026-10-12T09:59:00Z", "PR_other"),
            entry(PR, "2026-10-12T10:00:00Z", "PR_self"),
        ]
        code, out = self.run_main()
        self.assertEqual(code, 10)
        self.assertEqual(
            self.log, ["pin", f"enqueue:{HEAD}:merge_queue", "dequeue-self:id=PR_self"]
        )
        self.assertIs(out["unattended"]["enqueue"]["dequeuedSelf"], True)
        self.assertIs(out["enqueued"], False)

    def test_the_earliest_entry_stays(self) -> None:
        self.entries = [
            entry(PR, "2026-10-12T10:00:00Z", "PR_self"),
            entry(5, "2026-10-12T10:00:01Z", "PR_other"),
        ]
        code, _ = self.run_main()
        self.assertEqual(code, 0)
        self.assertNotIn("dequeue-self:id=PR_self", self.log)

    def test_a_hold_on_a_queued_identity_entry_dequeues_it(self) -> None:
        # D3: a hold that appears after the enqueue removes the entry.
        self.flight = policy.InFlight(False, "identity-entry-queued:#5")
        self.queued = [5, 6]
        self.holds = {5: "do-not-merge"}
        code, out = self.run_main()
        self.assert_no_merge(code)
        self.assertEqual(self.log, ["dequeue:[5]"])
        self.assertEqual(out["unattended"]["writes"]["holds"], {"5": "do-not-merge"})

    def test_a_queued_entry_this_run_finds_ineligible_dequeues_itself(self) -> None:
        # claude-security-review on #7335: the fresh eligibility read of the
        # queued pull request itself refuses (a non-human restored its opt-in
        # label), so its own entry leaves the queue even though no entry hold
        # fired.
        self.flight = policy.InFlight(False, f"identity-entry-queued:#{PR}")
        self.queued = [PR]
        self.eligible = policy.Eligibility(False, "opt-in-label:labeler-not-human")
        code, out = self.run_main()
        self.assert_no_merge(code)
        self.assertEqual(self.log, [f"dequeue:[{PR}]"])
        self.assertEqual(
            out["unattended"]["writes"]["holds"],
            {str(PR): "ineligible:opt-in-label:labeler-not-human"},
        )

    def test_a_queued_entry_whose_class_rose_above_the_rung_dequeues_itself(
        self,
    ) -> None:
        # Local review of ed841af72: a human relabels the linked issue C4 after
        # the enqueue. Eligibility still passes, so only the class ceiling says
        # it must never merge unattended.
        self.flight = policy.InFlight(False, f"identity-entry-queued:#{PR}")
        self.queued = [PR]
        self.eligible = policy.Eligibility(True, None, "C4", 40)
        code, out = self.run_main()
        self.assert_no_merge(code)
        # The scorer rates C4 HIGH, so the reasons comment follows the dequeue.
        self.assertEqual(self.log, [f"dequeue:[{PR}]", "risk-comment:POST"])
        self.assertEqual(
            out["unattended"]["writes"]["holds"], {str(PR): "class-above-rung:C4>C2"}
        )

    def test_a_queued_entry_this_run_scores_above_low_dequeues_itself(self) -> None:
        # #7339 comment 2: an eligible entry rescored MED stayed queued.
        self.flight = policy.InFlight(False, f"identity-entry-queued:#{PR}")
        self.queued = [PR]
        self.lanes = UNBOUND
        code, out = self.run_main()
        self.assert_no_merge(code)
        self.assertEqual(self.log, [f"dequeue:[{PR}]", "risk-comment:POST"])
        self.assertEqual(out["unattended"]["writes"]["holds"], {str(PR): "risk:MED"})

    def test_a_queued_entry_on_a_non_default_base_dequeues_itself(self) -> None:
        # #7339 comment 2: base-not-default refused but left its own entry.
        self.default_branch = "trunk"
        self.queued = [PR]
        code, out = self.run_main()
        self.assert_no_merge(code)
        self.assertEqual(self.log, [f"dequeue:[{PR}]"])
        self.assertEqual(
            out["unattended"]["writes"]["holds"], {str(PR): "base-not-default:main"}
        )

    def test_an_unproven_head_pusher_refuses_and_dequeues_its_entry(self) -> None:
        # #7339 item 3: an unlinked commit author on a non-force push.
        self.flight = policy.InFlight(False, f"identity-entry-queued:#{PR}")
        self.queued = [PR]
        self.lane_error = merge.HeadPusherUnproven("head-pusher-unproven:aaaaaaaaaaaa")
        code, out = self.run_main()
        self.assert_no_merge(code)
        self.assertEqual(self.log, [f"dequeue:[{PR}]"])
        self.assertEqual(
            out["unattended"]["writes"]["holds"],
            {str(PR): "head-pusher-unproven:aaaaaaaaaaaa"},
        )

    def test_a_non_default_base_still_holds_the_identitys_entries(self) -> None:
        self.default_branch = "trunk"
        self.queued = [5]
        self.holds = {5: "do-not-merge"}
        code, out = self.run_main()
        self.assert_no_merge(code)
        self.assertEqual(out["unattended"]["reason"], "base-not-default:main")
        self.assertEqual(self.log, ["dequeue:[5]"])


class GateReviewFixes(Unattended):
    """Phase 13 Fable gate findings, red first."""

    def landed(self) -> None:
        self.pr_view = fixtures._pr(state="MERGED")
        self.prior = {
            "queued": True,
            "head": HEAD,
            "status": "merged",
            "verification": {"verified": True, "mismatches": []},
            "requestedAt": "2026-10-12T10:00:00Z",
        }

    def test_a_refused_credential_reruns_no_review(self) -> None:
        # A wrongly launched lane holding the operator's token must not re-run a
        # workflow as the operator.
        self.credentials = "other-account-listed"
        code, _ = self.run_main()
        self.assertEqual(code, 10)
        self.rerun.assert_not_called()

    def test_a_live_refusal_still_reruns_a_rate_limited_review(self) -> None:
        self.flight = policy.InFlight(False, "identity-entry-queued:#5")
        self.run_main()
        self.rerun.assert_called_once()

    def test_an_unreadable_queue_re_read_still_dequeues_by_node_id(self) -> None:
        self.entries_total = 5  # the read is truncated
        code, out = self.run_main()
        self.assertEqual(code, 10)
        self.assertIn("dequeue-self:id=PR_self", self.log)
        self.assertIs(out["unattended"]["enqueue"]["dequeuedSelf"], True)

    def test_a_self_dequeue_not_sent_says_so(self) -> None:
        self.entries_total = 5
        self.node_id = ""
        code, out = self.run_main()
        self.assertEqual(code, 10)
        self.assertNotIn("dequeue-self:id=", " ".join(self.log))
        self.assertIs(out["unattended"]["enqueue"]["dequeuedSelf"], False)
        refusal = [b for b in out["blockers"] if b.startswith("unattended merge")]
        self.assertTrue(any("could not be dequeued" in b for b in refusal), refusal)

    def test_a_stopped_path_dispatches_nothing_after_the_read_back(self) -> None:
        self.landed()
        self.kill = [policy.KillSwitch(False, "org-switch-not-false")]
        with tempfile.TemporaryDirectory() as state:
            _, out = self.run_main("--state-dir", state)
        self.dispatch.assert_not_called()
        self.assertNotIn("dispatched", out["unattended"])

    def test_allow_unprotected_is_refused(self) -> None:
        code, out = self.run_main("--allow-unprotected")
        self.assertEqual(code, 2)
        self.assertIn("--allow-unprotected", out["error"])
        self.async_merge.assert_not_called()


class ReasonsComment(Unattended):
    """MED/HIGH on an eligible pull request: one upserted comment (T14, D15)."""

    def body(self) -> str:
        self.lanes = UNBOUND
        self.run_main()
        posted = [
            c
            for c in self.capture.call_args_list
            if "babysit-merge-risk" in " ".join(c.args[0])
        ]
        return posted[0].args[0][-1].removeprefix("body=")

    def test_a_med_pull_request_gets_one_comment(self) -> None:
        self.lanes = UNBOUND
        code, out = self.run_main()
        self.assert_no_merge(code)
        self.assertEqual(self.log, ["risk-comment:POST"])
        self.assertEqual(out["unattended"]["writes"]["riskComment"], "created")
        body = self.capture.call_args.args[0][-1]
        self.assertTrue(body.startswith(f"body={merge.RISK_MARKER}\n"))
        self.assertIn("evidence-unbound:claude-review", body)
        self.assertIn(HEAD, body)

    def test_an_unchanged_assessment_is_not_rewritten(self) -> None:
        body = self.body()
        self.setUp()
        self.comments = [
            {
                "id": 77,
                "user": {"login": IDENTITY, "type": "Bot"},
                "created_at": "2026-10-12T10:00:00Z",
                "body": body,
            }
        ]
        self.lanes = UNBOUND
        _, out = self.run_main()
        self.assertEqual(out["unattended"]["writes"]["riskComment"], "unchanged")
        self.assertEqual(self.log, [])

    def test_a_changed_assessment_rewrites_the_identitys_comment(self) -> None:
        self.comments = [
            {
                "id": 77,
                "user": {"login": IDENTITY, "type": "Bot"},
                "created_at": "2026-10-12T10:00:00Z",
                "body": f"{merge.RISK_MARKER}\nan older assessment",
            },
            {
                "id": 78,
                "user": {"login": "maintainer", "type": "User"},
                "created_at": "2026-10-12T10:01:00Z",
                "body": f"{merge.RISK_MARKER}\nquoted by a human",
            },
        ]
        self.lanes = UNBOUND
        _, out = self.run_main()
        self.assertEqual(out["unattended"]["writes"]["riskComment"], "updated")
        self.assertEqual(self.log, ["risk-comment:PATCH"])
        self.assertIn(
            "repos/owner/repo/issues/comments/77", self.capture.call_args.args[0]
        )

    def test_a_low_pull_request_gets_no_comment(self) -> None:
        self.run_main()
        self.assertNotIn("risk-comment:POST", self.log)


class HeadFile(unittest.TestCase):
    """`bind()`'s head-file reader proves a deletion, never a rename."""

    def read(self, proc: Any, files: Any = ()) -> str | None:
        with (
            mock.patch.object(merge, "gh_capture", return_value=proc),
            mock.patch.object(merge, "gh_json", return_value={"files": list(files)}),
        ):
            return merge._head_file("owner/repo", HEAD)("app.py", "b" * 40)

    @staticmethod
    def proc(code: int, out: str = "", err: str = "") -> Any:
        return subprocess.CompletedProcess([], code, out, err)

    def test_text_at_head(self) -> None:
        self.assertEqual(self.read(self.proc(0, "x\n")), "x\n")

    def test_removed_file_reads_none(self) -> None:
        gone = self.proc(1, err="gh: Not Found (HTTP 404)")
        removed = {"filename": "app.py", "status": "removed"}
        self.assertIsNone(self.read(gone, [removed]))

    def test_renamed_or_unproven_file_raises(self) -> None:
        gone = self.proc(1, err="gh: Not Found (HTTP 404)")
        renamed = {"filename": "app.py", "status": "renamed"}
        removed = {"filename": "app.py", "status": "removed"}
        for name, proc, files in (
            ("renamed", gone, [renamed]),
            ("capped", gone, [removed] + [{"filename": "f"}] * 299),
            ("forbidden", self.proc(1, err="gh: Forbidden (HTTP 403)"), [removed]),
        ):
            with self.subTest(name), self.assertRaises(RuntimeError):
                self.read(proc, files)


class HeadPushers(unittest.TestCase):
    """#7339 item 3: who pushed a commit is known only through a linked login."""

    def read(self, commits: list[dict[str, Any]], total: Any = None) -> Any:
        pr = {
            "head": {"ref": "feat", "sha": HEAD},
            "user": {"login": IDENTITY},
            "commits": len(commits) if total is None else total,
        }

        def paginated(endpoint: str, label: str) -> list[dict[str, Any]]:
            return commits if endpoint.endswith("/commits?per_page=100") else []

        with (
            mock.patch.object(merge, "fetch_paginated_api", side_effect=paginated),
            mock.patch.object(merge, "fetch_review_threads", return_value=[]),
            mock.patch.object(merge, "collect_lane_runs", return_value=[]),
        ):
            return merge._lane_evidence(
                "owner/repo",
                PR,
                pr,
                IDENTITY,
                frozenset(),
                lambda login: "write",
            )

    def test_an_unlinked_author_or_committer_is_unproven(self) -> None:
        bot = {"login": IDENTITY}
        for name, commit in (
            ("author", {"sha": "a" * 40, "author": None, "committer": bot}),
            ("committer", {"sha": "a" * 40, "author": bot, "committer": None}),
        ):
            with self.subTest(name):
                with self.assertRaises(merge.HeadPusherUnproven) as raised:
                    self.read([commit])
                self.assertEqual(
                    str(raised.exception), "head-pusher-unproven:aaaaaaaaaaaa"
                )

    def test_a_head_longer_than_the_commits_list_is_unproven(self) -> None:
        # The pull request commits endpoint lists at most 250 commits; a
        # pusher of commit 251 is in no list, so the head cannot be judged.
        bot = {"login": IDENTITY}
        listed = [
            {"sha": f"{n:040x}", "author": bot, "committer": bot} for n in range(250)
        ]
        # An unreadable count is no better than a larger one.
        for total in (251, "missing", "251"):
            with self.subTest(total=total):
                with self.assertRaises(merge.HeadPusherUnproven) as raised:
                    self.read(listed, total=total)
                self.assertIn("commits-listed:250", str(raised.exception))

    def test_linked_commits_bind_as_before(self) -> None:
        bot = {"login": IDENTITY}
        lanes, _ = self.read([{"sha": "a" * 40, "author": bot, "committer": bot}])
        self.assertEqual(len(lanes), 2)


class QueueRead(unittest.TestCase):
    def test_the_branch_is_a_raw_string_variable(self) -> None:
        # #7339 comment 2: `-F` reads `@path` and turns `123` into a number.
        queue = {
            "data": {
                "repository": {
                    "mergeQueue": {"entries": {"totalCount": 0, "nodes": []}}
                }
            }
        }
        with mock.patch.object(merge, "gh_json", return_value=queue) as gh_json:
            merge._identity_queue_entries("owner/repo", "123", IDENTITY)
        args = gh_json.call_args.args[0]
        self.assertNotIn("-F", args)
        self.assertEqual(args[args.index("b=123") - 1], "-f")


class MainHarness(unittest.TestCase):
    """Run `main()` with every write seam replaced by a mock that records calls."""

    def setUp(self) -> None:
        self.repo_config = RepoConfigFake().install(self)

    def _main(
        self,
        *flags: str,
        resolved: policy.UnattendedPolicy | None = None,
        login: str | Exception = "operator",
    ) -> tuple[int, dict[str, Any]]:
        verdict = {
            "ready": True,
            "blockers": [],
            "headRefOid": HEAD,
            "baseRef": "main",
            "mergeAction": "direct_merge",
            "stack": {"enabled": False, "member": False, "landsLowerLayers": False},
            "autoMerge": {"ready": True, "blockers": []},
        }
        self.evaluate = mock.Mock(return_value=verdict)
        self.gh_capture = mock.Mock(
            return_value=mock.Mock(returncode=0, stdout="", stderr="")
        )
        self.async_merge = mock.Mock(side_effect=AssertionError("merge call"))
        self.rerun = mock.Mock(return_value=[])
        self.assess = mock.Mock(return_value=INERT if resolved is None else resolved)
        self.login = mock.Mock(
            side_effect=login if isinstance(login, Exception) else None,
            return_value=None if isinstance(login, Exception) else login,
        )
        argv = ["babysit_merge.py", "owner/repo#1", "--allowed-owners", "owner", *flags]
        out = io.StringIO()
        with (
            mock.patch.object(sys, "argv", argv),
            mock.patch.object(
                policy, "resolve", return_value=INERT if resolved is None else resolved
            ),
            mock.patch.object(merge, "assess_unattended", self.assess),
            mock.patch.object(merge, "evaluate", self.evaluate),
            mock.patch.object(merge, "gh_capture", self.gh_capture),
            mock.patch.object(merge, "gh_json", side_effect=AssertionError("gh_json")),
            mock.patch.object(merge, "async_merge", self.async_merge),
            mock.patch.object(merge, "rerun_rate_limited_reviews", self.rerun),
            mock.patch.object(merge, "resolve_author", self.login),
            mock.patch.object(merge, "allowed_method", return_value="squash"),
            mock.patch.object(merge, "repository_default_branch", return_value="dev"),
            mock.patch.object(
                merge, "read_merge_queue", return_value=fixtures._queue_read()
            ),
            contextlib.redirect_stdout(out),
        ):
            code = merge.main()
        return code, json.loads(out.getvalue()) if out.getvalue() else {}

    def assert_no_write(self) -> None:
        self.assertFalse(self.gh_capture.called, self.gh_capture.call_args_list)
        self.assertFalse(self.async_merge.called)
        self.assertFalse(self.rerun.called)


class UnattendedCheckOnly(MainHarness):
    def test_check_only_passes_the_policy_to_evaluate(self) -> None:
        self._main("--unattended")
        self.assertEqual(self.evaluate.call_args.kwargs["unattended"], INERT)
        self.assert_no_write()

    def test_only_bot_self_logins_reach_the_policy(self) -> None:
        self._main("--unattended", "--self-logins", "operator,lane-app[bot]")
        self.assertEqual(
            self.assess.call_args.kwargs["self_logins"], frozenset({"lane-app[bot]"})
        )

    def test_without_the_flag_evaluate_gets_no_policy(self) -> None:
        self._main()
        self.assertIsNone(self.evaluate.call_args.kwargs.get("unattended"))
        self.assess.assert_not_called()

    def test_an_unreadable_policy_refuses_at_exit_10(self) -> None:
        self.assess_error = policy.PolicyReadError("config unreadable")
        with mock.patch.object(
            merge, "assess_unattended", side_effect=self.assess_error
        ):
            argv = ["babysit_merge.py", "owner/repo#1", "--allowed-owners", "owner"]
            out = io.StringIO()
            with (
                mock.patch.object(sys, "argv", [*argv, "--unattended"]),
                contextlib.redirect_stdout(out),
            ):
                self.assertEqual(merge.main(), 10)
        self.assertIn("unreadable", json.loads(out.getvalue())["error"])


class UnattendedRefusesWideningFlags(MainHarness):
    def test_each_widening_flag_is_refused_before_any_read(self) -> None:
        for flags, named in (
            (("--allow-dependency",), "--allow-dependency"),
            (("--merge", "--expected-head", HEAD, "--auto"), "--auto"),
            (("--merge", "--allow-unpinned-head"), "--allow-unpinned-head"),
            (("--stacked-prs",), "--stacked-prs"),
        ):
            with self.subTest(named):
                code, out = self._main("--unattended", *flags)
                self.assertEqual(code, 2)
                self.assertIn(named, out["error"])
                self.assertFalse(self.evaluate.called)
                self.assess.assert_not_called()
                self.assert_no_write()
                self.assertEqual(self.repo_config.calls, [])

    def test_an_unattended_merge_needs_the_expected_head(self) -> None:
        code, out = self._main("--unattended", "--merge")
        self.assertEqual(code, 2)
        self.assertIn("--expected-head", out["error"])
        self.assess.assert_not_called()


class AgentIdentityCannotUsePlainMerge(MainHarness):
    CONFIGURED = policy.UnattendedPolicy(
        reason="authority-unconfigured", agent_identity=IDENTITY
    )

    def test_identity_token_with_plain_merge_exits_10(self) -> None:
        code, out = self._main(
            "--merge", "--expected-head", HEAD, resolved=self.CONFIGURED, login=IDENTITY
        )
        self.assertEqual(code, 10)
        self.assert_no_write()
        self.assertFalse(self.evaluate.called)
        self.assertIn(IDENTITY, out["error"])
        self.assertEqual(out["actingLogin"], IDENTITY)
        self.assertEqual(out["agentIdentity"], IDENTITY)

    def test_identity_match_ignores_case(self) -> None:
        code, _ = self._main(
            "--merge",
            "--expected-head",
            HEAD,
            resolved=self.CONFIGURED,
            login="Agent-Lanes[bot]",
        )
        self.assertEqual(code, 10)
        self.assert_no_write()

    def test_padded_identity_still_refuses_its_login(self) -> None:
        padded = policy.UnattendedPolicy(
            reason="authority-unconfigured", agent_identity="  my-app[bot]  "
        )
        code, _ = self._main(
            "--merge", "--expected-head", HEAD, resolved=padded, login="my-app[bot]"
        )
        self.assertEqual(code, 10)
        self.assert_no_write()
        self.assertFalse(self.evaluate.called)

    def test_blank_identity_counts_as_unconfigured(self) -> None:
        blank = policy.UnattendedPolicy(
            reason="authority-unconfigured", agent_identity=" \t "
        )
        self.assertIsNone(blank.agent_identity)
        code, _ = self._main("--merge", "--expected-head", HEAD, resolved=blank)
        self.assertEqual(code, 0)
        self.assertFalse(self.login.called)

    def test_unresolvable_acting_login_refuses(self) -> None:
        code, _ = self._main(
            "--merge",
            "--expected-head",
            HEAD,
            resolved=self.CONFIGURED,
            login=RuntimeError("gh api user failed"),
        )
        self.assertEqual(code, 10)
        self.assert_no_write()
        self.assertFalse(self.evaluate.called)

    def test_another_login_still_merges(self) -> None:
        code, _ = self._main(
            "--merge",
            "--expected-head",
            HEAD,
            resolved=self.CONFIGURED,
            login="operator",
        )
        self.assertEqual(code, 0)
        self.assertTrue(self.evaluate.called)
        self.assertTrue(self.gh_capture.called)

    def test_no_configured_identity_reads_no_login(self) -> None:
        code, _ = self._main("--merge", "--expected-head", HEAD)
        self.assertEqual(code, 0)
        self.assertFalse(self.login.called)
        self.assertTrue(self.gh_capture.called)

    def test_plain_merge_never_passes_the_policy_to_evaluate(self) -> None:
        # The policy resolved for the identity check must not hold plain merges.
        self._main("--merge", "--expected-head", HEAD, resolved=self.CONFIGURED)
        self.assertIsNone(self.evaluate.call_args.kwargs["unattended"])
        self.assess.assert_not_called()


class LandedRequestUnderARefusingCheck(async_fixtures.AsyncMergeHarness):
    """A prior async request recorded `merged` at the evaluated head: a plain
    check reports that merge as its outcome; a refusing `--unattended` check
    reports the merge too but stays not ready."""

    def setUp(self) -> None:
        super().setUp()
        state = tempfile.TemporaryDirectory()
        self.addCleanup(state.cleanup)
        self.state_flags = ("--state-dir", state.name)
        patcher = mock.patch.object(merge, "assess_unattended", return_value=INERT)
        patcher.start()
        self.addCleanup(patcher.stop)
        code = self._run(
            async_fixtures._proc(async_fixtures._async("pending")),
            [async_fixtures._async("pending")],
            clock=[0.0, merge.ASYNC_MERGE_POLL_TIMEOUT_SECONDS + 1],
            extra=self.state_flags,
        )
        self.assertEqual((code, self.output["merge"]["status"]), (10, "pending"))

    def _check(self, *flags: str) -> int:
        # The verdict evaluate() returns under the refusing policy.
        return self._run(
            async_fixtures._proc(),
            [async_fixtures._async("merged")],
            merge_flag=False,
            blockers=[INERT_BLOCKER],
            report={"unattended": INERT.report()},
            extra=(*self.state_flags, *flags),
        )

    def test_a_refusing_check_reports_the_merge_and_stays_not_ready(self) -> None:
        self.assertEqual(self._check("--unattended"), 10)
        self.assertIs(self.output["merged"], True)
        self.assertIs(self.output["ready"], False)
        self.assertIn(INERT_BLOCKER, self.output["blockers"])
        self.assertIs(self.output["unattended"]["enabled"], False)
        self.assertEqual(self.output["merge"]["status"], "merged")

    def test_a_plain_check_reports_the_merge_as_ready(self) -> None:
        self.assertEqual(self._check(), 0)
        self.assertIs(self.output["merged"], True)
        self.assertIs(self.output["ready"], True)
        self.assertEqual(self.output["blockers"], [])


if __name__ == "__main__":
    unittest.main()
