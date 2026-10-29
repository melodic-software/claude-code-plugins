"""Owner decisions Q7 and Q5 (#10743): `merge.lane-arm-gate`.

With the switch on, a pull request held only by the merge gate's own code
(babysit_risk.py and the pr-merge scripts) needs no person once both
review lanes are bound to a main-run review of the head with no open finding
and no review thread is open. A `trust` path, a person-held path and every
doubt (switch off, evidence unbound, bound by a pull_request run, a finding,
an open or unread thread count) keep the person hold. The expected outcomes
come from the decision record
(https://github.com/melodic-software/claude-code-plugins/pull/10743#issuecomment-6486023647)
and the follow-up brief, never from running the scorer.
"""

from __future__ import annotations

import importlib.util
import pathlib
import subprocess
import sys
import tempfile
import unittest
from dataclasses import replace
from unittest import mock

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import babysit_merge
import babysit_risk
from babysit_risk import (
    ChangedFile,
    LaneEvidence,
    RiskInput,
    holds,
    person_reasons,
    score,
)

ROOT = pathlib.Path(__file__).resolve().parents[6]


def _file(path: str) -> ChangedFile:
    return ChangedFile(
        path=path,
        previous_path=None,
        status="modified",
        additions=1,
        deletions=1,
        has_patch=True,
        mode="100644",
        previous_mode="100644",
        patch="@@ -1 +1 @@\n-# a\n+# b",
        contents=("# a\n", "# b\n"),
    )


def _lanes(*, main_run: bool = True, findings: int = 0, critical: int = 0):
    return (
        LaneEvidence(
            "claude-review", True, None, findings, False, None, main_run=main_run
        ),
        LaneEvidence(
            "claude-security-review",
            True,
            None,
            critical,
            False,
            critical,
            main_run=main_run,
        ),
    )


def _input(
    *paths: str, threads: int | None = 0, lanes_app: bool = True, **lanes
) -> RiskInput:
    return RiskInput(
        files=tuple(_file(p) for p in paths),
        files_complete=True,
        max_changed_lines=None,
        high_paths=(),
        lanes=_lanes(**lanes),
        public=True,
        lines_optional=True,
        max_changed_files=None,
        open_threads=threads,
        lanes_app=lanes_app,
    )


def _high(result) -> list[str]:
    return [r.code for r in result.reasons if r.code.startswith("high-path:")]


# Owner decision Q5: the switch lane-arms the merge gate's own code alone.
SAMPLE_FLOOR = babysit_risk.LANE_ARMED_FLOOR
ARMED = (
    "plugins/source-control/skills/babysit-prs/scripts/babysit_risk.py",
    ".github/scripts/pr-merge/clear-escalations.mjs",
    ".github/scripts/pr-merge/merge-holds.mjs",
    ".github/scripts/pr-merge/who.mjs",
    ".github/scripts/pr-merge/lane-armed.mjs",
)
# Everything else on the person floor: a person whatever the lanes say.
PERSON = (
    ".github/workflows/pr-require-checks.yml",
    ".github/workflows/pr-merge.yml",
    ".github/workflows/pr-review-main.yml",
    ".github/workflows/pr-review-security-hosted.yml",
    ".github/scripts/pr-review-main/write-verdict.mjs",
    "plugins/source-control/skills/babysit-prs/scripts/babysit_merge.py",
    "plugins/source-control/skills/babysit-prs/scripts/babysit_review_evidence.py",
    "scripts/sync-hold-floor.py",
    "docs/conventions/pr-pipeline.yaml",
    ".github/actions/request-lane-token/action.yml",
    ".github/actions/log-api-budget/rate-guard.mjs",
    ".github/actions/report-check-run/posting-run.mjs",
    "AGENTS.md",
    ".claude/settings.json",
    "REVIEW.md",
    "docs/standards/README.md",
)


# A lane-armed sample path, the glob that names it.
WHO = ".github/scripts/pr-merge/who.mjs"


class TheSwitchLaneArmsGatePaths(unittest.TestCase):
    def setUp(self) -> None:
        patch = mock.patch.object(babysit_risk, "LANE_ARMED_FLOOR", SAMPLE_FLOOR)
        patch.start()
        self.addCleanup(patch.stop)

    def test_a_gate_path_with_both_lanes_clean_on_main_and_no_thread_needs_no_person(
        self,
    ) -> None:
        for path in ARMED:
            with self.subTest(path):
                result = score(_input(path))
                self.assertEqual(_high(result), [])
                self.assertFalse(holds(result), result.reasons)

    def test_with_the_switch_off_every_gate_path_holds_for_a_person(self) -> None:
        with mock.patch.object(babysit_risk, "LANE_ARMED_FLOOR", ()):
            for path in ARMED:
                with self.subTest(path):
                    result = score(_input(path))
                    self.assertEqual(len(_high(result)), 1, result.reasons)
                    self.assertTrue(person_reasons(result.reasons))

    def test_each_doubt_keeps_the_person_hold(self) -> None:
        cases = {
            "an open review thread": _input(WHO, threads=1),
            "an unread thread count": _input(WHO, threads=None),
            "a malformed thread count": _input(WHO, threads=True),  # type: ignore[arg-type]
            "a code-review finding, any severity": _input(WHO, findings=1),
            "a CRITICAL security finding": _input(WHO, critical=1),
            # ci-status holds only the lanes App's pull requests for the
            # attestation, so any other author's keeps the person hold.
            "another author's pull request": _input(WHO, lanes_app=False),
            "bound by a pull_request run, not main": _input(WHO, main_run=False),
        }
        for name, inp in cases.items():
            with self.subTest(name):
                result = score(inp)
                self.assertIn(f"high-path:{WHO}", _high(result))
                self.assertTrue(holds(result))
        unbound = replace(
            _input(WHO),
            lanes=(
                _lanes()[0],
                LaneEvidence(
                    "claude-security-review", False, "lane-source-changed", None
                ),
            ),
        )
        # An IMPORTANT or SUGGESTION security finding: open but not blocking.
        below = replace(
            _input(WHO),
            lanes=(
                _lanes()[0],
                LaneEvidence(
                    "claude-security-review", True, None, 1, False, 0, main_run=True
                ),
            ),
        )
        missing = replace(_input(WHO), lanes=_lanes()[:1])
        doubled = replace(_input(WHO), lanes=(*_lanes(), _lanes()[0]))
        for name, inp in (
            ("unbound", unbound),
            ("a security finding below CRITICAL", below),
            ("missing", missing),
            ("doubled", doubled),
        ):
            with self.subTest(name):
                self.assertIn(f"high-path:{WHO}", _high(score(inp)))

    def test_a_person_held_or_trust_path_holds_even_with_everything_clean(self) -> None:
        for path in PERSON:
            with self.subTest(path):
                result = score(_input(path))
                self.assertEqual(len(_high(result)), 1, result.reasons)
                self.assertTrue(person_reasons(result.reasons))
        # Beside a lane-armed path, only the person-held one is named.
        result = score(_input(WHO, ".github/workflows/pr-require-checks.yml"))
        self.assertEqual(
            _high(result), ["high-path:.github/workflows/pr-require-checks.yml"]
        )

    def test_a_configured_denied_path_is_never_lane_armed(self) -> None:
        inp = replace(_input(WHO), high_paths=(WHO,))
        self.assertEqual(_high(score(inp)), [f"high-path:{WHO}"])

    def test_the_thread_count_is_read_only_when_it_could_lane_arm(self) -> None:
        self.assertTrue(babysit_risk.lane_arm_pending(_input(WHO, threads=None)))
        for name, inp in (
            (
                "a person-held path",
                _input(".github/workflows/pr-merge.yml", threads=None),
            ),
            ("a path off the floor", _input("docs/a.md", threads=None)),
            ("a finding", _input(WHO, threads=None, findings=1)),
            ("not main-run", _input(WHO, threads=None, main_run=False)),
        ):
            with self.subTest(name):
                self.assertFalse(babysit_risk.lane_arm_pending(inp))
        with mock.patch.object(babysit_risk, "LANE_ARMED_FLOOR", ()):
            self.assertFalse(babysit_risk.lane_arm_pending(_input(WHO)))

    def test_the_gate_reads_the_threads_and_an_unreadable_read_keeps_the_hold(
        self,
    ) -> None:
        pending = _input(WHO, threads=None)
        for threads, expected in (([], 0), ([{"path": WHO}], 1), (None, None)):
            with (
                self.subTest(threads=threads),
                mock.patch.object(
                    babysit_merge, "unresolved_threads", return_value=threads
                ) as read,
            ):
                self.assertEqual(
                    babysit_merge.with_open_threads("o/r", 1, pending).open_threads,
                    expected,
                )
                read.assert_called_once_with("o/r", 1)
        with mock.patch.object(
            babysit_merge, "unresolved_threads", side_effect=RuntimeError("x")
        ):
            self.assertIsNone(
                babysit_merge.with_open_threads("o/r", 1, pending).open_threads
            )
        with mock.patch.object(babysit_merge, "unresolved_threads") as read:
            person = _input(".github/workflows/pr-merge.yml", threads=None)
            self.assertIs(babysit_merge.with_open_threads("o/r", 1, person), person)
            read.assert_not_called()


class TheAttestationRecord(unittest.TestCase):
    """What gate-check's `pr-merge/lane-armed` attestation records, and the
    first failed condition when it must not attest (owner decision Q5)."""

    def test_a_clean_head_records_its_lane_armed_paths_and_no_refusal(self) -> None:
        inp = _input(WHO, "docs/a.md")
        self.assertEqual(
            babysit_risk.lane_arm_record(inp, score(inp)),
            {
                "paths": [WHO],
                "lanes": {"claude-review": 0, "claude-security-review": 0},
                "threads": 0,
                "refused": None,
            },
        )

    def test_each_failed_condition_is_named(self) -> None:
        for inp, refused in (
            (_input(WHO, lanes_app=False), "not the lanes App's pull request"),
            (_input(WHO, main_run=False), "both review lanes are not bound"),
            (_input(WHO, findings=1), "both review lanes are not bound"),
            (_input(WHO, threads=None), "could not be read"),
            (_input(WHO, threads=2), "2 review thread(s) open"),
            (
                _input(WHO, ".github/workflows/pr-merge.yml"),
                "the risk score holds (HIGH)",
            ),
        ):
            with self.subTest(refused):
                record = babysit_risk.lane_arm_record(inp, score(inp))
                self.assertIn(refused, record["refused"])

    def test_a_head_with_no_lane_armed_path_records_nothing(self) -> None:
        inp = _input("AGENTS.md")
        self.assertIsNone(babysit_risk.lane_arm_record(inp, score(inp)))
        with mock.patch.object(babysit_risk, "LANE_ARMED_FLOOR", ()):
            inp = _input(WHO)
            self.assertIsNone(babysit_risk.lane_arm_record(inp, score(inp)))


class TheMergeEnforcementList(unittest.TestCase):
    def test_the_switch_lane_arms_exactly_the_merge_gates_own_code(self) -> None:
        # Owner decision Q5: babysit_risk.py and the pr-merge scripts, and
        # nothing more; every other trust and gate row is person-held.
        self.assertIs(babysit_risk.LANE_ARM_GATE, True)
        pr_merge = [
            g
            for g, c in babysit_risk.FLOOR_CLASSES
            if c in ("trust", "gate") and g.startswith(".github/scripts/pr-merge/")
        ]
        self.assertEqual(
            sorted(babysit_risk.LANE_ARMED_FLOOR),
            sorted(
                [
                    *pr_merge,
                    "plugins/source-control/skills/babysit-prs/scripts/babysit_risk.py",
                ]
            ),
        )
        person = [g for g, c in babysit_risk.FLOOR_CLASSES if c in ("trust", "gate")]
        self.assertEqual(
            sorted(babysit_risk.PERSON_HELD),
            sorted(g for g in person if g not in babysit_risk.LANE_ARMED_FLOOR),
        )
        for path in PERSON:
            with self.subTest(path):
                self.assertTrue(
                    any(
                        babysit_risk.glob_match(g, path)
                        for g in babysit_risk.PERSON_HELD
                    )
                )
                self.assertFalse(
                    any(babysit_risk.glob_match(g, path) for g in SAMPLE_FLOOR)
                )

    def test_every_gated_workflow_is_person_held_without_being_listed(self) -> None:
        on, held, armed = _sync_module().lane_arm()
        self.assertIs(on, True)
        self.assertEqual(tuple(held), babysit_risk.PERSON_HELD)
        self.assertEqual(tuple(armed), babysit_risk.LANE_ARMED_FLOOR)
        workflows = [
            g
            for g, c in babysit_risk.FLOOR_CLASSES
            if c == "gate" and g.startswith(".github/workflows/")
        ]
        self.assertGreater(len(workflows), 0)
        for glob in workflows:
            self.assertIn(glob, babysit_risk.PERSON_HELD, glob)

    def test_the_copies_match_pr_pipeline_yaml(self) -> None:
        proc = subprocess.run(
            [sys.executable, "-I", str(ROOT / "scripts/sync-hold-floor.py"), "--check"],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)


def _sync_module():
    spec = importlib.util.spec_from_file_location(
        "sync_hold_floor", ROOT / "scripts/sync-hold-floor.py"
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class TheGeneratorReadsTheSwitchFailClosed(unittest.TestCase):
    """The brief: a switch absent or unreadable keeps the person hold."""

    def lane_arm(self, merge_block: str):
        sync = _sync_module()
        with tempfile.TemporaryDirectory() as tmp:
            path = pathlib.Path(tmp) / "pr-pipeline.yaml"
            path.write_text(f"version: 2\nmerge:\n{merge_block}", encoding="utf-8")
            with mock.patch.object(sync, "PIPELINE", path):
                return sync.lane_arm()

    # Every `gate` row outside the merge gate's code and the workflows.
    FULL = "  person-held:\n" + "".join(
        f'    - "{g}"\n'
        for g, c in babysit_risk.FLOOR_CLASSES
        if c == "gate"
        and not g.startswith((".github/workflows/", ".github/scripts/pr-merge/"))
    )
    RISK = "plugins/source-control/skills/babysit-prs/scripts/babysit_risk.py"

    def test_only_a_literal_true_turns_it_on(self) -> None:
        on, held, armed = self.lane_arm(f"  lane-arm-gate: true\n{self.FULL}")
        self.assertIs(on, True)
        self.assertIn(".github/workflows/pr-require-checks.yml", held)
        self.assertIn(self.RISK, armed)
        # The shared reader unquotes a scalar, so 'true' reads as true.
        for value in (None, "false", "yes", "True", "1", "on", "~"):
            with self.subTest(value=value):
                line = "" if value is None else f"  lane-arm-gate: {value}\n"
                on, held, armed = self.lane_arm(f"{line}{self.FULL}")
                self.assertIs(on, False)
                self.assertEqual(armed, [])
                self.assertIn(self.RISK, held)

    def test_a_gate_row_outside_the_merge_gates_code_left_unlisted_stops_it(
        self,
    ) -> None:
        short = self.FULL.replace('    - "**/AGENTS.md"\n', "")
        for switch in ("true", "false"):
            with self.subTest(switch=switch), self.assertRaises(SystemExit):
                self.lane_arm(f"  lane-arm-gate: {switch}\n{short}")

    def test_a_listed_merge_gate_row_stays_with_a_person(self) -> None:
        on, held, armed = self.lane_arm(
            f"  lane-arm-gate: true\n{self.FULL}    - {self.RISK}\n"
        )
        self.assertNotIn(self.RISK, armed)
        self.assertIn(self.RISK, held)
        self.assertIn(".github/scripts/pr-merge/who.mjs", armed)

    def test_a_person_held_entry_off_the_floor_or_repeated_stops_it(self) -> None:
        for entries in (
            ["docs/held.md"],
            ["plugins/source-control/scripts/source-control-babysit-merge"],
            # An `enforcement` row is not a person's.
            ["plugins/source-control/skills/babysit-prs/scripts/babysit_gh.py"],
            [".github/workflows/pr-merge.yml", ".github/workflows/pr-merge.yml"],
        ):
            with self.subTest(entries=entries):
                block = "".join(f"    - {e}\n" for e in entries)
                with self.assertRaises(SystemExit):
                    self.lane_arm(f"  lane-arm-gate: true\n  person-held:\n{block}")


if __name__ == "__main__":
    unittest.main()
