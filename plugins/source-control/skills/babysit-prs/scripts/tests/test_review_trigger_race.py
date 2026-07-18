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

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import babysit_checks as checks
import babysit_review_trigger as review_trigger

HEAD = "a" * 40


def configured() -> review_trigger.ReviewTriggerConfig:
    return review_trigger.ReviewTriggerConfig(
        trigger_phrase="please review",
        reviewer_logins=frozenset({"reviewbot"}),
        gate_context="review-gate",
        ci_gateway_context="ci-gate",
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


class ReviewBotItemTests(unittest.TestCase):
    def test_configured_reviewer_bot_is_recognized(self) -> None:
        item = {"author": {"__typename": "Bot", "login": "reviewbot[bot]"}}
        self.assertTrue(review_trigger.is_review_bot_item(item, configured()))

    def test_human_author_is_not_a_review_bot(self) -> None:
        item = {"author": {"__typename": "User", "login": "reviewbot"}}
        self.assertFalse(review_trigger.is_review_bot_item(item, configured()))

    def test_unlisted_bot_is_not_a_review_bot(self) -> None:
        item = {"author": {"__typename": "Bot", "login": "otherbot[bot]"}}
        self.assertFalse(review_trigger.is_review_bot_item(item, configured()))


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


if __name__ == "__main__":
    unittest.main()
