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
import os
import pathlib
import re
import subprocess
import sys
import tempfile
import unittest
from datetime import UTC, datetime, timedelta
from typing import Any
from unittest import mock

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import babysit_dependabot as dependabot
import babysit_gh as gh
import babysit_merge as merge
import babysit_merge_prefilter as prefilter
import babysit_merge_policy as policy
import babysit_postmerge as postmerge
import babysit_run_cache as run_cache
import babysit_util as util
import test_babysit_merge as fixtures
import test_babysit_merge_async as async_fixtures
from babysit_risk import ChangedFile, LaneEvidence
from repo_config_fake import RepoConfigFake

HEAD = fixtures.HEAD
BASE = "c" * 40
PR = fixtures.PR_NUMBER
OPERATOR_LOGIN = "operator"
IDENTITY = "agent-lanes[bot]"
# A person on the trusted-actor list, kind human.
PERSON_ID = 4242
INERT = policy.UnattendedPolicy(reason="authority-unconfigured")
INERT_BLOCKER = "unattended merge refused: authority-unconfigured"
# Captured before setUpModule stubs `_role_label` for the rest of the module.
REAL_ROLE_LABEL = postmerge._role_label

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
    issue_comments: list[dict[str, Any]] | None = None,
    review_comments: list[dict[str, Any]] | None = None,
    reviews: list[dict[str, Any]] | None = None,
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
            merge,
            "fetch_pull_request_reviews",
            return_value=fixtures.CLEAN_APPROVAL + (reviews or []),
        ),
        mock.patch.object(
            merge, "fetch_issue_comments", return_value=issue_comments or []
        ),
        mock.patch.object(
            merge,
            "fetch_pull_request_review_comments",
            return_value=review_comments or [],
        ),
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


class RemappedHumanGatedLabel(unittest.TestCase):
    """A tracker that maps `human-gated` to another label: the label the
    verifier escalation adds is the one every autonomous hold reads."""

    LABEL = "human-review"

    def setUp(self) -> None:
        patcher = mock.patch.object(postmerge, "_role_label", return_value=self.LABEL)
        patcher.start()
        self.addCleanup(patcher.stop)

    def test_the_escalation_label_is_the_hold_label(self) -> None:
        capture = mock.Mock(return_value=subprocess.CompletedProcess([], 0, "", ""))
        with (
            mock.patch.object(merge, "gh_capture", capture),
            mock.patch.object(merge, "upsert_marker_comment", return_value="created"),
            mock.patch.object(merge, "fetch_paginated_api", return_value=[]),
        ):
            merge.escalate_verify(
                "owner/repo",
                fixtures.PR_NUMBER,
                IDENTITY,
                "verify:spec-changed",
                {"pr": {"head": {"sha": HEAD}, "labels": []}},
            )
        added = [
            a for c in capture.call_args_list for a in c.args[0] if "labels[]=" in a
        ]
        self.assertEqual(added, [f"labels[]={self.LABEL}"])

        permits = policy.UnattendedPolicy(None, IDENTITY, enabled=True, promoted=True)
        held = _evaluate(
            fixtures._pr(labels=[{"name": "Human-Review"}]), HEAD, None, permits
        )
        self.assertTrue(
            any(f"'{self.LABEL}' label" in b for b in held["blockers"]),
            held["blockers"],
        )
        self.assertEqual(
            prefilter.hold({"labels": ["Human-Review"]}, self.LABEL), self.LABEL
        )
        # The unmapped default no longer holds.
        free = _evaluate(
            fixtures._pr(labels=[{"name": "needs-human"}]), HEAD, None, permits
        )
        self.assertEqual(free["blockers"], [])
        self.assertIsNone(prefilter.hold({"labels": ["needs-human"]}, self.LABEL))


class UnreadableHumanGatedLabel(unittest.TestCase):
    """A tracker config read that fails for any reason but a 404 refuses an
    autonomous merge instead of holding on `needs-human`, and no fallback is
    shared with the run's later gate processes."""

    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        env = {run_cache.ENV: str(pathlib.Path(tmp.name, "run.json"))}
        for patcher in (
            mock.patch.dict("os.environ", env),
            mock.patch.object(
                postmerge,
                "_role_label",
                side_effect=postmerge.PostMergeReadError("tracker: HTTP 502"),
            ),
        ):
            patcher.start()
            self.addCleanup(patcher.stop)

    def test_the_gate_refuses_and_caches_nothing(self) -> None:
        permits = policy.UnattendedPolicy(None, IDENTITY, enabled=True, promoted=True)
        result = _evaluate(
            fixtures._pr(labels=[{"name": "human-review"}]), HEAD, None, permits
        )
        self.assertFalse(result["ready"])
        self.assertTrue(
            any(
                "human-gated role label is unreadable" in b for b in result["blockers"]
            ),
            result["blockers"],
        )
        self.assertIsNone(run_cache.get(merge.HUMAN_GATED_SECTION, "owner/repo", None))

    def test_the_escalation_falls_back_to_the_default(self) -> None:
        capture = mock.Mock(return_value=subprocess.CompletedProcess([], 0, "", ""))
        with (
            mock.patch.object(merge, "gh_capture", capture),
            mock.patch.object(merge, "upsert_marker_comment", return_value="created"),
            mock.patch.object(merge, "fetch_paginated_api", return_value=[]),
        ):
            merge.escalate_verify(
                "owner/repo",
                fixtures.PR_NUMBER,
                IDENTITY,
                "verify:spec-changed",
                {"pr": {"head": {"sha": HEAD}, "labels": []}},
            )
        added = [
            a for c in capture.call_args_list for a in c.args[0] if "labels[]=" in a
        ]
        self.assertEqual(added, ["labels[]=needs-human"])
        self.assertIsNone(run_cache.get(merge.HUMAN_GATED_SECTION, "owner/repo", None))


class HumanGatedLabelReadIsStrict(unittest.TestCase):
    """The gate reads the tracker config through the real `_role_label`: a
    502 must refuse, not fall back to `needs-human`, which would let a PR
    carrying a remapped label merge."""

    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        env = {run_cache.ENV: str(pathlib.Path(tmp.name, "run.json"))}
        failed = subprocess.CompletedProcess([], 1, "", "gh: Server Error (HTTP 502)")
        for patcher in (
            mock.patch.dict("os.environ", env),
            mock.patch.object(postmerge, "_role_label", REAL_ROLE_LABEL),
            mock.patch.object(postmerge, "gh_capture", return_value=failed),
        ):
            patcher.start()
            self.addCleanup(patcher.stop)

    def test_a_server_error_refuses_and_caches_nothing(self) -> None:
        permits = policy.UnattendedPolicy(None, IDENTITY, enabled=True, promoted=True)
        result = _evaluate(
            fixtures._pr(labels=[{"name": "human-review"}]), HEAD, None, permits
        )
        self.assertFalse(result["ready"])
        self.assertTrue(
            any(
                "human-gated role label is unreadable" in b for b in result["blockers"]
            ),
            result["blockers"],
        )
        self.assertIsNone(run_cache.get(merge.HUMAN_GATED_SECTION, "owner/repo", None))


class NeedsHumanHoldsOnlyAutonomous(unittest.TestCase):
    """`needs-human` holds an autonomous merge (unattended or the autopilot
    tier); the person it asks for may still merge attended. `do-not-merge`
    holds both."""

    def test_needs_human_holds_the_unattended_gate_not_an_attended_one(self) -> None:
        permits = policy.UnattendedPolicy(None, IDENTITY, enabled=True, promoted=True)
        pr = fixtures._pr(labels=[{"name": "Needs-Human"}])
        attended = _evaluate(pr, HEAD, None)
        unattended = _evaluate(pr, HEAD, None, unattended=permits)
        self.assertEqual(attended["blockers"], [])
        self.assertTrue(attended["ready"])
        self.assertFalse(unattended["ready"])
        self.assertTrue(
            any("'needs-human' label" in b for b in unattended["blockers"]),
            unattended["blockers"],
        )
        # The pr-merge prefilter drops what the unattended gate refuses.
        self.assertEqual(prefilter.hold({"labels": ["Needs-Human"]}), "needs-human")

    def test_needs_human_holds_the_autopilot_merge_tier(self) -> None:
        # The tier merges with no person present, like --unattended.
        result = _evaluate(
            fixtures._pr(labels=[{"name": "needs-human"}]), HEAD, fixtures.TIER
        )
        self.assertFalse(result["ready"])
        self.assertTrue(
            any("'needs-human' label" in b for b in result["blockers"]),
            result["blockers"],
        )

    def test_do_not_merge_holds_both(self) -> None:
        permits = policy.UnattendedPolicy(None, IDENTITY, enabled=True, promoted=True)
        pr = fixtures._pr(labels=[{"name": "do-not-merge"}])
        for run in (None, permits):
            with self.subTest(unattended=run is not None):
                self.assertFalse(_evaluate(pr, HEAD, None, unattended=run)["ready"])


def _comment(
    login: str,
    body: str,
    *,
    bot: bool = False,
    at: str = "2026-10-12T10:00:00Z",
    association: str = "MEMBER",
) -> dict[str, Any]:
    return {
        "authorAssociation": association,
        "author": {
            "login": login,
            "__typename": "Bot" if bot else "User",
            "is_bot": bot,
        },
        "body": body,
        "createdAt": at,
    }


class PrMergeHoldsOnAHumanVeto(unittest.TestCase):
    """The pr-merge lane enqueues with no person present, so a person whose
    newest comment with text says "do not merge" (`HUMAN_MERGE_VETO_RE` only)
    holds it before the enqueue, until a later comment of theirs. A bare "wait
    for CI" or a blocking word such as "regression" holds nothing."""

    PR_MERGE = policy.UnattendedPolicy(
        None,
        IDENTITY,
        enabled=True,
        promoted=True,
        inputs={"authority": policy.PR_MERGE},
    )
    LOCAL = policy.UnattendedPolicy(
        None,
        IDENTITY,
        enabled=True,
        promoted=True,
        inputs={"authority": policy.LOCAL_BABYSIT},
    )

    def _vetoes(self, result: dict[str, Any]) -> list[str]:
        return [b for b in result["blockers"] if "human blocking comment" in b or "human merge veto" in b]

    def test_a_human_do_not_merge_comment_holds(self) -> None:
        result = _evaluate(
            fixtures._pr(),
            HEAD,
            None,
            self.PR_MERGE,
            issue_comments=[_comment("maintainer", "Please don't merge this yet.")],
        )
        self.assertFalse(result["ready"])
        self.assertEqual(len(self._vetoes(result)), 1, result["blockers"])
        self.assertIn("maintainer", self._vetoes(result)[0])

    def test_a_human_inline_veto_holds(self) -> None:
        inline = {
            "user": {"login": "maintainer", "type": "User"},
            "author_association": "MEMBER",
            "body": "Do not merge: this is a regression.",
        }
        result = _evaluate(
            fixtures._pr(), HEAD, None, self.PR_MERGE, review_comments=[inline]
        )
        self.assertFalse(result["ready"])
        self.assertEqual(len(self._vetoes(result)), 1, result["blockers"])

    def test_a_bare_wait_holds_nothing(self) -> None:
        result = _evaluate(
            fixtures._pr(),
            HEAD,
            None,
            self.PR_MERGE,
            issue_comments=[_comment("maintainer", "Wait for CI, then it can go.")],
        )
        self.assertEqual(result["blockers"], [])

    def test_blocking_words_without_a_veto_hold_nothing(self) -> None:
        # The tier's wider vocabulary is not the lane's: these are not vetoes.
        for body in (
            "Fixed the regression you flagged.",
            "Pushed a fix, this is no longer blocking.",
        ):
            with self.subTest(body):
                result = _evaluate(
                    fixtures._pr(),
                    HEAD,
                    None,
                    self.PR_MERGE,
                    issue_comments=[_comment("maintainer", body)],
                )
                self.assertEqual(result["blockers"], [])

    def test_a_later_comment_from_the_same_person_lifts_the_veto(self) -> None:
        veto = _comment(
            "maintainer", "Do not merge until the release is cut.", at="2026-10-12T10:00:00Z"
        )
        lifted = _comment(
            "maintainer", "Release is out, go ahead.", at="2026-10-12T11:00:00Z"
        )
        result = _evaluate(
            fixtures._pr(), HEAD, None, self.PR_MERGE, issue_comments=[veto, lifted]
        )
        self.assertEqual(result["blockers"], [])

    def test_an_empty_review_after_the_veto_does_not_lift_it(self) -> None:
        # GitHub records an inline-only review, or an Approve with no text, as a
        # review summary with an empty body and a later submittedAt.
        def empty_review(state: str) -> dict[str, Any]:
            return {
                "author": {"login": "maintainer"},
                "authorAssociation": "MEMBER",
                "body": "",
                "state": state,
                "submittedAt": "2026-10-12T10:01:00Z",
                "commit": {"oid": HEAD},
            }

        inline = {
            "user": {"login": "maintainer", "type": "User"},
            "author_association": "COLLABORATOR",
            "body": "Do not merge until X.",
            "created_at": "2026-10-12T10:00:00Z",
        }
        cases = {
            "inline veto, empty review summary": {
                "review_comments": [inline],
                "reviews": [empty_review("COMMENTED")],
            },
            "issue-comment veto, approve with no text": {
                "issue_comments": [_comment("maintainer", "Do not merge yet.")],
                "reviews": [empty_review("APPROVED")],
            },
        }
        for name, kwargs in cases.items():
            with self.subTest(name):
                result = _evaluate(fixtures._pr(), HEAD, None, self.PR_MERGE, **kwargs)
                self.assertEqual(len(self._vetoes(result)), 1, result["blockers"])

    def test_only_owner_member_or_collaborator_can_veto(self) -> None:
        for association, holds in (
            ("NONE", False),
            ("CONTRIBUTOR", False),
            ("FIRST_TIME_CONTRIBUTOR", False),
            ("", False),
            ("MEMBER", True),
            ("OWNER", True),
            ("COLLABORATOR", True),
        ):
            with self.subTest(association):
                veto = _comment("someone", "Do not merge.", association=association)
                inline = {
                    "user": {"login": "someone", "type": "User"},
                    "author_association": association,
                    "body": "Do not merge.",
                    "created_at": "2026-10-12T10:00:00Z",
                }
                for kwargs in ({"issue_comments": [veto]}, {"review_comments": [inline]}):
                    result = _evaluate(fixtures._pr(), HEAD, None, self.PR_MERGE, **kwargs)
                    self.assertEqual(
                        len(self._vetoes(result)), int(holds), result["blockers"]
                    )

    def test_another_persons_later_comment_does_not_lift_it(self) -> None:
        veto = _comment("maintainer", "Do not merge yet.", at="2026-10-12T10:00:00Z")
        other = _comment("someone", "Looks good to me.", at="2026-10-12T11:00:00Z")
        result = _evaluate(
            fixtures._pr(), HEAD, None, self.PR_MERGE, issue_comments=[veto, other]
        )
        self.assertEqual(len(self._vetoes(result)), 1, result["blockers"])
        self.assertIn("maintainer", self._vetoes(result)[0])

    def test_a_bot_or_the_lane_identity_holds_nothing(self) -> None:
        for comment in (
            _comment("reviewer[bot]", "Do not merge: blocking regression.", bot=True),
            _comment(IDENTITY, "Do not merge until the queue drains."),
        ):
            with self.subTest(comment["author"]["login"]):
                result = _evaluate(
                    fixtures._pr(),
                    HEAD,
                    None,
                    self.PR_MERGE,
                    issue_comments=[comment],
                )
                self.assertEqual(result["blockers"], [])

    def test_another_authority_does_not_scan(self) -> None:
        result = _evaluate(
            fixtures._pr(),
            HEAD,
            None,
            self.LOCAL,
            issue_comments=[_comment("maintainer", "Do not merge.")],
        )
        self.assertEqual(result["blockers"], [])

    def test_the_tier_scan_is_not_repeated(self) -> None:
        result = _evaluate(
            fixtures._pr(),
            HEAD,
            fixtures.TIER,
            self.PR_MERGE,
            issue_comments=[_comment("maintainer", "Do not merge.")],
        )
        self.assertEqual(len(self._vetoes(result)), 1, result["blockers"])


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

        # The process seams every real gh read reaches, whichever module makes
        # it; no local clone holds the SHA, so the config comes from the API.
        with (
            mock.patch.object(policy, "_history_checkouts", return_value=[]),
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

# Flags with which `gh api` sends something: a method, or fields or a body
# (which turn the request into a POST).
WRITE_FLAGS = frozenset(
    {"-X", "--method", "-f", "-F", "--field", "--raw-field", "--input"}
)


def is_write(args: list[str]) -> bool:
    """A gh call that changes GitHub: anything but a plain `gh api` GET."""
    if not args or args[0] != "api":
        return True
    joined = " ".join(args)
    return bool(WRITE_FLAGS & set(args)) or "mutation" in joined


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
        self.timeline: list[dict[str, Any]] = []
        self.timeline_error: Exception | None = None
        self.timeline_reads: list[dict[str, Any]] = []
        # The trusted-actor list's people, and each ref it was read at.
        self.trusted_humans: tuple[int, ...] = (PERSON_ID,)
        self.trusted_refs: list[str] = []
        # The repository's default branch as `repository_default_branch` reads it.
        self.repo_default: str | None = "main"
        self.files = ((LOW_FILE,), True)
        self.pr_view = fixtures._pr()
        self.queue = fixtures._queue_read(required=True)
        self.entries = [entry(PR, "2026-10-12T10:00:00Z", "PR_self")]
        self.queued: list[int] = []
        self.holds: dict[int, str] = {}
        # Every queued entry the sweep judged, in order.
        self.hold_reads: list[int] = []
        self.dequeue_error: Exception | None = None
        # The permission reader the policy builds, and what a queued entry's
        # hold read does with its keyword arguments first.
        self.permission_reader: Any = lambda repo: lambda login: "write"
        self.hold_hook: Any = lambda kwargs: None
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
        self.lane_eligible = policy.Eligibility(True, None, "C2", 41)
        self.lane_recheck: str | None = None
        self.lane_recheck_kwargs: list[dict[str, Any]] = []
        # True runs the real re-read over a stubbed `_graphql`.
        self.real_lane_recheck = False
        # The base-branch read (the default branch's name).
        self.base_now: str | None = None
        self.base_reads: list[tuple[Any, ...]] = []
        # The pull request's REST author, and the Dependabot class's reads:
        # the assessment's, then the re-read before the enqueue.
        self.pr_user = {"login": IDENTITY, "type": "Bot"}
        self.pr_labels: list[dict[str, Any]] = []
        self.dependabot_reads: list[policy.Eligibility] = []
        self.dependabot_kwargs: list[dict[str, Any]] = []
        # The default branch head the in-flight cap is read at: the base, so
        # the cap is `self.config`'s.
        self.main_head = BASE
        # Reads of the pipeline config at `main_head` when it is not the
        # base, in order (the merge config's, the in-flight cap's, the room
        # check's): a config, or an exception to raise. Empty reads
        # `self.config`.
        self.head_configs: list[Any] = []
        # True runs the real `enabled_since` over the stubbed reads.
        self.real_enabled_since = False

    def _dependabot_eligibility(self, *args: Any, **kwargs: Any) -> Any:
        self.dependabot_kwargs.append(kwargs)
        if not self.dependabot_reads:
            raise AssertionError("the Dependabot class was read for this pull request")
        return (
            self.dependabot_reads.pop(0)
            if len(self.dependabot_reads) > 1
            else self.dependabot_reads[0]
        )

    def _lane_evidence(self, *args: Any) -> Any:
        self.lane_args = args
        if self.lane_error is not None:
            raise self.lane_error
        return self.lanes, self.comments

    def _paginated(self, endpoint: str, label: str, **kwargs: Any) -> Any:
        # The comments a write reads itself when no lane evidence was read
        # (a verifier refusal skips it).
        if endpoint == f"repos/owner/repo/issues/{PR}/comments?per_page=100":
            return self.comments
        # The pr-merge human-veto scan reads the inline review comments too.
        if endpoint == f"repos/owner/repo/pulls/{PR}/comments?per_page=100":
            return []
        # The timeline an escalation reads for a person's removal of its label.
        if endpoint == f"repos/owner/repo/issues/{PR}/timeline?per_page=100":
            self.timeline_reads.append(kwargs)
            if self.timeline_error is not None:
                raise self.timeline_error
            return self.timeline
        return self._real_paginated(endpoint, label, **kwargs)

    def _default_branch(self, repo: str, *, shared: bool = False) -> str:
        if self.default_branch is None:
            raise policy.PolicyReadError("the default branch could not be read")
        return self.default_branch

    def _read_config_at(self, repo: str, sha: str, *args: Any) -> Any:
        if sha != self.main_head or sha == BASE or not self.head_configs:
            return self.config
        read = self.head_configs.pop(0)
        if isinstance(read, Exception):
            raise read
        return read

    def _get(self, endpoint: str) -> tuple[int | None, Any]:
        if endpoint == "repos/owner/repo/commits/main":
            return 200, {"sha": self.main_head}
        return self._real_get(endpoint)

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
        self._real_get = policy._get
        self._real_paginated = merge.fetch_paginated_api
        patches = [
            mock.patch.object(sys, "argv", argv),
            mock.patch.object(policy, "_get", side_effect=self._get),
            mock.patch.object(policy, "pull_request", return_value=pr_record),
            mock.patch.object(
                policy, "_default_branch", side_effect=self._default_branch
            ),
            mock.patch.object(
                policy, "read_config_at", side_effect=self._read_config_at
            ),
            mock.patch.object(policy, "read_acting_login", return_value=self.acting),
            mock.patch.object(
                policy, "credential_refusal", return_value=self.credentials
            ),
            mock.patch.object(
                policy, "read_kill_switch", side_effect=lambda repo: kills.pop(0)
            ),
            mock.patch.object(
                policy, "permission_reader", side_effect=self.permission_reader
            ),
            mock.patch.object(policy, "read_demotion", return_value=self.demotion),
            *(
                []
                if self.real_enabled_since
                else [
                    mock.patch.object(
                        policy,
                        "enabled_since",
                        return_value=datetime(2026, 10, 1, tzinfo=UTC),
                    )
                ]
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
                "_base_refusal",
                side_effect=lambda *a, **k: self.base_reads.append(a) or self.base_now,
            ),
            *(
                []
                if self.real_lane_recheck
                else [
                    mock.patch.object(
                        policy,
                        "recheck_lane_issue",
                        side_effect=lambda *a, **k: (
                            self.lane_recheck_kwargs.append(k) or self.lane_recheck
                        ),
                    )
                ]
            ),
            mock.patch.object(
                policy,
                "dependabot_eligibility",
                side_effect=self._dependabot_eligibility,
            ),
            mock.patch.object(policy, "changed_files", return_value=self.files),
            mock.patch.object(policy, "pulumi_dirs_at", return_value=()),
            mock.patch.object(
                policy,
                "entry_hold",
                side_effect=lambda r, n, i, **kw: (
                    self.hold_reads.append(n) or self.hold_hook(kw) or self.holds.get(n)
                ),
            ),
            mock.patch.object(merge, "_lane_evidence", side_effect=self._lane_evidence),
            mock.patch.object(
                policy,
                "trusted_actors",
                side_effect=lambda repo, ref, exclude=(): (
                    self.trusted_refs.append(ref) or ((), self.trusted_humans)
                ),
            ),
            mock.patch.object(
                merge, "fetch_paginated_api", side_effect=self._paginated
            ),
            # The comment readers `babysit_merge` imports from `babysit_gh`
            # page through that module's own reader.
            mock.patch.object(gh, "fetch_paginated_api", side_effect=self._paginated),
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
            mock.patch.object(
                merge,
                "repository_default_branch",
                side_effect=lambda repo: self.repo_default,
            ),
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
        if self.dequeue_error is not None:
            raise self.dequeue_error
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
            BASE, "C2", "pr-merge", IDENTITY, 200, (".github/**",), "c2-mechanical",
            require_verifier_verdict=True,
        )  # fmt: skip
        # A passing verdict at every head (test_babysit_verify_evidence covers
        # the reader).
        passing = merge.verify_evidence.Evidence(
            refusal=None, head=HEAD, verdicts=(), ignored=0
        )
        patcher = mock.patch.object(
            merge.verify_evidence.Reader, "evidence", return_value=passing
        )
        patcher.start()
        self.addCleanup(patcher.stop)
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

    def test_an_adopted_pr_scores_only_paths_its_author_did_not_write(self) -> None:
        # Owner decision 2026-10-22: a trusted author's own denied-path lines
        # need no person; a denied path a lane commit touched still holds.
        self.config = dataclasses.replace(self.config, denied_paths=("notes/**",))
        self.files = ((dataclasses.replace(LOW_FILE, path="notes/x.md"),), True)
        self.lane_eligible = policy.Eligibility(
            True, None, "C2", 41, adoption="idle-owner:24h", body_is_intent=True
        )
        for others, score in (
            (frozenset(), "LOW"),
            (frozenset({"notes/x.md"}), "HIGH"),
            (None, "HIGH"),
        ):
            with (
                self.subTest(others=others),
                mock.patch.object(policy, "foreign_paths", return_value=others),
            ):
                _, out = self.lane()
                self.assertEqual(out["unattended"]["risk"]["score"], score)
        # A lane PR is scored whole like the lanes App's own.
        self.lane_eligible = policy.Eligibility(True, None, "C2", 41)
        with mock.patch.object(
            policy, "foreign_paths", side_effect=AssertionError("read")
        ):
            _, out = self.lane()
        self.assertEqual(out["unattended"]["risk"]["score"], "HIGH")

    def test_a_model_app_own_lines_skip_the_floor_only_under_scripts(self) -> None:
        # Owner decision Q14 (c): a model-driven App's own lines skip the
        # denied paths only under plugins/*/scripts/; the floor always scores.
        self.config = dataclasses.replace(self.config, high_path_floor=True)
        self.lane_eligible = policy.Eligibility(
            True, None, "C2", 41, adoption="trusted-app"
        )
        self.config = dataclasses.replace(
            self.config, denied_paths=("plugins/p/**", "scripts/**")
        )
        own, held = (
            ("plugins/p/scripts/x.md",),
            (
                "scripts/release-plugins.sh",
                "plugins/p/hooks/x.md",
                ".gitmodules",
                "plugins/p/skills/s/scripts/x.md",
            ),
        )
        self.files = (
            tuple(dataclasses.replace(LOW_FILE, path=p) for p in (*own, *held)),
            True,
        )
        with mock.patch.object(policy, "foreign_paths", return_value=frozenset()):
            _, out = self.lane()
        scored = {
            path
            for r in out["unattended"]["risk"]["reasons"]
            if r["code"].startswith("high-path:")
            for path in r["detail"].split(", ")
        }
        self.assertEqual(scored, set(held))

    def test_the_lane_takes_the_rung_cap_from_the_workflow(self) -> None:
        code, out = self.lane()
        self.assertEqual(code, 0, out["blockers"])
        self.read_cap.assert_not_called()
        self.assertEqual(
            out["unattended"]["rungCap"], {"value": None, "reason": "no-cap"}
        )

    def test_an_in_flight_refusal_skips_the_risk_and_verifier_reads(self) -> None:
        # Another pull request's lane entry is queued; this one is not.
        self.flight = policy.InFlight(False, "identity-entry-queued:#9", frozenset({9}))
        self.queued = [9]
        self.lane_error = AssertionError("risk evidence read")
        later = mock.Mock(side_effect=AssertionError("read after the refusal"))
        passing = merge.verify_evidence.Reader.evidence
        verdicts: list[int] = []

        def evidence(reader: Any, number: int, *args: Any) -> Any:
            verdicts.append(number)
            return passing(reader, number, *args)

        with (
            mock.patch.object(merge.verify_evidence.Reader, "evidence", evidence),
            mock.patch.object(policy, "changed_files", later),
        ):
            code, out = self.lane("--merge")
        self.assert_no_merge(code)
        later.assert_not_called()
        # Only the sweep's read of the queued entry, never this pull request's.
        self.assertEqual(verdicts, [9])
        self.assertIn(
            merge.UNATTENDED_REFUSED + "in-flight:identity-entry-queued:#9",
            out["blockers"],
        )
        self.assertNotIn("risk", out["unattended"])
        self.assertNotIn("riskComment", out["unattended"]["writes"])
        # The queue sweep still judges the queued entry.
        self.assertIn(9, self.hold_reads)

    def shared_rules(self) -> None:
        """A run cache holding the base's rules as an earlier candidate read
        them (QUEUE_RULES)."""
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        path = str(pathlib.Path(tmp.name, "run.json"))
        patcher = mock.patch.dict("os.environ", {"BABYSIT_RUN_CACHE": path})
        patcher.start()
        self.addCleanup(patcher.stop)
        merge.run_cache.put(merge.RULES_SECTION, "owner/repo|main", QUEUE_RULES)

    def test_rules_changed_since_the_shared_read_hold_the_enqueue(self) -> None:
        self.shared_rules()
        extra = {
            "type": "required_status_checks",
            "parameters": {"required_status_checks": [{"context": "new-check"}]},
        }
        self.rules = [*QUEUE_RULES, extra]
        code, out = self.lane()
        self.assert_no_merge(code)
        self.assertIn(
            merge.UNATTENDED_REFUSED
            + "the base branch's rules changed since the gate read them",
            out["blockers"],
        )

    def test_rules_shared_for_another_landing_base_are_read_again(self) -> None:
        # The gate read the rules of a landing base other than the pull
        # request's base (a `rules_base` override): that base is the one
        # read again before the enqueue.
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        path = str(pathlib.Path(tmp.name, "run.json"))
        patcher = mock.patch.dict("os.environ", {"BABYSIT_RUN_CACHE": path})
        patcher.start()
        self.addCleanup(patcher.stop)
        merge.run_cache.put(merge.RULES_SECTION, "owner/repo|trunk", QUEUE_RULES)
        real = merge.branch_rules
        patcher = mock.patch.object(
            merge,
            "branch_rules",
            side_effect=lambda repo, branch, **kw: real(
                repo, "trunk" if kw.get("shared", True) else branch, **kw
            ),
        )
        patcher.start()
        self.addCleanup(patcher.stop)
        extra = {
            "type": "required_status_checks",
            "parameters": {"required_status_checks": [{"context": "new-check"}]},
        }
        self.rules = [*QUEUE_RULES, extra]
        code, out = self.lane()
        self.assert_no_merge(code)
        self.assertIn(
            merge.UNATTENDED_REFUSED
            + "the base branch's rules changed since the gate read them",
            out["blockers"],
        )

    def test_unchanged_shared_rules_still_enqueue(self) -> None:
        self.shared_rules()
        code, out = self.lane()
        self.assertEqual(code, 0, out["blockers"])

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

    def test_a_human_do_not_merge_comment_holds_the_enqueue(self) -> None:
        self.comments = [
            {
                "id": 93,
                "user": {"login": "maintainer", "type": "User"},
                "author_association": "OWNER",
                "created_at": "2026-10-12T10:00:00Z",
                "body": "Do not merge until the release is cut.",
            }
        ]
        code, out = self.lane()
        self.assert_no_merge(code)
        self.assertTrue(
            any("human merge veto from maintainer" in b for b in out["blockers"]),
            out["blockers"],
        )
        self.assertNotIn(f"enqueue:{HEAD}:merge_queue", self.log)

    def test_the_lane_enqueues_through_graphql_not_merge_async(self) -> None:
        self._async_merge = REAL_ASYNC_MERGE  # type: ignore[method-assign]
        code, out = self.lane()
        self.assertEqual(code, 0, out["blockers"])
        self.assertTrue(out["enqueued"])
        self.assertEqual(self.log, ["pin", f"graphql-enqueue:id=PR_self:head={HEAD}"])
        self.assertEqual(out["merge"]["api"], "graphql")

    def test_no_write_runs_under_the_read_token(self) -> None:
        # The job hands the gate its read-only token for reads; the pin
        # comment and the enqueue must still go out under the lane token.
        self._async_merge = REAL_ASYNC_MERGE  # type: ignore[method-assign]
        tokens: list[tuple[list[str], str | None]] = []
        record = self._capture

        def capture(args: list[str], **kwargs: Any) -> Any:
            env = kwargs.get("env_overrides") or {}
            tokens.append((args, env.get("GH_TOKEN", os.environ.get("GH_TOKEN"))))
            return record(args)

        self._capture = capture  # type: ignore[method-assign]
        environ = {"GH_TOKEN": "lane-tok", "BABYSIT_VERIFY_GH_TOKEN": "read-tok"}
        with mock.patch.dict("os.environ", environ):
            code, out = self.lane()
        self.assertEqual(code, 0, out["blockers"])
        self.assertEqual(self.log, ["pin", f"graphql-enqueue:id=PR_self:head={HEAD}"])
        writes = [(args, token) for args, token in tokens if is_write(args)]
        self.assertGreaterEqual(len(writes), 2)
        for args, token in writes:
            with self.subTest(" ".join(args)[:80]):
                self.assertEqual(token, "lane-tok")

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

    def closing_issue_now(self, labels: list[str], number: int = 41) -> None:
        """Run the real enqueue re-read, its closing issue `number` now."""
        self.real_lane_recheck = True
        node = {
            "closingIssuesReferences": {
                "totalCount": 1,
                "nodes": [
                    {
                        "number": number,
                        "repository": {"nameWithOwner": "owner/repo"},
                        "labels": {
                            "totalCount": len(labels),
                            "nodes": [{"name": n} for n in labels],
                        },
                    }
                ],
            }
        }
        patcher = mock.patch.object(
            policy,
            "_graphql",
            return_value={"repository": {"pullRequest": node}},
        )
        patcher.start()
        self.addCleanup(patcher.stop)

    def test_a_closing_issue_changed_before_the_enqueue_refuses(self) -> None:
        self.closing_issue_now([], number=42)
        code, out = self.lane()
        self.assert_no_merge(code)
        self.assertIn(
            "unattended merge refused: ineligible:closing-issue-changed:41>42",
            out["blockers"],
        )

    def test_a_class_label_removed_before_the_enqueue_no_longer_refuses(self) -> None:
        self.closing_issue_now([])
        code, out = self.lane()
        self.assertEqual(code, 0, out["blockers"])
        self.assertEqual(self.log, ["pin", f"enqueue:{HEAD}:merge_queue"])

    def test_the_enqueue_recheck_reads_the_eligible_issue(self) -> None:
        self.lane()
        self.assertEqual(len(self.lane_recheck_kwargs), 1)
        self.assertEqual(self.lane_recheck_kwargs[0], {"issue": 41})

    def test_a_base_retargeted_before_the_enqueue_refuses(self) -> None:
        self.closing_issue_now([])
        self.base_now = "base-not-default:release"
        code, out = self.lane()
        self.assert_no_merge(code)
        self.assertIn(
            "unattended merge refused: ineligible:base-not-default:release",
            out["blockers"],
        )
        # Read fresh at the recheck.
        self.assertEqual([(o, n) for o, n, _ in self.base_reads], [("owner", "repo")])

    def test_an_ineligible_pr_is_refused(self) -> None:
        self.lane_eligible = policy.Eligibility(False, "denied-path:.gitmodules")
        code, out = self.lane()
        self.assert_no_merge(code)
        self.assertEqual(
            out["unattended"]["reason"], "ineligible:denied-path:.gitmodules"
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

    # merge.gate-candidate-minutes: the lane passes the limit in seconds; a
    # fake clock stands in for time, and `true` for the command a read or a
    # write starts through the one subprocess seam.
    def _clocked(self, *flags: str) -> tuple[int, dict[str, Any]]:
        self.now = 0.0
        with mock.patch.object(util, "_clock", lambda: self.now):
            return self.lane(*flags)

    def _command_at(self, now: float) -> None:
        self.now = now
        util.run_command(["true"], allowed_executables=("true",))

    def test_a_read_past_the_candidate_deadline_stops_before_any_write(self) -> None:
        read_on: list[float] = []

        def slow_read(*args: Any) -> Any:
            self._command_at(241.0)
            read_on.append(self.now)
            return self.lanes, self.comments

        self._lane_evidence = slow_read  # type: ignore[method-assign]
        code, out = self._clocked("--candidate-deadline-seconds", "240")
        self.assertEqual(code, 11)
        self.assertEqual(read_on, [], "the command past the deadline started")
        self.assertEqual(out["error"].split(";")[0], "unknown:candidate-deadline")
        self.assertNotIn("ready", out)
        self.assertEqual(self.log, [])
        self.async_merge.assert_not_called()
        self.dequeue.assert_not_called()

    def test_the_same_slow_read_without_a_deadline_still_enqueues(self) -> None:
        def slow_read(*args: Any) -> Any:
            self._command_at(10_000.0)
            return self.lanes, self.comments

        self._lane_evidence = slow_read  # type: ignore[method-assign]
        code, out = self._clocked()
        self.assertEqual(code, 0, out.get("blockers"))
        self.assertEqual(self.log, ["pin", f"enqueue:{HEAD}:merge_queue"])

    def test_a_deadline_passing_during_the_enqueue_never_stops_it(self) -> None:
        def slow_enqueue(repo: str, number: int, **kwargs: Any) -> dict[str, Any]:
            self._command_at(10_000.0)
            self.log.append(f"enqueue:{kwargs['sha']}:{kwargs['merge_action']}")
            return dict(ENQUEUED)

        self._async_merge = slow_enqueue  # type: ignore[method-assign]
        code, out = self._clocked("--candidate-deadline-seconds", "240")
        self.assertEqual(code, 0, out.get("blockers"))
        self.assertTrue(out["enqueued"])
        self.assertEqual(self.log, ["pin", f"enqueue:{HEAD}:merge_queue"])

    def test_the_candidate_deadline_is_the_lane_s_alone(self) -> None:
        code, out = self.run_main("--candidate-deadline-seconds", "240")
        self.assertEqual(code, 2)
        self.assertIn("--candidate-deadline-seconds", out["error"])
        self.async_merge.assert_not_called()

    def test_a_deadline_that_is_not_positive_is_refused(self) -> None:
        for value in ("0", "-5", "nan", "inf"):
            code, out = self._clocked("--candidate-deadline-seconds", value)
            self.assertEqual(code, 2, value)
            self.assertIn("positive", out["error"])


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

    def test_a_stale_dependabot_head_is_enqueued_not_written(self) -> None:
        self.config = dataclasses.replace(
            self.config, check_inputs=("scripts/shared-copies.txt",)
        )
        stale = {"state": "stale", "mergeBase": "e" * 40, "changed": ["x"]}
        with mock.patch.object(
            merge.check_inputs, "changed_since_merge_base", return_value=stale
        ):
            code, out = self.lane()
        self.assertEqual(code, 0, out["blockers"])
        self.assertEqual(self.log, ["pin", f"enqueue:{HEAD}:merge_queue"])

    def test_an_in_flight_refusal_still_reads_the_dependabot_class(self) -> None:
        # Off the queue and refused in flight: the class is still read, so
        # the gate keeps no dependency-manager hold it would not keep anyway.
        self.flight = policy.InFlight(False, "identity-entry-queued:#9", frozenset({9}))
        self.queued = [9]
        code, out = self.lane()
        self.assert_no_merge(code)
        self.assertIn(
            merge.UNATTENDED_REFUSED + "in-flight:identity-entry-queued:#9",
            out["blockers"],
        )
        self.assertFalse(any("dependency manager" in b for b in out["blockers"]))
        self.assertEqual(out["unattended"]["dependabot"]["mode"], "enforce")

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

    def test_the_enqueue_recheck_holds_a_major_under_the_config(self) -> None:
        held = "dependabot-major-held:x"
        tier = dependabot.Classification("review", ("major:x",), approved="55-1")
        for majors, hold in (("hold", True), ("review", False)):
            with self.subTest(majors=majors):
                self.config = dataclasses.replace(self.config, dependabot_majors=majors)
                self.dependabot_kwargs = []
                self.dependabot_reads = [
                    policy.Eligibility(True, None, "C2", dependabot=tier),
                    policy.Eligibility(False, held, "C2", dependabot=tier),
                ]
                code, out = self.lane()
                self.assert_no_merge(code)
                self.assertIn(
                    f"unattended merge refused: ineligible:{held}", out["blockers"]
                )
                self.assertEqual(
                    [k["hold_majors"] for k in self.dependabot_kwargs], [hold, hold]
                )

    def test_a_lane_authored_pr_still_reads_report_only(self) -> None:
        self.pr_user = {"login": IDENTITY, "type": "Bot"}
        self.pr_view = fixtures._pr()
        self.lane_eligible = policy.Eligibility(True, None, "C2")
        self.lane_error = None
        # A lane PR needs the verdict required; Dependabot's do not.
        self.config = dataclasses.replace(self.config, require_verifier_verdict=True)
        passing = merge.verify_evidence.Evidence(None, HEAD, (), 0)
        with mock.patch.object(
            merge.verify_evidence.Reader, "evidence", return_value=passing
        ):
            code, out = self.lane()
        self.assertEqual(code, 0, out["blockers"])
        self.assertIs(out["unattended"]["reportOnly"], True)
        self.assertEqual(self.log, [])

    def test_a_lane_pr_without_the_verdict_key_is_refused(self) -> None:
        self.pr_user = {"login": IDENTITY, "type": "Bot"}
        self.pr_view = fixtures._pr()
        self.lane_eligible = policy.Eligibility(True, None, "C2")
        self.lane_error = None
        code, out = self.lane()
        self.assert_no_merge(code)
        self.assertEqual(out["unattended"]["reason"], "verifier-verdict-not-required")


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

    def test_a_cached_head_config_is_read_again_before_the_enqueue(self) -> None:
        # The gate took main's config from the run cache, read at head B.
        # Main moved to D before the enqueue: D's config is read again, and a
        # tightening there holds; an unmoved head enqueues on one head read.
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        for main_head, d_lines, enqueued in (
            ("d" * 40, 100, False),
            ("b" * 40, None, True),
        ):
            with self.subTest(main_head=main_head):
                self.setUp()
                cache = str(pathlib.Path(tmp.name, f"{main_head[0]}.json"))
                patcher = mock.patch.dict("os.environ", {"BABYSIT_RUN_CACHE": cache})
                patcher.start()
                self.addCleanup(patcher.stop)
                cached = dataclasses.replace(self.config, base_sha="b" * 40)
                policy.run_cache.put(
                    policy.DEFAULT_BRANCH_CONFIG_SECTION,
                    "owner/repo",
                    dataclasses.asdict(cached),
                )
                policy.run_cache.put(policy.MAX_IN_FLIGHT_SECTION, "owner/repo", 1)
                self.main_head = main_head
                if d_lines is not None:
                    self.head_configs = [
                        dataclasses.replace(
                            self.config, base_sha=main_head, max_changed_lines=d_lines
                        )
                    ]
                code, out = self.run_main()
                self.assertEqual(
                    f"enqueue:{HEAD}:merge_queue" in self.log, enqueued, out["blockers"]
                )
                self.assertEqual(code, 0 if enqueued else 10)
                if not enqueued:
                    self.assertTrue(
                        any("merge config changed" in b for b in out["blockers"]),
                        out["blockers"],
                    )

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

    def test_a_landed_entry_read_back_under_a_cap_with_room_exits_zero(self) -> None:
        # At a cap of 5 the landed merge leaves room, so no refusal stands.
        self.config = dataclasses.replace(self.config, max_in_flight=5)
        self.flight = policy.InFlight(True, None, frozenset(), 1)
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
        self.assertIs(out["unattended"]["dispatched"], True)
        self.assertEqual(code, 0)

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

    def test_an_authority_differing_on_the_default_branch_dequeues_the_identitys_entries(
        self,
    ) -> None:
        # Switching merge.authority on main stops the lane as rung: off does,
        # so the identity's queued entries leave.
        # Unsetting merge.agent-identity on main switches the lane off too.
        for change in ({"authority": "pr-merge"}, {"agent_identity": None}):
            with self.subTest(change=change):
                self.setUp()
                self.main_head = "d" * 40
                self.head_configs = [
                    dataclasses.replace(self.config, base_sha=self.main_head, **change)
                ]
                code, out = self.run_main()
                self.assert_no_merge(code)
                self.assertEqual(out["unattended"]["reason"], "authority-differs")
                self.assertEqual(self.log, ["dequeue:all"])

    def test_another_identity_on_the_default_branch_dequeues_the_identitys_entries(
        self,
    ) -> None:
        self.main_head = "d" * 40
        self.head_configs = [
            dataclasses.replace(
                self.config, base_sha=self.main_head, agent_identity="other[bot]"
            )
        ]
        code, out = self.run_main()
        self.assert_no_merge(code)
        self.assertEqual(out["unattended"]["reason"], "authority-differs")
        self.assertEqual(self.log, ["dequeue:all"])

    def test_an_unparsable_default_branch_config_dequeues_the_identitys_entries(
        self,
    ) -> None:
        self.main_head = "d" * 40
        self.head_configs = [
            dataclasses.replace(
                self.config, base_sha=self.main_head, error="config-parse-error"
            )
        ]
        code, out = self.run_main()
        self.assert_no_merge(code)
        self.assertEqual(out["unattended"]["reason"], "default-branch-unreadable")
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

    def test_a_lane_run_listing_at_the_search_cap_binds_no_lane(self) -> None:
        # collect_lane_runs raises on a listing at the search cap.
        self.lane_error = RuntimeError(
            "pr-review-hosted.yml runs: total_count 1000, 1000 returned, "
            "at the 1000-run search cap"
        )
        code, out = self.run_main()
        self.assert_no_merge(code)
        self.assertEqual(
            {(e["bound"], e["unboundReason"]) for e in out["unattended"]["evidence"]},
            {(False, "evidence-missing")},
        )

    def test_a_rate_limited_evidence_read_holds_the_candidate(self) -> None:
        # A rate-limited evidence read binds no lane, so the candidate holds
        # until a later run reads again.
        self.lane_error = RuntimeError(
            "gh api repos/owner/repo/issues/1/timeline failed: gh: API rate limit"
            " exceeded for installation ID 4242. (HTTP 403)"
        )
        code, out = self.run_main()
        self.assert_no_merge(code)
        self.assertEqual(
            {(e["bound"], e["unboundReason"]) for e in out["unattended"]["evidence"]},
            {(False, "evidence-missing")},
        )

    def test_an_armed_auto_merge_is_disarmed_and_refused(self) -> None:
        self.queue = fixtures._queue_read(required=True, armed=True)
        code, out = self.run_main()
        self.assert_no_merge(code)
        self.assertEqual(self.log, ["disarm"])
        self.assertIs(out["unattended"]["enqueue"]["disarmed"], True)

    def test_a_head_the_queue_ejected_twice_is_not_enqueued_again(self) -> None:
        self.queue = fixtures._queue_read(required=True, failed_ejections=2)
        with mock.patch.object(merge, "_failed_merge_group_runs", return_value=[]):
            code, out = self.run_main()
        self.assert_no_merge(code)
        self.assertFalse([e for e in self.log if not e.startswith("write:")], self.log)
        self.assertTrue(
            any("queue-ejected:2" in b and HEAD in b for b in out["blockers"]),
            out["blockers"],
        )

    def test_a_refused_head_gets_one_marked_comment_naming_its_runs(self) -> None:
        self.queue = fixtures._queue_read(required=True, failed_ejections=2)
        url = "https://github.com/owner/repo/actions/runs/7"
        with mock.patch.object(
            merge, "_failed_merge_group_runs", return_value=[url]
        ) as runs:
            code, out = self.run_main()
        self.assert_no_merge(code)
        runs.assert_called_once_with("owner/repo", "main", PR)
        (write,) = [
            c.args[0]
            for c in self.capture.call_args_list
            if any(merge.QUEUE_EJECTION_MARKER in a for a in c.args[0])
        ]
        self.assertIn("POST", write)
        body = write[-1].removeprefix("body=")
        self.assertTrue(body.startswith(merge.QUEUE_EJECTION_MARKER + "\n"))
        self.assertIn(f"`{HEAD}`", body)
        self.assertIn(url, body)
        self.assertIn("A push resets the count.", body)
        self.assertEqual(out["unattended"]["enqueue"]["ejectionComment"], "created")
        # A rerun finds the same comment and writes nothing.
        self.comments = [
            {
                "id": 91,
                "user": {"login": IDENTITY, "type": "Bot"},
                "created_at": "2026-10-12T10:00:00Z",
                "body": body,
            }
        ]
        self.capture.reset_mock()
        with mock.patch.object(merge, "_failed_merge_group_runs", return_value=[url]):
            _, out = self.run_main()
        self.assertEqual(out["unattended"]["enqueue"]["ejectionComment"], "unchanged")
        self.assertFalse(
            any(
                merge.QUEUE_EJECTION_MARKER in a
                for c in self.capture.call_args_list
                for a in c.args[0]
            )
        )

    def test_one_ejection_still_enqueues(self) -> None:
        self.queue = fixtures._queue_read(required=True, failed_ejections=1)
        code, out = self.run_main()
        self.assertEqual(code, 0, out["blockers"])
        self.assertEqual(self.log, ["pin", f"enqueue:{HEAD}:merge_queue"])

    def test_the_ejection_cap_is_the_configured_one(self) -> None:
        self.config = dataclasses.replace(self.config, max_queue_ejections=3)
        self.queue = fixtures._queue_read(required=True, failed_ejections=2)
        code, out = self.run_main()
        self.assertEqual(code, 0, out["blockers"])

    def test_unreadable_ejections_refuse_the_enqueue(self) -> None:
        self.queue = fixtures._queue_read(required=True, failed_ejections=None)
        code, out = self.run_main()
        self.assert_no_merge(code)
        self.assertEqual(self.log, [])

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

    BINARY = dataclasses.replace(
        LOW_FILE, path="docs/logo.png", has_patch=False, patch=None
    )

    def test_a_med_on_path_reasons_alone_merges(self) -> None:
        # #9270: both lanes bound and clean, the only reason a path's.
        self.files = ((self.BINARY,), True)
        code, out = self.run_main()
        self.assertEqual(code, 0, out["blockers"])
        self.assertEqual(out["unattended"]["risk"]["score"], "MED")
        self.assertIsNone(out["unattended"]["reason"])
        self.assertEqual(self.log, ["pin", f"enqueue:{HEAD}:merge_queue"])

    def test_a_med_with_an_open_code_review_finding_merges(self) -> None:
        # Q25: a code-review finding is reported and does not hold.
        self.files = ((self.BINARY,), True)
        self.lanes = (LaneEvidence("claude-review", True, None, 1), BOUND[1])
        code, out = self.run_main()
        self.assertEqual(code, 0, out["blockers"])
        self.assertIsNone(out["unattended"]["reason"])
        codes = [r["code"] for r in out["unattended"]["risk"]["reasons"]]
        self.assertIn("findings:claude-review", codes)
        self.assertEqual(self.log, ["pin", f"enqueue:{HEAD}:merge_queue"])

    def test_a_critical_security_finding_holds(self) -> None:
        self.files = ((self.BINARY,), True)
        self.lanes = (
            BOUND[0],
            LaneEvidence("claude-security-review", True, None, 2, False, 1),
        )
        code, out = self.run_main()
        self.assert_no_merge(code)
        self.assertEqual(out["unattended"]["reason"], "risk:HIGH")

    def test_a_med_with_an_unbound_lane_holds(self) -> None:
        self.files = ((self.BINARY,), True)
        self.lanes = (BOUND[0], UNBOUND[1])
        code, out = self.run_main()
        self.assert_no_merge(code)
        self.assertEqual(out["unattended"]["reason"], "risk:MED")

    def test_a_cost_hold_holds(self) -> None:
        patch = "@@ -1,1 +1,1 @@\n-  max-in-flight: 5\n+  max-in-flight: 50"
        pipeline = dataclasses.replace(
            LOW_FILE, path="docs/conventions/pr-pipeline.yaml", patch=patch
        )
        self.files = ((pipeline,), True)
        code, out = self.run_main()
        self.assert_no_merge(code)
        self.assertEqual(out["unattended"]["reason"], "risk:HIGH")
        codes = [r["code"] for r in out["unattended"]["risk"]["reasons"]]
        self.assertEqual(codes, ["cost-review-required"])


class BaseConfigParseError(Unattended):
    """A base whose pipeline config the reader rejects answers to the default
    branch head's config alone; a base read failure still refuses."""

    def setUp(self) -> None:
        super().setUp()
        self.main_head = "d" * 40
        self.base_read: Any = dataclasses.replace(
            self.config, rung="off", error="config-parse-error"
        )
        self.main_read: Any = dataclasses.replace(self.config, base_sha=self.main_head)

    def _read_config_at(self, repo: str, sha: str, *args: Any) -> Any:
        read = self.base_read if sha == BASE else self.main_read
        if isinstance(read, Exception):
            raise read
        return read

    def test_the_default_branch_head_config_stands_in_for_an_unparsable_base(
        self,
    ) -> None:
        code, out = self.run_main()
        self.assertEqual(code, 0, out.get("blockers"))
        self.assertIsNone(out["unattended"]["reason"])
        self.assertEqual(
            out["unattended"]["baseConfigFallback"],
            f"{policy.CONFIG_PATH} at {BASE}: config-parse-error; "
            f"read at the default branch head {self.main_head}",
        )
        self.assertEqual(self.log, ["pin", f"enqueue:{HEAD}:merge_queue"])

    def test_the_floor_is_read_from_the_default_branch_head_history(self) -> None:
        # The real `enabled_since` walks the history of the commit the config
        # came from; the base's own history holds only unparsable configs.
        self.real_enabled_since = True
        local = mock.patch.object(policy, "_local_history", return_value=None)
        local.start()
        self.addCleanup(local.stop)
        code, out = self.run_main()
        self.assertEqual(code, 0, out.get("blockers"))
        self.assertIsNone(out["unattended"]["reason"])
        self.assertEqual(out["unattended"]["mergedSince"], "2026-10-01T00:00:00+00:00")

    def _get(self, endpoint: str) -> tuple[int | None, Any]:
        if endpoint.startswith("repos/owner/repo/commits?sha="):
            sha = endpoint.split("sha=", 1)[1].split("&", 1)[0]
            commit = {"committer": {"date": "2026-10-01T00:00:00Z"}}
            return 200, [{"sha": sha, "commit": commit}]
        return super()._get(endpoint)

    def test_an_unparsable_default_branch_config_too_refuses(self) -> None:
        self.main_read = dataclasses.replace(self.main_read, error="config-parse-error")
        code, out = self.run_main()
        self.assert_no_merge(code)
        self.assertIn("unattended merge policy unreadable", out["error"])
        self.assertIn(
            f"at the default branch head {self.main_head}: config-parse-error",
            out["error"],
        )
        self.assertEqual(self.log, [])

    def test_a_base_read_failure_refuses_without_the_fallback(self) -> None:
        self.base_read = policy.PolicyReadError("pr-pipeline.yaml (status 502)")
        code, out = self.run_main()
        self.assert_no_merge(code)
        self.assertIn("status 502", out["error"])
        self.assertEqual(self.log, [])


class CheckInputsChangedOnTheBase(Unattended):
    """A ready head whose merge base predates a base change to a
    `merge.check-inputs` path is updated from the base, not enqueued."""

    MERGE_BASE = "e" * 40
    UPDATE = f"repos/owner/repo/pulls/{PR}/update-branch"

    def setUp(self) -> None:
        super().setUp()
        self.config = dataclasses.replace(
            self.config, check_inputs=("scripts/shared-copies.txt",)
        )
        self.update_code = 0
        self.update_stdout = (
            '{"message":"Resource not accessible by integration","status":"403"}'
        )
        self.update_stderr = "gh: Resource not accessible by integration (HTTP 403)"
        self.update_failure: Exception | None = None
        self.inputs_reads: list[tuple[Any, ...]] = []
        self.inputs_kwargs: list[dict[str, Any]] = []
        self.inputs_answer: dict[str, Any] = {
            "state": "stale",
            "mergeBase": self.MERGE_BASE,
            "baseTip": BASE,
            "changed": ["scripts/shared-copies.txt"],
        }

    def _capture(self, args: list[str]) -> Any:
        if self.UPDATE in args:
            self.log.append("update-branch:" + args[-1])
            if self.update_failure is not None:
                raise self.update_failure
            if self.update_code == 0:
                return subprocess.CompletedProcess(args, 0, "{}", "")
            return subprocess.CompletedProcess(
                args, self.update_code, self.update_stdout, self.update_stderr
            )
        return super()._capture(args)

    def run_main(self, *flags: str, merge_flag: bool = True) -> Any:
        def read(*args: Any, **kwargs: Any) -> dict[str, Any]:
            self.inputs_reads.append(args)
            self.inputs_kwargs.append(kwargs)
            return dict(self.inputs_answer)

        with mock.patch.object(
            merge.check_inputs, "changed_since_merge_base", side_effect=read
        ):
            return super().run_main(*flags, merge_flag=merge_flag)

    def test_a_stale_head_is_updated_from_the_base_and_not_enqueued(self) -> None:
        code, out = self.run_main()
        self.assert_no_merge(code)
        self.assertEqual(self.log, [f"update-branch:expected_head_sha={HEAD}"])
        self.assertEqual(
            self.inputs_reads, [(("scripts/shared-copies.txt",), HEAD, "main")]
        )
        (blocker,) = [b for b in out["blockers"] if "check-inputs-changed:" in b]
        self.assertIn("scripts/shared-copies.txt", blocker)
        self.assertIn(self.MERGE_BASE, blocker)
        self.assertIs(out["unattended"]["enqueue"]["checkInputs"]["updated"], True)

    def test_the_default_branch_heads_own_list_is_read_on_its_own(self) -> None:
        self.main_head = "d" * 40
        head = dataclasses.replace(
            self.config, base_sha=self.main_head, check_inputs=("docs/x.txt",)
        )
        self.head_configs = [head, head]
        self.run_main()
        self.assertEqual(
            self.inputs_reads, [(("scripts/shared-copies.txt",), HEAD, "main")]
        )
        self.assertEqual(self.inputs_kwargs, [{"extra": ("docs/x.txt",)}])

    def test_an_unchanged_or_unknown_read_enqueues_as_before(self) -> None:
        for state in ("current", "unknown", "off"):
            with self.subTest(state=state):
                self.log = []
                self.inputs_answer = {"state": state}
                code, out = self.run_main()
                self.assertEqual(code, 0, out["blockers"])
                self.assertEqual(self.log, ["pin", f"enqueue:{HEAD}:merge_queue"])

    def test_a_refused_update_enqueues_as_before(self) -> None:
        self.update_code = 1
        code, out = self.run_main()
        self.assertEqual(code, 0, out["blockers"])
        self.assertEqual(
            self.log,
            [
                f"update-branch:expected_head_sha={HEAD}",
                "pin",
                f"enqueue:{HEAD}:merge_queue",
            ],
        )
        read = out["unattended"]["enqueue"]["checkInputs"]
        self.assertIs(read["updated"], False)
        self.assertEqual(
            read["updateError"],
            {"status": 403, "message": "Resource not accessible by integration"},
        )

    def test_a_standards_sync_head_is_never_updated(self) -> None:
        # The sync App is the branch's only writer: a merge commit from the
        # base fails the managed-files guard, so the head enqueues as before.
        self.pr_labels = [{"name": "Standards-Sync"}]
        code, out = self.run_main()
        self.assertEqual(code, 0, out["blockers"])
        self.assertEqual(self.log, ["pin", f"enqueue:{HEAD}:merge_queue"])
        read = out["unattended"]["enqueue"]["checkInputs"]
        self.assertIs(read["updated"], False)
        self.assertIn("'standards-sync'", read["updateSkipped"])

    def test_the_standards_sync_label_comes_from_the_tracker_config(self) -> None:
        def read(owner: str, name: str, **kwargs: Any) -> str:
            if kwargs.get("role") == "standards-sync":
                return "sync-managed"
            return "needs-human"

        with mock.patch.object(postmerge, "_role_label", side_effect=read):
            self.pr_labels = [{"name": "sync-managed"}]
            self.run_main()
            self.assertEqual(self.log, ["pin", f"enqueue:{HEAD}:merge_queue"])
            # The unmapped default no longer skips the update.
            self.log = []
            self.pr_labels = [{"name": "standards-sync"}]
            self.run_main()
            self.assertEqual(self.log, [f"update-branch:expected_head_sha={HEAD}"])

    def test_an_unreadable_standards_sync_label_holds(self) -> None:
        # Neither updated nor enqueued: a stale head fails the queue's merge.
        def read(owner: str, name: str, **kwargs: Any) -> str:
            if kwargs.get("role") == "standards-sync":
                raise postmerge.PostMergeReadError("tracker: HTTP 502")
            return "needs-human"

        with mock.patch.object(postmerge, "_role_label", side_effect=read):
            code, out = self.run_main()
        self.assert_no_merge(code)
        self.assertEqual(self.log, [])
        self.assertTrue(
            any(
                "standards-sync role label is unreadable" in b for b in out["blockers"]
            ),
            out["blockers"],
        )

    SHARED_COPY_LABEL = (
        f"write:api -X POST repos/owner/repo/issues/{PR}/labels -f labels[]=needs-human"
    )

    def refuse_shared_copy(self) -> tuple[int, dict[str, Any]]:
        self.inputs_answer["changed"] = ["lib/a.sh"]
        self.inputs_answer["regenerate"] = ["lib/a.sh"]
        return self.run_main()

    def test_a_carried_canonical_changed_on_the_base_is_refused_and_escalated(
        self,
    ) -> None:
        # Updating merges the base's canonical but leaves the copies the PR
        # generated from its own, so only a merge plus a regeneration clears
        # it, and no lane acts on the refusal: a person is asked, once.
        code, out = self.refuse_shared_copy()
        self.assert_no_merge(code)
        (comment,) = [e for e in self.log if "/issues/" in e and "/comments" in e]
        self.assertEqual(self.log, [comment, self.SHARED_COPY_LABEL])
        self.assertNotIn("update-branch", " ".join(self.log))
        body = comment.split(" -f body=", 1)[1]
        self.assertEqual(body.split("\n")[0], merge.SHARED_COPY_ESCALATION_MARKER)
        self.assertIn(f" at head `{HEAD}`", body.split("\n")[1])
        for text in (
            "shared-copy-sources-changed:lib/a.sh",
            "`lib/a.sh`",
            self.MERGE_BASE,
            "scripts/sync-shared-copies.sh",
            "push",
        ):
            self.assertIn(text, body)
        (blocker,) = [b for b in out["blockers"] if "shared-copy-sources-changed:" in b]
        self.assertIn("lib/a.sh", blocker)
        self.assertIn(self.MERGE_BASE, blocker)
        self.assertIn("scripts/sync-shared-copies.sh", blocker)
        self.assertEqual(
            out["unattended"]["enqueue"]["escalation"],
            {"label": "added", "comment": "created"},
        )

    def test_a_rerun_at_the_same_head_does_not_escalate_twice(self) -> None:
        self.refuse_shared_copy()
        body = self.log[0].split(" -f body=", 1)[1]
        self.log = []
        self.comments = [
            {
                "id": 81,
                "user": {"login": IDENTITY, "type": "Bot"},
                "created_at": "2026-10-12T10:00:00Z",
                "updated_at": "2026-10-12T10:00:00Z",
                "body": body,
            }
        ]
        self.pr_labels = [{"name": "needs-human"}]
        code, out = self.refuse_shared_copy()
        self.assert_no_merge(code)
        self.assertEqual(self.log, [])
        self.assertEqual(
            out["unattended"]["enqueue"]["escalation"],
            {"label": "present", "comment": "unchanged"},
        )

    def assert_held_after_update(self, code: int, out: Any) -> None:
        self.assert_no_merge(code)
        self.assertEqual(self.log, [f"update-branch:expected_head_sha={HEAD}"])
        (blocker,) = [b for b in out["blockers"] if "check-inputs-changed:" in b]
        self.assertIn("may have landed", blocker)

    def test_an_update_that_times_out_holds(self) -> None:
        # The update may have landed, so the old head is not pinned.
        self.update_failure = RuntimeError("gh api timed out after 30s")
        code, out = self.run_main()
        self.assert_held_after_update(code, out)
        read = out["unattended"]["enqueue"]["checkInputs"]
        self.assertIsNone(read["updated"])
        self.assertEqual(
            read["updateError"],
            {"status": None, "message": "gh api timed out after 30s"},
        )

    def test_an_update_with_no_status_or_a_server_error_holds(self) -> None:
        for stderr in ("Post: context deadline exceeded", "gh: Bad gateway (HTTP 502)"):
            with self.subTest(stderr=stderr):
                self.log = []
                self.update_code, self.update_stdout = 1, ""
                self.update_stderr = stderr
                code, out = self.run_main()
                self.assert_held_after_update(code, out)
                read = out["unattended"]["enqueue"]["checkInputs"]
                self.assertIsNone(read["updated"])

    def test_a_kill_switch_stop_writes_no_update(self) -> None:
        self.kill = [PROCEED, policy.KillSwitch(False, "disabled")]
        code, _ = self.run_main()
        self.assert_no_merge(code)
        self.assertFalse(any(e.startswith("update-branch") for e in self.log))


class UpdateError(unittest.TestCase):
    def test_a_body_that_is_not_json_keeps_the_stderr_status_and_text(self) -> None:
        proc = subprocess.CompletedProcess([], 1, "not json", "gh: Bad (HTTP 422)\n")
        self.assertEqual(
            merge.update_error(proc), {"status": 422, "message": "gh: Bad (HTTP 422)"}
        )

    def test_no_status_is_none(self) -> None:
        proc = subprocess.CompletedProcess([], 1, "", "timed out")
        self.assertEqual(
            merge.update_error(proc), {"status": None, "message": "timed out"}
        )


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

    def test_a_cap_of_five_keeps_an_entry_within_the_room(self) -> None:
        # Three earlier entries and one unverified merge: four in flight, so
        # this fifth entry stays; with two unverified merges it leaves.
        self.config = dataclasses.replace(self.config, max_in_flight=5)
        earlier = [entry(5 + i, f"2026-10-12T09:5{i}:00Z", f"PR_{i}") for i in range(3)]
        self.entries = [*earlier, entry(PR, "2026-10-12T10:00:00Z", "PR_self")]
        for unverified, kept in ((1, True), (2, False)):
            with self.subTest(unverified=unverified):
                self.log.clear()
                self.flight = policy.InFlight(True, None, frozenset(), unverified)
                code, out = self.run_main()
                self.assertIs(out["enqueued"], kept)
                self.assertEqual(
                    "dequeue-self:id=PR_self" in self.log, not kept, self.log
                )
                self.assertEqual(code, 0 if kept else 10)

    def test_the_room_check_reads_the_cap_again_not_from_the_run_cache(
        self,
    ) -> None:
        # Another gate process saved a cap of 1; the head's is 5, so the
        # fifth entry stays only on a fresh read.
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        path = str(pathlib.Path(tmp.name, "run.json"))
        patcher = mock.patch.dict("os.environ", {run_cache.ENV: path})
        patcher.start()
        self.addCleanup(patcher.stop)
        run_cache.put(policy.MAX_IN_FLIGHT_SECTION, "owner/repo", 1)
        self.config = dataclasses.replace(self.config, max_in_flight=5)
        earlier = [entry(5 + i, f"2026-10-12T09:5{i}:00Z", f"PR_{i}") for i in range(3)]
        self.entries = [*earlier, entry(PR, "2026-10-12T10:00:00Z", "PR_self")]
        self.flight = policy.InFlight(True, None, frozenset(), 1)
        code, out = self.run_main()
        self.assertIs(out["enqueued"], True)
        self.assertNotIn("dequeue-self:id=PR_self", self.log)
        self.assertEqual(code, 0)

    def test_the_room_check_reads_the_cap_at_the_default_branch_head(
        self,
    ) -> None:
        # Three earlier entries and one unverified merge: the fifth entry
        # stays only at a cap of 5, read at main's head, not at the base.
        self.main_head = "d" * 40
        earlier = [entry(5 + i, f"2026-10-12T09:5{i}:00Z", f"PR_{i}") for i in range(3)]
        self.flight = policy.InFlight(True, None, frozenset(), 1)
        for base_cap, head_cap, kept in ((1, 5, True), (5, 1, False)):
            with self.subTest(base_cap=base_cap, head_cap=head_cap):
                self.log.clear()
                self.config = dataclasses.replace(self.config, max_in_flight=base_cap)
                head = dataclasses.replace(self.config, max_in_flight=head_cap)
                self.head_configs = [head, head, head]
                self.entries = [*earlier, entry(PR, "2026-10-12T10:00:00Z", "PR_self")]
                code, out = self.run_main()
                self.assertEqual(out["unattended"]["inFlight"]["cap"], head_cap)
                self.assertIs(out["enqueued"], kept)
                self.assertEqual(
                    "dequeue-self:id=PR_self" in self.log, not kept, self.log
                )

    def test_a_failed_room_check_read_keeps_the_lower_applied_cap(self) -> None:
        # The gate applied main's cap of 1; the re-read fails, and the base's
        # 5 would leave room, so the lower cap holds and the entry leaves.
        self.main_head = "d" * 40
        self.config = dataclasses.replace(self.config, max_in_flight=5)
        self.head_configs = [
            dataclasses.replace(self.config, max_in_flight=1),
            dataclasses.replace(self.config, max_in_flight=1),
            policy.PolicyReadError("HTTP 502"),
        ]
        earlier = [entry(5 + i, f"2026-10-12T09:5{i}:00Z", f"PR_{i}") for i in range(3)]
        self.entries = [*earlier, entry(PR, "2026-10-12T10:00:00Z", "PR_self")]
        self.flight = policy.InFlight(True, None, frozenset(), 0)
        code, out = self.run_main()
        self.assertIn("dequeue-self:id=PR_self", self.log)
        self.assertIs(out["enqueued"], False)
        self.assertEqual(code, 10)

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


class TheQueueSweepIsSharedPerRun(Unattended):
    """pr-merge.yml runs one gate process per candidate and names a file in
    `BABYSIT_RUN_CACHE`: another queued entry one process judged and kept is
    not judged again by the next within the bound, and nothing else is
    shared. Each `run_main` here is one candidate's gate process."""

    def setUp(self) -> None:
        super().setUp()
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        path = str(pathlib.Path(tmp.name, "run.json"))
        patcher = mock.patch.dict("os.environ", {"BABYSIT_RUN_CACHE": path})
        patcher.start()
        self.addCleanup(patcher.stop)
        self.flight = policy.InFlight(False, "identity-entry-queued:#5")
        self.queued = [PR, 5]

    def candidates(self, count: int) -> None:
        for _ in range(count):
            code, _ = self.run_main()
            self.assert_no_merge(code)

    def test_a_kept_entry_is_judged_once_across_candidates(self) -> None:
        self.candidates(3)
        self.assertEqual(self.hold_reads.count(5), 1)
        # A gate always judges its own entry.
        self.assertEqual(self.hold_reads.count(PR), 3)
        self.assertEqual(self.log, [])

    def test_a_kept_entry_is_judged_again_past_the_bound(self) -> None:
        clock = [datetime(2026, 10, 18, 12, 0, tzinfo=UTC)]
        with mock.patch("babysit_run_cache.now", side_effect=lambda: clock[0]):
            self.candidates(1)
            clock[0] += merge.run_cache.MAX_AGE
            self.candidates(1)
            clock[0] += timedelta(seconds=1)
            self.candidates(1)
        self.assertEqual(self.hold_reads.count(5), 2)

    def test_a_held_entry_is_judged_by_every_candidate(self) -> None:
        self.holds = {5: "do-not-merge"}
        self.candidates(2)
        self.assertEqual(self.hold_reads.count(5), 2)
        self.assertEqual(self.log, ["dequeue:[5]", "dequeue:[5]"])

    def test_a_failed_dequeue_keeps_nothing(self) -> None:
        self.queued = [PR, 5, 6]
        self.holds = {6: "do-not-merge"}
        self.dequeue_error = postmerge.PostMergeWriteError("dequeue #6: boom")
        self.candidates(2)
        self.assertEqual(self.hold_reads.count(5), 2)

    def test_a_kept_entry_is_dated_by_its_oldest_shared_read(self) -> None:
        # The hold read uses a permission another process shared 90 s before
        # the judgment, so the entry is kept as of then and judged again by
        # the candidate 31 s later.
        self.permission_reader = policy.permission_reader
        self.hold_hook = lambda kwargs: kwargs["permission"](OPERATOR_LOGIN) and None
        start = datetime(2026, 10, 18, 12, 0, tzinfo=UTC)
        clock = [start - timedelta(seconds=90)]
        with (
            mock.patch("babysit_run_cache.now", side_effect=lambda: clock[0]),
            mock.patch.object(
                policy, "_get", return_value=(200, {"permission": "write"})
            ),
        ):
            merge.run_cache.put("permission", f"owner/repo|{OPERATOR_LOGIN}", "write")
            for seconds in (90, 121):
                clock[0] = start - timedelta(seconds=90) + timedelta(seconds=seconds)
                self.candidates(1)
        self.assertEqual(self.hold_reads.count(5), 2)
        self.assertEqual(self.log, [])  # kept both times, never dequeued

    def test_without_the_file_every_candidate_judges_every_entry(self) -> None:
        with mock.patch.dict("os.environ", {"BABYSIT_RUN_CACHE": ""}):
            self.candidates(2)
        self.assertEqual(self.hold_reads.count(5), 2)


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


class FloorReadsCapabilityText(Unattended):
    """With the floor on, the scorer gets each capability file's base and head
    text, so a prose-only SKILL.md edit scores LOW instead of unreadable."""

    def test_a_prose_only_skill_edit_scores_low(self) -> None:
        self.config = dataclasses.replace(self.config, high_path_floor=True)
        path = "plugins/foo/skills/bar/SKILL.md"
        self.files = (
            (ChangedFile(path, None, "modified", 1, 1, True, "100644", "100644"),),
            True,
        )
        front = "---\nname: bar\ndescription: y\n---\n\n"
        texts = {BASE: front + "Old prose.\n", HEAD: front + "New prose.\n"}
        policy._TEXT_AT.clear()
        self.addCleanup(policy._TEXT_AT.clear)
        with mock.patch.object(
            policy, "_file_at", side_effect=lambda o, n, p, sha: texts[sha]
        ):
            code, out = self.run_main(merge_flag=False)
        self.assertEqual(code, 0, out["blockers"])
        self.assertEqual(out["unattended"]["risk"]["score"], "LOW")


class CostHold(Unattended):
    """A change that could add or raise a charge refuses as risk:HIGH unless
    the body cites an owner decision; the decision is read only then."""

    PULUMI = ChangedFile(
        "infra/Pulumi.yaml", None, "modified", 1, 1, True, "100644", "100644"
    )

    def run_with_decision(self, decision: str | None) -> tuple[Any, dict[str, Any]]:
        read = mock.Mock(return_value=decision)
        with mock.patch.object(policy, "cost_decision", read):
            code, out = self.run_main(merge_flag=False)
        # A refusal exits 10, as every refused unattended check does.
        self.assertEqual(code, 0 if out["unattended"]["reason"] is None else 10)
        return read, out["unattended"]

    def test_a_cost_change_waits_for_a_human(self) -> None:
        self.files = ((LOW_FILE, self.PULUMI), True)
        read, out = self.run_with_decision(None)
        self.assertEqual(out["risk"]["score"], "HIGH")
        self.assertEqual(out["reason"], "risk:HIGH")
        codes = [r["code"] for r in out["risk"]["reasons"]]
        self.assertEqual(codes, ["cost-review-required"])
        read.assert_called_once()
        self.assertEqual(read.call_args.args[2], 40)

    def test_a_cited_owner_decision_clears_it(self) -> None:
        self.files = ((LOW_FILE, self.PULUMI), True)
        link = "https://github.com/owner/repo/issues/40#issuecomment-7"
        read, out = self.run_with_decision(link)
        self.assertEqual(out["risk"]["score"], "LOW")
        self.assertEqual(out["costDecision"], link)

    def test_a_raised_timeout_holds_only_on_a_model_workflow(self) -> None:
        # The gate reads the workflow's head text, floor off, to see its legs.
        workflow = ChangedFile(
            ".github/workflows/x.yml",
            None,
            "modified",
            1,
            1,
            True,
            "100644",
            "100644",
            patch="@@ -1 +1 @@\n-    timeout-minutes: 30\n+    timeout-minutes: 45",
        )
        self.files = ((workflow,), True)
        for text, held in (
            ("      - uses: anthropics/claude-code-action@abc\n", True),
            ("      - run: make\n", False),
        ):
            with self.subTest(held=held):
                policy._TEXT_AT.clear()
                self.addCleanup(policy._TEXT_AT.clear)
                with mock.patch.object(policy, "_file_at", return_value=text):
                    read, out = self.run_with_decision(None)
                codes = [r["code"] for r in out["risk"]["reasons"]]
                self.assertEqual("cost-review-required" in codes, held)

    def test_a_record_without_visibility_reads_as_not_public(self) -> None:
        # The harness record carries no base.repo.private: a standard runner
        # charges until the repository is known to be public.
        workflow = ChangedFile(
            ".github/workflows/x.yml",
            None,
            "modified",
            1,
            0,
            True,
            "100644",
            "100644",
            patch="@@ -1 +1,2 @@\n jobs:\n+    runs-on: ubuntu-24.04",
        )
        self.files = ((workflow,), True)
        policy._TEXT_AT.clear()
        self.addCleanup(policy._TEXT_AT.clear)
        head = "jobs:\n  a:\n    runs-on: ubuntu-24.04\n"
        with mock.patch.object(
            policy,
            "_file_at",
            side_effect=lambda o, n, p, sha: head if sha == HEAD else "jobs:\n",
        ):
            read, out = self.run_with_decision(None)
        codes = [r["code"] for r in out["risk"]["reasons"]]
        self.assertIn("cost-review-required", codes)

    def test_a_non_cost_change_reads_no_decision(self) -> None:
        read, out = self.run_with_decision("unused")
        self.assertEqual(out["risk"]["score"], "LOW")
        read.assert_not_called()
        self.assertNotIn("costDecision", out)


class LaneEvidenceGetsTheChangedPaths(Unattended):
    """The review evidence is bound against the diff's paths, both sides of
    a rename, and against None when the file list is incomplete."""

    def test_every_changed_path_reaches_the_lane_evidence(self) -> None:
        moved = ChangedFile(
            "docs/b.md", "docs/a.md", "renamed", 0, 0, True, "100644", "100644"
        )
        self.files = ((LOW_FILE, moved), True)
        self.run_main(merge_flag=False)
        self.assertEqual(
            set(self.lane_args[-1]), {"docs/guide.md", "docs/b.md", "docs/a.md"}
        )

    def test_an_incomplete_file_list_passes_none(self) -> None:
        self.files = ((LOW_FILE,), False)
        self.run_main(merge_flag=False)
        self.assertIsNone(self.lane_args[-1])


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

    def test_a_floor_hold_says_a_human_merges_it(self) -> None:
        # Owner decision Q648: only the owner merges a floor-held PR.
        self.files = ((dataclasses.replace(LOW_FILE, path=".gitmodules"),), True)
        self.run_main()
        body = next(
            c.args[0][-1]
            for c in self.capture.call_args_list
            if "babysit-merge-risk" in " ".join(c.args[0])
        )
        self.assertIn("high-path:**/.gitmodules", body)
        self.assertIn("a human merges it in person, never an agent or a lane", body)

    def test_a_trust_gate_hold_says_a_human_merges_it(self) -> None:
        # A trusted-actor widening waits for the owner.
        gate = merge.babysit_risk.Reason(
            merge.babysit_risk.TRUST_GATE_CODE,
            merge.babysit_risk.Risk.HIGH,
            "x",
        )
        risk = merge.babysit_risk.RiskResult(merge.babysit_risk.Risk.HIGH, (gate,))
        self.assertIn(
            "a human merges it in person, never an agent or a lane",
            merge.risk_comment_body(risk, HEAD),
        )

    def test_a_med_hold_does_not_claim_the_floor(self) -> None:
        self.assertNotIn("never an agent", self.body())

    def test_an_unsafe_path_hold_does_not_claim_the_floor(self) -> None:
        # A symlink or unreadable list scores this code with the floor off.
        unsafe = merge.babysit_risk.Reason(
            merge.babysit_risk.UNSAFE_PATH_CODE, merge.babysit_risk.Risk.HIGH, "x"
        )
        risk = merge.babysit_risk.RiskResult(merge.babysit_risk.Risk.HIGH, (unsafe,))
        self.assertNotIn("never an agent", merge.risk_comment_body(risk, HEAD))

    LABEL = (
        f"write:api -X POST repos/owner/repo/issues/{PR}/labels -f labels[]=needs-human"
    )
    # The earlier sweep's comment was written at 10:00; by default this run
    # is two hours on, past the 60-minute minimum.
    WRITTEN = datetime(2026, 10, 12, 10, 0, tzinfo=UTC)

    def setUp(self) -> None:
        super().setUp()
        self.now = self.WRITTEN + timedelta(hours=2)

    def run_main(
        self, *flags: str, merge_flag: bool = True
    ) -> tuple[int, dict[str, Any]]:
        with mock.patch.object(merge, "_now", return_value=self.now):
            return super().run_main(*flags, merge_flag=merge_flag)

    def earlier_sweep(
        self,
        body: str,
        login: str = IDENTITY,
        kind: str | None = None,
        updated: datetime | None = None,
    ) -> None:
        """The reasons comment an earlier run left, read before this one."""
        stamp = self.WRITTEN.isoformat().replace("+00:00", "Z")
        self.comments = [
            {
                "id": 77,
                "user": {
                    "login": login,
                    "type": kind or ("Bot" if login == IDENTITY else "User"),
                },
                "created_at": stamp,
                "updated_at": (updated.isoformat().replace("+00:00", "Z"))
                if updated
                else stamp,
                "body": body,
            }
        ]

    def test_a_review_still_running_reaches_the_score_as_med(self) -> None:
        # A review job in progress at the head binds no evidence, so the
        # pull request is scored, MED, not held back before scoring.
        running = {
            "path": merge.review_evidence.LANES["claude-review"][0],
            "event": "pull_request",
            "id": 1,
            "head_sha": HEAD,
            "status": "in_progress",
            "conclusion": None,
            "created_at": "2026-10-12T10:00:00Z",
        }
        lanes = merge.review_evidence.bind(
            HEAD, [running], [], [], is_human=lambda actor: False, changed_paths=()
        )
        self.assertEqual(lanes[0].unbound_reason, "run-not-success")
        self.lanes = lanes
        _, out = self.run_main()
        self.assertEqual(out["unattended"]["risk"]["score"], "MED")
        self.assertEqual(self.log, ["risk-comment:POST"])

    def test_a_review_pending_med_ten_minutes_on_gets_no_label(self) -> None:
        # A review still running scores MED on every
        # sweep; two sweeps minutes apart must not label it for good.
        body = self.body()
        self.setUp()
        self.earlier_sweep(body)
        self.now = self.WRITTEN + timedelta(minutes=10)
        self.lanes = UNBOUND
        _, out = self.run_main()
        self.assertEqual(self.log, [])
        self.assertEqual(out["unattended"]["writes"]["riskComment"], "unchanged")
        self.assertNotIn("riskEscalation", out["unattended"]["writes"])

    def test_the_same_reasons_sixty_one_minutes_on_get_the_label(self) -> None:
        body = self.body()
        self.setUp()
        self.earlier_sweep(body)
        self.now = self.WRITTEN + timedelta(minutes=61)
        self.lanes = UNBOUND
        _, out = self.run_main()
        self.assertEqual(self.log, ["risk-comment:PATCH", self.LABEL])
        self.assertEqual(
            out["unattended"]["writes"]["riskEscalation"],
            {"label": "added", "comment": "updated"},
        )

    def patched_body(self) -> str:
        """The body this run's PATCH of the reasons comment wrote."""
        patches = [
            c.args[0][-1].removeprefix("body=")
            for c in self.capture.call_args_list
            if "PATCH" in c.args[0] and "/issues/comments/" in " ".join(c.args[0])
        ]
        self.assertEqual(len(patches), 1)
        return patches[0]

    def test_escalating_rewrites_the_comment_before_the_label(self) -> None:
        # The rewrite stamps the comment's updated_at beside the label, so
        # the head-moved clear pairs the two.
        body = self.body()
        self.setUp()
        self.earlier_sweep(body)
        self.lanes = UNBOUND
        self.run_main()
        self.assertEqual(self.log, ["risk-comment:PATCH", self.LABEL])
        patched = self.patched_body()
        self.assertEqual(patched.split("\n")[:2], body.split("\n")[:2])
        self.assertTrue(patched.startswith(body))
        self.assertEqual(patched.count(merge.RISK_ESCALATION_LINE), 1)
        self.assertTrue(patched.endswith(merge.RISK_ESCALATION_LINE))

    def test_an_escalated_comment_is_not_extended_again(self) -> None:
        # A rerun after a failed label write retries only the label.
        body = self.body()
        self.setUp()
        self.earlier_sweep(f"{body}\n\n{merge.RISK_ESCALATION_LINE}")
        self.lanes = UNBOUND
        _, out = self.run_main()
        self.assertEqual(self.log, [self.LABEL])
        self.assertEqual(
            out["unattended"]["writes"]["riskEscalation"],
            {"label": "added", "comment": "unchanged"},
        )

    def unlabeled(
        self,
        login: str,
        kind: str,
        at: datetime,
        name: str = "Needs-Human",
        actor_id: int = PERSON_ID,
    ) -> dict[str, Any]:
        """A REST timeline event removing `name` at `at`."""
        return {
            "event": "unlabeled",
            "actor": {"login": login, "type": kind, "id": actor_id},
            "label": {"name": name},
            "created_at": at.isoformat().replace("+00:00", "Z"),
        }

    def escalated_earlier(self) -> None:
        """An earlier run escalated at this head at WRITTEN; the label is off."""
        self.setUp()
        body = self.body()
        self.setUp()
        self.earlier_sweep(f"{body}\n\n{merge.RISK_ESCALATION_LINE}")
        self.lanes = UNBOUND

    def test_a_person_removing_the_label_after_the_escalation_keeps_it_off(
        self,
    ) -> None:
        self.escalated_earlier()
        self.timeline = [
            self.unlabeled("owner-person", "User", self.WRITTEN + timedelta(minutes=30))
        ]
        _, out = self.run_main()
        self.assertEqual(self.log, [])
        self.assertEqual(
            out["unattended"]["writes"]["riskEscalation"],
            {"label": "lifted", "comment": "unchanged"},
        )
        # The trusted list is read at the base branch, never the head.
        self.assertEqual(self.trusted_refs, ["main"])

    def test_the_trusted_list_is_read_at_the_default_branch(self) -> None:
        # The pull request's base is main; a retarget cannot pick the list.
        self.escalated_earlier()
        self.repo_default = "trunk"
        self.timeline = [
            self.unlabeled("owner-person", "User", self.WRITTEN + timedelta(minutes=30))
        ]
        _, out = self.run_main()
        self.assertEqual(self.trusted_refs, ["trunk"])
        self.assertEqual(
            out["unattended"]["writes"]["riskEscalation"]["label"], "lifted"
        )

    def test_an_unread_default_branch_is_no_lift(self) -> None:
        self.escalated_earlier()
        self.repo_default = None
        self.timeline = [
            self.unlabeled("owner-person", "User", self.WRITTEN + timedelta(minutes=30))
        ]
        self.run_main()
        self.assertEqual(self.log, [self.LABEL])
        self.assertEqual(self.trusted_refs, [])

    def test_a_trusted_id_on_a_bot_account_is_no_lift(self) -> None:
        self.escalated_earlier()
        self.timeline = [
            self.unlabeled("person-app", "Bot", self.WRITTEN + timedelta(minutes=30))
        ]
        self.run_main()
        self.assertEqual(self.log, [self.LABEL])

    def test_a_tie_goes_to_the_later_removal(self) -> None:
        # Same second: the person's removal, then the lanes App's.
        self.escalated_earlier()
        at = self.WRITTEN + timedelta(minutes=30)
        self.timeline = [
            self.unlabeled("owner-person", "User", at),
            self.unlabeled("melodic-automation-lanes[bot]", "Bot", at, actor_id=1),
        ]
        self.run_main()
        self.assertEqual(self.log, [self.LABEL])

    def test_a_write_user_off_the_trusted_list_is_no_lift(self) -> None:
        # A model-driven User account can hold write access.
        self.escalated_earlier()
        self.timeline = [
            self.unlabeled(
                "model-agent",
                "User",
                self.WRITTEN + timedelta(minutes=30),
                actor_id=199161495,
            )
        ]
        _, out = self.run_main()
        self.assertEqual(self.log, [self.LABEL])
        self.assertEqual(
            out["unattended"]["writes"]["riskEscalation"],
            {"label": "added", "comment": "unchanged"},
        )

    def test_a_trusted_person_with_triage_access_is_no_lift(self) -> None:
        self.escalated_earlier()
        self.permission_reader = lambda repo: (
            lambda who: "triage" if who == "owner-person" else "write"
        )
        self.timeline = [
            self.unlabeled("owner-person", "User", self.WRITTEN + timedelta(minutes=30))
        ]
        self.run_main()
        self.assertEqual(self.log, [self.LABEL])

    def test_the_newest_removal_decides(self) -> None:
        # A person removed it; the lanes App put it back and took it off again.
        self.escalated_earlier()
        self.timeline = [
            self.unlabeled(
                "owner-person", "User", self.WRITTEN + timedelta(minutes=30)
            ),
            {
                "event": "labeled",
                "actor": {"login": "melodic-automation-lanes[bot]", "type": "Bot"},
                "label": {"name": "needs-human"},
                "created_at": "2026-10-12T10:40:00Z",
            },
            self.unlabeled(
                "melodic-automation-lanes[bot]",
                "Bot",
                self.WRITTEN + timedelta(minutes=50),
                actor_id=1,
            ),
        ]
        self.run_main()
        self.assertEqual(self.log, [self.LABEL])

    def test_an_escalation_comment_with_no_time_is_no_lift(self) -> None:
        self.escalated_earlier()
        for key in ("created_at", "updated_at"):
            self.comments[0][key] = "not a time"
        self.timeline = [
            self.unlabeled("owner-person", "User", self.WRITTEN + timedelta(minutes=30))
        ]
        self.run_main()
        self.assertEqual(self.log, [self.LABEL])
        self.assertEqual(self.timeline_reads, [])

    def test_a_bot_or_a_reader_removing_the_label_is_no_lift(self) -> None:
        later = self.WRITTEN + timedelta(minutes=30)
        for login, kind in (
            ("melodic-automation-lanes[bot]", "Bot"),
            ("github-actions[bot]", "Bot"),
            (IDENTITY, "Bot"),
            ("reader-person", "User"),
        ):
            with self.subTest(login):
                self.escalated_earlier()
                self.permission_reader = lambda repo: (
                    lambda who: "read" if who == "reader-person" else "write"
                )
                self.timeline = [self.unlabeled(login, kind, later)]
                _, out = self.run_main()
                self.assertEqual(self.log, [self.LABEL])
                self.assertEqual(
                    out["unattended"]["writes"]["riskEscalation"],
                    {"label": "added", "comment": "unchanged"},
                )

    def test_a_removal_before_the_escalation_is_no_lift(self) -> None:
        self.escalated_earlier()
        self.timeline = [
            self.unlabeled("owner-person", "User", self.WRITTEN - timedelta(minutes=5)),
            self.unlabeled("owner-person", "User", self.WRITTEN),
        ]
        self.run_main()
        self.assertEqual(self.log, [self.LABEL])

    def test_another_labels_removal_is_no_lift(self) -> None:
        self.escalated_earlier()
        self.timeline = [
            self.unlabeled(
                "owner-person", "User", self.WRITTEN + timedelta(minutes=30), "bug"
            )
        ]
        self.run_main()
        self.assertEqual(self.log, [self.LABEL])

    def test_an_unread_timeline_escalates(self) -> None:
        self.escalated_earlier()
        self.timeline_error = RuntimeError("HTTP 403: rate limit")
        _, out = self.run_main()
        self.assertEqual(self.log, [self.LABEL])
        self.assertEqual(
            out["unattended"]["writes"]["riskEscalation"]["label"], "added"
        )

    def test_the_timeline_is_read_under_the_verdict_readers_token(self) -> None:
        self.escalated_earlier()
        with mock.patch.dict(os.environ, {merge.verify_evidence.TOKEN_ENV: "reader"}):
            self.run_main()
        self.assertEqual(
            self.timeline_reads, [{"env_overrides": {"GH_TOKEN": "reader"}}]
        )

    def test_a_removal_before_a_new_escalation_does_not_lift_it(self) -> None:
        # The reasons comment says the refusal for the first time at this
        # head, so a person's earlier removal lifted some other escalation.
        body = self.body()
        self.setUp()
        self.earlier_sweep(body)
        self.lanes = UNBOUND
        self.timeline = [
            self.unlabeled("owner-person", "User", self.WRITTEN + timedelta(minutes=30))
        ]
        _, out = self.run_main()
        self.assertEqual(self.log, ["risk-comment:PATCH", self.LABEL])
        self.assertEqual(
            out["unattended"]["writes"]["riskEscalation"],
            {"label": "added", "comment": "updated"},
        )
        self.assertEqual(self.timeline_reads, [])

    def test_an_escalated_comment_at_a_new_head_drops_the_line(self) -> None:
        old = self.body().replace(HEAD, "d" * 40)
        self.setUp()
        self.earlier_sweep(f"{old}\n\n{merge.RISK_ESCALATION_LINE}")
        self.lanes = UNBOUND
        _, out = self.run_main()
        self.assertEqual(self.log, ["risk-comment:PATCH"])
        self.assertNotIn(merge.RISK_ESCALATION_LINE, self.patched_body())
        self.assertNotIn("riskEscalation", out["unattended"]["writes"])

    def test_a_recent_rewrite_of_the_reasons_resets_the_age(self) -> None:
        # Written two hours ago, its reasons rewritten ten minutes ago.
        body = self.body()
        self.setUp()
        self.earlier_sweep(body, updated=self.now - timedelta(minutes=10))
        self.lanes = UNBOUND
        _, out = self.run_main()
        self.assertEqual(self.log, [])
        self.assertNotIn("riskEscalation", out["unattended"]["writes"])

    def test_no_minimum_labels_the_second_sweep(self) -> None:
        body = self.body()
        self.setUp()
        self.earlier_sweep(body)
        self.config = dataclasses.replace(self.config, risk_escalation_minutes=0)
        self.now = self.WRITTEN + timedelta(minutes=1)
        self.lanes = UNBOUND
        self.run_main()
        self.assertEqual(self.log, ["risk-comment:PATCH", self.LABEL])

    def test_another_bot_accounts_marker_is_not_an_earlier_sweep(self) -> None:
        body = self.body()
        self.setUp()
        self.earlier_sweep(body, login="other-app[bot]", kind="Bot")
        self.lanes = UNBOUND
        self.run_main()
        self.assertEqual(self.log, ["risk-comment:POST"])

    def test_the_first_sweep_comments_without_a_label(self) -> None:
        self.lanes = UNBOUND
        _, out = self.run_main()
        self.assertEqual(self.log, ["risk-comment:POST"])
        self.assertNotIn("riskEscalation", out["unattended"]["writes"])

    def test_a_second_sweep_at_the_same_head_adds_the_human_gated_label(self) -> None:
        # A MED or HIGH refusal on two sweeps at one head is
        # labeled, the reasons comment first extended to say so.
        for name, files in (
            ("MED", ((LOW_FILE,), True)),
            ("HIGH", ((dataclasses.replace(LOW_FILE, path=".gitmodules"),), True)),
        ):
            with self.subTest(name):
                self.setUp()
                self.files = files
                body = self.body()
                self.setUp()
                self.files = files
                self.lanes = UNBOUND
                self.earlier_sweep(body)
                _, out = self.run_main()
                self.assertEqual(out["unattended"]["risk"]["score"], name)
                self.assertEqual(self.log, ["risk-comment:PATCH", self.LABEL])
                self.assertEqual(
                    out["unattended"]["writes"]["riskEscalation"],
                    {"label": "added", "comment": "updated"},
                )

    def test_changed_reasons_at_the_same_head_rewrite_without_a_label(
        self,
    ) -> None:
        # The rewrite restarts the age the next sweep measures.
        self.earlier_sweep(f"{merge.RISK_MARKER}\nrisk **HIGH** at head `{HEAD}`.")
        self.lanes = UNBOUND
        _, out = self.run_main()
        self.assertEqual(self.log, ["risk-comment:PATCH"])
        self.assertNotIn("riskEscalation", out["unattended"]["writes"])

    def test_a_same_head_rerun_with_the_label_writes_nothing(self) -> None:
        body = self.body()
        self.setUp()
        self.earlier_sweep(f"{body}\n\n{merge.RISK_ESCALATION_LINE}")
        self.pr_labels = [{"name": "Needs-Human"}]
        self.lanes = UNBOUND
        _, out = self.run_main()
        self.assertEqual(self.log, [])
        self.assertEqual(
            out["unattended"]["writes"]["riskEscalation"],
            {"label": "present", "comment": "unchanged"},
        )

    def test_a_new_head_rewrites_the_comment_without_a_label(self) -> None:
        self.earlier_sweep(f"{merge.RISK_MARKER}\nrisk **MED** at head `{'d' * 40}`.")
        self.lanes = UNBOUND
        _, out = self.run_main()
        self.assertEqual(self.log, ["risk-comment:PATCH"])
        self.assertNotIn("riskEscalation", out["unattended"]["writes"])

    def test_another_accounts_comment_at_the_head_is_not_an_earlier_sweep(
        self,
    ) -> None:
        body = self.body()
        self.setUp()
        self.earlier_sweep(body, login="maintainer")
        self.lanes = UNBOUND
        self.run_main()
        self.assertEqual(self.log, ["risk-comment:POST"])

    def comment_writes(self) -> list[str]:
        """This run's reasons-comment writes; a LOW run also enqueues."""
        return [e for e in self.log if e.startswith("risk-comment")]

    def test_a_low_score_after_an_earlier_sweep_clears_the_comment(self) -> None:
        # The refusal ended at this head: a later MED or HIGH with the same
        # reasons must not read the old comment's age as its own.
        body = self.body()
        self.setUp()
        self.earlier_sweep(body)
        _, out = self.run_main()
        self.assertEqual(out["unattended"]["risk"]["score"], "LOW")
        self.assertEqual(self.comment_writes(), ["risk-comment:PATCH"])
        self.assertEqual(out["unattended"]["writes"]["riskComment"], "updated")
        patched = self.patched_body()
        self.assertEqual(patched, merge.risk_cleared_body(HEAD))
        self.assertEqual(patched.split("\n")[0], merge.RISK_MARKER)
        self.assertIn(f"at head `{HEAD}`", patched.split("\n")[1])

    def test_a_low_score_with_the_comment_cleared_writes_nothing(self) -> None:
        self.earlier_sweep(merge.risk_cleared_body(HEAD))
        _, out = self.run_main()
        self.assertEqual(self.comment_writes(), [])
        self.assertNotIn("riskComment", out["unattended"]["writes"])

    def test_a_low_score_leaves_an_escalated_comment(self) -> None:
        # The label it explains stands; the head-moved clear pairs the two.
        body = self.body()
        self.setUp()
        self.earlier_sweep(f"{body}\n\n{merge.RISK_ESCALATION_LINE}")
        self.run_main()
        self.assertEqual(self.comment_writes(), [])

    def test_a_low_score_leaves_a_comment_at_an_old_head(self) -> None:
        # A later refusal at this head renders a different body anyway.
        old = self.body().replace(HEAD, "d" * 40)
        self.setUp()
        self.earlier_sweep(old)
        self.run_main()
        self.assertEqual(self.comment_writes(), [])

    def test_a_refusal_after_a_cleared_comment_restarts_the_time(self) -> None:
        # MED, then LOW, then MED again with the same reasons: the cleared
        # comment has stood two hours, but the refusal is new.
        self.earlier_sweep(merge.risk_cleared_body(HEAD))
        self.lanes = UNBOUND
        _, out = self.run_main()
        self.assertEqual(self.log, ["risk-comment:PATCH"])
        self.assertNotIn("riskEscalation", out["unattended"]["writes"])

    def test_report_only_writes_nothing_after_an_earlier_sweep(self) -> None:
        body = self.body()
        self.setUp()
        self.earlier_sweep(body)
        self.config = dataclasses.replace(self.config, report_only=True)
        self.lanes = UNBOUND
        _, out = self.run_main()
        self.assertIs(out["unattended"]["reportOnly"], True)
        self.capture.assert_not_called()

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


# Held only by a finding a clean whole review of the head would close.
CARRIED = (
    LaneEvidence("claude-review", True, None, 0),
    LaneEvidence("claude-security-review", True, None, 1, True),
)


class WholeReviewRequest(Unattended):
    """A lane pull request held only by findings an incremental review cannot
    clear gets one whole-review request per head: the record line in the
    reasons comment first, then the draft toggle."""

    WRITTEN = ReasonsComment.WRITTEN
    earlier_sweep = ReasonsComment.earlier_sweep

    def setUp(self) -> None:
        super().setUp()
        self.now = self.WRITTEN + timedelta(hours=2)
        self.lanes = CARRIED
        self.limit: str | None = None
        self.toggles: list[str] = []
        self.lane_toggles: int | None = 0

    def _toggle(self, node_id: str, **kwargs: Any) -> dict[str, Any]:
        self.log.append("toggle")
        self.toggles.append(node_id)
        return {"toggled": True}

    def run_main(
        self, *flags: str, merge_flag: bool = True
    ) -> tuple[int, dict[str, Any]]:
        with (
            mock.patch.object(merge, "_now", return_value=self.now),
            mock.patch.object(merge.whole_review, "limits", return_value=self.limit),
            mock.patch.object(merge.whole_review, "toggle", side_effect=self._toggle),
            mock.patch.object(
                merge.whole_review, "lane_toggles", return_value=self.lane_toggles
            ),
        ):
            return super().run_main(*flags, merge_flag=merge_flag)

    def posted(self) -> str:
        return next(
            c.args[0][-1].removeprefix("body=")
            for c in self.capture.call_args_list
            if "babysit-merge-risk" in " ".join(c.args[0])
        )

    def test_records_then_toggles_once(self) -> None:
        code, out = self.run_main()
        self.assert_no_merge(code)
        self.assertEqual(self.log, ["risk-comment:POST", "toggle"])
        self.assertEqual(self.toggles, [self.node_id])
        self.assertTrue(merge.whole_review.recorded(self.posted(), HEAD))
        self.assertEqual(out["unattended"]["writes"]["wholeReview"], {"toggled": True})

    def test_a_recorded_head_is_not_toggled_again_and_keeps_its_record(self) -> None:
        self.run_main()
        body = self.posted()
        self.setUp()
        self.earlier_sweep(body)
        self.now = self.WRITTEN + timedelta(minutes=10)
        _, out = self.run_main()
        self.assertEqual(self.log, [])
        self.assertEqual(out["unattended"]["writes"]["riskComment"], "unchanged")

    def test_the_record_survives_escalation(self) -> None:
        self.run_main()
        body = self.posted()
        self.setUp()
        self.earlier_sweep(body)
        self.now = self.WRITTEN + timedelta(hours=3)
        self.run_main()
        self.assertNotIn("toggle", self.log)
        patched = next(
            c.args[0][-1] for c in self.capture.call_args_list if "PATCH" in c.args[0]
        )
        self.assertTrue(merge.whole_review.recorded(patched, HEAD))
        self.assertTrue(patched.endswith(merge.RISK_ESCALATION_LINE))

    def test_a_record_at_an_older_head_does_not_stop_a_new_one(self) -> None:
        self.run_main()
        old = self.posted().replace(HEAD, "d" * 40)
        self.setUp()
        self.earlier_sweep(old)
        self.run_main()
        self.assertEqual(self.log, ["risk-comment:PATCH", "toggle"])

    def two_toggles(self) -> str:
        """A reasons comment recording whole reviews at two earlier heads."""
        stamp = self.WRITTEN
        return "\n".join(
            [
                f"{merge.RISK_MARKER}\nan earlier assessment",
                "",
                merge.whole_review.record_line("d" * 40, stamp),
                merge.whole_review.record_line("e" * 40, stamp),
            ]
        )

    def test_a_third_whole_review_is_never_toggled(self) -> None:
        # The lane resolved its threads and pushed a trivial commit; the new
        # head's clean incremental review would buy a third whole review.
        self.earlier_sweep(self.two_toggles())
        _, out = self.run_main()
        self.assertNotIn("toggle", self.log)
        self.assertEqual(
            out["unattended"]["writes"]["wholeReview"],
            {"toggled": False, "skipped": "toggle-cap:2"},
        )
        posted = self.posted()
        for head in ("d" * 40, "e" * 40):
            self.assertTrue(merge.whole_review.recorded(posted, head), head)

    def test_deleted_records_do_not_reset_the_timeline_cap(self) -> None:
        # The lane deleted the record lines from the reasons comment; its two
        # conversions to draft stay on the timeline.
        self.earlier_sweep(merge.whole_review.RECORD_RE.sub("", self.two_toggles()))
        self.lane_toggles = 2
        _, out = self.run_main()
        self.assertNotIn("toggle", self.log)
        self.assertEqual(
            out["unattended"]["writes"]["wholeReview"],
            {"toggled": False, "skipped": "toggle-cap:2"},
        )
        self.assertFalse(merge.whole_review.recorded(self.posted(), HEAD))

    def test_an_unread_timeline_requests_nothing(self) -> None:
        self.lane_toggles = None
        _, out = self.run_main()
        self.assertNotIn("toggle", self.log)
        self.assertEqual(
            out["unattended"]["writes"]["wholeReview"],
            {"toggled": False, "skipped": "toggle-cap:unread"},
        )

    def test_every_record_is_kept_when_the_score_clears(self) -> None:
        self.earlier_sweep(
            self.two_toggles().replace(
                "an earlier assessment",
                f"Unattended merge: risk **MED** at head `{HEAD}`.",
            )
        )
        self.lanes = BOUND
        self.run_main()
        cleared = self.posted()
        self.assertTrue(cleared.startswith(merge.risk_cleared_body(HEAD)))
        self.assertEqual(len(merge.whole_review.RECORD_RE.findall(cleared)), 2)

    def test_an_escalated_comment_is_not_toggled(self) -> None:
        self.run_main()
        body = self.posted()
        self.setUp()
        self.earlier_sweep(
            f"{merge.whole_review.RECORD_RE.sub('', body).rstrip()}"
            f"\n\n{merge.RISK_ESCALATION_LINE}"
        )
        self.run_main()
        self.assertNotIn("toggle", self.log)

    def test_a_limit_writes_no_record_and_no_toggle(self) -> None:
        self.limit = "running-jobs:40"
        _, out = self.run_main()
        self.assertEqual(self.log, ["risk-comment:POST"])
        self.assertFalse(merge.whole_review.recorded(self.posted(), HEAD))
        self.assertEqual(
            out["unattended"]["writes"]["wholeReview"],
            {"toggled": False, "skipped": "running-jobs:40"},
        )

    def test_another_refusal_is_not_toggled(self) -> None:
        self.lanes = (
            LaneEvidence("claude-review", False, "no-marker", None),
            CARRIED[1],
        )
        self.run_main()
        self.assertNotIn("toggle", self.log)

    def test_a_finding_at_the_head_is_not_toggled(self) -> None:
        self.lanes = (
            CARRIED[0],
            LaneEvidence("claude-security-review", True, None, 1, False),
        )
        self.run_main()
        self.assertNotIn("toggle", self.log)

    def test_another_authors_pull_request_is_not_toggled(self) -> None:
        self.pr_user = {"login": "someone", "type": "User"}
        self.run_main()
        self.assertNotIn("toggle", self.log)

    def test_report_only_requests_nothing(self) -> None:
        self.config = dataclasses.replace(self.config, report_only=True)
        self.run_main()
        self.assertNotIn("toggle", self.log)


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

        def paginated(endpoint: str, label: str, **_: Any) -> list[dict[str, Any]]:
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
                (),
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


class LaneEvidenceReadToken(unittest.TestCase):
    """The gate's review-evidence reads (timeline, comments, lane runs and
    their attempts, jobs and annotations) run under the job's read-only token
    (`BABYSIT_VERIFY_GH_TOKEN`), off the lane App's quota; each is a GET."""

    RUN = 11
    JOB = 21

    def answer(self, args: list[str]) -> Any:
        endpoint = args[1]
        runs = f"repos/owner/repo/actions/runs/{self.RUN}"
        bot = {"login": IDENTITY}
        if endpoint.endswith(f"/pulls/{PR}/commits?per_page=100"):
            return [[{"sha": HEAD, "author": bot, "committer": bot}]]
        if "/actions/workflows/" in endpoint:
            return [
                {"workflow_runs": [{"id": self.RUN, "pull_requests": [{"number": PR}]}]}
            ]
        if endpoint == runs:
            return {"id": self.RUN, "run_attempt": 1}
        if endpoint == f"{runs}/attempts/1":
            return {"id": self.RUN, "run_attempt": 1}
        if endpoint == f"{runs}/attempts/1/jobs?per_page=100":
            suffixes = [s for _, s in merge.review_evidence.LANES.values()]
            return [
                {
                    "jobs": [
                        {"id": self.JOB, "name": f"pr-review / {n}"} for n in suffixes
                    ]
                }
            ]
        if endpoint.endswith(("/timeline?per_page=100", "/comments?per_page=100")):
            return [[]]
        if endpoint.endswith("/annotations?per_page=100"):
            return [[]]
        raise AssertionError(f"unexpected gh call: {args}")

    def calls(self, environ: dict[str, str]) -> list[tuple[list[str], Any]]:
        calls: list[tuple[list[str], Any]] = []

        def fake_gh(
            args: list[str], *, env_overrides: Any = None, **_: Any
        ) -> subprocess.CompletedProcess[str]:
            calls.append((args, env_overrides))
            return subprocess.CompletedProcess(
                args, 0, json.dumps(self.answer(args)), ""
            )

        pr = {
            "number": PR,
            "head": {"ref": "feat", "sha": HEAD},
            "user": {"login": IDENTITY},
            "commits": 1,
            "created_at": "2026-10-22T00:00:00Z",
        }
        with (
            mock.patch.dict("os.environ", environ, clear=True),
            mock.patch.object(gh, "_run_gh", side_effect=fake_gh),
            mock.patch.object(merge, "fetch_review_threads", return_value=[]),
        ):
            merge._lane_evidence(
                "owner/repo", PR, pr, IDENTITY, frozenset(), lambda login: "write", ()
            )
        return calls

    def test_the_evidence_reads_carry_the_read_token_and_are_gets(self) -> None:
        calls = self.calls({"BABYSIT_VERIFY_GH_TOKEN": "read-tok"})
        carried = [args for args, env in calls if env == {"GH_TOKEN": "read-tok"}]
        for args in carried:
            with self.subTest(args[1]):
                self.assertFalse(is_write(args), args)
        kinds = (
            "/timeline?",
            "/comments?",
            "/actions/workflows/",
            f"/actions/runs/{self.RUN}",
            "/attempts/1",
            "/jobs?",
            "/annotations?",
        )
        for kind in kinds:
            with self.subTest(kind):
                self.assertTrue(any(kind in args[1] for args in carried), kind)
        # Two lanes: listing, run, jobs and one annotations read each; the run
        # read is the latest attempt's record.
        self.assertEqual(len(carried), 2 + 2 * 4)
        # The commits read is shared with other readers and keeps its token.
        others = [args[1] for args, env in calls if env is None]
        self.assertEqual(others, [f"repos/owner/repo/pulls/{PR}/commits?per_page=100"])

    def test_with_no_read_token_every_read_keeps_the_process_token(self) -> None:
        calls = self.calls({})
        self.assertEqual(len(calls), 1 + 2 + 2 * 4)
        self.assertEqual([env for _, env in calls], [None] * len(calls))


class LaneEvidenceReadTokenOutage(unittest.TestCase):
    """A review-evidence read refused under the read token stays refused: no
    read moves to the lane token, whatever the refusal, since GitHub's Terms
    of Service bar sharing tokens to exceed its rate limits. The read is made
    once, not retried, and raises, so `score_unattended` holds the candidate
    with `evidence-missing`. At 05:3xZ on 2026-10-23 `github.token` answered
    403 "API rate limit exceeded for installation" while GET /rate_limit
    still showed room, so no limit read decides anything here either. The
    fixture is a complete, passing review on the head for both lanes, so a
    bound result proves the reads that fed `bind()` succeeded."""

    LIMITED = (
        "gh: API rate limit exceeded for installation ID 4242. If you reach out"
        " to GitHub Support for help, please include the request ID"
        " 0000:0000:0000:0000. (HTTP 403)"
    )
    REFUSED = "gh: Resource not accessible by integration (HTTP 403)"

    def setUp(self) -> None:
        self.refusal: str | None = self.LIMITED
        self.ids = {
            lane: (100 + i, 200 + i)
            for i, lane in enumerate(merge.review_evidence.LANES)
        }
        cache = tempfile.TemporaryDirectory()
        self.addCleanup(cache.cleanup)
        self.cache = str(pathlib.Path(cache.name, "run-cache.json"))

    def answer(self, endpoint: str) -> Any:
        bot = {"login": IDENTITY}
        if endpoint.endswith(f"/pulls/{PR}/commits?per_page=100"):
            return [[{"sha": HEAD, "author": bot, "committer": bot}]]
        if endpoint.endswith("/timeline?per_page=100"):
            return [[]]
        if endpoint.endswith("/comments?per_page=100"):
            return [
                [
                    {
                        "id": 300 + i,
                        "user": {"login": "github-actions[bot]", "type": "Bot"},
                        "created_at": "2026-10-22T02:00:00Z",
                        "body": f"<!-- claude-lane-reviewed-head lane={lane}"
                        f" sha={HEAD} -->\n{lane} has reviewed this pull request"
                        f" through {HEAD}.",
                    }
                    for i, lane in enumerate(merge.review_evidence.LANES)
                ]
            ]
        for lane, (path, suffix) in merge.review_evidence.LANES.items():
            run, job = self.ids[lane]
            done = {"status": "completed", "conclusion": "success", "head_sha": HEAD}
            if f"/actions/workflows/{path.rsplit('/', 1)[-1]}/" in endpoint:
                item = {
                    "id": run,
                    "path": path,
                    "event": "pull_request",
                    "run_attempt": 1,
                    "created_at": "2026-10-22T01:00:00Z",
                    "pull_requests": [{"number": PR}],
                    **done,
                }
                return [{"workflow_runs": [item]}]
            base = f"repos/owner/repo/actions/runs/{run}"
            if endpoint == base:
                # The run read is the latest attempt's record.
                return {"id": run, "run_attempt": 1, **done}
            if endpoint == f"{base}/attempts/1/jobs?per_page=100":
                return [
                    {
                        "jobs": [
                            {
                                "id": job,
                                "run_id": run,
                                "run_attempt": 1,
                                "name": f"pr-review / {suffix}",
                                "started_at": "2026-10-22T01:00:00Z",
                                "completed_at": "2026-10-22T01:30:00Z",
                                **done,
                            }
                        ]
                    }
                ]
            if endpoint == f"repos/owner/repo/check-runs/{job}/annotations?per_page=100":
                message = (
                    f"claude-lane-review-complete lane={lane} sha={HEAD}"
                    " findings=0 inline=0 scope=whole"
                )
                return [
                    [
                        {
                            "path": ".github",
                            "annotation_level": "notice",
                            "title": "claude-lane-review-complete",
                            "message": message,
                        }
                    ]
                ]
        raise AssertionError(f"unexpected gh call: {endpoint}")

    def read(self) -> tuple[list[tuple[str, str]], Any]:
        """(endpoint, token) of every call, and `_lane_evidence`'s result or
        the exception it raised."""
        calls: list[tuple[str, str]] = []

        def fake_gh(
            args: list[str], *, check: bool = True, env_overrides: Any = None, **_: Any
        ) -> subprocess.CompletedProcess[str]:
            token = (env_overrides or {}).get("GH_TOKEN", "lane-tok")
            calls.append((args[1], token))
            if token == "read-tok" and self.refusal:
                if check:
                    raise RuntimeError(f"gh {' '.join(args)} failed: {self.refusal}")
                return subprocess.CompletedProcess(args, 1, "", self.refusal)
            return subprocess.CompletedProcess(
                args, 0, json.dumps(self.answer(args[1])), ""
            )

        pr = {
            "number": PR,
            "head": {"ref": "feat", "sha": HEAD},
            "user": {"login": IDENTITY},
            "commits": 1,
            "created_at": "2026-10-22T00:00:00Z",
        }
        environ = {
            "GH_TOKEN": "lane-tok",
            "BABYSIT_VERIFY_GH_TOKEN": "read-tok",
            "BABYSIT_RUN_CACHE": self.cache,
        }
        result: Any
        with (
            mock.patch.dict("os.environ", environ, clear=True),
            mock.patch.object(gh, "_run_gh", side_effect=fake_gh),
            mock.patch.object(merge, "fetch_review_threads", return_value=[]),
            contextlib.redirect_stderr(io.StringIO()),
        ):
            try:
                result = merge._lane_evidence(
                    "owner/repo",
                    PR,
                    pr,
                    IDENTITY,
                    frozenset(),
                    lambda login: "write",
                    (),
                )
            except RuntimeError as exc:
                result = exc
        return calls, result

    def test_a_refused_read_is_made_once_and_never_on_the_lane_token(self) -> None:
        timeline = f"repos/owner/repo/issues/{PR}/timeline?per_page=100"
        for refusal in (self.LIMITED, self.REFUSED):
            with self.subTest(refusal=refusal):
                self.refusal = refusal
                calls, result = self.read()
                self.assertIsInstance(result, RuntimeError)
                self.assertIn(refusal, str(result))
                # One attempt, on the read token: no retry, no limit read,
                # and no call at all under the lane token.
                self.assertEqual(calls, [(timeline, "read-tok")])

    def test_the_next_candidate_reads_with_the_read_token_again(self) -> None:
        self.read()
        self.refusal = None
        calls, result = self.read()
        lanes, comments = result
        self.assertEqual([lane.bound for lane in lanes], [True, True])
        self.assertEqual([lane.open_findings for lane in lanes], [0, 0])
        self.assertEqual(len(comments), 2)
        # No mark carries the refusal to later candidates: every evidence
        # read is under the read token, and only the shared commits read
        # keeps the process token.
        lane = [e for e, token in calls if token == "lane-tok"]
        self.assertEqual(lane, [f"repos/owner/repo/pulls/{PR}/commits?per_page=100"])
        self.assertNotIn("rate_limit", [e for e, _ in calls])


class CandidateReadsOnce(unittest.TestCase):
    """One candidate's gate process reads the pull request's commits once
    per head, and the record's commit count once, across the policy, the
    lane evidence, the verifier reader and the signature check. Before the
    scope existed those readers made three commit-list reads and a second
    record read (the pr-merge profile in the scope notes)."""

    BASE = "b" * 40

    def run_readers(self, rows: list[dict[str, Any]], *, scoped: bool) -> list[str]:
        """Every gh REST endpoint the four readers request, in order."""
        record = {
            "number": PR,
            "commits": len(rows),
            "created_at": "2026-10-12T00:00:00Z",
            "user": {"login": IDENTITY},
            "base": {"ref": "main", "sha": self.BASE},
            "head": {"ref": "feat", "sha": HEAD},
        }
        endpoints: list[str] = []

        def fake_gh(args: list[str], **_: Any) -> subprocess.CompletedProcess[str]:
            endpoint = args[1]
            endpoints.append(endpoint + (" --jq" if "--jq" in args else ""))
            if "--jq" in args:
                payload: Any = record["commits"]
            elif endpoint.endswith("/commits?per_page=100"):
                payload = [rows]
            elif "--paginate" in args:
                payload = [[]]
            elif endpoint == f"repos/owner/repo/pulls/{PR}":
                payload = record
            else:
                raise AssertionError(f"unexpected gh call: {args}")
            return subprocess.CompletedProcess(args, 0, json.dumps(payload), "")

        scope = gh.candidate_reads() if scoped else contextlib.nullcontext()
        with (
            mock.patch.object(gh, "_run_gh", side_effect=fake_gh),
            mock.patch.object(merge, "fetch_review_threads", return_value=[]),
            mock.patch.object(merge, "collect_lane_runs", return_value=[]),
            scope,
        ):
            pr = policy.pull_request("owner/repo", PR)
            merge._lane_evidence(
                "owner/repo", PR, pr, IDENTITY, frozenset(), lambda login: "write", ()
            )
            reader = merge.verify_evidence.Reader("owner/repo", "main")
            self.assertEqual(
                reader._commits(PR, HEAD), {str(row["sha"]) for row in rows}
            )
            blockers, _ = merge.evaluate_required_signatures("owner/repo", PR, HEAD)
            self.assertEqual(blockers, [])
        return endpoints

    def signed(self, *shas: str) -> list[dict[str, Any]]:
        bot = {"login": IDENTITY}
        verified = {"verification": {"verified": True, "reason": "valid"}}
        return [
            {"sha": sha, "author": bot, "committer": bot, "commit": verified}
            for sha in shas
        ]

    def counts(self, endpoints: list[str]) -> tuple[int, int, int]:
        """(commit-list reads, record reads, record count reads)."""
        commits = f"repos/owner/repo/pulls/{PR}/commits?per_page=100"
        record = f"repos/owner/repo/pulls/{PR}"
        return (
            endpoints.count(commits),
            endpoints.count(record),
            endpoints.count(record + " --jq"),
        )

    def test_outside_a_candidate_scope_every_reader_reads(self) -> None:
        endpoints = self.run_readers(self.signed("a" * 40, HEAD), scoped=False)
        self.assertEqual(self.counts(endpoints), (3, 1, 1))

    def test_a_candidate_scope_reads_the_commits_and_the_record_once(self) -> None:
        endpoints = self.run_readers(self.signed("a" * 40, HEAD), scoped=True)
        self.assertEqual(self.counts(endpoints), (1, 1, 0))

    def test_a_list_not_ending_at_the_head_is_read_again(self) -> None:
        # Read while the head moved: no reader reuses it.
        endpoints = self.run_readers(self.signed("a" * 40, "c" * 40), scoped=True)
        # The record's count is for the head, so the signature check reads a
        # count alongside rows that do not end there.
        self.assertEqual(self.counts(endpoints), (3, 1, 1))

    def test_a_moved_head_at_the_cap_is_refused_on_a_live_count(self) -> None:
        # The record counted 249 at the head; the head moved to 260 commits
        # and the list stops at 250. The old count would pass the cap check.
        rows = self.signed(*(f"{n:040x}" for n in range(250)))
        with (
            gh.candidate_reads(),
            mock.patch.object(gh, "fetch_paginated_api", return_value=rows),
            mock.patch.object(gh, "gh_json", return_value=260),
        ):
            gh.record_pull_request_total("owner/repo", PR, HEAD, 249)
            with self.assertRaisesRegex(RuntimeError, "walked 250 of 260"):
                gh.fetch_pull_request_commits("owner/repo", PR, HEAD)

    def test_another_head_is_read_fresh(self) -> None:
        rows = self.signed(HEAD)
        with (
            gh.candidate_reads(),
            mock.patch.object(
                gh, "fetch_paginated_api", side_effect=[rows, self.signed("d" * 40)]
            ) as read,
        ):
            for head in (HEAD, HEAD, "d" * 40):
                gh.pull_request_commits_once(
                    "owner/repo",
                    PR,
                    head,
                    lambda: gh.fetch_paginated_api("commits", "label"),
                )
        self.assertEqual(read.call_count, 2)


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

    def test_the_postmerge_result_is_read_once_and_handed_to_the_policy(self) -> None:
        lane = ("--unattended", "--authority", "pr-merge")
        shared = mock.sentinel.shared
        with mock.patch.object(
            merge.postmerge, "read_shared", return_value=shared
        ) as read:
            self._main(*lane, "--postmerge-result", "/tmp/post-merge.json")
        read.assert_called_once_with("/tmp/post-merge.json")
        self.assertIs(self.assess.call_args.kwargs["shared"], shared)

    def test_an_unreadable_postmerge_result_is_read_fresh_and_reported(self) -> None:
        lane = ("--unattended", "--authority", "pr-merge")
        with mock.patch.object(merge.postmerge, "read_shared", return_value=None):
            self._main(*lane, "--postmerge-result", "/tmp/post-merge.json")
        self.assertIsNone(self.assess.call_args.kwargs["shared"])
        unattended = self.evaluate.call_args.kwargs["unattended"]
        self.assertEqual(unattended.details["postMergeShared"], "unused:unreadable")

    def test_a_recompute_is_written_back_to_the_postmerge_result(self) -> None:
        lane = ("--unattended", "--authority", "pr-merge")
        with (
            mock.patch.object(merge.postmerge, "read_shared", return_value=None),
            mock.patch.object(merge.postmerge, "write_shared") as write,
        ):
            self._main(*lane, "--postmerge-result", "/tmp/post-merge.json")
            share = self.assess.call_args.kwargs["share"]
            share(mock.sentinel.answer)
        write.assert_called_once_with("/tmp/post-merge.json", mock.sentinel.answer)

    def test_without_a_postmerge_result_the_policy_reads_its_own(self) -> None:
        self._main("--unattended", "--authority", "pr-merge")
        self.assertIsNone(self.assess.call_args.kwargs["shared"])
        self.assertIsNone(self.assess.call_args.kwargs["share"])
        unattended = self.evaluate.call_args.kwargs["unattended"]
        self.assertNotIn("postMergeShared", unattended.details or {})

    def test_a_postmerge_result_outside_the_lane_is_refused(self) -> None:
        code, out = self._main("--unattended", "--postmerge-result", "/tmp/x.json")
        self.assertEqual(code, 2)
        self.assertIn("--postmerge-result", out["error"])
        self.assess.assert_not_called()

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


# The tracker's human-gated label read an autonomous gate makes: stubbed so
# no test reads GitHub.
_role_label = fixtures.role_label_stub()


def setUpModule() -> None:
    _role_label.start()


def tearDownModule() -> None:
    _role_label.stop()


class DependabotMajorEscalation(unittest.TestCase):
    """A Dependabot major held under `merge.dependabot.majors: hold` gets the
    escalation contract: one marked comment, then the tracker's human-gated
    role label, once."""

    REPO, PR, HEAD = "owner/repo", 7, "e" * 40

    def setUp(self) -> None:
        self.calls: list[list[str]] = []
        self.pr_labels: list[dict[str, str]] = []
        self.comments: list[dict[str, Any]] = []
        stack = contextlib.ExitStack()
        self.addCleanup(stack.close)
        stack.enter_context(
            mock.patch.object(postmerge, "identity_queue", return_value=([], 0))
        )
        stack.enter_context(
            mock.patch.object(postmerge, "dequeue_identity_entries", return_value=0)
        )
        self.role = stack.enter_context(
            mock.patch.object(
                merge, "human_gated_label", return_value="status: needs-decision"
            )
        )

        def capture(args: list[str]) -> subprocess.CompletedProcess[str]:
            self.calls.append(args)
            return subprocess.CompletedProcess(args, 0, "{}", "")

        stack.enter_context(mock.patch.object(merge, "gh_capture", capture))

    def writes(self, reason: str, eligibility: str | None = None) -> dict[str, Any]:
        inputs = {
            "identity": "agent-lanes[bot]",
            "branch": "main",
            "pr": {"head": {"sha": self.HEAD}, "labels": self.pr_labels},
            "comments": self.comments,
        }
        return merge.unattended_writes(
            self.REPO,
            self.PR,
            policy.UnattendedPolicy(
                reason,
                "agent-lanes[bot]",
                {
                    "eligibility": {
                        "eligible": False,
                        "reason": eligibility or reason.removeprefix("ineligible:"),
                    }
                },
                inputs=inputs,
            ),
        )

    def test_a_held_major_is_labeled_with_the_role_label_once(self) -> None:
        out = self.writes("ineligible:dependabot-major-held:x")
        comment, label = self.calls
        self.assertIn(f"repos/{self.REPO}/issues/{self.PR}/comments", comment)
        body = comment[-1].removeprefix("body=")
        self.assertTrue(
            body.startswith(
                f"{merge.ATTEND_QUEUE_MARKER}\n{merge.MAJOR_ESCALATION_MARKER}\n"
            )
        )
        self.assertIn("`x`", body)
        self.assertIn(self.HEAD, body)
        self.assertIn("`(disagree)`", body)
        self.assertEqual(
            label[-4:],
            ["POST", f"repos/{self.REPO}/issues/{self.PR}/labels"]
            + ["-f", "labels[]=status: needs-decision"],
        )
        self.assertNotIn("do-not-merge", " ".join(" ".join(c) for c in self.calls))
        self.assertEqual(
            out["majorEscalation"], {"label": "added", "comment": "created"}
        )

    def test_an_unreadable_version_hold_is_escalated_the_same_way(self) -> None:
        out = self.writes("ineligible:dependabot-major-held:x(unreadable)")
        comment, label = self.calls
        self.assertIn("`x(unreadable)`", comment[-1])
        self.assertEqual(label[-1], "labels[]=status: needs-decision")
        self.assertEqual(
            out["majorEscalation"], {"label": "added", "comment": "created"}
        )

    def test_a_rerun_writes_nothing(self) -> None:
        self.pr_labels = [{"name": "Status: Needs-Decision"}]
        self.comments = [
            {
                "id": 90,
                "user": {"login": "agent-lanes[bot]", "type": "Bot"},
                "created_at": "2026-10-18T10:00:00Z",
                "body": merge.major_escalation_body("x", self.HEAD),
            }
        ]
        out = self.writes("ineligible:dependabot-major-held:x")
        self.assertEqual(self.calls, [])
        self.assertEqual(
            out["majorEscalation"], {"label": "present", "comment": "unchanged"}
        )

    def lifted(self, timeline: list[dict[str, Any]]) -> dict[str, Any]:
        """A rerun at the head after the label came off, over `timeline`."""
        self.comments = [
            {
                "id": 90,
                "user": {"login": "agent-lanes[bot]", "type": "Bot"},
                "created_at": "2026-10-18T10:00:00Z",
                "body": merge.major_escalation_body("x", self.HEAD),
            }
        ]
        with mock.patch.object(merge, "fetch_paginated_api", return_value=timeline):
            return self.writes("ineligible:dependabot-major-held:x")

    def test_a_person_removing_the_label_keeps_a_held_major_off(self) -> None:
        with self.person():
            out = self.lifted([self.REMOVED])
        self.assertEqual(self.calls, [])
        self.assertEqual(
            out["majorEscalation"], {"label": "lifted", "comment": "unchanged"}
        )

    REMOVED = {
        "event": "unlabeled",
        "actor": {"login": "owner-person", "type": "User", "id": PERSON_ID},
        "label": {"name": "status: needs-decision"},
        "created_at": "2026-10-18T11:00:00Z",
    }

    def person(self) -> contextlib.ExitStack:
        """`owner-person` has admin access and is a person on the list."""
        stack = contextlib.ExitStack()
        stack.enter_context(
            mock.patch.object(
                policy, "permission_reader", return_value=lambda _: "admin"
            )
        )
        stack.enter_context(
            mock.patch.object(policy, "trusted_actors", return_value=((), (PERSON_ID,)))
        )
        stack.enter_context(
            mock.patch.object(merge, "repository_default_branch", return_value="main")
        )
        return stack

    def test_no_identity_is_no_lift(self) -> None:
        # With no agent identity no escalation comment is the identity's.
        comments = [
            {
                "id": 90,
                "user": {"login": "agent-lanes[bot]", "type": "Bot"},
                "created_at": "2026-10-18T10:00:00Z",
                "body": merge.major_escalation_body("x", self.HEAD),
            }
        ]
        with (
            self.person(),
            mock.patch.object(
                merge, "fetch_paginated_api", return_value=[self.REMOVED]
            ),
        ):
            for identity in ("", "agent-lanes[bot]"):
                with self.subTest(identity=identity):
                    self.assertEqual(
                        merge._lifted_by_person(
                            self.REPO,
                            self.PR,
                            identity,
                            "status: needs-decision",
                            merge.MAJOR_ESCALATION_MARKER,
                            comments,
                            {"branch": "main"},
                        ),
                        identity != "",
                    )

    def test_a_held_major_whose_label_write_failed_is_labeled_again(self) -> None:
        out = self.lifted([])
        (label,) = self.calls
        self.assertEqual(label[-1], "labels[]=status: needs-decision")
        self.assertEqual(
            out["majorEscalation"], {"label": "added", "comment": "unchanged"}
        )

    def test_the_first_line_is_the_attend_queue_escalation_marker(self) -> None:
        # The grammar and kinds come from the work-items reference, so a
        # change there fails here.
        reference = (
            pathlib.Path(__file__).resolve().parents[6]
            / "plugins/work-items/reference/escalation-marker.md"
        ).read_text(encoding="utf-8")
        template = re.search(
            r"## Comment prefix.*?```text\n(.+?)\n```", reference, re.S
        ).group(1)
        grammar = re.escape(template)
        grammar = grammar.replace(re.escape("<lane>"), r"(?P<lane>[a-z-]+)")
        grammar = grammar.replace(re.escape("<kind>"), r"(?P<kind>[a-z0-9-]+)")
        kinds = re.search(r"\| `<kind>` \| (.+?) \|\n", reference).group(1)
        body = merge.major_escalation_body("x", self.HEAD)
        match = re.fullmatch(grammar, body.split("\n", 1)[0])
        self.assertIsNotNone(match)
        self.assertIn(f"`{match['kind']}`", kinds)
        # attend-queue lists `escalated` and `routed-advisory` as escalated rows.
        self.assertIn(match["kind"], ("escalated", "routed-advisory"))

    def test_an_old_format_comment_is_rewritten_not_duplicated(self) -> None:
        self.pr_labels = [{"name": "status: needs-decision"}]
        old = merge.major_escalation_body("x", self.HEAD).removeprefix(
            merge.ATTEND_QUEUE_MARKER + "\n"
        )
        self.comments = [
            {
                "id": 92,
                "user": {"login": "agent-lanes[bot]", "type": "Bot"},
                "created_at": "2026-10-18T10:00:00Z",
                "body": old,
            }
        ]
        out = self.writes("ineligible:dependabot-major-held:x")
        (comment,) = self.calls
        self.assertIn("PATCH", comment)
        self.assertIn(f"repos/{self.REPO}/issues/comments/92", comment)
        self.assertEqual(
            out["majorEscalation"], {"label": "present", "comment": "updated"}
        )

    def test_a_held_major_under_an_earlier_refusal_escalates_once(self) -> None:
        out = self.writes("in-flight:queue-full", "dependabot-major-held:x")
        comment, label = self.calls
        self.assertIn("`x`", comment[-1])
        self.assertEqual(label[-1], "labels[]=status: needs-decision")
        self.assertEqual(
            out["majorEscalation"], {"label": "added", "comment": "created"}
        )
        # The next run finds both and writes nothing.
        self.calls.clear()
        self.pr_labels = [{"name": "status: needs-decision"}]
        self.comments = [
            {
                "id": 91,
                "user": {"login": "agent-lanes[bot]", "type": "Bot"},
                "created_at": "2026-10-18T10:00:00Z",
                "body": comment[-1].removeprefix("body="),
            }
        ]
        out = self.writes("in-flight:queue-full", "dependabot-major-held:x")
        self.assertEqual(self.calls, [])
        self.assertEqual(
            out["majorEscalation"], {"label": "present", "comment": "unchanged"}
        )

    def test_other_refusals_are_not_escalated(self) -> None:
        for reason in (
            "ineligible:dependabot-review:major:x",
            "ci-status:pending",
            "kill-switch:off",
        ):
            with self.subTest(reason):
                out = self.writes(
                    reason,
                    "dependabot-major-held:x" if reason.startswith("kill") else None,
                )
                self.assertEqual(self.calls, [])
                self.assertNotIn("majorEscalation", out)


class AdoptionHoldLabel(unittest.TestCase):
    """The pr-merge lane passes the tracker's resolved human-gated label to
    the policy, which holds an adopted owner pull request on it."""

    def run_assess(self, authority: str, label: Any) -> mock.Mock:
        assess = mock.Mock(return_value="policy")
        with (
            mock.patch.object(merge.merge_policy, "assess", assess),
            mock.patch.object(merge, "human_gated_label", label),
            mock.patch.object(merge, "score_unattended", lambda *a: a[2]),
        ):
            merge.assess_unattended(
                "o/r", 7, self_logins=frozenset(), authority=authority
            )
        return assess

    def test_the_lane_passes_the_resolved_label(self) -> None:
        assess = self.run_assess(policy.PR_MERGE, mock.Mock(return_value="awaiting"))
        self.assertEqual(assess.call_args.kwargs["human_gated"], "awaiting")

    def test_an_unreadable_label_adopts_nothing(self) -> None:
        unreadable = mock.Mock(side_effect=postmerge.PostMergeReadError("x"))
        assess = self.run_assess(policy.PR_MERGE, unreadable)
        self.assertIsNone(assess.call_args.kwargs["human_gated"])

    def test_the_local_lane_reads_no_label(self) -> None:
        label = mock.Mock(side_effect=AssertionError)
        assess = self.run_assess(policy.LOCAL_BABYSIT, label)
        self.assertIsNone(assess.call_args.kwargs["human_gated"])


if __name__ == "__main__":
    unittest.main()
