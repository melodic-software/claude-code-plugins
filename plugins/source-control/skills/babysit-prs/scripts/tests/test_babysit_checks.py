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


GEN = "2026-07-10T00:00:00Z"
OLD_TS = "2026-07-09T00:00:00Z"  # 24h before GEN -> aged out
NOW_TS = "2026-07-10T00:00:00Z"  # age 0 -> not aged out
THRESHOLD = 1800.0


def _norm(**fields: object) -> dict[str, object]:
    return checks.normalize_check(fields)


class NormalizeCreatedAtTests(unittest.TestCase):
    def test_check_run_created_at_from_started_at(self) -> None:
        normalized = checks.normalize_check(
            {"__typename": "CheckRun", "name": "x", "startedAt": OLD_TS}
        )
        self.assertEqual(normalized["created_at"], OLD_TS)

    def test_status_context_created_at_from_created_at(self) -> None:
        normalized = checks.normalize_check(
            {"__typename": "StatusContext", "context": "x", "state": "PENDING",
             "createdAt": OLD_TS}
        )
        self.assertEqual(normalized["created_at"], OLD_TS)


class ClassifyStuckChecksTests(unittest.TestCase):
    def _stuck(self, rows: list[dict[str, object]], merge_state: str = "UNSTABLE"):
        return checks.classify_stuck_checks(
            rows, GEN, merge_state=merge_state, age_threshold_seconds=THRESHOLD
        )

    def test_only_fires_under_unstable(self) -> None:
        orphan = _norm(__typename="StatusContext", context="x", state="PENDING",
                       targetUrl="")
        self.assertEqual(self._stuck([orphan], merge_state="CLEAN"), [])
        self.assertEqual(self._stuck([orphan], merge_state="BLOCKED"), [])

    def test_orphaned_status_is_not_age_gated(self) -> None:
        orphan = _norm(__typename="StatusContext", context="codex-review",
                       state="PENDING", targetUrl="", createdAt=NOW_TS)
        stuck = self._stuck([orphan])
        self.assertEqual([s["class"] for s in stuck], [checks.STUCK_ORPHANED_STATUS])
        self.assertEqual(stuck[0]["name"], "codex-review")
        self.assertEqual(stuck[0]["type"], "StatusContext")

    def test_stuck_queued_is_age_gated(self) -> None:
        young = _norm(__typename="CheckRun", name="build", status="QUEUED",
                      startedAt=NOW_TS)
        old = _norm(__typename="CheckRun", name="build", status="QUEUED",
                    startedAt=OLD_TS)
        self.assertEqual(self._stuck([young]), [])
        stuck = self._stuck([old])
        self.assertEqual([s["class"] for s in stuck], [checks.STUCK_QUEUED])
        self.assertGreater(stuck[0]["age_seconds"], THRESHOLD)

    def test_queued_without_start_time_is_unflagged(self) -> None:
        # A QUEUED CheckRun gh reports without startedAt has no provable age.
        no_ts = _norm(__typename="CheckRun", name="build", status="QUEUED")
        self.assertEqual(self._stuck([no_ts]), [])

    def test_never_settling_pending_past_threshold(self) -> None:
        old = _norm(__typename="StatusContext", context="ext", state="PENDING",
                    targetUrl="https://ci.example/run", createdAt=OLD_TS)
        stuck = self._stuck([old])
        self.assertEqual([s["class"] for s in stuck], [checks.STUCK_NEVER_SETTLING])
        self.assertEqual(stuck[0]["target_url"], "https://ci.example/run")

    def test_settled_and_success_checks_are_never_stuck(self) -> None:
        failed = _norm(__typename="CheckRun", name="build", status="COMPLETED",
                       conclusion="FAILURE", startedAt=OLD_TS)
        passed = _norm(__typename="CheckRun", name="build", status="COMPLETED",
                       conclusion="SUCCESS", startedAt=OLD_TS)
        self.assertEqual(self._stuck([failed, passed]), [])


if __name__ == "__main__":
    unittest.main()
