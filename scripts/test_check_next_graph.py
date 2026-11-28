#!/usr/bin/env python3

from __future__ import annotations

import importlib.util
import io
import shutil
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location(
    "check_next_graph", HERE / "check-next-graph.py"
)
if SPEC is None or SPEC.loader is None:
    raise ImportError(f"cannot load {HERE / 'check-next-graph.py'}")
gate = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(gate)

STEPS = """# Workflow Stages

## 1. Interview (optional: lock the Brief)
## 2. Explore (conditional: read the code)
## 3. Design
## 4. Plan
## 5. Decompose (conditional: split the plan)
## 6. Implement
## 7. Verify outcome
"""

STAGES = """stages:
  - {id: interview, name: Interview, flag: optional, entry: "p:interview", inbound: the first stage}
  - {id: explore, name: Explore, flag: conditional}
  - {id: design, name: Design, entry: "p:design"}
  - {id: plan, name: Plan, entry: "p:plan"}
  - {id: decompose, name: Decompose, flag: conditional, entry: "p:decompose"}
  - {id: implement, name: Implement, entry: "p:implement", terminal: the fixture ends here}
  - {id: verify, name: Verify outcome}
off-ladder: [anytime, pr]
aliases: {build: implement}
"""


class Fixture:
    def __init__(self) -> None:
        self.root = Path(tempfile.mkdtemp(prefix="next-graph-"))
        self.write("plugins/session-flow/skills/workflow/context/steps.md", STEPS)
        self.stages()

    def write(self, rel: str, text: str) -> None:
        path = self.root / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")

    def read(self, name: str) -> str:
        plugin, skill = name.split(":")
        return (self.root / f"plugins/{plugin}/skills/{skill}/SKILL.md").read_text(
            encoding="utf-8"
        )

    def stages(self, extra: str = "", base: str = STAGES) -> None:
        self.write(gate.STAGE_MAP, base + extra)

    def skill(
        self,
        name: str,
        stage: str | None,
        next_body: str | None,
        extra: str = "",
        related: str | None = None,
    ) -> None:
        plugin, skill = name.split(":")
        meta = f"metadata:\n  workflow-stage: {stage}\n" if stage else ""
        text = f"---\ndescription: x\n{meta}---\n\n## Purpose\n\nx\n{extra}"
        if next_body is not None:
            text += f"\n## Next\n\n{next_body}\n"
        if related is not None:
            text += f"\n## Related\n\n{related}\n"
        text += "\n## Gotchas\n\n- x\n"
        self.write(f"plugins/{plugin}/skills/{skill}/SKILL.md", text)

    def run(self, *args: str) -> tuple[int, str, str]:
        out, err = io.StringIO(), io.StringIO()
        with redirect_stdout(out), redirect_stderr(err):
            rc = gate.main(["--root", str(self.root), *args])
        return rc, out.getvalue(), err.getvalue()

    def clean(self) -> None:
        shutil.rmtree(self.root, ignore_errors=True)


class NextGraphTest(unittest.TestCase):
    def setUp(self) -> None:
        self.fx = Fixture()
        self.addCleanup(self.fx.clean)
        self.fx.skill("p:interview", "interview", "/p:design")
        self.fx.skill("p:design", "design", "/p:plan reads the design.")
        self.fx.skill(
            "p:plan",
            "plan",
            "- One ticket: /p:implement.\n- Many tickets: /p:decompose.",
        )
        self.fx.skill("p:decompose", "decompose", "/p:implement")
        self.fx.skill("p:implement", "implement", None)

    def test_clean_map_passes(self) -> None:
        rc, out, err = self.fx.run()
        self.assertEqual(rc, 0, err)
        self.assertIn("follows the stage map", out)
        self.assertEqual(err, "")

    def test_skip_over_flagged_stage_passes(self) -> None:
        self.fx.skill("p:start", "interview", "/p:design")
        rc, _, err = self.fx.run()
        self.assertEqual(rc, 0, err)

    def test_stage_skip_over_unflagged_stage_fails(self) -> None:
        self.fx.skill(
            "p:interview",
            "interview",
            "- Locked: /p:design.\n- No design question: /p:plan.",
        )
        rc, out, err = self.fx.run()
        self.assertEqual(rc, 1)
        self.assertIn(
            "stage-skip: /p:interview (interview) routes to /p:plan (plan), skipping the design stage",
            err,
        )
        self.assertEqual(out, "")

    def test_skill_outside_the_old_roster_is_checked(self) -> None:
        self.fx.skill("q:other", "design", "/p:implement")
        rc, _, err = self.fx.run()
        self.assertEqual(rc, 1)
        self.assertIn(
            "stage-skip: /q:other (design) routes to /p:implement (implement), skipping the plan stage",
            err,
        )

    def test_declared_skill_skip_passes_only_its_own_edge(self) -> None:
        self.fx.skill(
            "p:interview",
            "interview",
            "- Locked: /p:design.\n- Build items: /p:decompose.\n- No design question: /p:plan.",
        )
        self.fx.stages(
            "skips:\n  - {from: 'p:interview', to: 'p:decompose', reason: an owner decision}\n"
        )
        rc, _, err = self.fx.run()
        self.assertEqual(rc, 1)
        self.assertNotIn("/p:decompose (decompose)", err)
        self.assertIn("routes to /p:plan (plan), skipping the design stage", err)

    def test_declared_stage_skip_covers_every_skill_on_that_stage(self) -> None:
        self.fx.skill("q:other", "design", "/p:implement")
        self.fx.skill("q:more", "design", "/q:build-thing")
        self.fx.skill("q:build-thing", "implement", None)
        self.fx.stages(
            "skips:\n  - {from: design, to: implement, reason: built directly}\n"
        )
        rc, _, err = self.fx.run()
        self.assertEqual(rc, 0, err)

    def test_undeclared_backward_edge_fails(self) -> None:
        self.fx.skill(
            "p:plan",
            "plan",
            "- Departs from the design: /p:design.\n- Ready: /p:implement.",
        )
        rc, _, err = self.fx.run()
        self.assertEqual(rc, 1)
        self.assertIn(
            "loop-back: /p:plan (plan) routes back to /p:design (design), and "
            f"{gate.STAGE_MAP} declares no loop-back for it",
            err,
        )

    def test_declared_loop_back_passes(self) -> None:
        self.fx.skill(
            "p:plan",
            "plan",
            "- Departs from the design: /p:design.\n- Ready: /p:implement.\n- Many tickets: /p:decompose.",
        )
        for declaration in (
            "{from: plan, to: design, reason: departs}",
            "{from: any, to: design, reason: an interface question}",
            "{from: 'p:plan', to: 'p:design', reason: departs}",
        ):
            with self.subTest(declaration=declaration):
                self.fx.stages(f"loop-backs:\n  - {declaration}\n")
                rc, _, err = self.fx.run()
                self.assertEqual(rc, 0, err)

    def test_loop_back_to_another_stage_stays_undeclared(self) -> None:
        self.fx.skill(
            "p:implement",
            "implement",
            "- Not quick to review: /p:interview.\n- Done: /p:implement.",
        )
        self.fx.stages(
            "loop-backs:\n  - {from: implement, to: design, reason: an interface question}\n"
        )
        rc, _, err = self.fx.run()
        self.assertEqual(rc, 1)
        self.assertIn(
            "loop-back: /p:implement (implement) routes back to /p:interview (interview)",
            err,
        )

    def test_off_ladder_target_and_source_impose_no_order(self) -> None:
        self.fx.skill("p:track", "anytime", "/p:interview")
        self.fx.skill("p:pull-request", "pr", None)
        self.fx.skill(
            "p:interview",
            "interview",
            "- Locked: /p:design.\n- One unit for later: /p:track add.\n- Built: /p:pull-request.",
        )
        rc, _, err = self.fx.run()
        self.assertEqual(rc, 0, err)

    def test_alias_names_a_ladder_stage(self) -> None:
        self.fx.skill("q:builder", "build", "/p:design")
        rc, _, err = self.fx.run()
        self.assertEqual(rc, 1)
        self.assertIn(
            "loop-back: /q:builder (implement) routes back to /p:design (design)", err
        )

    def test_unknown_stage_fails_and_missing_stage_is_skipped(self) -> None:
        self.fx.skill("q:typo", "dsign", "/p:plan")
        self.fx.skill("q:none", None, "/p:implement")
        rc, _, err = self.fx.run()
        self.assertEqual(rc, 1)
        self.assertIn("unstaged: /q:typo has workflow-stage 'dsign'", err)
        self.assertNotIn("q:none", err)

    def test_unresolved_target_fails_anywhere_in_tree(self) -> None:
        self.fx.skill("q:outside", None, "/q:renamed-away")
        rc, _, err = self.fx.run()
        self.assertEqual(rc, 1)
        self.assertIn(
            "unresolved: plugins/q/skills/outside/SKILL.md '## Next' names /q:renamed-away",
            err,
        )

    def test_stage_bullet_naming_another_skill_fails(self) -> None:
        self.fx.skill("q:planner", "design", None)
        self.fx.skill(
            "p:design",
            "design",
            "- Decisions settled: the plan stage (/q:planner).\n- Open thread: /p:design.",
        )
        rc, _, err = self.fx.run()
        self.assertEqual(rc, 1)
        self.assertIn(
            "stage-entry: plugins/p/skills/design/SKILL.md '## Next' names /q:planner for the "
            "plan stage, whose entry skill is /p:plan (run --fix)",
            err,
        )

    def test_stage_bullet_naming_the_entry_skill_passes(self) -> None:
        self.fx.skill(
            "p:design",
            "design",
            "- Decisions settled: the Plan stage (`/p:plan`).\n- Open thread: /p:design.",
        )
        rc, _, err = self.fx.run()
        self.assertEqual(rc, 0, err)

    def test_stage_bullet_for_a_stage_without_entry_fails(self) -> None:
        self.fx.skill(
            "p:implement",
            "implement",
            "- Built: the verify outcome stage (/p:plan).\n- Not built: the deploy stage (/p:plan).",
        )
        rc, _, err = self.fx.run()
        self.assertEqual(rc, 1)
        self.assertIn("routes to 'the verify outcome stage', which", err)
        self.assertIn("routes to 'the deploy stage', which", err)

    def test_fix_rewrites_stage_bullet_from_the_map(self) -> None:
        self.fx.skill("q:planner", "design", None)
        self.fx.skill(
            "p:design",
            "design",
            "- Decisions settled: the plan stage (/q:planner).\n- Open thread: /p:design.",
            extra="\nProse names the plan stage (/q:planner) outside Next.\n",
        )
        rc, out, err = self.fx.run("--fix")
        self.assertEqual(rc, 0, err)
        self.assertIn("fixed plugins/p/skills/design/SKILL.md", out)
        text = self.fx.read("p:design")
        self.assertIn("- Decisions settled: the plan stage (/p:plan).", text)
        self.assertIn("Prose names the plan stage (/q:planner) outside Next.", text)

    def test_fix_resolves_a_stage_alias(self) -> None:
        self.fx.skill("q:builder", "design", None)
        self.fx.skill("p:design", "design", "- Plan approved: the build stage (/q:builder).\n- Open thread: /p:design.")
        self.fx.run("--fix")
        self.assertIn("- Plan approved: the build stage (/p:implement).", self.fx.read("p:design"))

    def test_fix_applies_renames_in_next_and_related_only(self) -> None:
        self.fx.skill(
            "q:user",
            None,
            "- Ready: /p:old-plan.\n- Not ready: /p:design.",
            extra="\nInline /p:old-plan stays.\n",
            related="- Ranking first: /p:old-plan.",
        )
        self.fx.write("renames.txt", "# old new\np:old-plan p:plan\n")
        rc, out, err = self.fx.run(
            "--fix", "--renames", str(self.fx.root / "renames.txt")
        )
        self.assertEqual(rc, 0, err)
        text = self.fx.read("q:user")
        self.assertIn("- Ready: /p:plan.", text)
        self.assertIn("- Ranking first: /p:plan.", text)
        self.assertIn("Inline /p:old-plan stays.", text)

    def test_fix_on_a_clean_tree_changes_nothing(self) -> None:
        before = self.fx.read("p:plan")
        rc, out, _ = self.fx.run("--fix")
        self.assertEqual(rc, 0)
        self.assertNotIn("fixed", out)
        self.assertEqual(self.fx.read("p:plan"), before)

    def test_malformed_rename_line_exits_2(self) -> None:
        self.fx.write("renames.txt", "p:old-plan\n")
        rc, _, err = self.fx.run(
            "--fix", "--renames", str(self.fx.root / "renames.txt")
        )
        self.assertEqual(rc, 2)
        self.assertIn("a rename line is 'plugin:old plugin:new'", err)

    def test_entry_skill_findings(self) -> None:
        self.fx.skill("p:design", "plan", None)
        self.fx.skill("p:interview", "interview", "/p:plan")
        self.fx.stages(base=STAGES.replace('entry: "p:decompose"', 'entry: "p:gone"'))
        rc, _, err = self.fx.run()
        self.assertEqual(rc, 1)
        self.assertIn(f"stale-entry: {gate.STAGE_MAP} names /p:gone for decompose", err)
        self.assertIn(
            "entry-stage: /p:design enters the design stage, but its workflow-stage is 'plan'",
            err,
        )
        self.assertIn("no-next: /p:design has no '## Next' section", err)
        self.assertIn("orphan: no skill's '## Next' names /p:design", err)

    def test_terminal_and_inbound_reasons_clear_entry_findings(self) -> None:
        self.fx.skill("p:interview", "interview", None)
        rc, _, err = self.fx.run()
        self.assertEqual(rc, 1)
        self.assertNotIn("no-next: /p:implement", err)
        self.assertIn("no-next: /p:interview", err)
        self.assertIn("orphan: no skill's '## Next' names /p:design", err)
        self.assertNotIn("orphan: no skill's '## Next' names /p:interview", err)

    def test_self_edge_does_not_count_as_inbound(self) -> None:
        self.fx.skill("p:interview", "interview", "/p:plan")
        self.fx.skill(
            "p:design", "design", "- Open thread: /p:design.\n- Settled: /p:plan."
        )
        rc, _, err = self.fx.run()
        self.assertEqual(rc, 1)
        self.assertIn("orphan: no skill's '## Next' names /p:design", err)

    def test_stale_declaration_fails(self) -> None:
        self.fx.stages("loop-backs:\n  - {from: 'p:gone', to: dsign, reason: x}\n")
        rc, _, err = self.fx.run()
        self.assertEqual(rc, 1)
        self.assertIn(
            f"stale-declaration: {gate.STAGE_MAP} loop-backs names 'p:gone'", err
        )
        self.assertIn(
            f"stale-declaration: {gate.STAGE_MAP} loop-backs names 'dsign'", err
        )

    def test_map_drift_from_steps_fails(self) -> None:
        self.fx.write(
            "plugins/session-flow/skills/workflow/context/steps.md",
            STEPS.replace("## 3. Design\n## 4. Plan", "## 3. Plan\n## 4. Design"),
        )
        rc, _, err = self.fx.run()
        self.assertEqual(rc, 1)
        self.assertIn("map-drift:", err)

    def test_token_outside_next_and_inside_fence_is_ignored(self) -> None:
        self.fx.skill(
            "p:interview",
            "interview",
            "/p:design",
            extra="\nSee /p:nowhere in prose.\n\n```text\n## Next\n/p:also-nowhere\n```\n",
        )
        rc, _, err = self.fx.run()
        self.assertEqual(rc, 0, err)

    def test_missing_map_exits_2(self) -> None:
        (self.fx.root / gate.STAGE_MAP).unlink()
        rc, out, err = self.fx.run()
        self.assertEqual(rc, 2)
        self.assertIn("cannot read the stage map", err)
        self.assertEqual(out, "")

    def test_malformed_map_exits_2(self) -> None:
        cases = {
            "no stages": ("off-ladder: [anytime]\n", "has no 'stages' list"),
            "bad flag": (
                STAGES.replace("flag: optional", "flag: maybe"),
                "flag 'maybe'",
            ),
            "reasonless edge": (
                STAGES + "skips:\n  - {from: plan, to: verify}\n",
                "needs 'from', 'to' and 'reason'",
            ),
            "bad entry": (
                STAGES.replace('entry: "p:plan"', "entry: plan"),
                "entry 'plan' is not plugin:skill",
            ),
        }
        for label, (text, message) in cases.items():
            with self.subTest(label=label):
                self.fx.stages(base=text)
                rc, _, err = self.fx.run()
                self.assertEqual(rc, 2)
                self.assertIn(message, err)

    def test_shipped_stage_map_loads(self) -> None:
        stage_map = gate.read_map(HERE.parent)
        self.assertEqual(stage_map.ladder[0], "interview")
        self.assertEqual(stage_map.entries["plan"], "planning:plan")
        self.assertEqual(
            stage_map.index("retro"), stage_map.ladder.index("retrospective")
        )


if __name__ == "__main__":
    unittest.main()
