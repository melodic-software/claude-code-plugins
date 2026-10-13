"""Advisory-round classification in the durable feedback ledger.

`record-advisory-round` is the only durable record of what a fix round
contained, so what it persists is what a post-rollover worker can know. These
cover the write shape and the tripwire the helper reports back at record time;
the two `--finding-class` argument refusals are guard-contract rows, executed
by `test_guards.py`.
"""

from __future__ import annotations

import argparse
import pathlib
import shlex
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import babysit_checks as checks
import babysit_lease as leases
import babysit_state as state
import manage_feedback_ledger as ledger

HEAD = "a" * 40
OLDER = "b" * 40
LEDGER_CLI = (
    pathlib.Path(__file__).resolve().parent.parent / "manage_feedback_ledger.py"
)


def record(
    ledger_entry: dict[str, object],
    head_sha: str,
    classes: list[str],
    *,
    apply: bool = True,
) -> dict[str, object]:
    args = argparse.Namespace(finding_class=classes, fix_round_cap=100, apply=apply)
    return ledger.record_advisory_round(args, "owner/repo#1", ledger_entry, head_sha)


class RecordAdvisoryRoundTests(unittest.TestCase):
    def test_per_finding_classes_are_persisted(self) -> None:
        entry: dict[str, object] = {}
        result = record(entry, HEAD, ["c", "c", "b"])
        self.assertEqual(result["finding_classes"], {"a": 0, "b": 1, "c": 2})
        self.assertEqual(result["composition"], "mixed")
        self.assertEqual(
            entry["advisory_fix_rounds"]["rounds"][HEAD]["finding_classes"],
            {"a": 0, "b": 1, "c": 2},
        )

    def test_each_round_gets_the_next_monotonic_sequence(self) -> None:
        # The ledger serializes with sorted keys, so the persisted sequence is
        # the only write order a post-rollover reader can reconstruct.
        entry: dict[str, object] = {}
        record(entry, OLDER, ["c"])
        record(entry, HEAD, ["c"])
        rounds = entry["advisory_fix_rounds"]["rounds"]
        self.assertEqual(rounds[OLDER]["sequence"], 1)
        self.assertEqual(rounds[HEAD]["sequence"], 2)

    def test_the_sequence_continues_past_pre_sequence_rounds(self) -> None:
        # A legacy round without a sequence neither blocks recording nor
        # collides with the new numbering.
        entry: dict[str, object] = {
            "advisory_fix_rounds": {
                "count": 1,
                "rounds": {OLDER: {"recorded_at": "2026-07-10T01:00:00Z"}},
            }
        }
        record(entry, HEAD, ["c"])
        self.assertEqual(entry["advisory_fix_rounds"]["rounds"][HEAD]["sequence"], 1)

    def test_a_dry_run_persists_nothing_but_still_reports_the_tripwire(self) -> None:
        entry: dict[str, object] = {}
        result = record(entry, HEAD, ["c"], apply=False)
        self.assertNotIn("advisory_fix_rounds", entry)
        self.assertIn("non_convergence_tripwire", result)

    def test_the_recorded_round_arms_the_tripwire_at_record_time(self) -> None:
        # The worker recording round N learns immediately that N-1 was also
        # all-(c) -- it does not have to wait for the next snapshot to find out.
        entry: dict[str, object] = {}
        record(entry, OLDER, ["c"])
        result = record(entry, HEAD, ["c", "c"])
        self.assertTrue(result["non_convergence_tripwire"]["armed"])

    def test_a_mixed_round_clears_the_tripwire(self) -> None:
        entry: dict[str, object] = {}
        record(entry, OLDER, ["c"])
        result = record(entry, HEAD, ["b", "c"])
        self.assertFalse(result["non_convergence_tripwire"]["armed"])


KEY = "owner/repo#1"
BUILD = {"type": "CheckRun", "name": "build", "workflow_name": "ci"}
LINT_CI = {"type": "CheckRun", "name": "lint", "workflow_name": "ci"}
LINT_NIGHTLY = {"type": "CheckRun", "name": "lint", "workflow_name": "nightly"}


def rerun(
    mutation_ledger: dict[str, object],
    check: dict[str, str],
    *,
    apply: bool = True,
) -> dict[str, object]:
    args = argparse.Namespace(check_id=checks.check_rerun_id(check), apply=apply)
    pr_state = {"checks_failing_identities": [BUILD, LINT_CI, LINT_NIGHTLY]}
    return ledger.record_rerun(args, KEY, mutation_ledger, pr_state, HEAD)


class RecordRerunTests(unittest.TestCase):
    def test_the_first_rerun_of_a_failing_check_is_recorded(self) -> None:
        mutation_ledger: dict[str, object] = {}
        result = rerun(mutation_ledger, BUILD)
        self.assertEqual((result["count_after"], result["cap"]), (1, 1))
        self.assertEqual(result["check"], BUILD)
        self.assertTrue(result["recorded"])

    def test_the_cap_allows_exactly_one_rerun_per_check_at_one_head(self) -> None:
        mutation_ledger: dict[str, object] = {}
        rerun(mutation_ledger, BUILD)
        with self.assertRaisesRegex(ledger.FlakeCapReached, "flake cap"):
            rerun(mutation_ledger, BUILD)
        # A different check at the same head still has its own rerun.
        self.assertEqual(rerun(mutation_ledger, LINT_CI)["count_after"], 1)

    def test_a_dry_run_records_nothing(self) -> None:
        mutation_ledger: dict[str, object] = {}
        result = rerun(mutation_ledger, BUILD, apply=False)
        self.assertEqual(result["count_after"], 1)
        self.assertEqual(mutation_ledger, {})

    def test_a_check_the_snapshot_does_not_list_as_failing_is_refused(self) -> None:
        deploy = {"type": "CheckRun", "name": "deploy", "workflow_name": "ci"}
        with self.assertRaisesRegex(RuntimeError, "not a failing check"):
            rerun({}, deploy)

    def test_one_name_in_two_workflows_is_two_ids(self) -> None:
        result = rerun({}, LINT_NIGHTLY)
        self.assertEqual(result["check"], LINT_NIGHTLY)

    def test_an_id_two_distinct_checks_share_is_refused(self) -> None:
        collided = "0" * 32
        args = argparse.Namespace(check_id=collided, apply=True)
        pr_state = {"checks_failing_identities": [BUILD, LINT_CI]}
        mutation_ledger: dict[str, object] = {}
        with mock.patch.object(ledger, "check_rerun_id", return_value=collided):
            with self.assertRaisesRegex(RuntimeError, "more than one failing check"):
                ledger.record_rerun(args, KEY, mutation_ledger, pr_state, HEAD)
        self.assertEqual(mutation_ledger, {})

    def test_the_same_check_listed_twice_is_not_a_collision(self) -> None:
        args = argparse.Namespace(check_id=checks.check_rerun_id(BUILD), apply=True)
        pr_state = {"checks_failing_identities": [BUILD, dict(BUILD)]}
        result = ledger.record_rerun(args, KEY, {}, pr_state, HEAD)
        self.assertEqual(result["check"], BUILD)

    def test_the_id_is_32_lowercase_hex_characters(self) -> None:
        self.assertRegex(checks.check_rerun_id(BUILD), r"\A[0-9a-f]{32}\Z")


CRAFTED_NAME = "build $(touch PWNED) `touch PWNED_TICK`"
CRAFTED_WORKFLOW = "ci $(touch PWNED_WORKFLOW)"
TOKEN = "worker-token"


class RecordRerunCommandTests(unittest.TestCase):
    """The documented command carries only the snapshot's hex rerun id.

    A fork PR names its own jobs, so a check name is attacker text. These run
    the command the way a model types it, through a shell, against a snapshot
    whose failing check name holds command substitutions.
    """

    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        root = pathlib.Path(tmp.name)
        self.state_dir = root / "state"
        self.cwd = root / "cwd"
        self.cwd.mkdir()
        rollup = [
            {
                "__typename": "CheckRun",
                "name": CRAFTED_NAME,
                "status": "COMPLETED",
                "conclusion": "FAILURE",
                "workflowName": CRAFTED_WORKFLOW,
            }
        ]
        failing = checks.classify_checks(rollup)["failing_identities"]
        self.rerun_id = str(failing[0]["rerun_id"])
        state.write_state(
            state.state_path_for(self.state_dir),
            {
                "schema_version": state.STATE_SCHEMA_VERSION,
                "prs": {KEY: {"head_sha": HEAD, "checks_failing_identities": failing}},
            },
        )
        leases.acquire(
            leases.lease_path(self.state_dir, "worker", KEY),
            "worker",
            TOKEN,
            None,
            leases.DEFAULT_WORKER_TTL_SECONDS,
        )

    def shell(self, check_id: str) -> subprocess.CompletedProcess[str]:
        command = (
            f"{shlex.quote(sys.executable)} {shlex.quote(str(LEDGER_CLI))} "
            f"record-rerun --pr {KEY} --expected-head-sha {HEAD} "
            f"--check-id {check_id} --lease-token {TOKEN} "
            f"--state-dir {shlex.quote(str(self.state_dir))} --apply"
        )
        return subprocess.run(
            ["bash", "-c", command],
            cwd=self.cwd,
            capture_output=True,
            text=True,
            check=False,
        )

    def test_a_crafted_check_name_is_recorded_without_running(self) -> None:
        result = self.shell(self.rerun_id)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(sorted(path.name for path in self.cwd.iterdir()), [])
        stored = state.load_state(state.state_path_for(self.state_dir))
        (record,) = stored["mutation_ledger"][KEY]["check_reruns"][HEAD].values()
        self.assertEqual(
            record["check"],
            {
                "type": "CheckRun",
                "name": CRAFTED_NAME,
                "workflow_name": CRAFTED_WORKFLOW,
            },
        )

    def test_the_second_rerun_exits_with_the_cap_code(self) -> None:
        self.assertEqual(self.shell(self.rerun_id).returncode, 0)
        second = self.shell(self.rerun_id)
        self.assertEqual(second.returncode, 4)
        self.assertIn("flake cap", second.stderr)

    def test_a_malformed_check_id_is_refused_before_any_lookup(self) -> None:
        for bad in (
            "$(touch PWNED)",
            "build",
            "12ab",
            "0123456789abcdef",
            "0123456789ABCDEF0123456789ABCDEF",
            "",
        ):
            with self.subTest(check_id=bad):
                result = invoke(
                    "record-rerun",
                    "--pr",
                    KEY,
                    "--expected-head-sha",
                    HEAD,
                    "--check-id",
                    bad,
                    "--lease-token",
                    TOKEN,
                    "--state-dir",
                    str(self.state_dir),
                    "--apply",
                )
                self.assertEqual(result.returncode, 2)
                self.assertIn("--check-id must be", result.stderr)
        self.assertNotIn(
            "mutation_ledger", state.load_state(state.state_path_for(self.state_dir))
        )

    def test_a_well_formed_id_the_snapshot_does_not_list_is_refused(self) -> None:
        result = self.shell("0123456789abcdef0123456789abcdef")
        self.assertEqual(result.returncode, 2)
        self.assertIn("not a failing check", result.stderr)

    def test_the_free_text_check_name_flag_is_gone(self) -> None:
        result = invoke(
            "record-rerun",
            "--pr",
            KEY,
            "--expected-head-sha",
            HEAD,
            "--check-name",
            "build",
            "--state-dir",
            str(self.state_dir),
        )
        self.assertEqual(result.returncode, 2)
        self.assertIn("unrecognized arguments: --check-name", result.stderr)


def invoke(*argv: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(LEDGER_CLI), *argv],
        capture_output=True,
        text=True,
        check=False,
    )


class ArgumentRefusalTests(unittest.TestCase):
    """The one refusal outside `guard_contract.py`'s two `--finding-class` rows."""

    def test_an_unknown_class_is_refused(self) -> None:
        with tempfile.TemporaryDirectory() as state_dir:
            result = invoke(
                "record-advisory-round",
                "--pr",
                "owner/repo#1",
                "--expected-head-sha",
                HEAD,
                "--state-dir",
                state_dir,
                "--finding-class",
                "d",
            )
        self.assertEqual(result.returncode, 2)


if __name__ == "__main__":
    unittest.main()
