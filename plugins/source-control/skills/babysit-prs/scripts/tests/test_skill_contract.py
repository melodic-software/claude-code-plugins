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


def _sections(text: str) -> dict[str, str]:
    """Split a reference file into its `### ` sections, keyed by heading."""
    sections: dict[str, str] = {}
    heading: str | None = None
    body: list[str] = []
    for line in text.replace("\r\n", "\n").split("\n"):
        if line.startswith("### ") or line.startswith("## "):
            if heading is not None:
                sections[heading] = "\n".join(body)
            heading = line.removeprefix("### ") if line.startswith("### ") else None
            body = []
        elif heading is not None:
            body.append(line)
    if heading is not None:
        sections[heading] = "\n".join(body)
    return sections


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

    def test_merge_gate_is_the_sole_merge_ready_authority(self) -> None:
        # #601: the two gates are separately named and both once called
        # "readiness"; SKILL.md must name the merge gate's `ready` field as the
        # only source of a MERGE-READY claim.
        paragraph = _paragraph_containing(self.skill_text, "**Merge readiness**")

        self.assertIn(
            "This gate's `ready` field is the sole authority for calling a PR merge-ready",
            paragraph,
        )
        self.assertIn("never the finding-classification gate's `READINESS_OK`", paragraph)
        self.assertIn("Two Gates, One Merge-Ready Authority", paragraph)

    def test_safety_md_separates_the_two_gates(self) -> None:
        safety = (SKILL.parent / "reference" / "safety.md").read_text(encoding="utf-8")

        self.assertIn("## Two Gates, One Merge-Ready Authority", safety)
        self.assertIn(
            "**Only the merge gate's `ready` field determines merge-readiness.**", safety
        )
        for marker in (
            "finding-classification gate",
            "babysit-readiness-gate.sh",
            "source-control-babysit-merge",
            "never `READINESS_OK`",
            "pre-gate",
        ):
            with self.subTest(marker=marker):
                self.assertIn(marker, safety)

    def test_loop_md_reports_the_two_gates_as_separate_fields(self) -> None:
        # The §5.5 template pairing a single "Readiness: ready for merge" field
        # with the classification gate is what produced the false report (#601).
        loop = (SKILL.parent / "reference" / "loop.md").read_text(encoding="utf-8")

        self.assertIn(
            "- [ ] Finding-classification gate: READINESS_OK / READINESS_BLOCKED", loop
        )
        self.assertIn("- [ ] Merge gate: `ready: true` / `ready: false`", loop)
        self.assertNotIn("Readiness: ready for merge", loop)
        self.assertIn("Never report a PR MERGE-READY off `READINESS_OK`", loop)

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

    def test_conflict_resolution_splits_resolve_from_push(self) -> None:
        # A dispatched conflict worker's isolated context cannot carry the
        # operator's own grant for an outward mutation, so the local resolution
        # stays with it and the push belongs to the dispatching context. Asserted
        # per section, with the negative, so the boundary cannot drift back to a
        # conflict worker that pushes while the markers still all appear somewhere.
        sections = _sections(
            (SKILL.parent / "reference" / "orchestration.md").read_text(
                encoding="utf-8"
            )
        )

        for header in (
            "Why The Push Stays With The Orchestrator",
            "Conflict-Worker Contract (local only — never writes to GitHub)",
            "Orchestrator Contract (the push)",
            "Conflict-Worker Prompt Delta",
        ):
            with self.subTest(header=header):
                self.assertIn(header, sections)

        worker = sections["Conflict-Worker Contract (local only — never writes to GitHub)"]
        for marker in (
            "git merge origin/<base-branch>",
            "never rebase",
            "never `git push`",
            "`resolved`",
            "`escalate`",
            "`verification-impossible`",
            "`no-conflict`",
        ):
            with self.subTest(side="conflict worker", marker=marker):
                self.assertIn(marker, worker)

        # The negative half: the push lives in exactly one of the two contracts.
        self.assertNotIn('push "$PUSH_REMOTE"', worker)

        orchestrator = sections["Orchestrator Contract (the push)"]
        for marker in (
            "Push only on `resolved`",
            "rev-parse HEAD^1",
            "rev-list --parents -n 1 HEAD",
            "Re-run the verification in the worktree",
            'push "$PUSH_REMOTE" HEAD:<headRefName>',
            "Never force, in any tier.",
        ):
            with self.subTest(side="orchestrator", marker=marker):
                self.assertIn(marker, orchestrator)

        rationale = sections["Why The Push Stays With The Orchestrator"]
        self.assertIn("https://code.claude.com/docs/en/sub-agents", rationale)

    def test_conflict_worker_is_bound_by_the_worker_rules(self) -> None:
        # The two contracts are the only differences from an ordinary worker;
        # every other worker rule (leases, concurrency cap, check-in) must keep
        # binding, so the vocabulary cannot quietly create an unowned actor.
        orchestration = (SKILL.parent / "reference" / "orchestration.md").read_text(
            encoding="utf-8"
        )

        self.assertIn("**A conflict worker is a worker.**", orchestration)
        self.assertIn("and it does not push", orchestration)

    def test_skill_table_states_the_conflict_push_boundary(self) -> None:
        row = _table_row(self.skill_text, "Dispatch a dedicated conflict worker")

        self.assertIn("never pushes", row)
        self.assertIn("the orchestrator re-verifies and pushes", row)

    def test_reference_files_agree_on_who_pushes_a_resolution(self) -> None:
        def unwrapped(path: pathlib.Path) -> str:
            return " ".join(path.read_text(encoding="utf-8").split())

        safety = unwrapped(SKILL.parent / "reference" / "safety.md")
        loop = unwrapped(SKILL.parent.parent / "babysit-loop" / "SKILL.md")

        # safety.md's Role Boundaries enumerates orchestrator authority; the one
        # push it owns has to appear there, not only in the stop-and-ask list.
        self.assertIn("push a dispatched conflict worker's verified resolution", safety)
        self.assertIn("which the conflict worker never does", safety)
        self.assertIn("the dispatched conflict worker never pushes", loop)

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
