"""SKILL.md prose contract assertions.

Ported near-verbatim from the monolith suite, retargeted to the plugin's
current SKILL.md. Guards the merge-opt-in mode table, the zero-blocker
check-only default, the pinned-head merge discipline, and the draft policy
against silent prose drift.
"""

from __future__ import annotations

import pathlib
import unittest

SKILL = pathlib.Path(__file__).resolve().parents[2] / "SKILL.md"


def _table_row(skill_text: str, label: str) -> str:
    return next(
        line for line in skill_text.splitlines() if line.startswith(f"| {label}")
    )


def _paragraph_containing(skill_text: str, marker: str) -> str:
    paragraphs = skill_text.replace("\r\n", "\n").split("\n\n")
    paragraph = next(paragraph for paragraph in paragraphs if marker in paragraph)
    return " ".join(paragraph.split())


class SkillContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.skill_text = SKILL.read_text(encoding="utf-8")

    def test_mode_table_keeps_merge_opt_in(self) -> None:
        cases = [
            ("*(none)*", False),
            ("`worker`", True),
            ("`autopilot`", True),
        ]

        for mode_label, merge_enabled in cases:
            with self.subTest(mode=mode_label):
                row = _table_row(self.skill_text, mode_label)
                if merge_enabled:
                    self.assertIn("merge", row.lower())
                else:
                    self.assertIn("Never resolves threads or merges.", row)

    def test_zero_blocker_default_path_is_check_only(self) -> None:
        paragraph = _paragraph_containing(
            self.skill_text, "A non-draft PR with zero blockers"
        )

        self.assertIn("default (safe) mode", paragraph)
        self.assertIn("without `--merge`", paragraph)
        self.assertIn("report readiness without merging", paragraph)
        self.assertNotIn("`babysit_merge.py` check/merge", paragraph)

    def test_zero_blocker_merge_path_names_every_opt_in(self) -> None:
        paragraph = _paragraph_containing(
            self.skill_text, "A non-draft PR with zero blockers"
        )

        self.assertIn(
            "`--merge --expected-head <snapshotted-head-sha>` only in `worker` or "
            "`autopilot` mode",
            paragraph,
        )
        self.assertIn("an explicit user order to merge that PR", paragraph)
        self.assertIn("exact head SHA from the snapshot", paragraph)
        self.assertIn("a missing or stale pin must refuse the merge", paragraph)
        self.assertIn("never an unattended unpinned override", paragraph)

    def test_unchanged_zero_blocker_gate_uses_the_snapshot_head(self) -> None:
        paragraph = _paragraph_containing(
            self.skill_text, "A non-draft PR with zero blockers"
        )

        self.assertIn("--merge --expected-head <snapshotted-head-sha>", paragraph)
        self.assertIn("exact head SHA from the snapshot", paragraph)
        self.assertNotIn("<post-push-head-sha>", paragraph)

    def test_direct_gate_path_wires_the_tier_when_enabled(self) -> None:
        # #675: the zero-blocker direct-gate autopilot path must also carry the
        # tier flags when the tier is enabled, or an already-clean PR merges via
        # the flagless base gate — the same fail-open §3 closed.
        paragraph = _paragraph_containing(
            self.skill_text, "A non-draft PR with zero blockers"
        )
        self.assertIn("an enabled autopilot merge tier adds the tier flags", paragraph)
        self.assertIn("reference/safety.md", paragraph)
        self.assertIn("never the flagless base command", paragraph)

    def test_worker_push_path_pins_the_post_push_head_command(self) -> None:
        # Worker tier has no merge tier, so its push paragraph still spells the
        # full pinned merge command inline.
        paragraph = _paragraph_containing(
            self.skill_text, "In worker mode, after a worker's fix"
        )
        self.assertIn("--merge --expected-head <post-push-head-sha>", paragraph)
        self.assertIn("fresh post-push snapshot", paragraph)
        self.assertIn("exact pushed commit", paragraph)
        self.assertIn("Never reuse the pre-worker snapshot pin", paragraph)
        self.assertNotIn("<snapshotted-head-sha>", paragraph)

    def test_autopilot_step3_points_at_safety_for_the_tier_wired_command(self) -> None:
        # Autopilot §3 no longer inlines a base-only merge command (the coherence
        # gap #675 closed): it points at safety.md, which holds both the base and
        # enabled-tier merge paths as one home so an enabled config cannot merge
        # via the flagless base path. The push discipline stays in the paragraph.
        paragraph = _paragraph_containing(
            self.skill_text, "After the worker's final push"
        )
        self.assertIn("fresh post-push snapshot", paragraph)
        self.assertIn("exact pushed commit", paragraph)
        self.assertIn("Never reuse the pre-worker snapshot pin", paragraph)
        self.assertIn("--autopilot-merge-tier", paragraph)
        self.assertIn("reference/safety.md", paragraph)
        self.assertNotIn("<snapshotted-head-sha>", paragraph)

    def test_generic_merge_gate_requires_the_vetted_head(self) -> None:
        paragraph = _paragraph_containing(self.skill_text, "**Merge readiness**")

        self.assertIn("--merge --expected-head <vetted-head-sha>", paragraph)
        self.assertIn("re-snapshot and reassess the new head", paragraph)

    def test_merge_gate_refuses_missing_or_stale_head_pins(self) -> None:
        paragraph = _paragraph_containing(self.skill_text, "**Merge readiness**")

        self.assertIn("expected-head pin is missing", paragraph)
        self.assertIn("no longer matches the live head", paragraph)
        self.assertIn("re-snapshot and reassess the new head", paragraph)
        self.assertIn("instead of using `--allow-unpinned-head`", paragraph)

    def test_zero_blocker_draft_always_uses_a_worker(self) -> None:
        paragraph = _paragraph_containing(
            self.skill_text, "**Zero-blocker drafts are the exception:**"
        )

        self.assertIn("always route them through a worker", paragraph)
        self.assertIn("never directly to the merge gate", paragraph)
        self.assertIn("In autopilot, that worker assesses", paragraph)
        self.assertIn("a completed draft is marked ready with `gh pr ready`",
                      paragraph)
        self.assertIn("a genuinely in-progress draft stays draft", paragraph)
        self.assertIn("reported and escalated with the reason", paragraph)

    def test_autopilot_merge_tier_ships_disabled_and_fail_closed(self) -> None:
        para = _paragraph_containing(self.skill_text, "config-gated escalation")
        for marker in (
            "shipped DISABLED",
            "separate announced steps",
            "genuine review pass",
            "second bot account",
            "author ≠ approver",
            "only when clean",
            "--autopilot-merge-tier",
            "fail-closed",
            "never routes around the gate",
            "reference/safety.md",
        ):
            with self.subTest(marker=marker):
                self.assertIn(marker, para)

    def test_safety_md_codifies_the_tier_criteria(self) -> None:
        safety = (SKILL.parent / "reference" / "safety.md").read_text(encoding="utf-8")
        self.assertIn("ships **DISABLED**", safety)
        self.assertIn("babysit_autopilot_merge_tier", safety)
        for criterion in (
            "issue-linked",
            "pipeline lane",
            "do-not-merge label",
            "distinct bot identity",
            "head SHA unchanged since review",
            "review workflow",
            "Decision defaulted",
        ):
            with self.subTest(criterion=criterion):
                self.assertIn(criterion, safety)

    def test_safety_md_specifies_the_enabled_path_mechanics(self) -> None:
        # #675 flip-precondition prose: the tier-wired merge command, the
        # second-account approve mechanic, and the review-context enabling
        # precondition are pinned so they cannot silently drift. Fenced command
        # lines land in their own paragraphs, so assert against the whole file.
        safety = (SKILL.parent / "reference" / "safety.md").read_text(encoding="utf-8")

        for header in (
            "Enabled-path merge command",
            "Second-account approve mechanic",
            "Review-workflow requiredness precondition",
        ):
            with self.subTest(header=header):
                self.assertIn(header, safety)

        # Enabled-path merge command — the four-flag tier layering is the single home.
        self.assertIn(
            "--autopilot-merge-tier --lane-logins <lane-logins> "
            "--approver-bot-logins <approver-bot-logins> "
            "--block-labels <merge-block-labels>",
            safety,
        )
        self.assertIn(
            "*only* autopilot merge path once the tier is enabled", safety
        )

        # Second-account approve mechanic — distinct approver identity, clean pass only.
        self.assertIn("gh pr review owner/repo#N --approve", safety)
        self.assertIn("GH_TOKEN=<approver-bot-token>", safety)
        self.assertIn("gh auth switch --user <approver-login>", safety)
        self.assertIn("never the PR author or a lane identity", safety)

        # Review-workflow requiredness enabling precondition (fork 3a).
        self.assertIn("required status context", safety)
        self.assertIn("mergeStateStatus == CLEAN", safety)
        self.assertIn("operator enabling precondition", safety)
        self.assertIn("do not enable the tier", safety)

    def test_unproven_readiness_contract_is_stated_on_both_sides(self) -> None:
        # The gate can print an UNPROVEN verdict, but it cannot report its own
        # non-invocation -- so half the #787 contract necessarily lives in prose:
        # the report quotes the verdict verbatim, and neither an UNPROVEN verdict
        # nor a denied call may be backfilled from live gh state. Pinned here
        # because a silent deletion would restore the exact ambiguity #787 hit.
        reference = SKILL.parent / "reference"
        safety = (reference / "safety.md").read_text(encoding="utf-8")
        loop = (reference / "loop.md").read_text(encoding="utf-8")

        self.assertIn(
            "READINESS_UNPROVEN reason=<bad-args|prereq-missing|fetch-failed>", safety
        )
        for marker in (
            "quoting the verdict line verbatim",
            "cannot report its own non-invocation",
            "NOT a substitute verdict",
        ):
            with self.subTest(file="safety.md", marker=marker):
                self.assertIn(marker, safety)

        for marker in (
            "Never report a readiness verdict the gate did not emit",
            "not emitted — harness denied: <exact command>",
            "readiness unproven",
        ):
            with self.subTest(file="loop.md", marker=marker):
                self.assertIn(marker, loop)

    def test_lane_script_prerequisite_names_its_actual_evidence(self) -> None:
        # #787's own repro used a wildcarded-interpreter form auto mode drops by
        # design, so it does not show the sanctioned bin/-path form being denied.
        # The section must keep saying so, and keep citing dotfiles#315 -- the
        # evidence that does hold -- or it reverts to overclaiming a repro.
        safety = (SKILL.parent / "reference" / "safety.md").read_text(encoding="utf-8")

        self.assertIn("does **not** demonstrate that the sanctioned", safety)
        self.assertIn("generalization from other evidence", safety)
        self.assertIn("melodic-software/dotfiles/issues/315", safety)
        self.assertIn("classifyAllShell", safety)

        # #455 disputes the never-retry rule this section sits beneath and
        # restates; the open-question note keeps the restatement from reading as
        # settled confirmation.
        self.assertIn("claude-code-plugins/issues/455", safety)
        self.assertIn("treat the retry semantics of a classifier denial", safety)

    def test_full_queue_and_draft_contract_remains_explicit(self) -> None:
        autopilot = _paragraph_containing(self.skill_text, '"Every PR" means every PR')
        drafts = _paragraph_containing(self.skill_text, "**Draft PRs** are in scope")

        self.assertIn("priority judgment is never", autopilot)
        self.assertIn("lease contention", autopilot)
        self.assertIn("owner allowlist", autopilot)
        self.assertIn("`mutation_policy.branch_write_allowed`", autopilot)
        self.assertIn("`needs_worker` delta", autopilot)
        self.assertIn("mark it ready for review (`gh pr ready`)", drafts)
        self.assertIn("leave it draft and report why", drafts)


if __name__ == "__main__":
    unittest.main()
