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

    def test_worker_push_paths_require_the_post_push_head(self) -> None:
        pinned_merge = "--merge --expected-head <post-push-head-sha>"
        markers = (
            "After the worker's final push",
            "In worker mode, after a worker's fix",
        )

        for marker in markers:
            with self.subTest(marker=marker):
                paragraph = _paragraph_containing(self.skill_text, marker)
                self.assertIn(pinned_merge, paragraph)
                self.assertIn("fresh post-push snapshot", paragraph)
                self.assertIn("exact pushed commit", paragraph)
                self.assertIn("Never reuse the pre-worker snapshot pin", paragraph)
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
        ):
            with self.subTest(criterion=criterion):
                self.assertIn(criterion, safety)

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
