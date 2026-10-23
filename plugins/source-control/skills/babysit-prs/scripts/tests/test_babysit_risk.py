"""Table tests for the unattended-merge diff risk scorer.

`babysit_risk.score` is a pure function, so every case builds a `RiskInput` and
reads the `RiskResult`; no network seam is involved. Expected reason codes and
severities come from the plan's scorer contract (reason-code list, HIGH floor,
200-line and 8-file limits, C2 re-check rules), never from running the scorer.
"""

from __future__ import annotations

import dataclasses
import difflib
import functools
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
    holds,
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
    contents=("", ""),
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
        contents=contents,
    )


def _edit(path, before, after, **kw):
    """A changed file carrying its base and head text and the unified patch
    between them, as git and the files API give it."""
    diff = difflib.unified_diff(before.split("\n"), after.split("\n"), n=3, lineterm="")
    patch = "\n".join(line for line in diff if not line.startswith(("--- ", "+++ ")))
    return _file(path, patch=patch, contents=(before, after), **kw)


FRONT = "---\nname: x\ndescription: y\n---\n\n# X\n\nBody.\n"
SKILL = "plugins/foo/skills/bar/SKILL.md"


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
            (".gitmodules", "high-path:**/.gitmodules"),
            (".github/CODEOWNERS", "high-path:**/CODEOWNERS"),
            (
                ".github/standards/trusted-actors/trusted-actors.json",
                "high-path:.github/standards/trusted-actors/**",
            ),
            (
                ".github/actions/check-trusted-trigger/action.yml",
                "high-path:.github/actions/check-trusted-trigger/**",
            ),
            (
                ".github/actions/resolve-config/resolve.mjs",
                "high-path:.github/actions/resolve-config/**",
            ),
        ]
        for path, code in cases:
            with self.subTest(path):
                result = score(_input(files=(_file(path),)))
                self.assertEqual(result.score, Risk.HIGH)
                self.assertIn(code, _codes(result))

    def test_paths_off_the_floor_take_no_path_code(self):
        # Owner direction 2026-10-23: only a takeover path waits for the owner.
        for path in (
            ".claude/settings.json",
            "plugins/foo/settings.local.json",
            "package.json",
            "plugins/foo/package-lock.json",
            "plugins/foo/requirements.txt",
            ".github/workflows/release-publish-plugins.yml",
            ".github/workflows/pr-merge.yml",
            ".github/workflows/pr-review-security-hosted.yml",
            ".github/workflows/work-resolve-issue.yml",
        ):
            with self.subTest(path):
                codes = _codes(score(_input(files=(_file(path),))))
                self.assertFalse([c for c in codes if c.startswith("high-path:")])

    def test_skill_prose_edit_stays_low(self):
        after = FRONT.replace("Body.", "Body, reworded.")
        result = score(_input(files=(_edit(SKILL, FRONT, after),)))
        self.assertEqual(result.score, Risk.LOW, result.reasons)

    def test_case_folded_paths_are_high(self):
        cases = [
            (
                ".GitHub/Standards/Trusted-Actors/README.MD",
                "high-path:.github/standards/trusted-actors/**",
            ),
            ("plugins/foo/Codeowners", "high-path:**/CODEOWNERS"),
            (".GITMODULES", "high-path:**/.gitmodules"),
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
        result = score(_input(files=(_file(".gitmodules"),), high_paths=()))
        self.assertEqual(result.score, Risk.HIGH)

    def test_near_miss_paths_are_not_high(self):
        for path in (
            "docs/conventions-old/x.md",
            "plugins/reviewer/x.md",
            "plugins/foo/REVIEW.md",
            "plugins/foo/agents.md.bak",
        ):
            with self.subTest(path):
                self.assertEqual(score(_input(files=(_file(path),))).score, Risk.LOW)


class RenameTests(unittest.TestCase):
    def test_rename_out_of_a_high_path_is_high(self):
        files = (
            _file(
                "plugins/foo/x.json",
                status="renamed",
                previous_path="plugins/foo/CODEOWNERS",
            ),
        )
        result = score(_input(files=files))
        self.assertEqual(result.score, Risk.HIGH)
        self.assertEqual(
            _codes(result), ("high-path:**/CODEOWNERS", "class-contradicted")
        )

    def test_rename_into_a_workflow_takes_the_cost_hold(self):
        files = (
            _file(
                ".github/workflows/x.yml",
                status="renamed",
                previous_path="plugins/foo/x.yml",
            ),
        )
        result = score(_input(files=files))
        self.assertEqual(result.score, Risk.HIGH)
        # A file renamed into a workflow also takes the cost hold.
        self.assertEqual(
            _codes(result),
            ("cost-review-required", "class-contradicted"),
        )

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
                files=(_file(".gitmodules", has_patch=False),),
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
            _file("CODEOWNERS"),
            _file(".gitmodules", has_patch=False),
            _file("plugins/foo/c.md", additions=500),
        )
        result = score(
            _input(work_class="C3", files=files, files_complete=False, lanes=lanes)
        )
        self.assertEqual(
            _codes(result),
            (
                "high-path:**/.gitmodules",
                "high-path:**/CODEOWNERS",
                "security-finding",
                "blast-radius-missing",
                "class-above-rung",
                "files-incomplete",
                "findings:claude-review",
                "lines-over",
                "no-patch:.gitmodules",
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

    def test_a_control_character_in_a_path_is_unsafe(self):
        result = score(_input(files=(_file("plugins/a\nb"),)))
        self.assertIn("high-path:**", _codes(result))

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
        result = score(_input(files=(_file("./.gitmodules"),)))
        self.assertIn("high-path:**/.gitmodules", _codes(result))

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
            (
                ".github/actions/check-trusted-trigger",
                "high-path:.github/actions/check-trusted-trigger/**",
            ),
            (
                ".github/standards/trusted-actors",
                "high-path:.github/standards/trusted-actors/**",
            ),
            (
                ".github/actions/resolve-config",
                "high-path:.github/actions/resolve-config/**",
            ),
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
        files = (_file(".gitmodules"),)
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


@functools.cache
def _lane_config():
    """This repository's live pr-merge config, read once: the file does not
    change during a run."""
    import babysit_merge_policy

    def file_at(path, _sha):
        found = REPO_ROOT / path
        return found.read_text(encoding="utf-8") if found.is_file() else None

    return babysit_merge_policy.read_config_at(
        "melodic-software/claude-code-plugins", "0" * 40, file_at
    )


def _lane_input(files):
    """The pr-merge lane's input under this repository's own
    docs/conventions/pr-pipeline.yaml, wired as babysit_merge.score_unattended
    wires it."""
    config = _lane_config()
    return _input(
        files=files,
        max_changed_lines=config.max_changed_lines,
        high_paths=config.denied_paths,
        high_floor=config.high_path_floor,
        c2_contradictions=config.c2_contradictions,
        max_changed_files=config.max_changed_files,
        lines_optional=True,
    )


class LanePathFloorTests(unittest.TestCase):
    """The live pr-merge config holds only the takeover set."""

    def test_the_live_config_has_the_floor_on(self):
        self.assertIs(_lane_config().high_path_floor, True)

    def test_the_keep_set_holds(self):
        for path in (
            ".gitmodules",
            ".github/CODEOWNERS",
            ".github/standards/trusted-actors/trusted-actors.json",
            ".github/actions/check-trusted-trigger/action.yml",
            ".github/actions/resolve-config/lane-rules.json",
        ):
            with self.subTest(path):
                result = score(_lane_input((_file(path),)))
                self.assertEqual(result.score, Risk.HIGH, result.reasons)

    def test_resolve_config_waits_for_the_owner(self):
        # Owner decision Q51: the token broker runs this code from main.
        result = score(_lane_input((_file(".github/actions/resolve-config/resolve.mjs"),)))
        self.assertEqual(result.score, Risk.HIGH, result.reasons)
        self.assertIn("high-path:.github/actions/resolve-config/**", _codes(result))

    def test_instructions_hooks_and_scripts_merge(self):
        # Owner direction 2026-10-22: the review lanes are the gate for these.
        for path in (
            "AGENTS.md",
            "CLAUDE.md",
            "prompts/x.md",
            ".claude/rules/x.md",
            "plugins/foo/hooks/hooks.json",
            "plugins/foo/hooks/guard.sh",
            "plugins/foo/bin/tool",
            "plugins/foo/lib/x.sh",
            "plugins/foo/scripts/run.py",
            "plugins/foo/skills/bar/scripts/run.ps1",
            "plugins/foo/.mcp.json",
            "plugins/foo/.lsp.json",
            "plugins/foo/monitors/monitors.json",
            "docs/conventions/x.md",
            "REVIEW.md",
            "plugins/review/skills/x/SKILL.md",
            "plugins/source-control/skills/babysit-prs/scripts/babysit_risk.py",
            "plugins/source-control/skills/babysit-loop/SKILL.md",
            "plugins/source-control/lib/x.awk",
            "plugins/work-items/x.md",
            "plugins/autonomy/reference/guardrails/x.md",
            "scripts/x.sh",
            "lib/x.sh",
            ".gitleaks.toml",
            ".work-item-tracker.json",
            ".node-version",
            ".python-version",
            ".gitattributes",
            ".github/scripts/pr-merge/x.mjs",
            "plugins/foo/evals/case/case.yaml",
            "plugins/foo/evals/case/scaffold.sh",
            ".claude/settings.json",
            "plugins/foo/.claude/settings.local.json",
            "package.json",
            "plugins/foo/package-lock.json",
            ".github/requirements-ci.txt",
            ".github/workflows/release-publish-plugins.yml",
            ".github/workflows/pr-merge.yml",
            ".github/workflows/pr-review-security-hosted.yml",
        ):
            with self.subTest(path):
                result = score(_lane_input((_file(path),)))
                self.assertEqual(result.score, Risk.LOW, result.reasons)

    def test_a_capability_change_merges(self):
        after = FRONT.replace("y\n", "y\nallowed-tools: Bash\n", 1)
        result = score(_lane_input((_edit(SKILL, FRONT, after),)))
        self.assertEqual(result.score, Risk.LOW, result.reasons)

    def test_a_pipeline_caps_edit_still_holds_as_cost(self):
        patch = "@@ -1,1 +1,1 @@\n-  max-in-flight: 5\n+  max-in-flight: 50"
        files = (_file("docs/conventions/pr-pipeline.yaml", patch=patch),)
        self.assertEqual(_codes(score(_lane_input(files))), ("cost-review-required",))


MANIFEST = "plugins/foo/.claude-plugin/plugin.json"
MARKETPLACE = ".claude-plugin/marketplace.json"
PLUGIN_BASE = (
    '{"name": "foo", "version": "1.0.0", "description": "Foo.",'
    ' "userConfig": {"guard_enabled": {"type": "boolean", "default": true}}}'
)
MARKET_BASE = (
    '{"name": "m", "plugins": [{"name": "foo", "source": "./plugins/foo",'
    ' "category": "dev"}]}'
)


def _manifest_change(path, before, after, **kw):
    return _file(path, contents=(before, after), **kw)


class ManifestTests(unittest.TestCase):
    """A manifest change holds as manifest-review-required only when it
    installs or runs something new: an executable plugin.json key, or a
    marketplace plugin added, removed, renamed or re-sourced."""

    REVIEW = "manifest-review-required"

    def _codes(self, path, before, after, **kw):
        return _codes(
            score(_input(files=(_manifest_change(path, before, after, **kw),)))
        )

    def test_non_executable_changes_clear(self):
        for after in (
            PLUGIN_BASE.replace("1.0.0", "1.1.0"),
            PLUGIN_BASE.replace("Foo.", "Foo, reworded."),
            PLUGIN_BASE.replace('"default": true', '"default": false'),
            PLUGIN_BASE.replace(
                '"name": "foo",', '"name": "foo", "dependencies": ["bar"],'
            ),
            PLUGIN_BASE.replace('"version": "1.0.0", ', ""),
        ):
            with self.subTest(after=after):
                self.assertEqual(self._codes(MANIFEST, PLUGIN_BASE, after), ())
        for after in (
            MARKET_BASE.replace('"dev"', '"tools"'),
            MARKET_BASE.replace(
                '"name": "m",', '"name": "m", "metadata": {"pluginRoot": "x"},'
            ),
        ):
            with self.subTest(after=after):
                self.assertEqual(self._codes(MARKETPLACE, MARKET_BASE, after), ())

    def test_an_executable_key_holds(self):
        for after in (
            PLUGIN_BASE.replace(
                '"name": "foo",', '"name": "foo", "hooks": "./h.json",'
            ),
            PLUGIN_BASE.replace('"name": "foo",', '"name": "foo", "mcpServers": {},'),
            PLUGIN_BASE.replace(
                '"name": "foo",', '"name": "foo", "experimental": {"monitors": []},'
            ),
            PLUGIN_BASE.replace('"name": "foo",', '"name": "foo", "lspServers": {},'),
            PLUGIN_BASE.replace('"name": "foo",', '"name": "foo", "monitors": [],'),
        ):
            with self.subTest(after=after):
                self.assertEqual(
                    self._codes(MANIFEST, PLUGIN_BASE, after), (self.REVIEW,)
                )

    def test_a_marketplace_add_remove_rename_or_source_holds(self):
        for after in (
            MARKET_BASE.replace("./plugins/foo", "https://example.com/foo.git"),
            MARKET_BASE.replace("]}", ', {"name": "bar", "source": "./plugins/bar"}]}'),
            MARKET_BASE.replace('"name": "foo"', '"name": "fob"'),
            MARKET_BASE.replace('"name": "m"', '"name": "n"'),
            '{"name": "m", "plugins": []}',
        ):
            with self.subTest(after=after):
                self.assertEqual(
                    self._codes(MARKETPLACE, MARKET_BASE, after), (self.REVIEW,)
                )

    def test_a_denied_manifest_path_keeps_the_hold(self):
        bump = _manifest_change(
            MANIFEST, PLUGIN_BASE, PLUGIN_BASE.replace("1.0.0", "1.1.0")
        )
        codes = _codes(
            score(_input(files=(bump,), high_paths=("**/.claude-plugin/**",)))
        )
        self.assertIn("high-path:**/.claude-plugin/**", codes)

    def test_unreadable_malformed_or_duplicate_sides_hold(self):
        duplicate = PLUGIN_BASE.replace('"name": "foo",', '"name": "foo", "name": "x",')
        for before, after in (
            (PLUGIN_BASE, "{"),
            ("not json", PLUGIN_BASE),
            (PLUGIN_BASE, duplicate),
            (PLUGIN_BASE, None),
            (PLUGIN_BASE, "[]"),
        ):
            with self.subTest(before=before, after=after):
                self.assertEqual(self._codes(MANIFEST, before, after), (self.REVIEW,))
        errored = dataclasses.replace(
            _manifest_change(MANIFEST, PLUGIN_BASE, PLUGIN_BASE),
            contents=None,
            contents_error="status 502",
        )
        self.assertEqual(_codes(score(_input(files=(errored,)))), (self.REVIEW,))

    def test_an_added_plugin_manifest_holds_only_with_an_executable_key(self):
        added = dict(status="added", previous_mode=None)
        self.assertEqual(self._codes(MANIFEST, None, PLUGIN_BASE, **added), ())
        hooked = PLUGIN_BASE.replace('"name": "foo",', '"name": "foo", "hooks": {},')
        self.assertEqual(self._codes(MANIFEST, None, hooked, **added), (self.REVIEW,))

    def test_a_removed_or_renamed_manifest_holds(self):
        removed = dict(status="removed", additions=0, previous_mode=None)
        self.assertIn(self.REVIEW, self._codes(MANIFEST, PLUGIN_BASE, None, **removed))
        renamed = dict(status="renamed", previous_path="plugins/foo/plugin.json")
        self.assertIn(
            self.REVIEW, self._codes(MANIFEST, PLUGIN_BASE, PLUGIN_BASE, **renamed)
        )


class HoldsTests(unittest.TestCase):
    """#9270: a MED score merges unattended when every reason is a class or
    size reason; every other reason holds."""

    def _holds(self, **changes):
        return holds(score(_input(**changes)))

    def test_low_does_not_hold(self):
        self.assertFalse(self._holds())

    def test_a_path_or_size_med_merges(self):
        for changes in (
            dict(files=(_file("plugins/foo/logo.png", has_patch=False),)),
            dict(files=(_file("plugins/foo/a.md", additions=500),)),
            dict(work_class="C3", rung=Rung.C3, blast_radius=None),
            dict(files=(_file("plugins/foo/a.md"), _file("plugins/bar/b.md"))),
        ):
            with self.subTest(changes=changes):
                result = score(_input(**changes))
                self.assertEqual(result.score, Risk.MED)
                self.assertFalse(holds(result), result.reasons)

    def test_an_open_code_review_finding_is_reported_and_does_not_hold(self):
        # Q25: a review flag other than cost, a trusted-actor widening or a
        # CRITICAL security finding is reported and merges.
        lanes = (
            _lane("claude-review", open_findings=1),
            _lane("claude-security-review"),
        )
        files = (_file("plugins/foo/logo.png", has_patch=False),)
        result = score(_input(lanes=lanes, files=files))
        self.assertIn("findings:claude-review", _codes(result))
        self.assertFalse(holds(result), result.reasons)

    def test_an_unbound_or_missing_lane_holds(self):
        for lanes in (
            (
                _lane("claude-review", bound=False, unbound_reason="no-run"),
                _lane("claude-security-review"),
            ),
            (_lane("claude-review"),),
        ):
            with self.subTest(lanes=lanes):
                self.assertTrue(self._holds(lanes=lanes))

    def test_the_cost_hold_and_high_hold(self):
        patch = "@@ -1,1 +1,1 @@\n-  max-in-flight: 5\n+  max-in-flight: 50"
        self.assertTrue(
            self._holds(
                files=(_file("docs/conventions/pr-pipeline.yaml", patch=patch),)
            )
        )
        self.assertTrue(self._holds(files=(_file(".gitmodules"),)))

    def test_the_rung_and_an_unread_listing_hold(self):
        for changes in (
            dict(work_class=None),
            dict(rung=Rung.OFF),
            dict(work_class="C3", blast_radius="low"),
            dict(files_complete=False),
        ):
            with self.subTest(changes=changes):
                self.assertTrue(self._holds(**changes))


class SecurityBlockingTests(unittest.TestCase):
    """The security lane holds only on its CRITICAL findings
    (`blocking_findings`); the rest are reported and do not hold."""

    def _security(self, open_findings, blocking):
        lane = LaneEvidence(
            "claude-security-review",
            True,
            None,
            open_findings,
            blocking_findings=blocking,
        )
        return score(_input(lanes=(_lane("claude-review"), lane)))

    def test_a_non_critical_security_finding_is_reported_and_does_not_hold(self):
        result = self._security(3, 0)
        self.assertEqual(result.score, Risk.MED)
        self.assertEqual(_codes(result), ("findings:claude-security-review",))
        self.assertIn("3 open", result.reasons[0].detail)
        self.assertFalse(holds(result))

    def test_a_critical_security_finding_is_high(self):
        result = self._security(3, 1)
        self.assertEqual(result.score, Risk.HIGH)
        self.assertEqual(
            _codes(result), ("security-finding", "findings:claude-security-review")
        )
        self.assertIn("2 open", result.reasons[1].detail)
        self.assertTrue(holds(result))

    def test_no_severity_count_holds_on_every_finding(self):
        self.assertEqual(_codes(self._security(2, None)), ("security-finding",))


B = "plugins/source-control/skills/babysit-prs/scripts/"
ACTORS = ".github/standards/trusted-actors/trusted-actors.json"
TRUSTED = "trust-gate:trusted-actors"
_KYLE = '{ "id": 1, "login": "kyle", "kind": "human" }'
_BOT = '{ "id": 2, "login": "lanes[bot]", "kind": "bot" }'


def _actors(*entries, version=1):
    return '{\n  "version": %d,\n  "actors": [\n    %s\n  ]\n}\n' % (
        version,
        ",\n    ".join(entries),
    )


BASE_ACTORS = _actors(_KYLE, _BOT)


class TrustGateTests(unittest.TestCase):
    """The owner's direction: the one trust-gate hold is a change that adds
    or widens entries in the trusted-actor list; a pure removal is not held,
    whatever the floor switch and the trusted author's own paths say."""

    def _score(self, after, before=BASE_ACTORS, path=ACTORS, **changes):
        changed = _edit(path, before, after)
        return score(_input(files=(changed,), high_floor=False, **changes))

    def test_a_widening_holds_with_the_floor_off_and_exempt(self):
        widen = {
            "an entry added": _actors(
                _KYLE, _BOT, '{ "id": 3, "login": "new", "kind": "bot" }'
            ),
            "an entry's kind changed": _actors(
                _KYLE, _BOT.replace('"bot"', '"human"')
            ),
            "an entry's id changed": _actors(_KYLE, _BOT.replace("2", "4")),
            "a removal beside an addition": _actors(
                _KYLE, '{ "id": 5, "login": "x", "kind": "bot" }'
            ),
            "another key changed": _actors(_KYLE, _BOT, version=2),
            "unparsable head": "{",
            "a repeated key": BASE_ACTORS.replace('"version": 1', '"version": 1, "version": 1'),
            "actors not a list": '{"version": 1, "actors": {}}',
        }  # fmt: skip
        for name, after in widen.items():
            for changes in (dict(), dict(floor_exempt=frozenset({ACTORS}))):
                with self.subTest(name, changes=changes):
                    result = self._score(after, **changes)
                    self.assertEqual(result.score, Risk.HIGH)
                    self.assertEqual(_codes(result), (TRUSTED,))
                    self.assertTrue(holds(result))

    def test_a_pure_removal_does_not_hold(self):
        for after in (_actors(_KYLE), _actors(_BOT), BASE_ACTORS.replace("  ", " ")):
            with self.subTest(after=after):
                result = self._score(after)
                self.assertEqual(result.score, Risk.LOW, result.reasons)

    def test_a_pure_removal_holds_on_the_floor(self):
        # The trusted-actor directory is on the floor: with the floor on, even
        # a removal waits for the owner.
        result = score(_input(files=(_edit(ACTORS, BASE_ACTORS, _actors(_KYLE)),)))
        self.assertEqual(result.score, Risk.HIGH)
        self.assertEqual(_codes(result), ("high-path:.github/standards/trusted-actors/**",))

    def test_an_unread_or_structural_change_holds(self):
        cases = (
            _file(ACTORS, contents=None),
            dataclasses.replace(_file(ACTORS), contents_error="boom"),
            _file(ACTORS, status="added", previous_mode="000000"),
            _file(ACTORS, status="removed"),
            _file("plugins/foo/x.json", status="renamed", previous_path=ACTORS),
            _file(ACTORS, status="renamed", previous_path="plugins/foo/x.json"),
        )
        for changed in cases:
            with self.subTest(changed=changed):
                result = score(
                    _input(files=(changed,), high_floor=False, c2_contradictions=False)
                )
                self.assertEqual(_codes(result), (TRUSTED,))

    def test_a_case_folded_path_holds(self):
        result = self._score(
            _actors(_KYLE, _BOT, '{ "id": 3 }'),
            path=".GitHub/Standards/Trusted-Actors/Trusted-Actors.JSON",
        )
        self.assertEqual(_codes(result), (TRUSTED,))

    def test_paths_the_owner_lifted_do_not_hold_with_the_floor_off(self):
        # The scorer, the merge gate, the pipeline config, workflows and the
        # security review merge normally.
        for path in (
            f"{B}babysit_risk.py",
            f"{B}babysit_merge.py",
            f"{B}babysit_review_evidence.py",
            ".github/workflows/pr-merge.yml",
            ".github/scripts/pr-merge/gate.mjs",
            ".github/workflows/pr-review-security-hosted.yml",
            ".github/standards/trusted-actors/README.md",
            "plugins/foo/trusted-actors/trusted-actors.json",
        ):
            with self.subTest(path):
                result = score(_input(files=(_file(path),), high_floor=False))
                self.assertEqual(result.score, Risk.LOW, result.reasons)


class ReviewFlagClassTests(unittest.TestCase):
    """Q25: a review flag holds only as a cost increase, a trusted-actor
    widening or a CRITICAL security finding (Q693); any other is reported."""

    def _lanes(self, review=0, security=0, critical=None):
        return (
            _lane("claude-review", open_findings=review),
            LaneEvidence(
                "claude-security-review", True, None, security,
                blocking_findings=critical,
            ),
        )  # fmt: skip

    def test_cost_flag_holds(self):
        patch = "@@ -1,1 +1,2 @@\n on: push\n+  cron: '0 * * * *'"
        result = score(_input(files=(_file(".github/workflows/x.yml", patch=patch),)))
        self.assertEqual(_codes(result), ("cost-review-required",))
        self.assertTrue(holds(result))

    def test_trust_gate_flag_holds(self):
        widened = _edit(ACTORS, BASE_ACTORS, _actors(_KYLE, _BOT, '{ "id": 3 }'))
        result = score(_input(files=(widened,), high_floor=False))
        self.assertEqual(_codes(result), (TRUSTED,))
        self.assertTrue(holds(result))

    def test_critical_security_flag_holds(self):
        result = score(_input(lanes=self._lanes(security=1, critical=1)))
        self.assertEqual(_codes(result), ("security-finding",))
        self.assertTrue(holds(result))

    def test_other_flags_are_reported_and_do_not_hold(self):
        result = score(_input(lanes=self._lanes(review=2, security=3, critical=0)))
        self.assertEqual(result.score, Risk.MED)
        self.assertEqual(
            {r.code: r.detail for r in result.reasons},
            {
                "findings:claude-review": "2 open, reported only",
                "findings:claude-security-review": "3 open below CRITICAL, reported only",
            },
        )
        self.assertFalse(holds(result))

    def test_a_reported_flag_beside_a_hold_is_still_listed(self):
        result = score(
            _input(
                files=(_file(".gitmodules"),),
                lanes=self._lanes(review=1),
            )
        )
        self.assertIn("findings:claude-review", _codes(result))
        self.assertTrue(holds(result))
