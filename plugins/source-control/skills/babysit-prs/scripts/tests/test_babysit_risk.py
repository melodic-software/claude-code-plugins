"""Table tests for the unattended-merge diff risk scorer.

`babysit_risk.score` is a pure function, so every case builds a `RiskInput` and
reads the `RiskResult`; no network seam is involved. Expected reason codes and
severities come from the plan's scorer contract (reason-code list, HIGH floor,
200-line and 8-file limits, C2 re-check rules), never from running the scorer.
"""

from __future__ import annotations

import dataclasses
import pathlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

from babysit_risk import (
    ChangedFile,
    LaneEvidence,
    Risk,
    RiskInput,
    Rung,
    score,
)


def _file(path, *, status="modified", previous_path=None, additions=10,
          deletions=5, has_patch=True):
    return ChangedFile(
        path=path,
        previous_path=previous_path,
        status=status,
        additions=additions,
        deletions=deletions,
        has_patch=has_patch,
    )


def _lane(lane, *, bound=True, unbound_reason=None, open_findings=0):
    return LaneEvidence(
        lane=lane,
        bound=bound,
        unbound_reason=unbound_reason,
        open_findings=open_findings,
    )


BOTH_LANES_CLEAN = (_lane("claude-review"), _lane("claude-security-review"))


def _input(**changes):
    base = RiskInput(
        work_class="C2",
        rung=Rung.C2,
        files=(_file("plugins/foo/skills/bar/SKILL.md"),),
        files_complete=True,
        max_changed_lines=200,
        high_paths=(),
        lanes=BOTH_LANES_CLEAN,
        blast_radius=None,
    )
    return dataclasses.replace(base, **changes)


def _codes(result):
    return tuple(reason.code for reason in result.reasons)


class AllPassTests(unittest.TestCase):
    def test_all_pass_input_scores_low_with_no_reasons(self):
        result = score(_input())
        self.assertEqual(result.score, Risk.LOW)
        self.assertEqual(result.reasons, ())

    def test_c1_class_under_c2_rung_scores_low(self):
        self.assertEqual(score(_input(work_class="C1")).score, Risk.LOW)


class SingleMedReasonTests(unittest.TestCase):
    """Each single miss flips an all-pass input to exactly one MED reason."""

    CASES = [
        ("class missing", dict(work_class=None), "class-missing"),
        ("class not a C1..C5 token", dict(work_class="C9"), "class-missing"),
        ("class above rung", dict(work_class="C3", blast_radius="low"),
         "class-above-rung"),
        ("rung off", dict(rung=Rung.OFF), "class-above-rung"),
        ("removed file", dict(files=(
            _file("plugins/foo/old.md", status="removed", additions=0),)),
         "class-contradicted"),
        ("renamed file", dict(files=(
            _file("plugins/foo/new.md", status="renamed",
                  previous_path="plugins/foo/old.md"),)),
         "class-contradicted"),
        ("schema file", dict(files=(_file("plugins/foo/config.schema.json"),)),
         "class-contradicted"),
        ("two plugins", dict(files=(
            _file("plugins/foo/a.md"), _file("plugins/bar/b.md"))),
         "class-contradicted"),
        ("201 changed lines", dict(files=(
            _file("plugins/foo/a.md", additions=150, deletions=51),)),
         "lines-over"),
        ("nine files", dict(files=tuple(
            _file(f"plugins/foo/f{i}.md", additions=1, deletions=0)
            for i in range(9))),
         "files-over"),
        ("listing incomplete", dict(files_complete=False), "files-incomplete"),
        ("no patch", dict(files=(_file("plugins/foo/logo.png", has_patch=False),)),
         "no-patch:plugins/foo/logo.png"),
        ("code-review lane unbound", dict(lanes=(
            _lane("claude-review", bound=False, unbound_reason="rerun-not-allowed",
                  open_findings=None),
            _lane("claude-security-review"))),
         "evidence-unbound:claude-review"),
        ("security lane unbound", dict(lanes=(
            _lane("claude-review"),
            _lane("claude-security-review", bound=False,
                  unbound_reason="incremental-gap", open_findings=None))),
         "evidence-unbound:claude-security-review"),
        ("security lane absent", dict(lanes=(_lane("claude-review"),)),
         "evidence-unbound:claude-security-review"),
        ("bound lane without a count", dict(lanes=(
            _lane("claude-review", open_findings=None),
            _lane("claude-security-review"))),
         "evidence-unbound:claude-review"),
        ("code-review finding open", dict(lanes=(
            _lane("claude-review", open_findings=1),
            _lane("claude-security-review"))),
         "findings:claude-review"),
        ("blast radius missing above C2", dict(
            work_class="C3", rung=Rung.C3, blast_radius=None),
         "blast-radius-missing"),
    ]

    def test_each_single_miss_is_one_med_reason(self):
        for name, changes, code in self.CASES:
            with self.subTest(name):
                result = score(_input(**changes))
                self.assertEqual(result.score, Risk.MED)
                self.assertEqual(_codes(result), (code,))
                self.assertEqual(result.reasons[0].severity, Risk.MED)


class LimitBoundaryTests(unittest.TestCase):
    def test_exactly_200_changed_lines_is_low(self):
        files = (_file("plugins/foo/a.md", additions=150, deletions=50),)
        self.assertEqual(score(_input(files=files)).score, Risk.LOW)

    def test_lines_are_summed_across_files(self):
        files = (
            _file("plugins/foo/a.md", additions=100, deletions=0),
            _file("plugins/foo/b.md", additions=0, deletions=101),
        )
        self.assertEqual(_codes(score(_input(files=files))), ("lines-over",))

    def test_exactly_eight_files_is_low(self):
        files = tuple(
            _file(f"plugins/foo/f{i}.md", additions=1, deletions=0)
            for i in range(8))
        self.assertEqual(score(_input(files=files)).score, Risk.LOW)

    def test_configured_line_limit_is_honoured(self):
        files = (_file("plugins/foo/a.md", additions=30, deletions=0),)
        self.assertEqual(
            _codes(score(_input(files=files, max_changed_lines=20))),
            ("lines-over",))


class HighReasonTests(unittest.TestCase):
    def test_security_finding_is_high(self):
        lanes = (_lane("claude-review"),
                 _lane("claude-security-review", open_findings=2))
        result = score(_input(lanes=lanes))
        self.assertEqual(result.score, Risk.HIGH)
        self.assertEqual(_codes(result), ("security-finding",))

    def test_floor_paths_are_high(self):
        cases = [
            (".github/workflows/ci.yml", "high-path:.github/**"),
            (".github/trusted-actors.json", "high-path:.github/**"),
            ("docs/conventions/pr-pipeline.yaml", "high-path:docs/conventions/**"),
            ("AGENTS.md", "high-path:**/AGENTS.md"),
            ("CLAUDE.md", "high-path:**/CLAUDE.md"),
            ("plugins/foo/.claude/settings.json", "high-path:**/.claude/**"),
            (".claude/rules/x.md", "high-path:**/.claude/**"),
            ("scripts/sync.sh", "high-path:scripts/**"),
            ("REVIEW.md", "high-path:REVIEW.md"),
            ("plugins/source-control/skills/babysit-prs/SKILL.md",
             "high-path:plugins/source-control/skills/babysit-prs/**"),
            ("plugins/review/agents/x.md", "high-path:plugins/review/**"),
            ("plugins/autonomy/reference/guardrails/work-classes.md",
             "high-path:plugins/autonomy/reference/guardrails/**"),
            ("plugins/foo/.claude-plugin/plugin.json",
             "high-path:**/.claude-plugin/**"),
            (".claude-plugin/marketplace.json", "high-path:**/.claude-plugin/**"),
            ("lib/parse-concern-value.sh", "high-path:lib/**"),
            ("plugins/source-control/lib/yaml-subset.awk",
             "high-path:plugins/source-control/lib/**"),
            ("plugins/source-control/skills/babysit-loop/SKILL.md",
             "high-path:plugins/source-control/skills/babysit-loop/**"),
            (".work-item-tracker.json", "high-path:.work-item-tracker.json"),
        ]
        for path, code in cases:
            with self.subTest(path):
                result = score(_input(files=(_file(path),)))
                self.assertEqual(result.score, Risk.HIGH)
                self.assertIn(code, _codes(result))

    def test_agents_md_at_depth_three_is_high(self):
        result = score(_input(files=(_file("plugins/foo/skills/AGENTS.md"),)))
        self.assertEqual(result.score, Risk.HIGH)
        self.assertEqual(_codes(result), ("high-path:**/AGENTS.md",))

    def test_case_folded_paths_are_high(self):
        cases = [
            (".GitHub/workflows/x.yml", "high-path:.github/**"),
            ("docs/Conventions/x.yaml", "high-path:docs/conventions/**"),
            ("plugins/foo/Claude.md", "high-path:**/CLAUDE.md"),
            ("Scripts/run.sh", "high-path:scripts/**"),
        ]
        for path, code in cases:
            with self.subTest(path):
                result = score(_input(files=(_file(path),)))
                self.assertEqual(result.score, Risk.HIGH)
                self.assertEqual(_codes(result), (code,))

    def test_configured_denied_path_joins_the_floor(self):
        result = score(_input(
            files=(_file("plugins/foo/Special.md"),),
            high_paths=("plugins/foo/special.md",)))
        self.assertEqual(_codes(result), ("high-path:plugins/foo/special.md",))

    def test_empty_configured_set_does_not_weaken_the_floor(self):
        result = score(_input(files=(_file(".github/x.yml"),), high_paths=()))
        self.assertEqual(result.score, Risk.HIGH)

    def test_near_miss_paths_are_not_high(self):
        for path in ("docs/conventions-old/x.md", "plugins/reviewer/x.md",
                     "plugins/foo/scripts/x.sh", "plugins/foo/REVIEW.md",
                     "plugins/foo/agents.md.bak"):
            with self.subTest(path):
                self.assertEqual(score(_input(files=(_file(path),))).score, Risk.LOW)


class RenameTests(unittest.TestCase):
    def test_rename_out_of_a_high_path_is_high(self):
        files = (_file("plugins/foo/x.yml", status="renamed",
                       previous_path=".github/workflows/x.yml"),)
        result = score(_input(files=files))
        self.assertEqual(result.score, Risk.HIGH)
        self.assertEqual(
            _codes(result), ("high-path:.github/**", "class-contradicted"))

    def test_rename_into_a_high_path_is_high(self):
        files = (_file(".github/workflows/x.yml", status="renamed",
                       previous_path="plugins/foo/x.yml"),)
        result = score(_input(files=files))
        self.assertEqual(result.score, Risk.HIGH)
        self.assertEqual(
            _codes(result), ("high-path:.github/**", "class-contradicted"))

    def test_rename_across_plugins_counts_both_plugins(self):
        files = (_file("plugins/foo/x.md", status="renamed",
                       previous_path="plugins/bar/x.md"),)
        self.assertEqual(_codes(score(_input(files=files))), ("class-contradicted",))


class OrderingTests(unittest.TestCase):
    def test_high_beats_every_med(self):
        result = score(_input(
            work_class=None,
            files=(_file(".github/x.yml", has_patch=False),),
            files_complete=False))
        self.assertEqual(result.score, Risk.HIGH)
        self.assertEqual(result.reasons[0].severity, Risk.HIGH)

    def test_reasons_sorted_by_severity_then_code(self):
        lanes = (_lane("claude-review", open_findings=3),
                 _lane("claude-security-review", open_findings=1))
        files = (
            _file("scripts/a.sh"),
            _file(".github/b.yml", has_patch=False),
            _file("plugins/foo/c.md", additions=500),
        )
        result = score(_input(
            work_class="C3", files=files, files_complete=False, lanes=lanes))
        self.assertEqual(_codes(result), (
            "high-path:.github/**",
            "high-path:scripts/**",
            "security-finding",
            "blast-radius-missing",
            "class-above-rung",
            "files-incomplete",
            "findings:claude-review",
            "lines-over",
            "no-patch:.github/b.yml",
        ))


class BlastRadiusTests(unittest.TestCase):
    def test_blast_radius_ignored_for_c2(self):
        for value in (None, "", "high"):
            with self.subTest(value):
                self.assertEqual(
                    score(_input(blast_radius=value)).score, Risk.LOW)

    def test_rated_blast_radius_above_c2_is_low(self):
        result = score(_input(work_class="C3", rung=Rung.C3, blast_radius="low"))
        self.assertEqual(result.score, Risk.LOW)

    def test_blank_blast_radius_above_c2_is_missing(self):
        result = score(_input(work_class="C3", rung=Rung.C3, blast_radius="  "))
        self.assertEqual(_codes(result), ("blast-radius-missing",))


if __name__ == "__main__":
    unittest.main()
