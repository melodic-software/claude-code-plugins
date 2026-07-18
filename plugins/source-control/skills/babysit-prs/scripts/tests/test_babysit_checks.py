"""Status-check rollup classification: identity dedupe, categories, rollup.

Ports the check-classification coverage of the monolith suite onto the
`babysit_checks` module surface: the durable `(type, name, workflow_name)`
identity, latest-wins dedupe that never merges a StatusContext with a
same-named CheckRun, category mapping, and the persisted-identity validator.
"""

from __future__ import annotations

import pathlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import babysit_checks as checks


def _run(**over: object) -> dict[str, object]:
    base = {"__typename": "CheckRun", "name": "check", "status": "COMPLETED"}
    base.update(over)
    return base


class CheckCategoryTests(unittest.TestCase):
    def test_failure_states_are_terminal(self) -> None:
        for state in ("FAILURE", "CANCELLED", "STALE", "TIMED_OUT", "ERROR"):
            with self.subTest(state=state):
                self.assertEqual(checks.check_category(state), "failing")

    def test_success_and_neutral_states_pass(self) -> None:
        for state in ("SUCCESS", "NEUTRAL", "SKIPPED"):
            with self.subTest(state=state):
                self.assertEqual(checks.check_category(state), "success")

    def test_pending_and_empty_states_are_pending(self) -> None:
        for state in ("IN_PROGRESS", "QUEUED", "", "SOMETHING_UNKNOWN"):
            with self.subTest(state=state):
                self.assertEqual(checks.check_category(state), "pending")


class NormalizeCheckTests(unittest.TestCase):
    def test_status_context_uses_its_state_not_conclusion(self) -> None:
        normalized = checks.normalize_check(
            {"__typename": "StatusContext", "context": "gate", "state": "PENDING"}
        )
        self.assertEqual(normalized["type"], "StatusContext")
        self.assertEqual(normalized["name"], "gate")
        self.assertEqual(normalized["effective_state"], "PENDING")
        self.assertEqual(normalized["category"], "pending")

    def test_check_run_prefers_conclusion_over_status(self) -> None:
        normalized = checks.normalize_check(
            {"__typename": "CheckRun", "name": "ci", "status": "COMPLETED",
             "conclusion": "FAILURE"}
        )
        self.assertEqual(normalized["effective_state"], "FAILURE")
        self.assertEqual(normalized["category"], "failing")


class DedupeIdentityTests(unittest.TestCase):
    def test_status_context_is_never_merged_with_same_named_check_run(self) -> None:
        result = checks.classify_checks(
            [
                {"__typename": "CheckRun", "name": "codex-review",
                 "conclusion": "SUCCESS"},
                {"__typename": "StatusContext", "context": "codex-review",
                 "state": "PENDING", "targetUrl": ""},
            ]
        )
        self.assertEqual(result["total"], 2)
        self.assertEqual(result["success"], 1)
        self.assertEqual(result["pending"], ["codex-review"])
        self.assertEqual(
            result["pending_identities"],
            [{"type": "StatusContext", "name": "codex-review", "workflow_name": ""}],
        )

    def test_latest_run_per_identity_wins(self) -> None:
        result = checks.classify_checks(
            [
                _run(name="test", conclusion="FAILURE", workflowName="wf",
                     completedAt="2026-01-01T00:00:00Z"),
                _run(name="test", conclusion="SUCCESS", workflowName="wf",
                     completedAt="2026-01-02T00:00:00Z"),
            ]
        )
        self.assertEqual(result["total"], 1)
        self.assertEqual(result["failing"], [])
        self.assertEqual(result["success"], 1)

    def test_workflow_name_disambiguates_same_named_checks(self) -> None:
        result = checks.classify_checks(
            [
                _run(name="test", conclusion="FAILURE", workflowName="alpha",
                     completedAt="2026-01-01T00:00:00Z"),
                _run(name="test", conclusion="SUCCESS", workflowName="beta",
                     completedAt="2026-01-02T00:00:00Z"),
            ]
        )
        self.assertEqual(result["total"], 2)
        self.assertEqual(result["failing"], ["test"])
        self.assertEqual(result["success"], 1)

    def test_missing_timestamp_falls_back_to_list_order(self) -> None:
        result = checks.classify_checks(
            [
                _run(name="test", conclusion="FAILURE", workflowName="wf"),
                _run(name="test", conclusion="SUCCESS", workflowName="wf"),
            ]
        )
        self.assertEqual(result["total"], 1)
        self.assertEqual(result["success"], 1)


class SummarizedStateTests(unittest.TestCase):
    def test_failing_beats_pending_beats_success(self) -> None:
        checks_list = [
            {"category": "success"},
            {"category": "pending"},
            {"category": "failing"},
        ]
        self.assertEqual(checks.summarized_state(checks_list), "failing")
        self.assertEqual(checks.summarized_state(checks_list[:2]), "pending")
        self.assertEqual(checks.summarized_state(checks_list[:1]), "success")

    def test_empty_rollup_is_absent(self) -> None:
        self.assertEqual(checks.summarized_state([]), "absent")


class PersistedIdentityValidationTests(unittest.TestCase):
    def test_valid_identities_round_trip_to_keys(self) -> None:
        keys = checks.persisted_check_identity_keys(
            [{"type": "CheckRun", "name": "ci", "workflow_name": "wf"}], "field"
        )
        self.assertEqual(keys, {("CheckRun", "ci", "wf")})

    def test_non_array_fails_closed(self) -> None:
        with self.assertRaises(ValueError):
            checks.persisted_check_identity_keys({"not": "array"}, "field")

    def test_missing_key_fails_closed(self) -> None:
        with self.assertRaises(ValueError):
            checks.persisted_check_identity_keys(
                [{"type": "CheckRun", "name": "ci"}], "field"
            )

    def test_empty_type_or_name_fails_closed(self) -> None:
        with self.assertRaises(ValueError):
            checks.persisted_check_identity_keys(
                [{"type": "", "name": "ci", "workflow_name": ""}], "field"
            )


if __name__ == "__main__":
    unittest.main()
