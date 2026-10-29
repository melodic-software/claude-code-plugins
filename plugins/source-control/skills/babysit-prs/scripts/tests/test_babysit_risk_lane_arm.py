"""Owner decision Q7 (#10743): `merge.lane-arm-gate`.

With the switch on, a pull request held only by `gate` floor paths outside
`merge.person-held` (the merge-enforcement set) needs no person once both
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


def _input(*paths: str, threads: int | None = 0, **lanes) -> RiskInput:
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
    )


def _high(result) -> list[str]:
    return [r.code for r in result.reasons if r.code.startswith("high-path:")]


# Gate paths the switch lane-arms: a credentialed workflow, a job-token
# writer, the agent settings and instruction files, a gate script.
ARMED = (
    ".github/workflows/pr-refine.yml",
    ".github/workflows/work-resolve-issue.yml",
    ".claude/settings.json",
    "plugins/foo/AGENTS.md",
    "CLAUDE.md",
    "docs/standards/README.md",
    ".github/scripts/pr-merge/who.mjs",
)
# The merge-enforcement set and trust paths: a person whatever the lanes say.
PERSON = (
    ".github/workflows/pr-require-checks.yml",
    ".github/workflows/pr-merge.yml",
    ".github/workflows/pr-review-main.yml",
    ".github/workflows/pr-review-security-hosted.yml",
    ".github/scripts/pr-review-main/write-verdict.mjs",
    ".github/scripts/pr-merge/merge-holds.mjs",
    ".github/scripts/pr-merge/enable-auto-merge.mjs",
    ".github/scripts/pr-merge/clear-escalations.mjs",
    "plugins/source-control/skills/babysit-prs/scripts/babysit_risk.py",
    "scripts/sync-hold-floor.py",
    "docs/conventions/pr-pipeline.yaml",
    ".github/actions/request-lane-token/action.yml",
)


class TheSwitchLaneArmsGatePaths(unittest.TestCase):
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
            "an open review thread": _input("AGENTS.md", threads=1),
            "an unread thread count": _input("AGENTS.md", threads=None),
            "a malformed thread count": _input("AGENTS.md", threads=True),  # type: ignore[arg-type]
            "a code-review finding, any severity": _input("AGENTS.md", findings=1),
            "a CRITICAL security finding": _input("AGENTS.md", critical=1),
            "bound by a pull_request run, not main": _input(
                "AGENTS.md", main_run=False
            ),
        }
        for name, inp in cases.items():
            with self.subTest(name):
                result = score(inp)
                self.assertIn("high-path:**/AGENTS.md", _high(result))
                self.assertTrue(holds(result))
        unbound = replace(
            _input("AGENTS.md"),
            lanes=(
                _lanes()[0],
                LaneEvidence(
                    "claude-security-review", False, "lane-source-changed", None
                ),
            ),
        )
        missing = replace(_input("AGENTS.md"), lanes=_lanes()[:1])
        doubled = replace(_input("AGENTS.md"), lanes=(*_lanes(), _lanes()[0]))
        for name, inp in (
            ("unbound", unbound),
            ("missing", missing),
            ("doubled", doubled),
        ):
            with self.subTest(name):
                self.assertIn("high-path:**/AGENTS.md", _high(score(inp)))

    def test_a_person_held_or_trust_path_holds_even_with_everything_clean(self) -> None:
        for path in PERSON:
            with self.subTest(path):
                result = score(_input(path))
                self.assertEqual(len(_high(result)), 1, result.reasons)
                self.assertTrue(person_reasons(result.reasons))
        # Beside a lane-armed path, only the person-held one is named.
        result = score(_input("AGENTS.md", ".github/workflows/pr-require-checks.yml"))
        self.assertEqual(
            _high(result), ["high-path:.github/workflows/pr-require-checks.yml"]
        )

    def test_a_configured_denied_path_is_never_lane_armed(self) -> None:
        inp = replace(_input("AGENTS.md"), high_paths=("**/AGENTS.md",))
        self.assertEqual(_high(score(inp)), ["high-path:**/AGENTS.md"])

    def test_the_thread_count_is_read_only_when_it_could_lane_arm(self) -> None:
        self.assertTrue(
            babysit_risk.lane_arm_pending(_input("AGENTS.md", threads=None))
        )
        for name, inp in (
            (
                "a person-held path",
                _input(".github/workflows/pr-merge.yml", threads=None),
            ),
            ("a path off the floor", _input("docs/a.md", threads=None)),
            ("a finding", _input("AGENTS.md", threads=None, findings=1)),
            ("not main-run", _input("AGENTS.md", threads=None, main_run=False)),
        ):
            with self.subTest(name):
                self.assertFalse(babysit_risk.lane_arm_pending(inp))
        with mock.patch.object(babysit_risk, "LANE_ARMED_FLOOR", ()):
            self.assertFalse(babysit_risk.lane_arm_pending(_input("AGENTS.md")))

    def test_the_gate_reads_the_threads_and_an_unreadable_read_keeps_the_hold(
        self,
    ) -> None:
        pending = _input("AGENTS.md", threads=None)
        for threads, expected in (([], 0), ([{"path": "AGENTS.md"}], 1), (None, None)):
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


class TheMergeEnforcementList(unittest.TestCase):
    def test_it_is_trust_and_gate_rows_and_holds_ci_status_and_the_merge_scripts(
        self,
    ) -> None:
        kinds = dict(babysit_risk.FLOOR_CLASSES)
        self.assertIs(babysit_risk.LANE_ARM_GATE, True)
        for glob in babysit_risk.PERSON_HELD:
            self.assertIn(kinds.get(glob), ("trust", "gate"), glob)
            self.assertNotIn(glob, babysit_risk.LANE_ARMED_FLOOR)
        for glob in babysit_risk.LANE_ARMED_FLOOR:
            self.assertEqual(kinds[glob], "gate", glob)
        for glob in (
            ".github/scripts/pr-merge/merge-holds.mjs",
            ".github/scripts/pr-merge/enable-auto-merge.mjs",
            ".github/scripts/pr-merge/superseded.mjs",
            ".github/scripts/pr-merge/clear-escalations.mjs",
            ".github/scripts/pr-merge/gate-check.mjs",
            ".github/scripts/pr-merge/head-ref-map.mjs",
            ".github/workflows/pr-require-checks.yml",
        ):
            self.assertIn(glob, babysit_risk.PERSON_HELD)

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

    def test_only_a_literal_true_turns_it_on(self) -> None:
        held = "  person-held:\n    - .github/workflows/pr-merge.yml\n"
        self.assertEqual(
            self.lane_arm(f"  lane-arm-gate: true\n{held}"),
            (True, [".github/workflows/pr-merge.yml"]),
        )
        # The shared reader unquotes a scalar, so 'true' reads as true.
        for value in (None, "false", "yes", "True", "1", "on", "~"):
            with self.subTest(value=value):
                line = "" if value is None else f"  lane-arm-gate: {value}\n"
                on, _ = self.lane_arm(f"{line}{held}")
                self.assertIs(on, False)

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
