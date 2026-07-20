"""Per-PR classifier and fan-out delta engine.

Ports the pull-request classification coverage onto `babysit_delta`: branch
freshness, the trust-boundary mutation policy, foreign-activity (L3)
detection, the twelve `worker_actionable_delta` arms (each suppressible arm
tested on both the direct-gate-ready and not-ready sides), the quiet-recheck
and branch-uniqueness-cleared paths, and cadence recommendation.
"""

from __future__ import annotations

import pathlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import babysit_delta as delta
import babysit_review_trigger as review_trigger

HEAD = "a" * 40
OLD = "c" * 40
OBS = "2026-07-10T00:00:00Z"
UPD = "2026-07-09T00:00:00Z"
CONFIG = delta.ClassifyConfig(allowed_owners=frozenset({"owner"}))

BOT_ERROR = {"author": {"login": "b[bot]", "__typename": "Bot"},
             "body": "encountered an error running"}
BOT_P1 = {"author": {"login": "b[bot]", "__typename": "Bot"},
          "body": "P1 must fix regression"}
HUMAN_BLOCKING = {"author": {"login": "person", "__typename": "User"},
                  "body": "must fix this blocking issue"}


def make_pr(**over: object) -> dict[str, object]:
    pr = {
        "repo": "owner/repo", "number": 1, "url": "u", "title": "t", "state": "OPEN",
        "author": {"login": "someone", "__typename": "User"},
        "headRefName": "feature", "headRefOid": HEAD, "baseRefName": "main",
        "baseRefOid": "b" * 40, "headRepository": {"nameWithOwner": "owner/repo"},
        "headRepositoryOwner": {"login": "owner"}, "isCrossRepository": False,
        "isDraft": False, "maintainerCanModify": True, "baseRepositoryArchived": False,
        "mergeStateStatus": "CLEAN", "mergeable": "MERGEABLE", "reviewDecision": "",
        "reviews": [], "latestReviews": [], "comments": [], "statusCheckRollup": [],
        "updatedAt": UPD,
    }
    pr.update(over)
    return pr


def make_prev(**over: object) -> dict[str, object]:
    prev = {
        "head_sha": HEAD, "updated_at": UPD, "is_draft": False, "merge_state": "CLEAN",
        "human_stop": {"required": False}, "blocking_feedback_ids": [],
        "material_feedback_ids": [], "human_feedback_ids": [],
        "human_blocking_feedback_ids": [], "checks_failing": [], "checks_pending": [],
        "checks_failing_identities": [], "checks_pending_identities": [],
        "last_worker_checkin_at": "", "last_worker_checkin_head_sha": HEAD,
        "pending_worker_dispatch_head_sha": "",
        "pending_worker_dispatch_unsuppressible": False,
        "pending_worker_dispatch_recorded_at": "",
    }
    prev.update(over)
    return prev


def classify(pr: dict[str, object], prev: dict[str, object] | None,
             config: delta.ClassifyConfig = CONFIG) -> dict[str, object]:
    return delta.classify_pr(pr, prev, None, OBS, config=config)


class BranchFreshnessTests(unittest.TestCase):
    def test_behind_merge_state_is_behind(self) -> None:
        result = delta.compute_branch_freshness(make_pr(mergeStateStatus="BEHIND"))
        self.assertEqual(result["state"], "behind")

    def test_dirty_or_conflicting_is_conflicting(self) -> None:
        self.assertEqual(
            delta.compute_branch_freshness(make_pr(mergeStateStatus="DIRTY"))["state"],
            "conflicting",
        )
        self.assertEqual(
            delta.compute_branch_freshness(
                make_pr(mergeStateStatus="CLEAN", mergeable="CONFLICTING"))["state"],
            "conflicting",
        )

    def test_unknown_merge_state_is_unknown(self) -> None:
        self.assertEqual(
            delta.compute_branch_freshness(make_pr(mergeStateStatus=""))["state"],
            "unknown",
        )

    def test_blocked_with_compare_confirmed_divergence_is_behind(self) -> None:
        pr = make_pr(mergeStateStatus="BLOCKED",
                     _blocked_base_compare={"status": "behind", "behind_by": 3})
        result = delta.compute_branch_freshness(pr)
        self.assertEqual(result["state"], "behind")
        self.assertEqual(result["source"], "compare_api")

    def test_blocked_without_compare_signal_is_not_reported_behind(self) -> None:
        result = delta.compute_branch_freshness(make_pr(mergeStateStatus="BLOCKED"))
        self.assertEqual(result["state"], "not_reported_behind")


class MutationPolicyTests(unittest.TestCase):
    def test_same_repo_pr_allows_branch_writes(self) -> None:
        policy = delta.head_repository_scope(make_pr(), frozenset({"owner"}))
        self.assertTrue(policy["branch_write_allowed"])
        self.assertTrue(policy["review_trigger_allowed"])

    def test_external_fork_is_monitored_but_not_write_allowed(self) -> None:
        pr = make_pr(isCrossRepository=True,
                     headRepository={"nameWithOwner": "fork/repo"},
                     headRepositoryOwner={"login": "fork"})
        policy = delta.head_repository_scope(pr, frozenset({"owner"}))
        self.assertTrue(policy["review_trigger_allowed"])
        self.assertFalse(policy["branch_write_allowed"])

    def test_archived_base_disables_mutation(self) -> None:
        policy = delta.head_repository_scope(
            make_pr(baseRepositoryArchived=True), frozenset({"owner"}))
        self.assertFalse(policy["review_trigger_allowed"])

    def test_owner_not_in_allowlist_is_not_allowed(self) -> None:
        policy = delta.head_repository_scope(make_pr(), frozenset({"other"}))
        self.assertFalse(policy["base_repo_allowed"])

    def test_incomplete_head_metadata_fails_closed(self) -> None:
        pr = make_pr(headRepository=None, isCrossRepository=None)
        policy = delta.head_repository_scope(pr, frozenset({"owner"}))
        self.assertFalse(policy["head_metadata_complete"])
        self.assertFalse(policy["branch_write_allowed"])


class ClassificationStatusTests(unittest.TestCase):
    def test_failing_check_is_active(self) -> None:
        pr = make_pr(statusCheckRollup=[
            {"__typename": "CheckRun", "name": "ci", "conclusion": "FAILURE"}])
        self.assertEqual(classify(pr, None)["classification"], "active")

    def test_new_clean_pr_is_normal(self) -> None:
        self.assertEqual(classify(make_pr(), None)["classification"], "normal")

    def test_unchanged_clean_open_pr_is_quiet(self) -> None:
        self.assertEqual(classify(make_pr(), make_prev())["classification"], "quiet")


class ForeignActivityTests(unittest.TestCase):
    def _config(self) -> delta.ClassifyConfig:
        return delta.ClassifyConfig(
            allowed_owners=frozenset({"owner"}),
            self_logins=frozenset({"me"}),
            review_trigger=review_trigger.ReviewTriggerConfig(
                trigger_phrase="please review",
                reviewer_logins=frozenset({"reviewbot"}),
                gate_context="gate"),
        )

    def test_dormant_without_phrase_or_self_logins(self) -> None:
        pr = make_pr(comments=[{"author": {"login": "me"},
                                "body": "please review", "databaseId": 100}])
        result = delta.detect_foreign_activity(pr, None, CONFIG)
        self.assertFalse(result["detected"])

    def test_detects_self_login_trigger_absent_from_ledger(self) -> None:
        pr = make_pr(comments=[{"author": {"login": "me"},
                                "body": "please review", "databaseId": 100}])
        result = delta.detect_foreign_activity(pr, None, self._config())
        self.assertTrue(result["detected"])
        self.assertEqual(result["evidence"][0]["comment_id"], "100")

    def test_ignores_trigger_recorded_in_our_own_ledger(self) -> None:
        pr = make_pr(comments=[{"author": {"login": "me"},
                                "body": "please review", "databaseId": 100}])
        prev = {"review_trigger": {"request_history": {HEAD: {"comment_id": "100"}}}}
        result = delta.detect_foreign_activity(pr, prev, self._config())
        self.assertFalse(result["detected"])


class AttributionDriftTests(unittest.TestCase):
    """A recorded write landing under a self-login other than the intended one."""

    def _config(self, intended: str = "bot") -> delta.ClassifyConfig:
        return delta.ClassifyConfig(
            allowed_owners=frozenset({"owner"}),
            self_logins=frozenset({"bot", "personal"}),
            intended_write_identity=intended,
        )

    def _ledger_prev(self) -> dict[str, object]:
        return {"review_trigger": {"request_history": {HEAD: {"comment_id": "100"}}}}

    def _recorded_write(self, author: str) -> dict[str, object]:
        return make_pr(comments=[{"author": {"login": author},
                                  "body": "please review", "databaseId": 100}])

    def test_dormant_without_intended_identity(self) -> None:
        pr = self._recorded_write("personal")
        result = delta.detect_attribution_drift(pr, self._ledger_prev(),
                                                self._config(intended=""))
        self.assertFalse(result["detected"])

    def test_detects_recorded_write_landed_under_other_self_login(self) -> None:
        pr = self._recorded_write("personal")
        result = delta.detect_attribution_drift(pr, self._ledger_prev(),
                                                self._config())
        self.assertTrue(result["detected"])
        self.assertEqual(result["evidence"][0]["landed_author"], "personal")
        self.assertEqual(result["evidence"][0]["intended_author"], "bot")

    def test_no_drift_when_landed_under_intended_identity(self) -> None:
        pr = self._recorded_write("bot")
        result = delta.detect_attribution_drift(pr, self._ledger_prev(),
                                                self._config())
        self.assertFalse(result["detected"])

    def test_unledgered_write_is_not_drift(self) -> None:
        pr = self._recorded_write("personal")
        result = delta.detect_attribution_drift(pr, None, self._config())
        self.assertFalse(result["detected"])

    def test_drift_surfaces_as_material_finding_via_classify(self) -> None:
        # Acceptance path: the finding must ride the cycle-status material
        # channel, not merely the raw detector return -- and with no gh-bot.sh
        # (token wrapper) in the loop at all.
        pr = self._recorded_write("personal")
        prev = make_prev(review_trigger={"request_history":
                                         {HEAD: {"comment_id": "100"}}})
        result = delta.classify_pr(pr, prev, None, OBS, config=self._config())
        self.assertTrue(result["attribution_drift"]["detected"])
        self.assertTrue(
            any("attribution drift" in finding
                for finding in result["material_findings"]),
            result["material_findings"],
        )


class SuppressibleDeltaArmTests(unittest.TestCase):
    """Each suppressible arm: reason present only when NOT direct-gate-ready."""

    def _assert_arm(self, arm: str, pr_over: dict[str, object],
                    prev_over: dict[str, object], *, comments=None) -> None:
        clean_pr = make_pr(**pr_over)
        if comments is not None:
            clean_pr["comments"] = comments
        clean = classify(clean_pr, make_prev(**prev_over))
        self.assertTrue(clean["pr_clean_ready_for_direct_gate"])
        self.assertNotIn(arm, clean["needs_worker_reasons"])
        self.assertFalse(clean["needs_worker"])

        not_ready_over = {**pr_over, "mergeStateStatus": "UNKNOWN"}
        not_ready_prev = {**prev_over, "merge_state": "UNKNOWN"}
        not_ready_pr = make_pr(**not_ready_over)
        if comments is not None:
            not_ready_pr["comments"] = comments
        fired = classify(not_ready_pr, make_prev(**not_ready_prev))
        self.assertFalse(fired["pr_clean_ready_for_direct_gate"])
        self.assertIn(arm, fired["needs_worker_reasons"])
        self.assertTrue(fired["needs_worker"])

    def test_new_to_state(self) -> None:
        clean = classify(make_pr(), None)
        self.assertFalse(clean["needs_worker"])
        fired = classify(make_pr(mergeStateStatus="UNKNOWN"), None)
        self.assertIn("new_to_state", fired["needs_worker_reasons"])
        self.assertTrue(fired["needs_worker"])

    def test_head_sha_changed(self) -> None:
        self._assert_arm("head_sha_changed", {},
                         {"head_sha": OLD, "last_worker_checkin_head_sha": HEAD})

    def test_resolved_human_blocking(self) -> None:
        self._assert_arm("resolved_human_blocking", {},
                         {"human_stop": {"required": True}})

    def test_resolved_blocking_feedback(self) -> None:
        self._assert_arm("resolved_blocking_feedback", {},
                         {"blocking_feedback_ids": ["comment:x"]})

    def test_checks_changed(self) -> None:
        self._assert_arm(
            "checks_changed", {},
            {"checks_failing_identities": [
                {"type": "CheckRun", "name": "ci", "workflow_name": "wf"}]})

    def test_worker_checkin_head_unconfirmed(self) -> None:
        self._assert_arm("worker_checkin_head_unconfirmed", {},
                         {"last_worker_checkin_head_sha": OLD})

    def test_merge_state_became_actionable(self) -> None:
        # This arm requires the current merge state to be actionable (CLEAN),
        # so the not-ready side is reached with untriaged material rather than a
        # non-actionable merge state.
        clean = classify(make_pr(), make_prev(merge_state="UNKNOWN"))
        self.assertTrue(clean["pr_clean_ready_for_direct_gate"])
        self.assertNotIn("merge_state_became_actionable",
                         clean["needs_worker_reasons"])
        self.assertFalse(clean["needs_worker"])

        fired = classify(make_pr(comments=[BOT_ERROR]),
                         make_prev(merge_state="UNKNOWN"))
        self.assertFalse(fired["pr_clean_ready_for_direct_gate"])
        self.assertIn("merge_state_became_actionable", fired["needs_worker_reasons"])
        self.assertTrue(fired["needs_worker"])


class UnsuppressibleDeltaArmTests(unittest.TestCase):
    """Each unsuppressible arm fires even on an otherwise direct-gate-ready PR."""

    def test_new_blocking_feedback(self) -> None:
        result = classify(make_pr(comments=[BOT_P1]), make_prev())
        self.assertIn("new_blocking_feedback", result["needs_worker_reasons"])
        self.assertTrue(result["needs_worker"])

    def test_new_material_feedback(self) -> None:
        result = classify(make_pr(comments=[BOT_ERROR]), make_prev())
        self.assertIn("new_material_feedback", result["needs_worker_reasons"])
        self.assertTrue(result["needs_worker"])

    def test_new_human_blocking_feedback(self) -> None:
        result = classify(make_pr(comments=[HUMAN_BLOCKING]), make_prev())
        self.assertIn("new_human_blocking_feedback", result["needs_worker_reasons"])
        self.assertTrue(result["needs_worker"])

    def test_became_ready_for_review_fires_even_when_clean(self) -> None:
        result = classify(make_pr(), make_prev(is_draft=True))
        self.assertTrue(result["pr_clean_ready_for_direct_gate"])
        self.assertIn("became_ready_for_review", result["needs_worker_reasons"])
        self.assertTrue(result["needs_worker"])


class SelfLoginHumanFeedbackExclusionTests(unittest.TestCase):
    """The engine must not dispatch a worker onto its own prior-round replies.

    A solo maintainer whose login is the configured self-login posts every
    worker classification reply and `Fixed in <sha>` follow-up under that login.
    Counting those as new human feedback manufactures a self-inflicted,
    unsuppressible `new_human_blocking_feedback` dispatch that re-fires forever
    (issue #473). The bot arms are self-filtered structurally; the human arm
    needs an explicit self-login filter -- but only over the *new-feedback
    deltas*, never the classification itself.
    """

    SELF = frozenset({"solo"})
    CONFIG = delta.ClassifyConfig(allowed_owners=frozenset({"owner"}),
                                  self_logins=SELF)
    SELF_BLOCKING = {"author": {"login": "solo", "__typename": "User"},
                     "body": "must fix this blocking issue"}
    # GitHub logins are case-insensitive: a differently-cased self login must
    # still be recognized, matching the casefold the engine applies.
    SELF_BLOCKING_MIXED_CASE = {"author": {"login": "SoLo", "__typename": "User"},
                                "body": "must fix this blocking issue"}
    OTHER_BLOCKING = {"author": {"login": "reviewer", "__typename": "User"},
                      "body": "must fix this blocking issue"}
    SELF_NONBLOCKING = {"author": {"login": "solo", "__typename": "User"},
                        "body": "small stylistic note, take it or leave it"}
    OTHER_NONBLOCKING = {"author": {"login": "reviewer", "__typename": "User"},
                         "body": "small stylistic note, take it or leave it"}

    def test_self_login_reply_does_not_manufacture_dispatch(self) -> None:
        # A recent worker check-in suppresses the bounded `quiet_recheck_due`
        # fallback, so the only signal that could still dispatch is the
        # (unsuppressible) new_human_blocking_feedback delta. Filtered out for a
        # self-authored comment, it must leave the PR needing no worker.
        result = classify(make_pr(comments=[self.SELF_BLOCKING]),
                          make_prev(last_worker_checkin_at=OBS), self.CONFIG)
        self.assertNotIn("new_human_blocking_feedback",
                         result["needs_worker_reasons"])
        self.assertFalse(result["needs_worker"])

    def test_self_login_match_is_case_insensitive(self) -> None:
        result = classify(make_pr(comments=[self.SELF_BLOCKING_MIXED_CASE]),
                          make_prev(last_worker_checkin_at=OBS), self.CONFIG)
        self.assertNotIn("new_human_blocking_feedback",
                         result["needs_worker_reasons"])
        self.assertFalse(result["needs_worker"])

    def test_self_login_item_is_still_classified_human_blocking(self) -> None:
        # Deliberate scope: the comment is excluded only from the dispatch
        # delta, not from classification -- so a genuine "do not merge" comment
        # the maintainer posts under their own login still halts the merge gate.
        result = classify(make_pr(comments=[self.SELF_BLOCKING]),
                          make_prev(last_worker_checkin_at=OBS), self.CONFIG)
        authors = [item["author"]
                   for item in result["feedback"]["human_blocking"]]
        self.assertEqual(authors, ["solo"])
        self.assertTrue(result["human_stop"]["required"])
        self.assertFalse(result["pr_clean_ready_for_direct_gate"])

    def test_other_login_still_fires_under_same_config(self) -> None:
        # The filter is login-specific, not a blanket human-feedback mute:
        # genuine feedback from any other login must still dispatch a worker,
        # even with a recent check-in that suppresses the quiet-recheck fallback.
        result = classify(make_pr(comments=[self.OTHER_BLOCKING]),
                          make_prev(last_worker_checkin_at=OBS), self.CONFIG)
        self.assertIn("new_human_blocking_feedback",
                      result["needs_worker_reasons"])
        self.assertTrue(result["needs_worker"])

    def test_self_login_nonblocking_excluded_from_new_feedback_human(self) -> None:
        # The self-login filter over the new-human-feedback delta also covers the
        # non-blocking `human` arm surfaced in new_feedback["human"]: a self-authored
        # non-blocking comment stays classified human -- so it never hollows out the
        # maintainer's own signal -- but must not be re-surfaced to the orchestrator
        # as new feedback every cycle.
        result = classify(make_pr(comments=[self.SELF_NONBLOCKING]),
                          make_prev(last_worker_checkin_at=OBS), self.CONFIG)
        self.assertEqual([item["author"]
                          for item in result["feedback"]["human"]], ["solo"])
        self.assertEqual(result["new_feedback"]["human"], [])

    def test_other_login_nonblocking_still_surfaces_as_new_feedback(self) -> None:
        # The non-blocking-arm filter is login-specific, not a blanket mute: a
        # non-blocking comment from any other login must still surface as new
        # human feedback for the orchestrator to relay.
        result = classify(make_pr(comments=[self.OTHER_NONBLOCKING]),
                          make_prev(last_worker_checkin_at=OBS), self.CONFIG)
        self.assertEqual([item["author"]
                          for item in result["new_feedback"]["human"]], ["reviewer"])


class DispatchPendingUnconfirmedTests(unittest.TestCase):
    def test_pending_dispatch_survives_direct_gate_readiness(self) -> None:
        prev = make_prev(pending_worker_dispatch_head_sha=HEAD,
                         pending_worker_dispatch_unsuppressible=True,
                         pending_worker_dispatch_recorded_at=OBS,
                         last_worker_checkin_at="")
        result = classify(make_pr(), prev)
        self.assertTrue(result["pr_clean_ready_for_direct_gate"])
        self.assertIn("dispatch_pending_unconfirmed", result["needs_worker_reasons"])
        self.assertTrue(result["needs_worker"])

    def test_pending_dispatch_clears_once_a_later_checkin_confirms(self) -> None:
        prev = make_prev(pending_worker_dispatch_head_sha=HEAD,
                         pending_worker_dispatch_unsuppressible=True,
                         pending_worker_dispatch_recorded_at=OBS,
                         last_worker_checkin_at="2026-07-10T01:00:00Z")
        result = classify(make_pr(), prev)
        self.assertNotIn("dispatch_pending_unconfirmed",
                         result["needs_worker_reasons"])
        self.assertFalse(result["needs_worker"])


class QuietRecheckTests(unittest.TestCase):
    def test_quiet_recheck_forces_worker_when_no_checkin_recorded(self) -> None:
        prev = make_prev(merge_state="UNKNOWN")
        result = classify(make_pr(mergeStateStatus="UNKNOWN"), prev)
        self.assertIn("quiet_recheck_due", result["needs_worker_reasons"])
        self.assertTrue(result["needs_worker"])

    def test_recent_checkin_suppresses_quiet_recheck(self) -> None:
        prev = make_prev(merge_state="UNKNOWN", last_worker_checkin_at=OBS)
        result = classify(make_pr(mergeStateStatus="UNKNOWN"), prev)
        self.assertNotIn("quiet_recheck_due", result["needs_worker_reasons"])
        self.assertFalse(result["needs_worker"])


class HeadRefGuardTests(unittest.TestCase):
    def test_shared_head_disables_writes_for_matching_pr(self) -> None:
        pr = classify(make_pr(), None)
        delta.apply_head_ref_guard(pr, checked=True,
                                   matching_prs=[pr["key"], "owner/repo#2"],
                                   prev_unique=None)
        self.assertFalse(pr["head_ref_uniqueness"]["unique"])
        self.assertFalse(pr["mutation_policy"]["branch_write_allowed"])
        self.assertEqual(pr["classification"], "active")
        self.assertIn("head branch is shared by multiple open PRs; user decision "
                      "required", pr["blockers"])

    def test_uniqueness_cleared_forces_worker_when_not_direct_gate_ready(self) -> None:
        prev = make_prev(merge_state="UNKNOWN", last_worker_checkin_at=OBS)
        pr = classify(make_pr(mergeStateStatus="UNKNOWN"), prev)
        self.assertFalse(pr["needs_worker"])
        delta.apply_head_ref_guard(pr, checked=True, matching_prs=[pr["key"]],
                                   prev_unique=False)
        self.assertTrue(pr["needs_worker"])
        self.assertIn("branch_uniqueness_cleared", pr["needs_worker_reasons"])
        self.assertEqual(pr["pending_worker_dispatch_head_sha"], HEAD)

    def test_uniqueness_cleared_suppressed_on_direct_gate_ready_pr(self) -> None:
        pr = classify(make_pr(), make_prev())
        self.assertFalse(pr["needs_worker"])
        delta.apply_head_ref_guard(pr, checked=True, matching_prs=[pr["key"]],
                                   prev_unique=False)
        self.assertFalse(pr["needs_worker"])
        self.assertNotIn("branch_uniqueness_cleared", pr["needs_worker_reasons"])


class QuietRecheckOverrideTests(unittest.TestCase):
    def test_positive_override_is_accepted(self) -> None:
        self.assertEqual(delta.validated_max_quiet_recheck_seconds(120), 120.0)

    def test_non_positive_and_non_finite_overrides_are_rejected(self) -> None:
        for value in (0, -1, float("inf"), float("nan")):
            with self.subTest(value=value), self.assertRaises(ValueError):
                delta.validated_max_quiet_recheck_seconds(value)

    def test_invalid_override_fails_on_a_clean_pr_path_too(self) -> None:
        config = delta.ClassifyConfig(allowed_owners=frozenset({"owner"}),
                                      max_quiet_recheck_seconds=0)
        with self.assertRaises(ValueError):
            delta.classify_pr(make_pr(), None, None, OBS, config=config)


class RecommendCadenceTests(unittest.TestCase):
    def test_cadence_precedence(self) -> None:
        self.assertEqual(delta.recommend_cadence([]), "idle")
        self.assertEqual(delta.recommend_cadence(["quiet"]), "quiet")
        self.assertEqual(delta.recommend_cadence(["normal", "quiet"]), "normal")
        self.assertEqual(delta.recommend_cadence(["active", "normal"]), "active")


if __name__ == "__main__":
    unittest.main()
