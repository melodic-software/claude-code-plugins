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
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import babysit_risk
from babysit_risk import (
    ChangedFile,
    LaneEvidence,
    Reason,
    Risk,
    RiskInput,
    holding,
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
        files=(_file("plugins/foo/skills/bar/SKILL.md"),),
        files_complete=True,
        max_changed_lines=200,
        high_paths=(),
        lanes=BOTH_LANES_CLEAN,
    )
    return dataclasses.replace(base, **changes)


def _codes(result):
    return tuple(reason.code for reason in result.reasons)


class AllPassTests(unittest.TestCase):
    def test_all_pass_input_scores_low_with_no_reasons(self):
        result = score(_input())
        self.assertEqual(result.score, Risk.LOW)
        self.assertEqual(result.reasons, ())

    def test_a_structural_shaped_diff_scores_low(self):
        # The former class-contradicted shapes: a removal, a rename, a schema
        # change and a two-plugin diff, each with nothing else wrong, now
        # score LOW with no reason (owner decision, option a).
        for name, files in (
            ("removed", (_file("plugins/foo/old.md", status="removed", additions=0),)),
            (
                "renamed",
                (
                    _file(
                        "plugins/foo/new.md",
                        status="renamed",
                        previous_path="plugins/foo/old.md",
                    ),
                ),
            ),
            (
                "copied",
                (
                    _file(
                        "plugins/foo/b.md",
                        status="copied",
                        previous_path="plugins/foo/a.md",
                    ),
                ),
            ),
            ("changed", (_file("plugins/foo/a.md", status="changed"),)),
            ("schema", (_file("plugins/foo/config.schema.json"),)),
            ("two plugins", (_file("plugins/foo/a.md"), _file("plugins/bar/b.md"))),
        ):
            with self.subTest(name):
                result = score(_input(files=files))
                self.assertEqual((result.score, result.reasons), (Risk.LOW, ()))


class SingleMedReasonTests(unittest.TestCase):
    """Each single miss flips an all-pass input to exactly one MED reason."""

    CASES = [
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

    def test_floor_paths_are_high_whatever_the_switch(self):
        # Owner decisions Q-FLOOR (B) and Q-ENFORCE (A): the narrow floor,
        # with the files that enforce it, holds with high-path-floor off too.
        # Owner decision Q26 option B: each glob's class; a person clears a
        # `trust` or `gate` path, a clean security review an `enforcement` one.
        self.assertEqual(
            babysit_risk.FLOOR_CLASSES,
            (
                (".github/actions/check-trusted-trigger/**", "trust"),
                ("**/CODEOWNERS", "trust"),
                ("**/.gitmodules", "trust"),
                (".github/actions/resolve-config/**", "gate"),
                (".github/actions/check-kill-switch/**", "trust"),
                (".github/actions/request-lane-token/**", "trust"),
                (".github/actions/log-api-budget/rate-guard.mjs", "gate"),
                (".github/scripts/pr-merge/merge-holds.mjs", "gate"),
                (".github/scripts/pr-merge/enable-auto-merge.mjs", "gate"),
                (".github/scripts/pr-merge/superseded.mjs", "gate"),
                (".github/scripts/pr-merge/clear-escalations.mjs", "gate"),
                (".github/scripts/pr-merge/carry-run-cache.mjs", "gate"),
                (".github/scripts/pr-merge/gate-check.mjs", "gate"),
                (".github/scripts/pr-merge/head-ref-map.mjs", "gate"),
                (".github/scripts/pr-merge/lane-records.mjs", "gate"),
                (".github/scripts/pr-merge/rate-stop.bash", "gate"),
                (".github/scripts/pr-merge/refire-refused.mjs", "gate"),
                (".github/scripts/pr-merge/rotation.mjs", "gate"),
                (".github/scripts/pr-merge/sweep-summary.mjs", "gate"),
                (".github/scripts/pr-merge/who.mjs", "gate"),
                (".github/scripts/pr-merge/post-unarmed-status.mjs", "gate"),
                ("plugins/source-control/skills/babysit-prs/scripts/babysit_risk.py", "enforcement"),
                ("plugins/source-control/skills/babysit-prs/scripts/babysit_check_inputs.py", "enforcement"),
                ("plugins/source-control/skills/babysit-prs/scripts/babysit_checks.py", "enforcement"),
                ("plugins/source-control/skills/babysit-prs/scripts/babysit_classify.py", "enforcement"),
                ("plugins/source-control/skills/babysit-prs/scripts/babysit_dependabot.py", "enforcement"),
                ("plugins/source-control/skills/babysit-prs/scripts/babysit_feedback.py", "enforcement"),
                ("plugins/source-control/skills/babysit-prs/scripts/babysit_gh.py", "enforcement"),
                ("plugins/source-control/skills/babysit-prs/scripts/babysit_merge.py", "gate"),
                ("plugins/source-control/skills/babysit-prs/scripts/babysit_merge_policy.py", "gate"),
                ("plugins/source-control/skills/babysit-prs/scripts/babysit_postmerge.py", "enforcement"),
                ("plugins/source-control/skills/babysit-prs/scripts/babysit_repo_config.py", "enforcement"),
                ("plugins/source-control/skills/babysit-prs/scripts/babysit_review_evidence.py", "enforcement"),
                ("plugins/source-control/skills/babysit-prs/scripts/babysit_review_trigger.py", "enforcement"),
                ("plugins/source-control/skills/babysit-prs/scripts/babysit_run_cache.py", "enforcement"),
                ("plugins/source-control/skills/babysit-prs/scripts/babysit_state.py", "enforcement"),
                ("plugins/source-control/skills/babysit-prs/scripts/babysit_util.py", "enforcement"),
                ("plugins/source-control/skills/babysit-prs/scripts/babysit_verify_evidence.py", "enforcement"),
                ("plugins/source-control/skills/babysit-prs/scripts/babysit_whole_review.py", "enforcement"),
                (".github/workflows/pr-require-checks.yml", "gate"),
                (".github/workflows/pr-merge.yml", "gate"),
                ("docs/conventions/pr-pipeline.yaml", "gate"),
                (".github/scripts/pr-unblock/address-feedback.mjs", "enforcement"),
                (".github/scripts/pr-unblock/gate-source.mjs", "enforcement"),
                (".github/scripts/pr-unblock/thread-scope.mjs", "enforcement"),
                (".github/scripts/work-resolve-issue/report-outcome.mjs", "enforcement"),
                (".github/scripts/work-resolve-issue/limits.mjs", "enforcement"),
            ),
        )  # fmt: skip
        self.assertEqual(
            babysit_risk.HIGH_FLOOR,
            tuple(g for g, c in babysit_risk.FLOOR_CLASSES if c in {"trust", "gate"}),
        )
        self.assertEqual(
            babysit_risk.REVIEW_FLOOR,
            tuple(g for g, c in babysit_risk.FLOOR_CLASSES if c == "enforcement"),
        )
        cases = [
            (".gitmodules", "**/.gitmodules"),
            ("vendor/.GitModules", "**/.gitmodules"),
            (".github/CODEOWNERS", "**/CODEOWNERS"),
            (".github/actions/check-trusted-trigger/action.yml", ".github/actions/check-trusted-trigger/**"),
            (".github/actions/resolve-config/resolve.mjs", ".github/actions/resolve-config/**"),
            (".github/actions/check-kill-switch/check-kill-switch.mjs", ".github/actions/check-kill-switch/**"),
            (".github/actions/request-lane-token/action.yml", ".github/actions/request-lane-token/**"),
            (".github/actions/log-api-budget/rate-guard.mjs", ".github/actions/log-api-budget/rate-guard.mjs"),
            (".github/scripts/pr-merge/merge-holds.mjs", ".github/scripts/pr-merge/merge-holds.mjs"),
            (".github/scripts/pr-merge/enable-auto-merge.mjs", ".github/scripts/pr-merge/enable-auto-merge.mjs"),
            (".github/scripts/pr-merge/superseded.mjs", ".github/scripts/pr-merge/superseded.mjs"),
            (".github/scripts/pr-merge/clear-escalations.mjs", ".github/scripts/pr-merge/clear-escalations.mjs"),
            ("plugins/source-control/skills/babysit-prs/scripts/babysit_risk.py", "plugins/source-control/skills/babysit-prs/scripts/babysit_risk.py"),
            ("plugins/source-control/skills/babysit-prs/scripts/babysit_verify_evidence.py", "plugins/source-control/skills/babysit-prs/scripts/babysit_verify_evidence.py"),
            ("plugins/source-control/skills/babysit-prs/scripts/babysit_merge.py", "plugins/source-control/skills/babysit-prs/scripts/babysit_merge.py"),
            (".github/workflows/pr-require-checks.yml", ".github/workflows/pr-require-checks.yml"),
            (".github/workflows/pr-merge.yml", ".github/workflows/pr-merge.yml"),
            ("docs/conventions/pr-pipeline.yaml", "docs/conventions/pr-pipeline.yaml"),
            ("Docs/Conventions/PR-Pipeline.yaml", "docs/conventions/pr-pipeline.yaml"),
            (".github/scripts/pr-unblock/address-feedback.mjs", ".github/scripts/pr-unblock/address-feedback.mjs"),
            (".github/scripts/pr-unblock/gate-source.mjs", ".github/scripts/pr-unblock/gate-source.mjs"),
            (".github/scripts/pr-unblock/thread-scope.mjs", ".github/scripts/pr-unblock/thread-scope.mjs"),
            (".github/scripts/work-resolve-issue/report-outcome.mjs", ".github/scripts/work-resolve-issue/report-outcome.mjs"),
            (".github/scripts/work-resolve-issue/limits.mjs", ".github/scripts/work-resolve-issue/limits.mjs"),
        ]  # fmt: skip
        unreviewed = (
            _lane("claude-review"),
            _lane("claude-security-review", bound=False),
        )
        for path, glob in cases:
            for on in (True, False):
                with self.subTest(path, high_floor=on):
                    result = score(
                        _input(files=(_file(path),), high_floor=on, lanes=unreviewed)
                    )
                    self.assertEqual(result.score, Risk.HIGH)
                    code = (
                        "review-path"
                        if glob in babysit_risk.REVIEW_FLOOR
                        else "high-path"
                    )
                    self.assertIn(f"{code}:{glob}", _codes(result))

    def test_trusted_paths_off_the_floor_hold_only_when_configured(self):
        # Owner direction 2026-10-24: a trusted-path match alone holds nothing.
        for path in (
            ".github/actions/log-api-budget/action.yml",
            ".github/actions/check-trusted-trigger-x/a.mjs",
            ".github/scripts/pr-unblock/other.mjs",
            "docs/CODEOWNERS.md",
        ):
            for on in (True, False):
                with self.subTest(path, high_floor=on):
                    result = score(_input(files=(_file(path),), high_floor=on))
                    self.assertEqual(result.score, Risk.LOW, _codes(result))
            with self.subTest(path, configured=True):
                result = score(_input(files=(_file(path),), high_paths=(path,)))
                self.assertEqual(_codes(result), (f"high-path:{path}",))

    def test_paths_off_the_floor_take_no_path_code(self):
        # Owner direction 2026-10-23: only a takeover path waits for the owner.
        for path in (
            ".claude/settings.json",
            "plugins/foo/settings.local.json",
            "package.json",
            "plugins/foo/package-lock.json",
            "plugins/foo/requirements.txt",
            ".github/workflows/release-publish-plugins.yml",
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
                configured = (code.removeprefix("high-path:"),)
                result = score(_input(files=(_file(path),), high_paths=configured))
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
        result = score(_input(files=files, high_paths=("**/CODEOWNERS",)))
        self.assertEqual(result.score, Risk.HIGH)
        self.assertEqual(_codes(result), ("high-path:**/CODEOWNERS",))

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
        self.assertEqual(_codes(result), ("cost-review-required",))


class OrderingTests(unittest.TestCase):
    def test_high_beats_every_med(self):
        result = score(
            _input(
                files=(_file(".gitmodules", has_patch=False),),
                files_complete=False,
                high_paths=("**/.gitmodules",),
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
            _input(
                files=files,
                files_complete=False,
                lanes=lanes,
                high_paths=("**/.gitmodules", "**/CODEOWNERS"),
            )
        )
        self.assertEqual(
            _codes(result),
            (
                "high-path:**/.gitmodules",
                "high-path:**/CODEOWNERS",
                "security-finding",
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


class _OverBudget(BaseException):
    """A BaseException, so an `except Exception` in the matcher cannot
    swallow it."""


def _glob_work(pattern, path, cap=None):
    """Lines of babysit_risk.py that glob_match(pattern, path) runs, counted
    under sys.settrace rather than timed, so runner load cannot fail it.
    Past `cap` the trace raises, so a blow-up fails at once."""
    count = 0

    def local(frame, event, arg):
        nonlocal count
        if event == "line":
            count += 1
            if cap is not None and count > cap:
                raise _OverBudget(f"glob_match ran past {cap} lines")
        return local

    def calls(frame, event, arg):
        return local if frame.f_code.co_filename == babysit_risk.__file__ else None

    previous = sys.gettrace()
    sys.settrace(calls)
    try:
        matched = babysit_risk.glob_match(pattern, path)
    finally:
        sys.settrace(previous)
    return matched, count


class GlobWorkTests(unittest.TestCase):
    """Spec (glob_match): the work is O(glob segments x path segments), and
    within a segment O(len(pattern) x len(name)) (_segment_match). Each test
    doubles the input and bounds the growth of the counted work, so constant
    factors and the interpreter's line events cancel out: doubling the path
    alone may at most double the work (2.5 allows slack, quadratic gives 4);
    doubling pattern and path may at most quadruple it (5 allows slack; a
    blow-up in the stars gives far more). `**/` runs collapse to one `**`
    and `*a` runs stay linear, so those two keep the 2.5 bound. The trace
    counts Python lines only: work moved into a C builtin is not counted."""

    def assertScales(self, build, small, ratio, floor=None):
        matched, base = _glob_work(*build(small))
        if floor is not None:
            # The counted work grows with the path: the matcher is still in
            # this module, not in C or elsewhere.
            self.assertGreaterEqual(base, floor(small))
        cap = int(ratio * base)
        doubled, count = _glob_work(*build(2 * small), cap=cap)
        self.assertLessEqual(count, cap)
        self.assertEqual(doubled, matched)
        return matched

    def test_star_heavy_globs_do_bounded_work(self):
        for label, build, small, ratio in (
            (
                "**/ run",
                lambda k: ("**/" * k + "z", "/".join(["a"] * 3 * k) + "/b.md"),
                9,
                2.5,
            ),
            (
                "**/a/ run",
                lambda k: ("**/a/" * k + "z", "/".join(["a"] * 3 * k) + "/b.md"),
                9,
                5,
            ),
            (
                "*a run",
                lambda k: (
                    "plugins/foo/" + "*a" * k + "z",
                    "plugins/foo/" + "a" * 3 * k + ".md",
                ),
                20,
                2.5,
            ),
        ):
            with self.subTest(label):
                self.assertFalse(self.assertScales(build, small, ratio))
                glob, path = build(small)
                result = score(_input(files=(_file(path),), high_paths=(glob,)))
                self.assertEqual(result.score, Risk.LOW)

    def test_star_runs_inside_a_segment_fail_closed(self):
        # Spec: '**' inside a segment is not a whole '**' segment: unreadable.
        # Such a glob is refused before it reaches glob_match.
        for stars in (10, 20):
            glob = "plugins/foo/" + "*" * stars + "z"
            path = "plugins/foo/" + "a" * 40 + ".md"
            with self.subTest(glob):
                result = score(_input(files=(_file(path),), high_paths=(glob,)))
                self.assertEqual(_codes(result), ("high-path:**",))

    def test_work_over_a_deep_path_grows_linearly(self):
        for glob in ("**/a/**/b", "*"):
            with self.subTest(glob):
                self.assertScales(
                    lambda n: (glob, "/".join(["a"] * n) + "/x.md"),
                    2_000,
                    2.5,
                    floor=lambda n: n,
                )
        path = "/".join(["a"] * 20_000) + "/x.md"
        result = score(_input(files=(_file(path),), high_paths=("**/a/**/b",)))
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
        # to files-incomplete, an unreadable limit to lines-over, an unreadable HIGH set or path to
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
        # or '000000' (absent) is HIGH.
        for status in ("modified", "changed", "renamed", "copied"):
            for previous_mode in (None, "777", "000000"):
                with self.subTest((status, previous_mode)):
                    result = score(
                        _input(
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

    def test_rename_or_copy_without_a_previous_path_is_high(self):
        for status in ("renamed", "copied"):
            with self.subTest(status):
                result = score(
                    _input(files=(_file("plugins/foo/x.md", status=status),))
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
        result = score(
            _input(files=(_file("./.gitmodules"),), high_paths=("**/.gitmodules",))
        )
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
                configured = (code.removeprefix("high-path:"),)
                result = score(_input(files=(_file(path),), high_paths=configured))
                self.assertEqual(result.score, Risk.HIGH)
                self.assertIn(code, _codes(result))

    def test_trailing_double_star_forms_match_the_bare_entry(self):
        # Spec: 'X/**' also matches X; 'X/**/' and 'X/**/**' mean the same glob.
        for glob in ("docs/**", "docs/**/", "docs/**/**"):
            with self.subTest(glob):
                result = score(_input(files=(_file("docs"),), high_paths=(glob,)))
                self.assertIn(f"high-path:{glob}", _codes(result))


class LaneSwitchTests(unittest.TestCase):
    """Owner decision Q624: in the pr-merge lane the manifest review, the
    file and line caps and the C2 contradictions are each a setting the
    caller turns off. Off, the same diff that scored above LOW is LOW. The
    HIGH path floor is not one (owner decision Q-FLOOR (B))."""

    def test_the_floor_holds_either_way(self):
        files = (_file(".gitmodules"),)
        for on in (True, False):
            with self.subTest(high_floor=on):
                result = score(_input(files=files, high_floor=on))
                self.assertEqual(_codes(result), ("high-path:**/.gitmodules",))

    def test_the_floor_off_still_honors_configured_paths(self):
        files = (_file(".github/workflows/x.yml"),)
        result = score(
            _input(files=files, high_floor=False, high_paths=(".github/**",))
        )
        self.assertEqual(_codes(result), ("high-path:.github/**",))

    def test_the_floor_off_still_refuses_unsafe_paths(self):
        result = score(_input(files=(_file("../x"),), high_floor=False))
        self.assertIn("high-path:**", _codes(result))

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
        max_changed_files=config.max_changed_files,
        lines_optional=True,
    )


class LanePathFloorTests(unittest.TestCase):
    """The live pr-merge config holds no path for being trusted alone (owner
    direction 2026-10-24) except the narrow floor (owner decisions Q-FLOOR
    (B) and Q-ENFORCE (A)); the trust gate still holds the trusted-actor
    list."""

    def test_the_live_config_has_the_floor_off(self):
        self.assertIs(_lane_config().high_path_floor, False)

    def test_the_floor_holds_with_the_switch_off(self):
        for path in (
            ".gitmodules",
            ".github/CODEOWNERS",
            ".github/actions/check-trusted-trigger/action.yml",
            ".github/actions/resolve-config/lane-rules.json",
            ".github/actions/resolve-config/resolve.mjs",
            ".github/actions/check-kill-switch/action.yml",
            ".github/actions/request-lane-token/action.yml",
            ".github/actions/log-api-budget/rate-guard.mjs",
            ".github/scripts/pr-merge/merge-holds.mjs",
            ".github/scripts/pr-merge/enable-auto-merge.mjs",
            ".github/scripts/pr-merge/superseded.mjs",
            ".github/scripts/pr-merge/clear-escalations.mjs",
            ".github/scripts/pr-merge/gate-check.mjs",
            ".github/scripts/pr-merge/who.mjs",
            "plugins/source-control/skills/babysit-prs/scripts/babysit_risk.py",
            "plugins/source-control/skills/babysit-prs/scripts/babysit_verify_evidence.py",
            "plugins/source-control/skills/babysit-prs/scripts/babysit_merge.py",
            ".github/workflows/pr-require-checks.yml",
            ".github/workflows/pr-merge.yml",
            "docs/conventions/pr-pipeline.yaml",
            ".github/scripts/pr-unblock/address-feedback.mjs",
            ".github/scripts/pr-unblock/gate-source.mjs",
            ".github/scripts/pr-unblock/thread-scope.mjs",
            ".github/scripts/work-resolve-issue/report-outcome.mjs",
            ".github/scripts/work-resolve-issue/limits.mjs",
        ):
            with self.subTest(path):
                unreviewed = (
                    _lane("claude-review"),
                    _lane("claude-security-review", open_findings=1),
                )
                result = score(
                    dataclasses.replace(_lane_input((_file(path),)), lanes=unreviewed)
                )
                self.assertEqual(result.score, Risk.HIGH, result.reasons)

    def test_trusted_paths_off_the_floor_merge(self):
        for path in (
            ".github/scripts/pr-unblock/other.mjs",
            "plugins/source-control/scripts/source-control-babysit-merge",
            ".github/actions/log-api-budget/action.yml",
        ):
            with self.subTest(path):
                result = score(_lane_input((_file(path),)))
                self.assertEqual(result.score, Risk.LOW, result.reasons)

    def test_the_trusted_actor_list_still_holds(self):
        path = ".github/standards/trusted-actors/trusted-actors.json"
        result = score(_lane_input((_file(path),)))
        self.assertEqual(_codes(result), ("trust-gate:trusted-actors",))

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
            "plugins/source-control/scripts/source-control-babysit-merge",
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
        self.assertEqual(
            _codes(score(_lane_input(files))),
            ("cost-review-required", "high-path:docs/conventions/pr-pipeline.yaml"),
        )


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
        copied = dict(
            status="copied", previous_path="plugins/bar/.claude-plugin/plugin.json"
        )
        self.assertIn(
            self.REVIEW, self._codes(MANIFEST, PLUGIN_BASE, PLUGIN_BASE, **copied)
        )


class HoldsTests(unittest.TestCase):
    """A MED score merges unattended when every reason is a size or
    reported-finding reason; every other reason holds."""

    def _holds(self, **changes):
        return holds(score(_input(**changes)))

    def test_low_does_not_hold(self):
        self.assertFalse(self._holds())

    def test_a_path_or_size_med_merges(self):
        for changes in (
            dict(files=(_file("plugins/foo/logo.png", has_patch=False),)),
            dict(files=(_file("plugins/foo/a.md", additions=500),)),
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
        self.assertTrue(
            self._holds(files=(_file(".gitmodules"),), high_paths=("**/.gitmodules",))
        )

    def test_an_unread_listing_holds(self):
        self.assertTrue(self._holds(files_complete=False))


class PersonReasonsTests(unittest.TestCase):
    """Owner rule 2026-10-26: a person clears only a security issue, a trust
    or provenance hold, or a cost hold; the lanes clear every other holding
    reason by judging again."""

    def test_person_reasons_are_security_trust_cost_and_high_paths(self):
        person = (
            "security-finding",
            "trust-gate:trusted-actors",
            "cost-review-required",
            "high-path:**",
            "high-path:**/.gitmodules",
            "files-capped",
        )
        lane = (
            "evidence-unbound:claude-review",
            "evidence-unbound:unknown",
            "files-incomplete",
            "manifest-review-required",
            "lines-over",
        )
        reasons = [Reason(code, Risk.HIGH, "d") for code in person + lane]
        self.assertEqual(
            tuple(r.code for r in babysit_risk.person_reasons(reasons)), person
        )

    def test_an_unbound_review_holds_for_the_lanes_and_a_finding_for_a_person(self):
        unbound = score(
            _input(lanes=(_lane("claude-review", bound=False), BOTH_LANES_CLEAN[1]))
        )
        self.assertTrue(holds(unbound))
        self.assertEqual(babysit_risk.person_reasons(holding(unbound)), [])
        finding = score(
            _input(
                lanes=(
                    BOTH_LANES_CLEAN[0],
                    _lane("claude-security-review", open_findings=1),
                )
            )
        )
        self.assertEqual(
            [r.code for r in babysit_risk.person_reasons(holding(finding))],
            ["security-finding"],
        )

    def test_a_carried_security_finding_on_an_unbound_lane_holds_for_a_person(self):
        # The binder's unbound shape when an earlier bound review left a
        # blocking finding open (babysit_review_evidence._carried_blocking;
        # bound through the binder in CarriedBlockingTests there).
        lane = LaneEvidence("claude-security-review", False, "no-run", None, False, 2)
        result = score(_input(lanes=(BOTH_LANES_CLEAN[0], lane)))
        codes = [r.code for r in babysit_risk.person_reasons(holding(result))]
        self.assertEqual(codes, ["security-finding"])

    def test_a_size_reason_holds_nothing_so_no_one_is_needed(self):
        # lines-over, files-over and no-patch are MED reasons an unattended
        # merge passes (MERGEABLE_MED): they never hold, so they never sit
        # unarmed waiting for a lane or a person.
        result = score(
            _input(
                max_changed_lines=10,
                max_changed_files=1,
                files=(
                    _file("plugins/foo/a.md", additions=50),
                    _file("plugins/foo/logo.png", has_patch=False),
                ),
            )
        )
        codes = {r.code for r in result.reasons}
        self.assertTrue({"lines-over", "files-over"} <= codes, codes)
        self.assertTrue(any(c.startswith("no-patch:") for c in codes), codes)
        self.assertFalse(holds(result), result.reasons)
        self.assertEqual(babysit_risk.person_reasons(holding(result)), [])

    def test_a_listing_past_the_files_api_cap_holds_for_a_person(self):
        capped = score(_input(files_complete=False, files_capped=True))
        self.assertEqual(
            [r.code for r in babysit_risk.person_reasons(holding(capped))],
            ["files-capped"],
        )
        unread = score(_input(files_complete=False))
        self.assertTrue(holds(unread))
        self.assertEqual(babysit_risk.person_reasons(holding(unread)), [])


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

    def test_a_pure_removal_merges_with_the_floor_on(self):
        # No floor holds the trusted-actor directory (owner direction
        # 2026-10-24): only a widening waits for the owner.
        result = score(_input(files=(_edit(ACTORS, BASE_ACTORS, _actors(_KYLE)),)))
        self.assertEqual(result.score, Risk.LOW, result.reasons)

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
                result = score(_input(files=(changed,), high_floor=False))
                self.assertEqual(_codes(result), (TRUSTED,))

    def test_a_case_folded_path_holds(self):
        result = self._score(
            _actors(_KYLE, _BOT, '{ "id": 3 }'),
            path=".GitHub/Standards/Trusted-Actors/Trusted-Actors.JSON",
        )
        self.assertEqual(_codes(result), (TRUSTED,))

    def test_paths_the_owner_lifted_do_not_hold_with_the_floor_off(self):
        # The merge gate's wrapper and skill, workflows and the security review
        # merge normally; the scorer, the Python that decides the holds and the
        # pipeline config are on the floor (owner decision Q-ENFORCE (A)).
        for path in (
            "plugins/source-control/scripts/source-control-babysit-merge",
            "plugins/source-control/skills/babysit-prs/SKILL.md",
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
                high_paths=("**/.gitmodules",),
            )
        )
        self.assertIn("findings:claude-review", _codes(result))
        self.assertTrue(holds(result))


def _floor_sample(glob):
    """A path the floor glob `glob` matches."""
    return glob.removeprefix("**/").replace("**", "x.mjs")


class ReviewClearedFloorTests(unittest.TestCase):
    """Owner decision Q26 option B: an `enforcement` floor path holds as
    `review-path:` until the security lane's review is bound to the head with
    no open finding; a `trust` or `gate` path holds for a person whatever
    the review says."""

    def _score(self, path, security):
        lanes = (_lane("claude-review"), *security)
        return score(_input(files=(_file(path),), lanes=lanes))

    def test_a_clean_bound_security_review_clears_each_enforcement_path(self):
        self.assertEqual(len(babysit_risk.REVIEW_FLOOR), 21)
        for glob in babysit_risk.REVIEW_FLOOR:
            with self.subTest(glob):
                result = self._score(glob, (_lane("claude-security-review"),))
                self.assertEqual(result.score, Risk.LOW, _codes(result))
                self.assertFalse(holds(result))

    def test_an_enforcement_path_holds_without_a_clean_bound_review(self):
        security = "claude-security-review"
        cases = {
            "unbound": (_lane(security, bound=False, unbound_reason="no-run"),),
            "bound with an unbound reason": (_lane(security, unbound_reason="x"),),
            "a CRITICAL finding": (
                LaneEvidence(security, True, None, 1, blocking_findings=1),
            ),
            "an IMPORTANT finding open": (
                LaneEvidence(security, True, None, 1, blocking_findings=0),
            ),
            "an unread count": (_lane(security, open_findings=None),),
            "a negative count": (_lane(security, open_findings=-1),),
            "a bool count": (_lane(security, open_findings=False),),
            "a float count": (
                LaneEvidence(security, True, None, 0.0, blocking_findings=0),
            ),
            "a CRITICAL count the open count misses": (
                LaneEvidence(security, True, None, 0, blocking_findings=1),
            ),
            "an unread CRITICAL count": (
                LaneEvidence(security, True, None, 0, blocking_findings=-1),
            ),
            "no security lane": (),
            "two security entries": (_lane(security), _lane(security)),
        }
        path = B + "babysit_risk.py"
        for name, lanes in cases.items():
            with self.subTest(name):
                result = self._score(path, lanes)
                self.assertIn(f"review-path:{path}", _codes(result))
                self.assertTrue(holds(result))

    def test_a_clean_code_review_alone_clears_nothing(self):
        path = ".github/scripts/work-resolve-issue/report-outcome.mjs"
        lanes = (_lane("claude-security-review", bound=False), _lane("claude-review"))
        result = score(_input(files=(_file(path),), lanes=lanes))
        self.assertIn(f"review-path:{path}", _codes(result))

    def test_the_review_hold_is_not_a_person_code(self):
        # enable-auto-merge labels a `high-path:` reason for a person; this
        # one the lanes clear by reviewing again.
        result = self._score(B + "babysit_gh.py", ())
        codes = [c for c in _codes(result) if c.startswith("review-path:")]
        self.assertEqual(codes, [f"review-path:{B}babysit_gh.py"])
        self.assertFalse(any(c.startswith("high-") for c in _codes(result)))
        self.assertEqual(babysit_risk.person_reasons(result.reasons), [])

    def test_each_gate_and_trust_path_holds_even_with_a_clean_review(self):
        for glob in babysit_risk.HIGH_FLOOR:
            with self.subTest(glob):
                result = self._score(
                    _floor_sample(glob), (_lane("claude-security-review"),)
                )
                self.assertEqual(_codes(result), (f"high-path:{glob}",))
                self.assertTrue(holds(result))

    def test_a_review_caller_workflow_change_unbinds_the_review(self):
        # Any .github/workflows/ change is a lane source
        # (babysit_review_evidence.LANE_SOURCE_PREFIXES), so no lane binds and
        # the enforcement path stays held.
        import babysit_review_evidence

        path = B + "babysit_verify_evidence.py"
        changed = [path, ".github/workflows/pr-review-security-hosted.yml"]
        lanes = babysit_review_evidence.bind(
            "a" * 40, [], [], [], is_human=lambda _: False, changed_paths=changed
        )
        self.assertEqual(
            {lane.unbound_reason for lane in lanes}, {"lane-source-changed"}
        )
        files = tuple(_file(each) for each in changed)
        result = score(_input(files=files, lanes=lanes))
        self.assertIn(f"review-path:{path}", _codes(result))
        self.assertTrue(holds(result))
