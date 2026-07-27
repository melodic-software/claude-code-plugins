"""Config-driven review-trigger gate and request-state machine.

Ports the review-trigger coverage onto `babysit_review_trigger`, reoriented
from the monolith's CLI race suite to the module's pure config-driven surface:
the gate is dormant until configured, and the trigger recognizer derives from
exactly one configured phrase.
"""

from __future__ import annotations

import pathlib
import sys
import unittest
from unittest import mock

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import babysit_checks as checks
import babysit_review_trigger as review_trigger
import request_review

HEAD = "a" * 40


def _reaction(reaction_id: str, *, scope: str = "pull_request",
              content: str = "+1", created_at: str = "2026-07-09T00:00:00Z",
              comment_id: str = "") -> dict[str, str]:
    return {
        "id": f"{scope}:{reaction_id}",
        "reaction_id": reaction_id,
        "author": "reviewbot",
        "content": content,
        "created_at": created_at,
        "scope": scope,
        "comment_id": comment_id,
    }


def configured() -> review_trigger.ReviewTriggerConfig:
    return review_trigger.ReviewTriggerConfig(
        trigger_phrase="please review",
        reviewer_logins=frozenset({"reviewbot"}),
        gate_context="review-gate",
        ci_gateway_context="ci-gate",
    )


def declared_non_structural() -> review_trigger.ReviewTriggerConfig:
    """`configured()` plus the reviewer declared a non-structural bot account."""
    return review_trigger.ReviewTriggerConfig(
        trigger_phrase="please review",
        reviewer_logins=frozenset({"reviewbot"}),
        gate_context="review-gate",
        ci_gateway_context="ci-gate",
        extra_bot_logins=frozenset({"reviewbot"}),
    )


class ConfigTests(unittest.TestCase):
    def test_default_config_is_not_configured(self) -> None:
        self.assertFalse(review_trigger.DEFAULT_REVIEW_TRIGGER_CONFIG.configured)

    def test_partial_config_is_not_configured(self) -> None:
        partial = review_trigger.ReviewTriggerConfig(trigger_phrase="please review")
        self.assertFalse(partial.configured)

    def test_full_config_is_configured(self) -> None:
        self.assertTrue(configured().configured)


class TriggerRegexTests(unittest.TestCase):
    def test_recognizer_derives_from_the_configured_phrase(self) -> None:
        recognizer = review_trigger.trigger_regex("please review")
        assert recognizer is not None
        self.assertTrue(recognizer.fullmatch("please review"))
        self.assertTrue(recognizer.fullmatch("  please   review  "))
        self.assertTrue(recognizer.fullmatch("please review for security"))
        self.assertIsNone(recognizer.fullmatch("something unrelated"))

    def test_special_characters_in_phrase_are_escaped(self) -> None:
        recognizer = review_trigger.trigger_regex("@codex review")
        assert recognizer is not None
        self.assertTrue(recognizer.fullmatch("@codex review"))
        self.assertIsNone(recognizer.fullmatch("xcodex review"))

    def test_empty_phrase_yields_no_recognizer(self) -> None:
        self.assertIsNone(review_trigger.trigger_regex(""))


class ReviewGateStateTests(unittest.TestCase):
    def test_dormant_gate_is_absent_when_unconfigured(self) -> None:
        rollup = [{"__typename": "StatusContext", "context": "review-gate",
                   "state": "PENDING", "targetUrl": ""}]
        gate = review_trigger.review_gate_state(
            checks.classify_checks(rollup),
            review_trigger.DEFAULT_REVIEW_TRIGGER_CONFIG)
        self.assertEqual(gate["gate_state"], "absent")
        self.assertFalse(gate["request_signal_pending"])
        # No ci_gateway_context configured -> the gateway is treated as
        # satisfied. Harmless while dormant: gate_state "absent" still blocks
        # candidacy (see test_dormant_gate_never_produces_a_candidate).
        self.assertTrue(gate["ci_gateway_green"])

    def test_unset_ci_gateway_context_is_treated_as_green(self) -> None:
        # A configured gate with no ci_gateway_context (the documented
        # gateway-unused fallback) must not stall the trigger forever.
        config = review_trigger.ReviewTriggerConfig(
            trigger_phrase="please review",
            reviewer_logins=frozenset({"reviewbot"}),
            gate_context="review-gate",
            ci_gateway_context="",
        )
        rollup = [{"__typename": "StatusContext", "context": "review-gate",
                   "state": "PENDING", "targetUrl": ""}]
        gate = review_trigger.review_gate_state(
            checks.classify_checks(rollup), config)
        self.assertEqual(gate["gate_state"], "pending")
        self.assertTrue(gate["ci_gateway_green"])

    def test_configured_gate_reflects_the_matching_context(self) -> None:
        rollup = [
            {"__typename": "StatusContext", "context": "review-gate",
             "state": "PENDING", "targetUrl": ""},
            {"__typename": "CheckRun", "name": "ci-gate", "conclusion": "SUCCESS"},
        ]
        gate = review_trigger.review_gate_state(
            checks.classify_checks(rollup), configured())
        self.assertEqual(gate["gate_state"], "pending")
        self.assertTrue(gate["request_signal_pending"])
        self.assertTrue(gate["ci_gateway_green"])
        self.assertTrue(gate["non_review_checks_green"])


class FailingGateIsNotAnEngagementSignalTests(unittest.TestCase):
    """A failing `<review-gate-context>` never becomes a trigger candidate; it
    is passed through as its own reported state for the operator to act on."""

    def _rollup(self) -> list[dict[str, object]]:
        # The gate StatusContext is the ONLY non-success check, and it is
        # excluded from `non_review_checks`, so every other conjunct of
        # `request_eligible` holds -- the gate state is the isolated variable.
        return [
            {"__typename": "StatusContext", "context": "review-gate",
             "state": "FAILURE", "targetUrl": ""},
            {"__typename": "CheckRun", "name": "ci-gate", "conclusion": "SUCCESS"},
        ]

    def test_failing_gate_is_not_a_pending_request_signal(self) -> None:
        gate = review_trigger.review_gate_state(
            checks.classify_checks(self._rollup()), configured())
        self.assertEqual(gate["gate_state"], "failing")
        self.assertFalse(gate["request_signal_pending"])
        self.assertTrue(gate["ci_gateway_green"])
        self.assertTrue(gate["non_review_checks_green"])

    def test_failing_gate_never_becomes_a_candidate(self) -> None:
        gate = review_trigger.review_gate_state(
            checks.classify_checks(self._rollup()), configured())
        pr = {"headRefOid": HEAD, "mergeStateStatus": "CLEAN",
              "mergeable": "MERGEABLE", "state": "OPEN", "isDraft": False,
              "reviews": []}
        result = review_trigger.classify_review_request(
            pr, gate, {}, "2026-07-10T00:00:00Z",
            review_trigger_allowed=True, config=configured())
        self.assertFalse(result["request_eligible"])
        self.assertEqual(result["missing_head_sha"], "")
        self.assertEqual(result["state"], "failing")

    def test_failing_gate_surfaces_as_an_ordinary_failing_check(self) -> None:
        # Why excluding it from candidacy is not a silent dead-end: the gate
        # StatusContext is bucketed like any other check, so babysit_delta
        # raises its failing-check blocker.
        classified = checks.classify_checks(self._rollup())
        self.assertEqual(classified["failing"], ["review-gate"])


class ReviewBotItemTests(unittest.TestCase):
    def test_configured_reviewer_bot_is_recognized(self) -> None:
        item = {"author": {"__typename": "Bot", "login": "reviewbot[bot]"}}
        self.assertTrue(review_trigger.is_review_bot_item(item, configured()))

    def test_human_author_is_not_a_review_bot(self) -> None:
        # Also the dormant-default pin for the `extra_bot_logins` widening: with
        # the field unset, a `User`-typed author is refused however the reviewer
        # set reads, so no unconfigured consumer's behavior moves.
        item = {"author": {"__typename": "User", "login": "reviewbot"}}
        self.assertFalse(review_trigger.is_review_bot_item(item, configured()))

    def test_unlisted_bot_is_not_a_review_bot(self) -> None:
        item = {"author": {"__typename": "Bot", "login": "otherbot[bot]"}}
        self.assertFalse(review_trigger.is_review_bot_item(item, configured()))

    def test_declared_user_typed_reviewer_is_a_review_bot(self) -> None:
        item = {"author": {"__typename": "User", "login": "reviewbot"}}
        self.assertTrue(
            review_trigger.is_review_bot_item(item, declared_non_structural()))

    def test_declared_login_outside_the_reviewer_set_is_not_a_review_bot(self) -> None:
        # The reviewer-set bound survives the widening: declaring an account a
        # bot never promotes it to reviewer.
        config = review_trigger.ReviewTriggerConfig(
            trigger_phrase="please review",
            reviewer_logins=frozenset({"reviewbot"}),
            gate_context="review-gate",
            extra_bot_logins=frozenset({"otherbot"}),
        )
        item = {"author": {"__typename": "User", "login": "otherbot"}}
        self.assertFalse(review_trigger.is_review_bot_item(item, config))

    def test_rest_user_typed_reviewer_is_recognized_when_declared(self) -> None:
        # REST payloads carry `type`, not `__typename`.
        item = {"author": {"type": "User", "login": "reviewbot"}}
        self.assertTrue(
            review_trigger.is_review_bot_item(item, declared_non_structural()))


class UserTypedReviewerConsumerTests(unittest.TestCase):
    """Every `is_review_bot_item` consumer honors a declared `User`-typed reviewer."""

    def _reviews(self) -> list[dict[str, object]]:
        return [{
            "id": "R1",
            "author": {"__typename": "User", "login": "reviewbot"},
            "state": "COMMENTED",
            "commit": {"oid": HEAD},
            "url": "https://example.invalid/r1",
        }]

    def _review_comments(self) -> list[dict[str, object]]:
        return [{
            "id": 7,
            "user": {"type": "User", "login": "reviewbot"},
            "commit_id": HEAD,
            "html_url": "https://example.invalid/c7",
        }]

    def test_evidence_accepts_a_declared_user_typed_reviewer(self) -> None:
        evidence = review_trigger.fetch_review_evidence(
            "owner/repo", 42, self._reviews(), self._review_comments(),
            config=declared_non_structural())
        self.assertEqual(
            [item["id"] for item in evidence], ["review:R1", "review_comment:7"])

    def test_evidence_refuses_the_same_reviewer_when_undeclared(self) -> None:
        evidence = review_trigger.fetch_review_evidence(
            "owner/repo", 42, self._reviews(), self._review_comments(),
            config=configured())
        self.assertEqual(evidence, [])

    def test_current_head_review_accepts_a_declared_user_typed_reviewer(self) -> None:
        pr = {"headRefOid": HEAD, "reviews": self._reviews()}
        self.assertTrue(review_trigger.has_current_head_review(
            pr, HEAD, config=declared_non_structural()))

    def test_current_head_review_refuses_the_same_reviewer_when_undeclared(self) -> None:
        pr = {"headRefOid": HEAD, "reviews": self._reviews()}
        self.assertFalse(
            review_trigger.has_current_head_review(pr, HEAD, config=configured()))

    def _reactions(self) -> list[dict[str, object]]:
        return [{
            "id": 11,
            "user": {"type": "User", "login": "reviewbot"},
            "content": "eyes",
            "created_at": "2026-07-09T00:00:00Z",
        }]

    def test_reactions_accept_a_declared_user_typed_reviewer(self) -> None:
        with mock.patch.object(review_trigger, "fetch_paginated_api",
                               return_value=self._reactions()):
            signals = review_trigger.fetch_review_reactions(
                "repos/owner/repo/issues/42/reactions", scope="pull_request",
                config=declared_non_structural())
        self.assertEqual([signal["id"] for signal in signals], ["pull_request:11"])

    def test_reactions_refuse_the_same_reviewer_when_undeclared(self) -> None:
        with mock.patch.object(review_trigger, "fetch_paginated_api",
                               return_value=self._reactions()):
            signals = review_trigger.fetch_review_reactions(
                "repos/owner/repo/issues/42/reactions", scope="pull_request",
                config=configured())
        self.assertEqual(signals, [])


class ClassifyReviewRequestTests(unittest.TestCase):
    def _pr(self) -> dict[str, object]:
        return {"headRefOid": HEAD, "mergeStateStatus": "CLEAN",
                "mergeable": "MERGEABLE", "state": "OPEN", "isDraft": False,
                "reviews": []}

    def _gate(self) -> dict[str, object]:
        rollup = [
            {"__typename": "StatusContext", "context": "review-gate",
             "state": "PENDING", "targetUrl": ""},
            {"__typename": "CheckRun", "name": "ci-gate", "conclusion": "SUCCESS"},
        ]
        return review_trigger.review_gate_state(
            checks.classify_checks(rollup), configured())

    def test_dormant_state_is_gate_absent_when_unconfigured(self) -> None:
        gate = review_trigger.review_gate_state(
            checks.classify_checks([]),
            review_trigger.DEFAULT_REVIEW_TRIGGER_CONFIG)
        result = review_trigger.classify_review_request(
            self._pr(), gate, {}, "2026-07-10T00:00:00Z")
        self.assertEqual(result["state"], "absent")

    def test_first_observation_is_observing_not_yet_eligible(self) -> None:
        result = review_trigger.classify_review_request(
            self._pr(), self._gate(), {}, "2026-07-10T00:00:00Z",
            review_trigger_allowed=True, config=configured())
        self.assertEqual(result["state"], "observing")
        self.assertFalse(result["request_eligible"])

    def test_two_spaced_observations_become_eligible(self) -> None:
        prior = {"review_trigger": {"missing_head_sha": HEAD,
                                    "missing_first_seen_at": "2026-07-10T00:00:00Z",
                                    "missing_observations": 1}}
        result = review_trigger.classify_review_request(
            self._pr(), self._gate(), prior, "2026-07-10T00:05:00Z",
            review_trigger_allowed=True, config=configured())
        self.assertEqual(result["state"], "eligible")
        self.assertTrue(result["request_eligible"])

    def test_dormant_gate_never_produces_a_candidate(self) -> None:
        gate = review_trigger.review_gate_state(
            checks.classify_checks([]),
            review_trigger.DEFAULT_REVIEW_TRIGGER_CONFIG)
        result = review_trigger.classify_review_request(
            self._pr(), gate, {}, "2026-07-10T00:05:00Z",
            review_trigger_allowed=True)
        self.assertFalse(result["request_eligible"])
        self.assertEqual(result["missing_head_sha"], "")

    def test_stale_earlier_head_reaction_does_not_suppress_new_window(self) -> None:
        # F8: a reviewer reaction left on an earlier head carries no commit SHA,
        # so it persists onto the new head. With no prior reaction bound to this
        # head it is not current-head-associated and must not block candidacy.
        stale = [_reaction("1")]
        result = review_trigger.classify_review_request(
            self._pr(), self._gate(), {}, "2026-07-10T00:00:00Z",
            reaction_signals=stale, review_trigger_allowed=True,
            config=configured())
        self.assertEqual(result["state"], "engagement_signal_unverified")
        self.assertEqual(result["missing_head_sha"], HEAD)
        self.assertEqual(result["missing_observations"], 1)

    def test_current_head_reaction_still_suppresses_candidacy(self) -> None:
        # Guard on the F8 fix: a reaction newly observed while on THIS head is
        # current-head-associated and must still block the observation window.
        reaction = [_reaction("9")]
        prior = {"review_trigger": {"reaction_head_sha": HEAD,
                                    "reaction_signal_ids": []}}
        result = review_trigger.classify_review_request(
            self._pr(), self._gate(), prior, "2026-07-10T00:00:00Z",
            reaction_signals=reaction, review_trigger_allowed=True,
            config=configured())
        self.assertFalse(result["request_eligible"])
        self.assertEqual(result["missing_head_sha"], "")


class ValidateCurrentCandidateFreshnessTests(unittest.TestCase):
    """F7: the pre-POST freshness guard must reject a BLOCKED-masked BEHIND head."""

    def _patches(self, pr: dict[str, object]):
        return (
            mock.patch.object(request_review, "view_pr", return_value=pr),
            mock.patch.object(request_review, "head_repository_scope",
                              return_value={"review_trigger_allowed": True}),
            mock.patch.object(request_review, "fetch_review_evidence",
                              return_value=[]),
            mock.patch.object(request_review, "fetch_reaction_signals",
                              return_value=[]),
            mock.patch.object(request_review, "fetch_current_human_stop",
                              return_value={"required": False}),
            mock.patch.object(request_review, "has_current_head_review",
                              return_value=False),
        )

    def test_blocked_head_masking_behind_is_rejected(self) -> None:
        pr = {"state": "OPEN", "headRefOid": HEAD, "isDraft": False,
              "mergeStateStatus": "BLOCKED", "mergeable": "MERGEABLE",
              "_blocked_base_compare": {"status": "behind", "behind_by": 2}}
        patches = self._patches(pr)
        with patches[0], patches[1]:
            with self.assertRaises(RuntimeError) as ctx:
                request_review.validate_current_candidate(
                    "owner/repo", 1, HEAD, configured(),
                    frozenset({"owner"}), {})
        self.assertIn("not a stable fresh review candidate", str(ctx.exception))
        self.assertIn("BEHIND", str(ctx.exception))

    def test_blocked_but_fresh_head_passes_the_freshness_guard(self) -> None:
        # A PR BLOCKED purely on pending review (no compare-behind signal) is the
        # primary review-trigger target and must still pass this guard.
        pr = {"state": "OPEN", "headRefOid": HEAD, "isDraft": False,
              "mergeStateStatus": "BLOCKED", "mergeable": "MERGEABLE"}
        patches = self._patches(pr)
        with patches[0], patches[1], patches[2], patches[3], patches[4], \
                patches[5]:
            self.assertEqual(
                request_review.validate_current_candidate(
                    "owner/repo", 1, HEAD, configured(),
                    frozenset({"owner"}), {}),
                pr,
            )


class ValidateCurrentCandidateReactionScopingTests(unittest.TestCase):
    """F8 follow-on (Codex P2): the posting guard must apply the same
    current-head reaction scoping as the state-machine candidate predicate,
    not gate on the raw `fetch_reaction_signals` result."""

    def _pr(self) -> dict[str, object]:
        return {"state": "OPEN", "headRefOid": HEAD, "isDraft": False,
                "mergeStateStatus": "CLEAN", "mergeable": "MERGEABLE"}

    def _patches(self, pr: dict[str, object], reactions: list[dict[str, str]]):
        return (
            mock.patch.object(request_review, "view_pr", return_value=pr),
            mock.patch.object(request_review, "head_repository_scope",
                              return_value={"review_trigger_allowed": True}),
            mock.patch.object(request_review, "fetch_review_evidence",
                              return_value=[]),
            mock.patch.object(request_review, "fetch_reaction_signals",
                              return_value=reactions),
            mock.patch.object(request_review, "fetch_current_human_stop",
                              return_value={"required": False}),
            mock.patch.object(request_review, "has_current_head_review",
                              return_value=False),
        )

    def test_stale_earlier_head_reaction_does_not_block_posting(self) -> None:
        # The reaction has no `reaction_head_sha` recorded for HEAD in the
        # snapshot, so it is an earlier-head reaction and must not suppress
        # the posting guard the way the raw `reaction_signals` list would.
        stale = [_reaction("1")]
        patches = self._patches(self._pr(), stale)
        with patches[0], patches[1], patches[2], patches[3], patches[4], \
                patches[5]:
            result = request_review.validate_current_candidate(
                "owner/repo", 1, HEAD, configured(),
                frozenset({"owner"}), {})
        self.assertEqual(result, self._pr())

    def test_current_head_reaction_still_blocks_posting(self) -> None:
        reaction = [_reaction("9")]
        review_trigger_state = {"reaction_head_sha": HEAD, "reaction_signal_ids": []}
        patches = self._patches(self._pr(), reaction)
        with patches[0], patches[1], patches[2], patches[3], patches[4], \
                patches[5]:
            with self.assertRaises(RuntimeError) as ctx:
                request_review.validate_current_candidate(
                    "owner/repo", 1, HEAD, configured(),
                    frozenset({"owner"}), review_trigger_state)
        self.assertIn("reviewer reaction signal", str(ctx.exception))


class ResolveAssociatedReactionsTests(unittest.TestCase):
    def test_stale_reaction_from_a_different_recorded_head_is_not_associated(self) -> None:
        stale = [_reaction("1")]
        result = review_trigger.resolve_associated_reactions(stale, HEAD, {})
        self.assertEqual(result, [])

    def test_reaction_new_since_the_last_snapshot_for_this_head_is_associated(self) -> None:
        reaction = [_reaction("9")]
        prior = {"reaction_head_sha": HEAD, "reaction_signal_ids": []}
        result = review_trigger.resolve_associated_reactions(reaction, HEAD, prior)
        self.assertEqual(result, reaction)

    def test_reaction_already_seen_for_this_head_stays_associated(self) -> None:
        reaction = [_reaction("9")]
        prior = {
            "reaction_head_sha": HEAD,
            "reaction_signal_ids": ["pull_request:9"],
            "current_head_reaction_ids": ["pull_request:9"],
        }
        result = review_trigger.resolve_associated_reactions(reaction, HEAD, prior)
        self.assertEqual(result, reaction)

    def test_reaction_on_a_known_trigger_comment_for_this_head_is_associated(self) -> None:
        reaction = [_reaction("5", scope="trigger_comment", comment_id="42")]
        prior = {
            "reaction_head_sha": "",
            "request_history": {HEAD: {"comment_id": "42"}},
        }
        result = review_trigger.resolve_associated_reactions(reaction, HEAD, prior)
        self.assertEqual(result, reaction)


if __name__ == "__main__":
    unittest.main()
