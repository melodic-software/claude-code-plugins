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
    Reason,
    Risk,
    RiskInput,
    Rung,
    _merge_by_code,
    normalize_path,
    score,
)


def _file(
    path,
    *,
    status="modified",
    previous_path=None,
    additions=10,
    deletions=5,
    has_patch=True,
    mode="100644",
    previous_mode=None,
):
    return ChangedFile(
        path=path,
        previous_path=previous_path,
        status=status,
        additions=additions,
        deletions=deletions,
        has_patch=has_patch,
        mode=mode,
        previous_mode=previous_mode,
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

    def test_configured_line_limit_is_honoured(self):
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

    def test_double_star_over_a_very_deep_path_is_linear(self):
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
    """Missing or unrecognised data is a miss: never LOW, and never a raise."""

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

    def test_merge_keeps_the_highest_severity_on_a_duplicate_detail(self):
        merged = _merge_by_code(
            [
                Reason("x", Risk.MED, "same"),
                Reason("x", Risk.HIGH, "same"),
            ]
        )
        self.assertEqual(merged, [Reason("x", Risk.HIGH, "same")])

    def test_merge_appends_a_distinct_detail(self):
        merged = _merge_by_code(
            [Reason("x", Risk.MED, "a"), Reason("x", Risk.MED, "b")]
        )
        self.assertEqual(merged, [Reason("x", Risk.MED, "a; b")])


class AddedFloorTests(unittest.TestCase):
    def test_added_floor_paths_are_high_under_their_own_code(self):
        for path, glob in (
            ("plugins/guardrails/hooks/x.sh", "plugins/guardrails/**"),
            ("plugins/work-items/skills/x.md", "plugins/work-items/**"),
            ("plugins/foo/hooks/hooks.json", "plugins/*/hooks/**"),
            ("prompts/x.md", "prompts/**"),
            ("package.json", "package.json"),
            ("package-lock.json", "package-lock.json"),
            ("plugins/foo/package-lock.json", "**/package-lock.json"),
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

    def test_nested_package_json_is_not_on_the_floor(self):
        result = score(_input(files=(_file("plugins/foo/package.json"),)))
        self.assertEqual(result.score, Risk.LOW)


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
        self.assertEqual(reason.detail, "not bound")

    def test_class_contradicted_names_the_files(self):
        files = (_file("plugins/foo/old.md", status="removed", additions=0),)
        reason = score(_input(files=files)).reasons[0]
        self.assertEqual(reason.code, "class-contradicted")
        self.assertIn("plugins/foo/old.md", reason.detail)

    def test_rung_is_named_in_the_detail(self):
        reasons = score(
            _input(work_class="C3", rung=Rung.C2, blast_radius="low")
        ).reasons
        self.assertEqual(reasons[0].detail, "C3 above rung C2")


if __name__ == "__main__":
    unittest.main()
