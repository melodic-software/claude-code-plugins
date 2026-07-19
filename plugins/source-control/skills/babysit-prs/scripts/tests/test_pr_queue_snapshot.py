"""Snapshot CLI: exit-code taxonomy and config assembly.

Exit-code taxonomy covers every code the module documents (0/1/2/3), including
the split that distinguishes an advisory-only head-ref alias failure (valid
snapshot) from a substantive per-PR hydration failure.

Config assembly covers the decoupling of the self-identity suppression set from
the discovery `--author` filter. `@me` resolution is stubbed by monkeypatching
the `babysit_gh` seam; no real gh process is spawned.
"""

from __future__ import annotations

import argparse
import pathlib
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import babysit_delta as delta  # noqa: E402
import babysit_gh as gh  # noqa: E402
import pr_queue_snapshot as snapshot  # noqa: E402


def _advisory_error(key="owner/repo#1"):
    return f"{key} {delta.HEAD_REF_ALIAS_ERROR_MARKER} query timed out"


def _substantive_error(key="owner/repo#2"):
    return f"{key}: HTTP 500 fetching PR"


class ExitCodeTaxonomy(unittest.TestCase):
    def test_clean_snapshot_returns_zero(self):
        self.assertEqual(snapshot.exit_code_for({"errors": []}), 0)

    def test_substantive_error_returns_one(self):
        self.assertEqual(
            snapshot.exit_code_for({"errors": [_substantive_error()]}), 1
        )

    def test_advisory_only_error_returns_three(self):
        self.assertEqual(
            snapshot.exit_code_for({"errors": [_advisory_error()]}), 3
        )

    def test_substantive_precedence_over_advisory(self):
        # A run carrying both must never be masked by the advisory split.
        self.assertEqual(
            snapshot.exit_code_for(
                {"errors": [_advisory_error(), _substantive_error()]}
            ),
            1,
        )

    def test_advisory_predicate_matches_only_the_marker(self):
        self.assertTrue(delta.is_head_ref_alias_error(_advisory_error()))
        self.assertFalse(delta.is_head_ref_alias_error(_substantive_error()))


class SubstantiveErrors(unittest.TestCase):
    """The split that keeps advisory failures out of completeness and cadence.

    `complete`, `exit_code_for`, and `cadence_blocking_errors` all derive from
    this predicate, so an advisory-only sweep is a complete sweep and never
    forces the tight cadence.
    """

    def test_advisory_only_has_no_substantive_errors(self):
        self.assertEqual(snapshot.substantive_errors([_advisory_error()]), [])

    def test_substantive_error_is_retained(self):
        substantive = _substantive_error()
        self.assertEqual(
            snapshot.substantive_errors([substantive]), [substantive]
        )

    def test_mixed_keeps_only_substantive(self):
        substantive = _substantive_error()
        self.assertEqual(
            snapshot.substantive_errors([_advisory_error(), substantive]),
            [substantive],
        )

    def test_advisory_only_reports_complete_via_helper(self):
        # `complete` is `not substantive_errors(errors)`; an advisory-only run
        # is still a complete sweep even though `errors` is non-empty.
        self.assertFalse(bool(snapshot.substantive_errors([_advisory_error()])))


class FatalRunReturnsTwo(unittest.TestCase):
    def test_main_returns_two_when_build_snapshot_raises(self):
        with tempfile.TemporaryDirectory() as td:
            argv = [
                "pr_queue_snapshot.py",
                "--queue",
                "--owners",
                "owner",
                "--state-dir",
                td,
            ]
            original_argv = sys.argv
            original_build = snapshot.build_snapshot

            def _raise(_args):
                raise RuntimeError("discovery exploded before any snapshot existed")

            sys.argv = argv
            snapshot.build_snapshot = _raise
            try:
                self.assertEqual(snapshot.main(), 2)
            finally:
                sys.argv = original_argv
                snapshot.build_snapshot = original_build


class ResolveSelfLoginsTests(unittest.TestCase):
    def test_autopilot_empty_authors_still_yields_authenticated_login(self) -> None:
        with mock.patch.object(gh, "resolve_author", return_value="kyle-sexton"):
            self.assertEqual(snapshot.resolve_self_logins([]), ["kyle-sexton"])

    def test_discovery_authors_are_unioned_with_the_self_login(self) -> None:
        with mock.patch.object(gh, "resolve_author", return_value="kyle-sexton"):
            self.assertEqual(
                snapshot.resolve_self_logins(["alice", "bob"]),
                ["alice", "bob", "kyle-sexton"],
            )

    def test_self_login_already_present_is_not_duplicated(self) -> None:
        with mock.patch.object(gh, "resolve_author", return_value="Kyle-Sexton"):
            self.assertEqual(
                snapshot.resolve_self_logins(["alice", "kyle-sexton"]),
                ["alice", "kyle-sexton"],
            )

    def test_input_author_list_is_not_mutated(self) -> None:
        authors = ["alice"]
        with mock.patch.object(gh, "resolve_author", return_value="kyle-sexton"):
            snapshot.resolve_self_logins(authors)
        self.assertEqual(authors, ["alice"])

    def test_unresolvable_self_login_leaves_discovery_authors_intact(self) -> None:
        with mock.patch.object(gh, "resolve_author", return_value=None):
            self.assertEqual(snapshot.resolve_self_logins(["alice"]), ["alice"])


HEAD = "a" * 40
OBS = "2026-07-19T16:10:00Z"

# Faithful abbreviation of the claude[bot] issue-comment review on
# melodic-software/claude-code-plugins#492 (workflow run 29694104425): an
# explicit **Approve** verdict whose only findings are two 🟡 nits, each
# self-deprioritized, and no CRITICAL/IMPORTANT/P-severity marker anywhere. The
# load-bearing tokens are the descriptive occurrences of the word "blocking"
# ("blocking criteria", "blocking checks", "No blocking issues") that made the
# old text heuristic misfire.
APPROVE_WITH_NITS_BODY = (
    "**Claude finished @kyle-sexton's task** —— [View job](run/29694104425)\n\n"
    "### PR Review\n\n"
    "**Verdict: Approve** — clean, focused, well-reasoned patch. No blocking "
    "issues. I checked each changed file against the REVIEW.md blocking "
    "criteria — none of the security/authorization gates apply here.\n\n"
    "### 🟡 Nit — parenthetical inside code fence\n"
    "A first-time reader might misread the parenthetical. Not worth a change on "
    "its own, but worth noting.\n\n"
    "### 🟡 Nit — table cell verbosity\n"
    "These files are AI-readable instruction documents, so this is low impact.\n\n"
    "### No concerns on REVIEW.md blocking criteria\n"
    "All six blocking checks (auth, tenancy, secrets, injection, audit logging, "
    "atomicity) are inapplicable — a documentation-only change."
)
APPROVE_BUT_CRITICAL_BODY = (
    "**Verdict: Approve** overall, but one item stands out.\n\n"
    "### 🔴 CRITICAL — hardcoded secret\n"
    "A live credential is committed in config; must fix before merge."
)
REQUEST_CHANGES_BODY = (
    "**Verdict: Request changes** — the new endpoint skips the tenant scope "
    "check, so cross-tenant reads are possible."
)


def _pr_with_claude_review(body: str) -> dict[str, object]:
    return {
        "repo": "melodic-software/claude-code-plugins",
        "number": 492,
        "url": "u",
        "title": "docs patch",
        "state": "OPEN",
        "author": {"login": "kyle-sexton", "__typename": "User"},
        "headRefName": "feature",
        "headRefOid": HEAD,
        "baseRefName": "main",
        "baseRefOid": "b" * 40,
        "headRepository": {"nameWithOwner": "melodic-software/claude-code-plugins"},
        "headRepositoryOwner": {"login": "melodic-software"},
        "isCrossRepository": False,
        "isDraft": False,
        "maintainerCanModify": True,
        "baseRepositoryArchived": False,
        "mergeStateStatus": "CLEAN",
        "mergeable": "MERGEABLE",
        "reviewDecision": "",
        "reviews": [],
        "latestReviews": [],
        "comments": [
            {"id": 1, "author": {"login": "claude", "__typename": "Bot"}, "body": body}
        ],
        "statusCheckRollup": [],
        "updatedAt": "2026-07-19T16:00:00Z",
    }


class ApproveWithNitsClassification(unittest.TestCase):
    """The snapshot classifier must agree with babysit-readiness-gate.sh.

    Reproduces melodic-software/claude-code-plugins#499: the gate reports
    `READINESS_OK findings=0` for #492's Approve-with-nits review (no severity
    marker present), while the snapshot classified the same review as a blocking
    bot-feedback item because its prose contains the word "blocking". After the
    fix the two agree: an Approve verdict carrying only non-blocking nits is
    non-blocking, and a genuine CRITICAL finding or a Request-changes verdict
    still blocks.
    """

    _CONFIG = delta.ClassifyConfig(
        allowed_owners=frozenset({"melodic-software"})
    )

    def _classify(self, body: str) -> dict[str, object]:
        return delta.classify_pr(
            _pr_with_claude_review(body), None, None, OBS, config=self._CONFIG
        )

    def test_approve_with_only_nits_is_not_blocking(self) -> None:
        result = self._classify(APPROVE_WITH_NITS_BODY)
        self.assertEqual(result["feedback"]["blocking"], [])
        self.assertEqual(result["new_feedback"]["blocking"], [])
        self.assertEqual(result["feedback"]["material"], [])
        self.assertNotIn(
            "1 blocking bot feedback item(s)", result["blockers"]
        )
        # Consistent with the gate's findings=0: a clean approval is fully
        # non-blocking, so a worker is never dispatched for it and the PR routes
        # straight to the direct merge gate.
        self.assertFalse(result["needs_worker"])
        self.assertTrue(result["pr_clean_ready_for_direct_gate"])

    def test_approve_with_critical_finding_still_blocks(self) -> None:
        result = self._classify(APPROVE_BUT_CRITICAL_BODY)
        self.assertEqual(len(result["feedback"]["blocking"]), 1)
        self.assertIn("1 blocking bot feedback item(s)", result["blockers"])
        self.assertTrue(result["needs_worker"])

    def test_request_changes_verdict_still_blocks(self) -> None:
        result = self._classify(REQUEST_CHANGES_BODY)
        self.assertEqual(len(result["feedback"]["blocking"]), 1)
        self.assertIn("1 blocking bot feedback item(s)", result["blockers"])
        self.assertTrue(result["needs_worker"])


class BuildConfigSelfLoginsTests(unittest.TestCase):
    def test_resolved_self_logins_populate_config_self_logins(self) -> None:
        args = argparse.Namespace(
            owners="melodic-software",
            resolved_self_logins=["kyle-sexton"],
        )
        config = snapshot.build_config(args)
        self.assertEqual(config.self_logins, frozenset({"kyle-sexton"}))

    def test_resolved_self_logins_take_precedence_over_resolved_authors(self) -> None:
        args = argparse.Namespace(
            owners="melodic-software",
            resolved_authors=["alice"],
            resolved_self_logins=["kyle-sexton"],
        )
        config = snapshot.build_config(args)
        self.assertEqual(config.self_logins, frozenset({"kyle-sexton"}))

    def test_raw_author_fallback_drops_me_when_unresolved(self) -> None:
        args = argparse.Namespace(
            owners="melodic-software",
            author="@me,alice",
        )
        config = snapshot.build_config(args)
        self.assertEqual(config.self_logins, frozenset({"alice"}))


if __name__ == "__main__":
    unittest.main()
