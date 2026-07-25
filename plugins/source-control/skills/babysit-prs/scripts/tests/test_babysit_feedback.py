"""Actor typing and bot/human feedback classification.

Ports the feedback-classification coverage onto `babysit_feedback`: structural
bot typing with the empty-config fallback, the dependency-manager author test,
and `collect_feedback`'s blocking/material/human bucketing including
head-scoped dispositions and negated-severity redaction.
"""

from __future__ import annotations

import pathlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import babysit_feedback as fb

HEAD = "a" * 40


def _pr(comments: list[dict[str, object]], **over: object) -> dict[str, object]:
    pr = {"headRefOid": HEAD, "comments": comments, "reviews": [], "latestReviews": []}
    pr.update(over)
    return pr


class DependencyAuthorTests(unittest.TestCase):
    def test_dependency_managers_are_recognized(self) -> None:
        for login in ("dependabot[bot]", "app/dependabot", "renovate",
                      "renovate-bot", "dependabot-preview[bot]"):
            with self.subTest(login=login):
                self.assertTrue(fb.is_dependency_author(login))

    def test_humans_and_other_bots_are_not_dependency_authors(self) -> None:
        for login in ("someone", "codex[bot]", "", "reviewbot"):
            with self.subTest(login=login):
                self.assertFalse(fb.is_dependency_author(login))

    def test_extra_logins_are_recognized(self) -> None:
        # A non-dependabot/renovate dependency bot an operator runs keeps the
        # same hold-merge protection once named. Matching is normalization-
        # insensitive on both sides (casefold, strip `app/` and `[bot]`).
        extra = frozenset({"MyDepBot"})
        for login in ("mydepbot", "MyDepBot[bot]", "app/mydepbot"):
            with self.subTest(login=login):
                self.assertTrue(fb.is_dependency_author(login, extra))

    def test_extra_login_config_form_is_normalized(self) -> None:
        # The configured entry itself may carry `app/` / `[bot]`; it still matches
        # the normalized incoming login.
        self.assertTrue(fb.is_dependency_author("mydepbot", frozenset({"app/MyDepBot[bot]"})))

    def test_unconfigured_extra_matches_builtin_set_only(self) -> None:
        # Empty extra (the shipped default) never widens the built-in set.
        self.assertFalse(fb.is_dependency_author("mydepbot"))
        self.assertFalse(fb.is_dependency_author("mydepbot", frozenset()))
        self.assertTrue(fb.is_dependency_author("dependabot", frozenset()))


class ActorKindTests(unittest.TestCase):
    def test_authoritative_bot_typename_wins_over_unknown_login(self) -> None:
        item = {"author": {"login": "ambiguous", "__typename": "Bot"}}
        self.assertEqual(fb.actor_kind(item), "bot")

    def test_is_bot_flag_true_classifies_bot(self) -> None:
        item = {"author": {"login": "svc", "is_bot": True}}
        self.assertEqual(fb.actor_kind(item), "bot")

    def test_is_bot_flag_false_classifies_human(self) -> None:
        item = {"author": {"login": "person", "is_bot": False}}
        self.assertEqual(fb.actor_kind(item), "human")

    def test_human_login_containing_bot_substring_is_not_a_bot(self) -> None:
        item = {"author": {"login": "robotics-fan", "__typename": "User"}}
        self.assertEqual(fb.actor_kind(item), "human")

    def test_bot_suffix_login_is_a_bot_under_empty_config(self) -> None:
        item = {"author": {"login": "linter[bot]"}}
        self.assertEqual(fb.actor_kind(item), "bot")

    def test_extra_bot_login_supplements_structural_detection(self) -> None:
        item = {"author": {"login": "misreported"}}
        self.assertEqual(fb.actor_kind(item), "human")
        config = fb.FeedbackConfig(extra_bot_logins=frozenset({"misreported"}))
        self.assertEqual(fb.actor_kind(item, config), "bot")


class CollectFeedbackTests(unittest.TestCase):
    def test_bot_approval_absence_is_not_blocking(self) -> None:
        pr = _pr([
            {"id": 1, "author": {"login": "bugbot[bot]", "__typename": "Bot"},
             "body": "No P1 issues found. Approved."}
        ])
        result = fb.collect_feedback(pr)
        self.assertEqual(result["blocking"], [])
        self.assertEqual(result["material"], [])
        self.assertEqual(len(result["ignored"]), 1)

    def test_bot_execution_error_is_material_not_blocking(self) -> None:
        pr = _pr([
            {"id": 2, "author": {"login": "bugbot[bot]", "__typename": "Bot"},
             "body": "The reviewer encountered an error and could not finish."}
        ])
        result = fb.collect_feedback(pr)
        self.assertEqual(result["blocking"], [])
        self.assertEqual(len(result["material"]), 1)

    def test_explicit_severity_is_blocking(self) -> None:
        pr = _pr([
            {"id": 3, "author": {"login": "bugbot[bot]", "__typename": "Bot"},
             "body": "P1: this is a blocking regression that must fix."}
        ])
        result = fb.collect_feedback(pr)
        self.assertEqual(len(result["blocking"]), 1)
        self.assertEqual(result["material"], [])

    def test_explicit_blocker_wins_over_execution_error_phrase(self) -> None:
        pr = _pr([
            {"id": 4, "author": {"login": "bugbot[bot]", "__typename": "Bot"},
             "body": "P1 vulnerability found; the tool also could not finish."}
        ])
        result = fb.collect_feedback(pr)
        self.assertEqual(len(result["blocking"]), 1)
        self.assertEqual(result["material"], [])

    def test_negated_severity_is_not_blocking(self) -> None:
        pr = _pr([
            {"id": 5, "author": {"login": "bugbot[bot]", "__typename": "Bot"},
             "body": "Found no P1 issues in this change."}
        ])
        result = fb.collect_feedback(pr)
        self.assertEqual(result["blocking"], [])

    def test_bot_approval_with_descriptive_blocking_prose_is_ignored(self) -> None:
        # #499: an Approve verdict whose body uses the word "blocking" only
        # descriptively ("blocking criteria"/"blocking checks") and carries no
        # severity marker must be fully non-blocking, matching the readiness
        # gate's findings=0 — not routed to blocking or even material.
        pr = _pr([
            {"id": 20, "author": {"login": "claude", "__typename": "Bot"},
             "body": "Verdict: Approve. No blocking issues. Checked the REVIEW.md "
                     "blocking criteria; all six blocking checks are inapplicable. "
                     "\U0001F7E1 Nit: worth noting, not worth a change."}
        ])
        result = fb.collect_feedback(pr)
        self.assertEqual(result["blocking"], [])
        self.assertEqual(result["material"], [])
        self.assertEqual(len(result["ignored"]), 1)
        self.assertEqual(result["ignored"][0]["downgrade"], "approval_verdict")

    def test_configured_login_surfaces_clean_approval_as_material(self) -> None:
        # An opt-in `approval_downgrade_logins` login routes the same clean
        # approval to the more-conservative material bucket instead of ignored.
        comment = {"id": 21, "author": {"login": "claude", "__typename": "Bot"},
                   "body": "Verdict: Approve. Checked every blocking criterion; "
                           "all blocking checks are inapplicable."}
        config = fb.FeedbackConfig(approval_downgrade_logins=frozenset({"claude"}))
        result = fb.collect_feedback(_pr([comment]), config=config)
        self.assertEqual(result["blocking"], [])
        self.assertEqual(len(result["material"]), 1)
        self.assertEqual(result["material"][0]["downgrade"], "approval_verdict")

    def test_approval_verdict_with_critical_marker_stays_blocking(self) -> None:
        pr = _pr([
            {"id": 22, "author": {"login": "claude", "__typename": "Bot"},
             "body": "Verdict: Approve overall. \U0001F534 CRITICAL: hardcoded "
                     "secret; must fix before merge."}
        ])
        result = fb.collect_feedback(pr)
        self.assertEqual(len(result["blocking"]), 1)
        self.assertEqual(result["material"], [])

    def test_request_changes_verdict_is_blocking(self) -> None:
        pr = _pr([
            {"id": 23, "author": {"login": "claude", "__typename": "Bot"},
             "body": "Verdict: Request changes. The endpoint skips the tenant "
                     "scope check."}
        ])
        result = fb.collect_feedback(pr)
        self.assertEqual(len(result["blocking"]), 1)

    def test_disposition_only_applies_at_matching_head(self) -> None:
        comment = {"id": 6, "author": {"login": "bugbot[bot]", "__typename": "Bot"},
                   "body": "P1 must fix regression."}
        dispositions = {"comment:6": {"head_sha": HEAD, "reason": "triaged stale"}}
        at_head = fb.collect_feedback(_pr([comment]), None, dispositions)
        self.assertEqual(at_head["blocking"], [])
        self.assertEqual(len(at_head["material"]), 1)
        self.assertEqual(at_head["material"][0]["disposed_reason"], "triaged stale")

        moved = fb.collect_feedback(_pr([comment], headRefOid="b" * 40), None,
                                    dispositions)
        self.assertEqual(len(moved["blocking"]), 1)
        self.assertEqual(moved["material"], [])

    def test_distinct_ids_are_not_collapsed(self) -> None:
        pr = _pr([
            {"id": 7, "author": {"login": "bugbot[bot]", "__typename": "Bot"},
             "body": "P1 must fix issue A"},
            {"id": 8, "author": {"login": "bugbot[bot]", "__typename": "Bot"},
             "body": "P1 must fix issue B"},
        ])
        result = fb.collect_feedback(pr)
        self.assertEqual(len(result["blocking"]), 2)

    def test_human_changes_requested_review_is_human_blocking(self) -> None:
        pr = _pr([], latestReviews=[
            {"id": 9, "author": {"login": "reviewer", "__typename": "User"},
             "state": "CHANGES_REQUESTED", "submittedAt": "2026-01-01T00:00:00Z"}
        ])
        result = fb.collect_feedback(pr)
        self.assertEqual(len(result["human_blocking"]), 1)
        self.assertEqual(result["blocking"], [])

    def test_ordinary_human_comment_is_notify_only(self) -> None:
        pr = _pr([
            {"id": 10, "author": {"login": "reviewer", "__typename": "User"},
             "body": "Looks nice, thanks for the change."}
        ])
        result = fb.collect_feedback(pr)
        self.assertEqual(result["human_blocking"], [])
        self.assertEqual(len(result["human"]), 1)

    def test_unresolved_inline_comment_is_human_blocking(self) -> None:
        pr = _pr([])
        inline = [{"id": 11, "author": {"login": "reviewer", "__typename": "User"},
                   "body": "consider renaming", "path": "src/x.py"}]
        result = fb.collect_feedback(pr, inline)
        self.assertEqual(len(result["human_blocking"]), 1)


class ReviewSupersessionTests(unittest.TestCase):
    def test_latest_approval_supersedes_older_changes_requested(self) -> None:
        pr = {
            "latestReviews": [],
            "reviews": [
                {"id": 1, "author": {"login": "rev", "__typename": "User"},
                 "state": "CHANGES_REQUESTED", "submittedAt": "2026-01-01T00:00:00Z"},
                {"id": 2, "author": {"login": "rev", "__typename": "User"},
                 "state": "APPROVED", "submittedAt": "2026-01-02T00:00:00Z"},
            ],
        }
        latest = fb.latest_reviews_by_author(pr)
        self.assertEqual(len(latest), 1)
        self.assertEqual(latest[0]["state"], "APPROVED")

    def test_differently_cased_login_still_collapses_to_one_latest_review(self) -> None:
        """GitHub logins are case-insensitive: 'Rev' and 'rev' are the same
        actor, so their reviews must collapse under one latest-review key."""
        pr = {
            "latestReviews": [],
            "reviews": [
                {"id": 1, "author": {"login": "Rev", "__typename": "User"},
                 "state": "CHANGES_REQUESTED", "submittedAt": "2026-01-01T00:00:00Z"},
                {"id": 2, "author": {"login": "rev", "__typename": "User"},
                 "state": "APPROVED", "submittedAt": "2026-01-02T00:00:00Z"},
            ],
        }
        latest = fb.latest_reviews_by_author(pr)
        self.assertEqual(len(latest), 1)
        self.assertEqual(latest[0]["state"], "APPROVED")

    def test_commented_review_does_not_clear_decisive_changes_request(self) -> None:
        pr = {
            "latestReviews": [],
            "reviews": [
                {"id": 1, "author": {"login": "rev", "__typename": "User"},
                 "state": "CHANGES_REQUESTED", "submittedAt": "2026-01-01T00:00:00Z"},
                {"id": 2, "author": {"login": "rev", "__typename": "User"},
                 "state": "COMMENTED", "submittedAt": "2026-01-02T00:00:00Z"},
            ],
        }
        decisive = fb.latest_reviews_by_author(pr, decisive_only=True)
        self.assertEqual(len(decisive), 1)
        self.assertEqual(decisive[0]["state"], "CHANGES_REQUESTED")


class DowngradeHeuristicTests(unittest.TestCase):
    def test_has_blocking_text_redacts_negated_findings(self) -> None:
        self.assertTrue(fb.has_blocking_text("P1 regression must fix"))
        self.assertFalse(fb.has_blocking_text("no P1 issues, no blocking findings"))

    def test_approval_downgrade_requires_clear_verdict_without_required_fix(self) -> None:
        self.assertTrue(fb.approval_downgrade("Approved; no blocking issues."))
        self.assertFalse(fb.approval_downgrade("Approved, but P1 must fix remains."))
        self.assertFalse(fb.approval_downgrade("Not approving this change yet."))

    def test_approval_downgrade_rejects_critical_or_important_marker(self) -> None:
        self.assertFalse(fb.approval_downgrade("Approve, but CRITICAL: fix this."))
        self.assertFalse(fb.approval_downgrade("Approve. IMPORTANT: revisit."))
        # Lowercase severity words are ordinary prose, not markers.
        self.assertTrue(
            fb.approval_downgrade("Approve; it is important to note the nit.")
        )

    def test_has_blocking_severity_matches_only_uppercase_markers(self) -> None:
        self.assertTrue(fb.has_blocking_severity("CRITICAL: null deref"))
        self.assertTrue(fb.has_blocking_severity("IMPORTANT: revisit this"))
        self.assertFalse(fb.has_blocking_severity("this is a critical path"))
        self.assertFalse(fb.has_blocking_severity("SUGGESTION: rename the var"))

    def test_negated_severity_marker_is_not_blocking(self) -> None:
        # A clean approval stating the absence of high-severity findings uses the
        # same structured vocabulary in its verdict; it must not re-introduce a
        # false blocker (the mirror of no-P1/P2 redaction for CRITICAL/IMPORTANT).
        self.assertFalse(
            fb.has_blocking_severity("No CRITICAL or IMPORTANT findings.")
        )
        self.assertFalse(fb.has_blocking_severity("No CRITICAL issues found."))
        self.assertTrue(
            fb.approval_downgrade(
                "Verdict: Approve. No CRITICAL or IMPORTANT findings."
            )
        )
        # A live marker without a negator still blocks.
        self.assertTrue(fb.has_blocking_severity("CRITICAL: null deref remains"))

    def test_skip_downgrade_only_when_review_could_not_run(self) -> None:
        self.assertTrue(
            fb.skip_downgrade("bugbot skipped: usage limit reached. Not approving.")
        )
        self.assertFalse(fb.skip_downgrade("Not approving; P1 regression found."))

    def test_skip_downgrade_rejects_live_severity_marker(self) -> None:
        # A skip comment carrying a genuine CRITICAL/IMPORTANT marker has no
        # imperative blocking text, so has_blocking_text alone would let it
        # downgrade; the severity guard keeps the live finding blocking.
        self.assertFalse(
            fb.skip_downgrade(
                "bugbot skipped: usage limit reached. Not approving. "
                "CRITICAL: authorization bypass."
            )
        )
        self.assertFalse(
            fb.skip_downgrade(
                "bugbot skipped: usage limit reached. Not approving. "
                "IMPORTANT: unbounded retry loop."
            )
        )
        # A negated severity conclusion still downgrades -- it is not a finding.
        self.assertTrue(
            fb.skip_downgrade(
                "bugbot skipped: usage limit reached. Not approving. "
                "No CRITICAL or IMPORTANT issues seen before the cutoff."
            )
        )


if __name__ == "__main__":
    unittest.main()
