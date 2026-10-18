"""Table tests for the unattended-merge diff risk scorer.

`babysit_risk.score` is a pure function, so every case builds a `RiskInput` and
reads the `RiskResult`; no network seam is involved. Expected reason codes and
severities come from the plan's scorer contract (reason-code list, HIGH floor,
200-line and 8-file limits, C2 re-check rules), never from running the scorer.
"""

from __future__ import annotations

import dataclasses
import pathlib
import subprocess
import sys
import time
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

from babysit_risk import (
    ChangedFile,
    LaneEvidence,
    Risk,
    RiskInput,
    Rung,
    normalize_path,
    score,
)


_UNSET = object()


def _file(
    path,
    *,
    status="modified",
    previous_path=None,
    additions=10,
    deletions=5,
    has_patch=True,
    mode="100644",
    previous_mode=_UNSET,
    patch="",
):
    if previous_mode is _UNSET:
        # A well-formed two-sided change carries its base-side mode.
        two_sided = status in ("modified", "changed", "renamed", "copied")
        previous_mode = "100644" if two_sided else None
    return ChangedFile(
        path=path,
        previous_path=previous_path,
        status=status,
        additions=additions,
        deletions=deletions,
        has_patch=has_patch,
        mode=mode,
        previous_mode=previous_mode,
        patch=patch if has_patch else None,
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

    def test_c1_class_is_contradicted_by_any_pull_request(self):
        # Spec: C1 work produces no pull request, so a C1 PR is contradicted.
        result = score(_input(work_class="C1"))
        self.assertEqual(result.score, Risk.MED)
        self.assertEqual(_codes(result), ("class-contradicted",))


class SingleMedReasonTests(unittest.TestCase):
    """Each single miss flips an all-pass input to exactly one MED reason."""

    CASES = [
        ("class missing", dict(work_class=None), "class-missing"),
        ("class not a C1..C5 token", dict(work_class="C9"), "class-missing"),
        (
            "class above rung",
            dict(work_class="C3", blast_radius="low"),
            "class-above-rung",
        ),
        ("rung off", dict(rung=Rung.OFF), "class-above-rung"),
        (
            "removed file",
            dict(files=(_file("plugins/foo/old.md", status="removed", additions=0),)),
            "class-contradicted",
        ),
        (
            "renamed file",
            dict(
                files=(
                    _file(
                        "plugins/foo/new.md",
                        status="renamed",
                        previous_path="plugins/foo/old.md",
                    ),
                )
            ),
            "class-contradicted",
        ),
        (
            "schema file",
            dict(files=(_file("plugins/foo/config.schema.json"),)),
            "class-contradicted",
        ),
        (
            "two plugins",
            dict(files=(_file("plugins/foo/a.md"), _file("plugins/bar/b.md"))),
            "class-contradicted",
        ),
        (
            "201 changed lines",
            dict(files=(_file("plugins/foo/a.md", additions=150, deletions=51),)),
            "lines-over",
        ),
        (
            "nine files",
            dict(
                files=tuple(
                    _file(f"plugins/foo/f{i}.md", additions=1, deletions=0)
                    for i in range(9)
                )
            ),
            "files-over",
        ),
        ("listing incomplete", dict(files_complete=False), "files-incomplete"),
        (
            "no patch",
            dict(files=(_file("plugins/foo/logo.png", has_patch=False),)),
            "no-patch:plugins/foo/logo.png",
        ),
        (
            "code-review lane unbound",
            dict(
                lanes=(
                    _lane(
                        "claude-review",
                        bound=False,
                        unbound_reason="rerun-not-allowed",
                        open_findings=None,
                    ),
                    _lane("claude-security-review"),
                )
            ),
            "evidence-unbound:claude-review",
        ),
        (
            "security lane unbound",
            dict(
                lanes=(
                    _lane("claude-review"),
                    _lane(
                        "claude-security-review",
                        bound=False,
                        unbound_reason="incremental-gap",
                        open_findings=None,
                    ),
                )
            ),
            "evidence-unbound:claude-security-review",
        ),
        (
            "security lane absent",
            dict(lanes=(_lane("claude-review"),)),
            "evidence-unbound:claude-security-review",
        ),
        (
            "bound lane without a count",
            dict(
                lanes=(
                    _lane("claude-review", open_findings=None),
                    _lane("claude-security-review"),
                )
            ),
            "evidence-unbound:claude-review",
        ),
        (
            "code-review finding open",
            dict(
                lanes=(
                    _lane("claude-review", open_findings=1),
                    _lane("claude-security-review"),
                )
            ),
            "findings:claude-review",
        ),
        (
            "blast radius missing above C2",
            dict(work_class="C3", rung=Rung.C3, blast_radius=None),
            "blast-radius-missing",
        ),
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
            _file(f"plugins/foo/f{i}.md", additions=1, deletions=0) for i in range(8)
        )
        self.assertEqual(score(_input(files=files)).score, Risk.LOW)

    def test_configured_line_limit_is_honored(self):
        files = (_file("plugins/foo/a.md", additions=30, deletions=0),)
        self.assertEqual(
            _codes(score(_input(files=files, max_changed_lines=20))), ("lines-over",)
        )


class HighReasonTests(unittest.TestCase):
    def test_security_finding_is_high(self):
        lanes = (
            _lane("claude-review"),
            _lane("claude-security-review", open_findings=2),
        )
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
            (
                "plugins/source-control/skills/babysit-prs/SKILL.md",
                "high-path:plugins/source-control/skills/babysit-prs/**",
            ),
            ("plugins/review/agents/x.md", "high-path:plugins/review/**"),
            (
                "plugins/autonomy/reference/guardrails/work-classes.md",
                "high-path:plugins/autonomy/reference/guardrails/**",
            ),
            (
                "plugins/foo/.claude-plugin/plugin.json",
                "high-path:**/.claude-plugin/**",
            ),
            (".claude-plugin/marketplace.json", "high-path:**/.claude-plugin/**"),
            ("lib/parse-concern-value.sh", "high-path:lib/**"),
            (
                "plugins/source-control/lib/yaml-subset.awk",
                "high-path:plugins/source-control/lib/**",
            ),
            (
                "plugins/source-control/skills/babysit-loop/SKILL.md",
                "high-path:plugins/source-control/skills/babysit-loop/**",
            ),
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
            ("AGENTS.MD", "high-path:**/AGENTS.md"),
            ("LIB/x.sh", "high-path:lib/**"),
        ]
        for path, code in cases:
            with self.subTest(path):
                result = score(_input(files=(_file(path),)))
                self.assertEqual(result.score, Risk.HIGH)
                self.assertEqual(_codes(result), (code,))

    def test_configured_denied_path_joins_the_floor(self):
        result = score(
            _input(
                files=(_file("plugins/foo/Special.md"),),
                high_paths=("plugins/foo/special.md",),
            )
        )
        self.assertEqual(_codes(result), ("high-path:plugins/foo/special.md",))

    def test_empty_configured_set_does_not_weaken_the_floor(self):
        result = score(_input(files=(_file(".github/x.yml"),), high_paths=()))
        self.assertEqual(result.score, Risk.HIGH)

    def test_near_miss_paths_are_not_high(self):
        for path in (
            "docs/conventions-old/x.md",
            "plugins/reviewer/x.md",
            "plugins/foo/scripts/x.sh",
            "plugins/foo/REVIEW.md",
            "plugins/foo/agents.md.bak",
        ):
            with self.subTest(path):
                self.assertEqual(score(_input(files=(_file(path),))).score, Risk.LOW)


class RenameTests(unittest.TestCase):
    def test_rename_out_of_a_high_path_is_high(self):
        files = (
            _file(
                "plugins/foo/x.yml",
                status="renamed",
                previous_path=".github/workflows/x.yml",
            ),
        )
        result = score(_input(files=files))
        self.assertEqual(result.score, Risk.HIGH)
        self.assertEqual(_codes(result), ("high-path:.github/**", "class-contradicted"))

    def test_rename_into_a_high_path_is_high(self):
        files = (
            _file(
                ".github/workflows/x.yml",
                status="renamed",
                previous_path="plugins/foo/x.yml",
            ),
        )
        result = score(_input(files=files))
        self.assertEqual(result.score, Risk.HIGH)
        self.assertEqual(_codes(result), ("high-path:.github/**", "class-contradicted"))

    def test_rename_across_plugins_counts_both_plugins(self):
        files = (
            _file(
                "plugins/foo/x.md", status="renamed", previous_path="plugins/bar/x.md"
            ),
        )
        self.assertEqual(_codes(score(_input(files=files))), ("class-contradicted",))


class OrderingTests(unittest.TestCase):
    def test_high_beats_every_med(self):
        result = score(
            _input(
                work_class=None,
                files=(_file(".github/x.yml", has_patch=False),),
                files_complete=False,
            )
        )
        self.assertEqual(result.score, Risk.HIGH)
        self.assertEqual(result.reasons[0].severity, Risk.HIGH)

    def test_reasons_sorted_by_severity_then_code(self):
        lanes = (
            _lane("claude-review", open_findings=3),
            _lane("claude-security-review", open_findings=1),
        )
        files = (
            _file("scripts/a.sh"),
            _file(".github/b.yml", has_patch=False),
            _file("plugins/foo/c.md", additions=500),
        )
        result = score(
            _input(work_class="C3", files=files, files_complete=False, lanes=lanes)
        )
        self.assertEqual(
            _codes(result),
            (
                "high-path:.github/**",
                "high-path:scripts/**",
                "security-finding",
                "blast-radius-missing",
                "class-above-rung",
                "files-incomplete",
                "findings:claude-review",
                "lines-over",
                "no-patch:.github/b.yml",
            ),
        )


class EvidenceAndPluginTests(unittest.TestCase):
    def test_bound_lane_carrying_an_unbound_reason_is_unbound(self):
        lanes = (
            _lane("claude-review", unbound_reason="stale-sha"),
            _lane("claude-security-review"),
        )
        result = score(_input(lanes=lanes))
        self.assertEqual(result.score, Risk.MED)
        self.assertEqual(_codes(result), ("evidence-unbound:claude-review",))

    def test_plugin_directories_differing_only_in_case_are_two_plugins(self):
        files = (_file("plugins/Foo/a.md"), _file("plugins/foo/b.md"))
        result = score(_input(files=files))
        self.assertEqual(_codes(result), ("class-contradicted",))

    def test_plugins_segment_is_folded_when_counting_plugins(self):
        files = (_file("Plugins/foo/a.md"), _file("plugins/bar/b.md"))
        result = score(_input(files=files))
        self.assertEqual(_codes(result), ("class-contradicted",))


class GlobTimingTests(unittest.TestCase):
    """Spec: each configured glob is judged in under 0.5s, however many stars."""

    CASES = (
        ("**/" * 9 + "z", "/".join(["a"] * 30) + "/b.md"),
        ("**/a/" * 9 + "z", "/".join(["a"] * 30) + "/b.md"),
        ("plugins/foo/" + "*a" * 20 + "z", "plugins/foo/" + "a" * 60 + ".md"),
    )

    def test_star_heavy_globs_finish_fast(self):
        for glob, path in self.CASES:
            with self.subTest(glob):
                start = time.perf_counter()
                result = score(_input(files=(_file(path),), high_paths=(glob,)))
                self.assertLess(time.perf_counter() - start, 0.5)
                self.assertEqual(result.score, Risk.LOW)

    def test_star_runs_inside_a_segment_fail_closed_fast(self):
        # Spec: '**' inside a segment is not a whole '**' segment: unreadable.
        for stars in (10, 20):
            glob = "plugins/foo/" + "*" * stars + "z"
            with self.subTest(glob):
                start = time.perf_counter()
                result = score(
                    _input(
                        files=(_file("plugins/foo/" + "a" * 40 + ".md"),),
                        high_paths=(glob,),
                    )
                )
                self.assertLess(time.perf_counter() - start, 0.5)
                self.assertEqual(_codes(result), ("high-path:**",))

    def test_double_star_over_a_very_deep_path_finishes_quickly(self):
        path = "/".join(["a"] * 20_000) + "/x.md"
        start = time.perf_counter()
        result = score(_input(files=(_file(path),), high_paths=("**/a/**/b",)))
        self.assertLess(time.perf_counter() - start, 1.0)
        self.assertEqual(result.score, Risk.LOW)

    def test_star_globs_still_match(self):
        for glob, path in (
            ("plugins/foo/*.md", "plugins/foo/" + "a" * 40 + ".md"),
            ("**/" * 9 + "b.md", "/".join(["a"] * 30) + "/b.md"),
            ("plugins/*o*/a*.md", "plugins/foo/abc.md"),
        ):
            with self.subTest(glob):
                result = score(_input(files=(_file(path),), high_paths=(glob,)))
                self.assertIn(f"high-path:{glob}", _codes(result))


class BlastRadiusTests(unittest.TestCase):
    def test_blast_radius_ignored_for_c2(self):
        for value in (None, "", "high"):
            with self.subTest(value):
                self.assertEqual(score(_input(blast_radius=value)).score, Risk.LOW)

    def test_rated_blast_radius_above_c2_is_low(self):
        result = score(_input(work_class="C3", rung=Rung.C3, blast_radius="low"))
        self.assertEqual(result.score, Risk.LOW)

    def test_only_a_low_rating_keeps_a_class_above_c2_low(self):
        # Spec: the plan's scale is LOW / MEDIUM / HIGH / CRITICAL; any value
        # other than LOW above C2 rates MED.
        for value in (
            "high",
            "HIGH",
            "MEDIUM",
            "CRITICAL",
            "unknown",
            "none",
            "null",
            " low",
        ):
            with self.subTest(value):
                result = score(
                    _input(work_class="C3", rung=Rung.C3, blast_radius=value)
                )
                self.assertEqual(result.score, Risk.MED)
        result = score(_input(work_class="C3", rung=Rung.C3, blast_radius="LOW"))
        self.assertEqual(result.score, Risk.LOW)

    def test_blank_blast_radius_above_c2_is_missing(self):
        result = score(_input(work_class="C3", rung=Rung.C3, blast_radius="  "))
        self.assertEqual(_codes(result), ("blast-radius-missing",))


class MalformedInputTests(unittest.TestCase):
    """Missing or unrecognized data is a miss: never LOW, and never a raise."""

    CASES = [
        ("empty file list", dict(files=()), Risk.MED, "files-incomplete"),
        ("files None", dict(files=None), Risk.MED, "files-incomplete"),
        (
            "unknown status",
            dict(files=(_file("plugins/foo/a.md", status="deleted"),)),
            Risk.MED,
            "files-incomplete",
        ),
        (
            "status None",
            dict(files=(_file("plugins/foo/a.md", status=None),)),
            Risk.MED,
            "files-incomplete",
        ),
        (
            "copied is structural",
            dict(
                files=(
                    _file(
                        "plugins/foo/b.md",
                        status="copied",
                        previous_path="plugins/foo/a.md",
                    ),
                )
            ),
            Risk.MED,
            "class-contradicted",
        ),
        (
            "changed is structural",
            dict(files=(_file("plugins/foo/a.md", status="changed"),)),
            Risk.MED,
            "class-contradicted",
        ),
        (
            "negative additions",
            dict(files=(_file("plugins/foo/a.md", additions=-500),)),
            Risk.MED,
            "files-incomplete",
        ),
        (
            "string additions",
            dict(files=(_file("plugins/foo/a.md", additions="3"),)),
            Risk.MED,
            "files-incomplete",
        ),
        (
            "additions None",
            dict(files=(_file("plugins/foo/a.md", additions=None),)),
            Risk.MED,
            "files-incomplete",
        ),
        (
            "float deletions",
            dict(files=(_file("plugins/foo/a.md", deletions=1.5),)),
            Risk.MED,
            "files-incomplete",
        ),
        (
            "files_complete string",
            dict(files_complete="false"),
            Risk.MED,
            "files-incomplete",
        ),
        (
            "files_complete None",
            dict(files_complete=None),
            Risk.MED,
            "files-incomplete",
        ),
        (
            "has_patch string",
            dict(files=(_file("plugins/foo/a.md", has_patch="false"),)),
            Risk.MED,
            "files-incomplete",
        ),
        (
            "has_patch None",
            dict(files=(_file("plugins/foo/a.md", has_patch=None),)),
            Risk.MED,
            "files-incomplete",
        ),
        ("rung out of range", dict(rung=9), Risk.MED, "class-above-rung"),
        ("rung None", dict(rung=None), Risk.MED, "class-above-rung"),
        (
            "max_changed_lines None",
            dict(max_changed_lines=None),
            Risk.MED,
            "lines-over",
        ),
        ("lanes None", dict(lanes=None), Risk.MED, "evidence-unbound:claude-review"),
        ("high_paths None", dict(high_paths=None), Risk.HIGH, "high-path:**"),
        ("path None", dict(files=(_file(None),)), Risk.HIGH, "high-path:**"),
    ]

    def test_malformed_inputs_map_to_the_documented_code(self):
        # Spec: the module docstring's mapping (per-file data and the listing
        # to files-incomplete, an unknown rung to class-above-rung, an
        # unreadable limit to lines-over, an unreadable HIGH set or path to
        # high-path:**), never LOW and never a raise.
        for name, changes, severity, code in self.CASES:
            with self.subTest(name):
                result = score(_input(**changes))
                self.assertEqual(result.score, severity)
                self.assertIn(code, _codes(result))

    def test_malformed_has_patch_is_reported_once(self):
        for value in ("false", None):
            with self.subTest(value):
                result = score(
                    _input(files=(_file("plugins/foo/a.md", has_patch=value),))
                )
                self.assertEqual(_codes(result), ("files-incomplete",))

    def test_file_modes_other_than_regular_are_high_any_path(self):
        # Spec: a missing or malformed mode, a symlink (120000) or submodule
        # (160000), or a previous_mode of another type rates HIGH.
        for name, changes in (
            ("mode None", dict(mode=None)),
            ("mode empty", dict(mode="")),
            ("mode tree", dict(mode="040000")),
            ("mode int", dict(mode=100644)),
            ("symlink", dict(mode="120000")),
            ("submodule", dict(mode="160000")),
            ("regular to symlink", dict(mode="120000", previous_mode="100644")),
            ("symlink to regular", dict(mode="100644", previous_mode="120000")),
            ("submodule to regular", dict(mode="100755", previous_mode="160000")),
            ("previous mode malformed", dict(previous_mode="777")),
        ):
            with self.subTest(name):
                result = score(_input(files=(_file("plugins/foo/a.md", **changes),)))
                self.assertEqual(result.score, Risk.HIGH)
                self.assertIn("high-path:**", _codes(result))

    def test_regular_modes_stay_low(self):
        for changes in (
            dict(mode="100644"),
            dict(mode="100755"),
            dict(mode="100755", previous_mode="100644"),
        ):
            with self.subTest(changes):
                result = score(_input(files=(_file("plugins/foo/a.md", **changes),)))
                self.assertEqual(result.score, Risk.LOW)

    def test_two_sided_change_needs_a_previous_mode(self):
        # Spec: modified, changed, renamed or copied with previous_mode None, malformed
        # or '000000' (absent) is HIGH, at a class where nothing else fires.
        for status in ("modified", "changed", "renamed", "copied"):
            for previous_mode in (None, "777", "000000"):
                with self.subTest((status, previous_mode)):
                    result = score(
                        _input(
                            work_class="C3",
                            rung=Rung.C3,
                            blast_radius="low",
                            files=(
                                _file(
                                    "plugins/foo/b.md",
                                    status=status,
                                    previous_path="plugins/foo/a.md",
                                    previous_mode=previous_mode,
                                ),
                            ),
                        )
                    )
                    self.assertEqual(result.score, Risk.HIGH)
                    unsafe = [r for r in result.reasons if r.code == "high-path:**"]
                    self.assertEqual(len(unsafe), 1)
                    self.assertIn("previous mode", unsafe[0].detail)

    def test_absent_previous_mode_is_allowed_only_for_an_added_file(self):
        added = _file("plugins/foo/a.md", status="added", previous_mode="000000")
        self.assertEqual(score(_input(files=(added,))).score, Risk.LOW)
        modified = _file("plugins/foo/a.md", previous_mode="000000")
        result = score(_input(files=(modified,)))
        self.assertEqual(result.score, Risk.HIGH)
        self.assertIn("high-path:**", _codes(result))

    def test_odd_path_forms_are_high_any_path(self):
        # Spec: a `..` segment, a trailing `/`, a `:` in a segment, or a
        # `~<digit>` segment marks the path unsafe: HIGH as high-path:**.
        for path in (
            "plugins/foo/../bar.md",
            "plugins/foo/../../plugins/foo/x.md",
            ".github/",
            "plugins/foo/x.md/",
            "AGENTS.md::$DATA",
            "AGENTS.md:stream",
            "GITHUB~1/workflows/x.yml",
        ):
            with self.subTest(path):
                result = score(_input(files=(_file(path),)))
                self.assertEqual(result.score, Risk.HIGH)
                self.assertIn("high-path:**", _codes(result))

    def test_paths_outside_the_segment_allowlist_are_high_any_path(self):
        # Spec: safe only if every segment is non-empty, matches
        # [A-Za-z0-9._-]+ and does not end in `.`.
        for path in (
            "plugins/foo/x.md\n",
            "AGENTS.md\n",
            "plugins/foo/x.schema.json\n",
            "plugins/foo/\x00x.md",
            "plugins/foo/\tx.md",
            "plugins/foo/\x1bx.md",
            " plugins/foo/x.md",
            "plugins/foo/x.md ",
            "plugins/foo/x .md",
            "plugins/foo/x　.md",
            "plugins/foo/x‌.md",
            "plugins/foo/lıb.md",
            "plugins/foo/і.md",
            "plugins/foo/Ａ.md",
            "plugins/foo/a~b.md",
        ):
            with self.subTest(repr(path)):
                result = score(_input(files=(_file(path),)))
                self.assertEqual(result.score, Risk.HIGH)
                self.assertIn("high-path:**", _codes(result))

    def test_every_tracked_path_is_safe(self):
        here = pathlib.Path(__file__).resolve().parent
        try:
            listing = subprocess.run(
                ["git", "-C", str(here), "ls-files", "-z", "--full-name", ":/"],
                capture_output=True,
                check=True,
            ).stdout
        except (OSError, subprocess.CalledProcessError):
            self.skipTest("git or a checkout is unavailable")
        paths = [p for p in listing.decode("utf-8").split("\0") if p]
        self.assertTrue(paths)
        unsafe = [p for p in paths if not normalize_path(p)[1]]
        self.assertEqual(unsafe, [])

    def test_double_star_spans_any_character(self):
        result = score(_input(files=(_file(".github/a\nb"),)))
        self.assertIn("high-path:.github/**", _codes(result))

    def test_rename_or_copy_without_a_previous_path_is_high_at_every_class(self):
        for status in ("renamed", "copied"):
            for work_class, rung in (("C2", Rung.C2), ("C3", Rung.C3)):
                with self.subTest((status, work_class)):
                    result = score(
                        _input(
                            work_class=work_class,
                            rung=rung,
                            blast_radius="low",
                            files=(_file("plugins/foo/x.md", status=status),),
                        )
                    )
                    self.assertEqual(result.score, Risk.HIGH)
                    self.assertIn("high-path:**", _codes(result))

    def test_unhashable_status_is_malformed_not_a_raise(self):
        for status in ([], {}, ["renamed"]):
            with self.subTest(repr(status)):
                result = score(
                    _input(files=(_file("plugins/foo/a.md", status=status),))
                )
                self.assertGreaterEqual(result.score, Risk.MED)

    def test_configured_globs_outside_the_allowlist_fail_closed(self):
        for glob in (
            "",
            ".",
            "./",
            "   ",
            "plugins/../x",
            "plugins/./x",
            "..",
            "plugins/fo o/**",
            "plugins/foo:x",
            "plugins/ｆoo/**",
            "plugins/foo\n",
        ):
            with self.subTest(repr(glob)):
                result = score(_input(high_paths=(glob,)))
                self.assertEqual(result.score, Risk.HIGH)
                self.assertIn("high-path:**", _codes(result))

    def test_configured_globs_inside_the_allowlist_are_accepted(self):
        for glob in ("docs/*.md", "**/build/**", "plugins/bar/", "tools/x-y_z.json"):
            with self.subTest(glob):
                self.assertEqual(score(_input(high_paths=(glob,))).score, Risk.LOW)

    def test_paths_that_could_alias_a_floor_path_are_high_any_path(self):
        for path in (
            "../.github/x.yml",
            "plugins/foo/../../.github/x.yml",
            "./.github/x.yml",
            "/.github/x.yml",
            ".github\\workflows\\x.yml",
            "plugins\\foo\\AGENTS.md",
            "docs\\conventions\\x.yaml",
            "docs//conventions/x.yaml",
            "AGENTS.md.",
            ".github./x.yml",
            "plugins/foo /x.md",
            "",
            "../plugins/foo/x.md",
        ):
            with self.subTest(path):
                result = score(_input(files=(_file(path),)))
                self.assertEqual(result.score, Risk.HIGH)
                self.assertIn("high-path:**", _codes(result))

    def test_dot_slash_prefix_matches_the_floor_glob(self):
        result = score(_input(files=(_file("./scripts/x.sh"),)))
        self.assertIn("high-path:scripts/**", _codes(result))

    def test_caller_globs_are_read_exactly_as_written(self):
        # Spec: a './' or '/' prefix, a backslash, a segment ending in '.', or
        # a '.' or '..' segment fails closed, whatever the changed files are.
        for glob in (
            "/plugins/foo/x.md",
            "./plugins/foo/x.md",
            "plugins\\foo\\x.md",
            "plugins/foo./x.md",
            "plugins/./foo",
            "plugins/../foo",
        ):
            with self.subTest(glob):
                result = score(_input(high_paths=(glob,)))
                self.assertEqual(result.score, Risk.HIGH)
                self.assertIn("high-path:**", _codes(result))

    def test_directory_glob_covers_everything_under_it(self):
        result = score(
            _input(files=(_file("plugins/foo/deep/x.md"),), high_paths=("plugins/foo",))
        )
        self.assertEqual(_codes(result), ("high-path:plugins/foo",))

    def test_floor_directory_glob_matches_the_bare_entry(self):
        # Spec: 'X/**' also matches X itself.
        for path, code in (
            (".github", "high-path:.github/**"),
            ("scripts", "high-path:scripts/**"),
            ("docs/conventions", "high-path:docs/conventions/**"),
            ("plugins/foo/.claude", "high-path:**/.claude/**"),
            ("plugins/foo/.claude-plugin", "high-path:**/.claude-plugin/**"),
        ):
            with self.subTest(path):
                result = score(_input(files=(_file(path),)))
                self.assertEqual(result.score, Risk.HIGH)
                self.assertIn(code, _codes(result))

    def test_trailing_double_star_forms_match_the_bare_entry(self):
        # Spec: 'X/**' also matches X; 'X/**/' and 'X/**/**' mean the same glob.
        for glob in ("docs/**", "docs/**/", "docs/**/**"):
            with self.subTest(glob):
                result = score(_input(files=(_file("docs"),), high_paths=(glob,)))
                self.assertIn(f"high-path:{glob}", _codes(result))


class LaneSwitchTests(unittest.TestCase):
    """Owner decision Q624: in the pr-merge lane the HIGH path floor, the
    file and line caps and the C2 contradictions are each a setting the
    caller turns off. Off, the same diff that scored above LOW is LOW."""

    def test_the_floor_off_leaves_floor_paths_low(self):
        files = (_file(".github/workflows/x.yml"),)
        self.assertEqual(score(_input(files=files)).score, Risk.HIGH)
        result = score(_input(files=files, high_floor=False))
        self.assertEqual(result.score, Risk.LOW, _codes(result))

    def test_the_floor_off_still_honors_configured_paths(self):
        files = (_file(".github/workflows/x.yml"),)
        result = score(
            _input(files=files, high_floor=False, high_paths=(".github/**",))
        )
        self.assertEqual(_codes(result), ("high-path:.github/**",))

    def test_the_floor_off_still_refuses_unsafe_paths(self):
        result = score(_input(files=(_file("../x"),), high_floor=False))
        self.assertIn("high-path:**", _codes(result))

    def test_contradictions_off_leave_a_structural_diff_low(self):
        files = (
            _file("plugins/a/x.md", status="removed", previous_mode=None),
            _file("plugins/b/y.schema.json"),
        )
        self.assertIn("class-contradicted", _codes(score(_input(files=files))))
        result = score(_input(files=files, c2_contradictions=False))
        self.assertEqual(result.score, Risk.LOW, _codes(result))

    def test_no_file_cap_leaves_many_files_low(self):
        files = tuple(
            _file(f"plugins/foo/f{i}.md", additions=1, deletions=0) for i in range(9)
        )
        self.assertIn("files-over", _codes(score(_input(files=files))))
        result = score(_input(files=files, max_changed_files=None))
        self.assertEqual(result.score, Risk.LOW, _codes(result))
        capped = score(_input(files=files, max_changed_files=3))
        self.assertIn(
            ("files-over", "9 > 3"), [(r.code, r.detail) for r in capped.reasons]
        )

    def test_no_line_cap_leaves_a_large_diff_low(self):
        files = (_file("plugins/foo/a.md", additions=5000, deletions=0),)
        unread = score(_input(files=files, max_changed_lines=None))
        self.assertIn("lines-over", _codes(unread))
        result = score(_input(files=files, max_changed_lines=None, lines_optional=True))
        self.assertEqual(result.score, Risk.LOW, _codes(result))
        capped = score(_input(files=files, max_changed_lines=10, lines_optional=True))
        self.assertIn("lines-over", _codes(capped))


class NeverRaisesTests(unittest.TestCase):
    def _assert_high_any_path(self, result):
        self.assertEqual(result.score, Risk.HIGH)
        self.assertEqual(_codes(result), ("high-path:**",))

    def test_unreadable_input_is_high_any_path(self):
        class Exploding:
            def __getattr__(self, name):
                raise RuntimeError(name)

        for name, value in (
            ("None", None),
            ("object without fields", object()),
            ("raising attributes", Exploding()),
        ):
            with self.subTest(name):
                self._assert_high_any_path(score(value))

    def test_deeply_nested_input_is_high_not_a_raise(self):
        nested = []
        for _ in range(100_000):
            nested = [nested]
        result = score(_input(files=(_file(nested),)))
        self.assertEqual(result.score, Risk.HIGH)
        self.assertIn("high-path:**", _codes(result))

    def test_counts_past_the_limit_are_malformed_and_never_formatted(self):
        huge = 10**5000
        for name, changes in (
            (
                "additions over 10**9",
                dict(files=(_file("plugins/foo/a.md", additions=10**9 + 1),)),
            ),
            (
                "huge deletions",
                dict(files=(_file("plugins/foo/a.md", deletions=huge),)),
            ),
            ("huge max_changed_lines", dict(max_changed_lines=huge)),
            (
                "huge open_findings",
                dict(
                    lanes=(
                        _lane("claude-review", open_findings=huge),
                        _lane("claude-security-review"),
                    )
                ),
            ),
            ("huge path", dict(files=(_file(huge),))),
            (
                "huge unbound_reason",
                dict(
                    lanes=(
                        _lane("claude-review", bound=False, unbound_reason=huge),
                        _lane("claude-security-review"),
                    )
                ),
            ),
        ):
            with self.subTest(name):
                result = score(_input(**changes))
                self.assertGreaterEqual(result.score, Risk.MED)
                self.assertNotIn(
                    "scorer could not read", " ".join(r.detail for r in result.reasons)
                )

    def test_count_at_the_limit_is_read(self):
        result = score(_input(max_changed_lines=10**9))
        self.assertEqual(result.score, Risk.LOW)

    def test_each_reason_code_appears_once(self):
        result = score(_input(files=(_file("plugins/foo/a b.md"),), high_paths=("**",)))
        codes = _codes(result)
        self.assertEqual(len(codes), len(set(codes)))
        self.assertIn("high-path:**", codes)

    def test_configured_double_star_alone_is_unreadable(self):
        # Spec: a configured glob of exactly '**' names no specific denied path.
        for glob in ("**", "**/"):
            with self.subTest(glob):
                result = score(_input(high_paths=(glob,)))
                self.assertEqual(result.score, Risk.HIGH)
                self.assertEqual(_codes(result), ("high-path:**",))

    def test_configured_glob_repeating_a_floor_glob_yields_one_code(self):
        result = score(
            _input(
                files=(_file(".github/x.yml"),),
                high_paths=(".github/**", ".github/**"),
            )
        )
        self.assertEqual(_codes(result), ("high-path:.github/**",))


class AddedFloorTests(unittest.TestCase):
    def test_added_floor_paths_are_high_under_their_own_code(self):
        for path, glob in (
            ("plugins/guardrails/hooks/x.sh", "plugins/guardrails/**"),
            ("plugins/work-items/skills/x.md", "plugins/work-items/**"),
            ("plugins/foo/hooks/hooks.json", "plugins/*/hooks/**"),
            ("prompts/x.md", "prompts/**"),
            ("package.json", "**/package.json"),
            ("plugins/foo/package.json", "**/package.json"),
            ("package-lock.json", "**/package-lock.json"),
            ("plugins/foo/package-lock.json", "**/package-lock.json"),
            ("plugins/actionlint/lib/prerequisites.sh", "plugins/*/lib/**"),
            (
                "plugins/disk-hygiene/skills/clean/scripts/destructive_guard.py",
                "plugins/disk-hygiene/skills/clean/scripts/destructive_guard.py",
            ),
            (
                "plugins/disk-hygiene/skills/clean/scripts/engine_context.py",
                "plugins/disk-hygiene/skills/clean/scripts/engine_context.py",
            ),
            (
                "plugins/disk-hygiene/skills/clean/scripts/guard_launch_monitor.py",
                "plugins/disk-hygiene/skills/clean/scripts/guard_launch_monitor.py",
            ),
            (".node-version", ".node-version"),
            (".python-version", ".python-version"),
            (".gitleaks.toml", ".gitleaks.toml"),
            (".gitleaksignore", ".gitleaksignore"),
            (".gitattributes", ".gitattributes"),
            ("plugins/foo/.gitmodules", "**/.gitmodules"),
            ("plugins/foo/CLAUDE.local.md", "**/CLAUDE.local.md"),
            ("plugins/foo/.mcp.json", "**/.mcp.json"),
            ("plugins/foo/AGENTS.override.md", "**/AGENTS.override.md"),
        ):
            with self.subTest(path):
                result = score(_input(files=(_file(path),)))
                self.assertEqual(result.score, Risk.HIGH)
                self.assertIn(f"high-path:{glob}", _codes(result))

    def test_root_package_lock_has_one_floor_code(self):
        codes = _codes(score(_input(files=(_file("package-lock.json"),))))
        self.assertEqual(codes, ("high-path:**/package-lock.json",))


class UnreadableSetAndDetailTests(unittest.TestCase):
    def test_unreadable_configured_set_matches_only_the_floor(self):
        result = score(
            _input(
                files=(_file("plugins/foo/a.md"),),
                high_paths=("plugins/foo/**", "./bad"),
            )
        )
        self.assertEqual(_codes(result), ("high-path:**",))

    def test_unbound_lane_detail_says_not_bound(self):
        lanes = (
            _lane("claude-review", bound=False, open_findings=None),
            _lane("claude-security-review"),
        )
        reason = score(_input(lanes=lanes)).reasons[0]
        self.assertEqual(reason.code, "evidence-unbound:claude-review")
        self.assertIn("not bound", reason.detail)

    def test_lane_evidence_naming_no_known_lane_is_a_miss(self):
        # Spec: unrecognized data is a miss, never a pass.
        clean = (_lane("claude-review"), _lane("claude-security-review"))
        for extra in ("claude-docs-review", "", None, 7, ["claude-review"]):
            with self.subTest(extra):
                result = score(_input(lanes=(*clean, _lane(extra))))
                self.assertEqual(result.score, Risk.MED)
                self.assertIn("evidence-unbound:unknown", _codes(result))

    def test_class_contradicted_names_the_files(self):
        files = (_file("plugins/foo/old.md", status="removed", additions=0),)
        reason = score(_input(files=files)).reasons[0]
        self.assertEqual(reason.code, "class-contradicted")
        self.assertIn("plugins/foo/old.md", reason.detail)

    def test_rung_is_named_in_the_detail(self):
        reasons = score(
            _input(work_class="C3", rung=Rung.C2, blast_radius="low")
        ).reasons
        self.assertIn("C2", reasons[0].detail)
        self.assertNotIn("<Rung", reasons[0].detail)


REPO_ROOT = pathlib.Path(__file__).resolve().parents[6]


def _lane_config():
    import babysit_merge_policy

    def file_at(path, _sha):
        found = REPO_ROOT / path
        return found.read_text(encoding="utf-8") if found.is_file() else None

    return babysit_merge_policy.read_config_at(
        "melodic-software/claude-code-plugins", "0" * 40, file_at
    )


def _lane_input(files, *, high_floor=True):
    """The pr-merge lane's input under this repository's own
    docs/conventions/pr-pipeline.yaml, wired as babysit_merge.score_unattended
    wires it, with `high-path-floor` set here rather than read: the live
    config keeps it off (owner decisions Q661 and Q663), and these tests check
    what its lists hold once it is on."""
    config = _lane_config()
    return _input(
        files=files,
        max_changed_lines=config.max_changed_lines,
        high_paths=config.denied_paths,
        floor_paths=config.floor_paths,
        floor_script_scopes=config.floor_script_scopes,
        high_floor=high_floor,
        c2_contradictions=config.c2_contradictions,
        max_changed_files=config.max_changed_files,
        lines_optional=True,
    )


class LanePathFloorTests(unittest.TestCase):
    """Owner decision Q641: the config adds bin/, .lsp.json, settings*.json and
    the scripts of the plugins the CI lanes load, so with the floor on a lane
    pull request touching one waits for a human. Paths come from the decision
    text. The floor itself stays off (Q661, Q663)."""

    def test_the_live_config_keeps_the_floor_off(self):
        self.assertIs(_lane_config().high_path_floor, False)
        result = score(_lane_input((_file("plugins/foo/bin/run"),), high_floor=False))
        self.assertEqual(result.score, Risk.LOW, _codes(result))

    LANE_PLUGINS = (
        "ai-slop",
        "source-control",
        "work-items",
        "discovery",
        "knowledge",
        "skill-quality",
        "testing",
        "review",
        "autonomy",
    )

    def test_each_new_path_class_is_held(self):
        paths = [
            "plugins/foo/bin/tool",
            "plugins/foo/package.json",
            "plugins/foo/.mcp.json",
            "plugins/foo/.lsp.json",
            "plugins/foo/settings.json",
            ".config/settings.local.json",
        ]
        for plugin in self.LANE_PLUGINS:
            paths.append(f"plugins/{plugin}/scripts/run.py")
            paths.append(f"plugins/{plugin}/skills/some-skill/scripts/run.sh")
        for path in paths:
            with self.subTest(path=path):
                result = score(_lane_input((_file(path),)))
                self.assertEqual(result.score, Risk.HIGH, _codes(result))
                self.assertTrue(
                    any(
                        r.code.startswith("high-path:")
                        and r.code != "high-path:**"
                        and path in r.detail
                        for r in result.reasons
                    ),
                    _codes(result),
                )

    def test_script_types_in_lane_plugins_and_the_top_level_are_held(self):
        # Owner decision Q646: .ps1, .cjs and mode 100755 files.
        held = (
            _file("plugins/testing/reference/run.ps1"),
            _file("plugins/knowledge/vendor/x/digest.cjs"),
            _file("plugins/autonomy/reference/tool", mode="100755"),
            _file("install.ps1"),
            _file("tool.cjs"),
            _file("run-me", mode="100755"),
        )
        for changed in held:
            with self.subTest(changed.path):
                result = score(_lane_input((changed,)))
                self.assertEqual(result.score, Risk.HIGH, _codes(result))
                self.assertIn("high-script", _codes(result))

    def test_script_types_in_other_plugins_stay_low(self):
        # Q640c: outside the lane plugins they are an accepted risk.
        for changed in (
            _file("plugins/foo/reference/run.ps1"),
            _file("plugins/foo/reference/x.cjs"),
            _file("plugins/foo/reference/tool", mode="100755"),
        ):
            with self.subTest(changed.path):
                result = score(_lane_input((changed,)))
                self.assertEqual(result.score, Risk.LOW, _codes(result))

    def test_an_unreadable_script_scope_list_fails_closed(self):
        result = score(_input(files=(_file("docs/a.md"),), floor_script_scopes=("**",)))
        self.assertIn("high-path:**", _codes(result))

    def test_a_path_outside_the_floor_stays_low(self):
        files = (_file("plugins/foo/skills/bar/reference/notes.md"),)
        result = score(_lane_input(files))
        self.assertEqual(result.score, Risk.LOW, _codes(result))

    def test_a_skill_diff_adding_allowed_tools_is_held(self):
        patch = (
            "@@ -1,4 +1,5 @@\n"
            " ---\n"
            " name: bar\n"
            " description: Does bar.\n"
            "+allowed-tools: Bash\n"
            " ---\n"
        )
        files = (_file("plugins/foo/skills/bar/SKILL.md", patch=patch),)
        result = score(_lane_input(files))
        self.assertEqual(result.score, Risk.HIGH, _codes(result))
        self.assertIn("high-capability", _codes(result))

    def test_a_prose_only_skill_diff_is_not_held(self):
        patch = (
            "@@ -12,3 +12,4 @@ description: Does bar.\n"
            " ## Steps\n"
            " \n"
            " Run the check.\n"
            "+Then read the report it prints.\n"
        )
        files = (_file("plugins/foo/skills/bar/SKILL.md", patch=patch),)
        result = score(_lane_input(files))
        self.assertEqual(result.score, Risk.LOW, _codes(result))


class CapabilityTriggerTests(unittest.TestCase):
    """Owner decision Q641: a SKILL.md, agents/*.md or commands/*.md diff that
    adds or changes frontmatter hooks, allowed-tools, tools, permissionMode or
    mcpServers, or adds a `!` backtick command line, scores HIGH with the
    floor. Each patch is a hand-written unified diff."""

    HELD = [
        (
            "agent permissionMode added",
            "plugins/foo/agents/runner.md",
            "@@ -1,3 +1,4 @@\n ---\n name: runner\n+permissionMode: acceptEdits\n ---\n",
        ),
        (
            "command adds a shell line",
            "plugins/foo/commands/go.md",
            "@@ -8,2 +8,3 @@\n Status:\n \n+Current branch: !`git branch --show-current`\n",
        ),
        (
            "an allowed-tools list item changes mid-list",
            "plugins/foo/skills/bar/SKILL.md",
            "@@ -4,4 +4,5 @@ description: x\n allowed-tools:\n"
            '   - "Bash(git status*)"\n+  - "Bash(git push*)"\n ---\n',
        ),
        (
            "a list item with no key in the hunk",
            "plugins/foo/skills/bar/SKILL.md",
            '@@ -9,3 +9,4 @@\n   - "Bash(a*)"\n   - "Bash(b*)"\n   - "Bash(c*)"\n'
            '+  - "Bash(d*)"\n',
        ),
        (
            "hooks removed",
            "plugins/foo/skills/bar/SKILL.md",
            "@@ -1,5 +1,3 @@\n ---\n name: bar\n-hooks:\n-  Stop: x\n ---\n",
        ),
        (
            "mcpServers changed",
            "plugins/foo/agents/runner.md",
            "@@ -2,3 +2,3 @@\n name: runner\n-mcpServers: [a]\n+mcpServers: [a, b]\n ---\n",
        ),
        (
            "agent tools widened",
            "plugins/foo/agents/runner.md",
            "@@ -1,4 +1,4 @@\n ---\n name: runner\n-tools: Read\n+tools: Read, Bash\n ---\n",
        ),
        (
            "agent tools line deleted, which grants every tool",
            "plugins/foo/agents/runner.md",
            "@@ -1,4 +1,3 @@\n ---\n name: runner\n-tools: Read\n ---\n",
        ),
        (
            "double-quoted allowed-tools key",
            "plugins/foo/skills/bar/SKILL.md",
            '@@ -1,3 +1,4 @@\n ---\n name: bar\n+"allowed-tools": Bash\n ---\n',
        ),
        (
            "single-quoted hooks key",
            "plugins/foo/skills/bar/SKILL.md",
            "@@ -1,3 +1,4 @@\n ---\n name: bar\n+'hooks': {}\n ---\n",
        ),
        (
            "closing delimiter moved below body lines",
            "plugins/foo/skills/bar/SKILL.md",
            "@@ -1,6 +1,6 @@\n ---\n name: bar\n----\n # Bar\n allowed-tools: Bash\n+---\n",
        ),
        (
            "zero-indent list item added under allowed-tools",
            "plugins/foo/skills/bar/SKILL.md",
            "@@ -1,5 +1,6 @@\n ---\n name: x\n allowed-tools:\n - Read\n+- Bash\n ---\n",
        ),
        (
            "zero-indent list item with no key in the hunk",
            "plugins/foo/skills/bar/SKILL.md",
            '@@ -6,2 +6,3 @@\n - Read\n+- "Bash(*)"\n ---\n',
        ),
        (
            "a removed sibling key moves its items under allowed-tools",
            "plugins/foo/skills/bar/SKILL.md",
            '@@ -3,6 +3,5 @@\n allowed-tools:\n   - Read\n-other:\n   - "Bash(*)"\n ---\n',
        ),
        (
            "agent disallowedTools entry dropped",
            "plugins/foo/agents/runner.md",
            "@@ -1,4 +1,3 @@\n ---\n name: runner\n-disallowedTools: Bash\n ---\n",
        ),
        (
            "frontmatter rewritten as a flow mapping",
            "plugins/foo/skills/bar/SKILL.md",
            "@@ -1,4 +1,3 @@\n ---\n-name: x\n-description: y\n"
            "+{name: x, description: y, allowed-tools: Bash(*)}\n ---\n",
        ),
        (
            "a quoted key with an escape",
            "plugins/foo/skills/bar/SKILL.md",
            '@@ -1,3 +1,4 @@\n ---\n name: x\n+"allowed\\x2Dtools": Bash(*)\n ---\n',
        ),
        (
            "a tagged key",
            "plugins/foo/skills/bar/SKILL.md",
            "@@ -1,3 +1,4 @@\n ---\n name: x\n+!!str allowed-tools: Bash(*)\n ---\n",
        ),
        (
            "an explicit key",
            "plugins/foo/skills/bar/SKILL.md",
            "@@ -1,3 +1,5 @@\n ---\n name: x\n+? allowed-tools\n+: Bash(*)\n ---\n",
        ),
        (
            "a merge key",
            "plugins/foo/skills/bar/SKILL.md",
            "@@ -1,3 +1,5 @@\n ---\n name: x\n+x-b: &b {allowed-tools: Bash(*)}\n"
            "+<<: *b\n ---\n",
        ),
        (
            "an anchor the base already aliases under allowed-tools",
            "plugins/foo/skills/bar/SKILL.md",
            "@@ -1,4 +1,4 @@\n ---\n-x-t: &t Read\n+x-t: &t Bash(*)\n allowed-tools: *t\n ---\n",
        ),
        (
            "disable-model-invocation removed",
            "plugins/foo/skills/bar/SKILL.md",
            "@@ -1,4 +1,3 @@\n ---\n name: x\n-disable-model-invocation: true\n ---\n",
        ),
        (
            "context fork added",
            "plugins/foo/skills/bar/SKILL.md",
            "@@ -1,3 +1,4 @@\n ---\n name: x\n+context: fork\n ---\n",
        ),
        (
            "shell changed",
            "plugins/foo/skills/bar/SKILL.md",
            "@@ -1,4 +1,4 @@\n ---\n name: x\n-shell: bash\n+shell: powershell\n ---\n",
        ),
    ]

    def test_plugin_monitors_and_workflows_are_on_the_floor(self):
        for path in (
            "plugins/foo/monitors/monitors.json",
            "plugins/foo/workflows/sweep.js",
        ):
            with self.subTest(path):
                result = score(_input(files=(_file(path),)))
                self.assertEqual(result.score, Risk.HIGH, _codes(result))

    def test_a_numbered_step_added_to_the_body_mid_file_is_not_held(self):
        patch = (
            "@@ -20,3 +20,4 @@\n Run the check.\n \n 1. Read it.\n+2. (Then) fix it.\n"
        )
        files = (_file("plugins/foo/skills/bar/SKILL.md", patch=patch),)
        self.assertEqual(score(_input(files=files)).score, Risk.LOW)

    RENAMED = [
        ("agents", "plugins/foo/agents/runner.md"),
        ("commands", "plugins/foo/commands/go.md"),
        ("skills", "plugins/foo/skills/bar/SKILL.md"),
    ]

    def test_a_rename_or_copy_into_a_capability_path_is_held(self):
        context = "@@ -1,3 +1,3 @@\n ---\n allowed-tools: Bash\n ---\n"
        for status in ("renamed", "copied"):
            for name, path in self.RENAMED:
                with self.subTest(status=status, into=name):
                    changed = _file(
                        path,
                        status=status,
                        previous_path="plugins/foo/reference/notes.md",
                        additions=0,
                        deletions=0,
                        patch=context if status == "copied" else "",
                    )
                    result = score(_input(files=(changed,)))
                    self.assertEqual(result.score, Risk.HIGH, _codes(result))
                    self.assertIn("high-capability", _codes(result))

    def test_capability_changes_are_held(self):
        for name, path, patch in self.HELD:
            with self.subTest(name):
                result = score(_input(files=(_file(path, patch=patch),)))
                self.assertEqual(result.score, Risk.HIGH, _codes(result))
                self.assertIn("high-capability", _codes(result))

    def test_a_description_edit_is_not_held(self):
        patch = (
            "@@ -1,4 +1,4 @@\n ---\n name: bar\n-description: Old.\n"
            "+description: New.\n ---\n"
        )
        files = (_file("plugins/foo/skills/bar/SKILL.md", patch=patch),)
        self.assertEqual(score(_input(files=files)).score, Risk.LOW)

    def test_a_body_change_below_the_frontmatter_is_not_held(self):
        patch = (
            "@@ -1,6 +1,7 @@\n ---\n name: bar\n allowed-tools: Read\n ---\n"
            " \n # Bar\n+Read the file first.\n"
        )
        files = (_file("plugins/foo/skills/bar/SKILL.md", patch=patch),)
        self.assertEqual(score(_input(files=files)).score, Risk.LOW)

    def test_a_skill_with_no_patch_text_is_held(self):
        files = (_file("plugins/foo/skills/bar/SKILL.md", has_patch=False),)
        self.assertIn("high-capability", _codes(score(_input(files=files))))

    def test_a_non_capability_markdown_file_is_not_read(self):
        patch = "@@ -1,2 +1,3 @@\n # Notes\n+allowed-tools: Bash\n"
        files = (_file("plugins/foo/skills/bar/reference/notes.md", patch=patch),)
        self.assertEqual(score(_input(files=files)).score, Risk.LOW)

    def test_the_floor_off_reads_no_capability(self):
        patch = "@@ -1,3 +1,4 @@\n ---\n name: bar\n+allowed-tools: Bash\n ---\n"
        files = (_file("plugins/foo/skills/bar/SKILL.md", patch=patch),)
        result = score(_input(files=files, high_floor=False))
        self.assertEqual(result.score, Risk.LOW, _codes(result))


if __name__ == "__main__":
    unittest.main()
