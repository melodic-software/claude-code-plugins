#!/usr/bin/env python3
"""Tests for scripts/check-next-graph.py, each against a fixture tree."""

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
gate = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(gate)

STEPS = """# Workflow Stages

## 1. Explore
## 2. Research
## 3. PRD (conditional: lock product intent)
## 4. Contract (optional: lock the brief)
## 5. Design
## 6. Plan
## 7. Decompose (conditional: split the plan)
## 8. Implement
"""


class Fixture:
    def __init__(self) -> None:
        self.root = Path(tempfile.mkdtemp(prefix="next-graph-"))
        self.write("plugins/session-flow/skills/workflow/context/steps.md", STEPS)
        self.skill("session-flow:workflow", "anytime", None)

    def write(self, rel: str, text: str) -> None:
        path = self.root / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")

    def skill(
        self, name: str, stage: str, next_body: str | None, extra: str = ""
    ) -> None:
        plugin, skill = name.split(":")
        text = f"---\ndescription: x\nmetadata:\n  workflow-stage: {stage}\n---\n\n## Purpose\n\nx\n{extra}"
        if next_body is not None:
            text += f"\n## Next\n\n{next_body}\n"
        text += "\n## Gotchas\n\n- x\n"
        self.write(f"plugins/{plugin}/skills/{skill}/SKILL.md", text)

    def roster(self, *lines: str) -> None:
        self.write(
            "scripts/next-graph-chain.txt", "# roster\n" + "\n".join(lines) + "\n"
        )

    def run(self) -> tuple[int, str, str]:
        out, err = io.StringIO(), io.StringIO()
        with redirect_stdout(out), redirect_stderr(err):
            rc = gate.main(["--root", str(self.root)])
        return rc, out.getvalue(), err.getvalue()

    def clean(self) -> None:
        shutil.rmtree(self.root, ignore_errors=True)


class NextGraphTest(unittest.TestCase):
    def setUp(self) -> None:
        self.fx = Fixture()
        self.addCleanup(self.fx.clean)
        # A clean chain: interview -> design -> plan -> implement, with plan also
        # skipping the conditional decompose stage to implement.
        self.fx.skill("p:interview", "contract", "/p:design")
        self.fx.skill("p:design", "design", "/p:plan reads the design.")
        self.fx.skill(
            "p:plan",
            "plan",
            "- One ticket: /p:implement.\n- Many tickets: /p:decompose.",
        )
        self.fx.skill("p:decompose", "decompose", "/p:implement")
        self.fx.skill("p:implement", "implement", None)
        self.fx.roster(
            "p:interview | entry: the chain starts here",
            "p:design",
            "p:plan",
            "p:decompose",
            "p:implement | terminal: the chain ends here",
        )

    def test_clean_chain_passes(self) -> None:
        rc, out, err = self.fx.run()
        self.assertEqual(rc, 0, err)
        self.assertIn("has no orphan", out)
        self.assertEqual(err, "")

    def test_skip_over_conditional_stage_passes(self) -> None:
        # prd is conditional and contract optional: a brainstorm-like contract
        # skill routing back to prd, and prd routing to design over the
        # optional contract stage, are both legal.
        self.fx.skill("p:prd", "prd", "/p:design")
        self.fx.skill(
            "p:interview", "contract", "- Locked: /p:design.\n- Product intent: /p:prd."
        )
        self.fx.roster(
            "p:interview | entry: start",
            "p:prd",
            "p:design",
            "p:plan",
            "p:decompose",
            "p:implement | terminal: end",
        )
        rc, _, err = self.fx.run()
        self.assertEqual(rc, 0, err)

    def test_stage_skip_over_required_stage_fails(self) -> None:
        self.fx.skill(
            "p:interview",
            "contract",
            "- Locked: /p:design.\n- No design question: /p:plan.",
        )
        rc, out, err = self.fx.run()
        self.assertEqual(rc, 1)
        self.assertIn(
            "stage-skip: /p:interview (contract) routes to /p:plan (plan), skipping the design stage",
            err,
        )
        self.assertEqual(out, "")

    def test_backward_edge_is_not_a_skip(self) -> None:
        self.fx.skill(
            "p:plan",
            "plan",
            "- Departs from the design: /p:design.\n- Ready: /p:implement.\n- Many tickets: /p:decompose.",
        )
        rc, _, err = self.fx.run()
        self.assertEqual(rc, 0, err)

    def test_off_ladder_target_is_not_a_skip(self) -> None:
        self.fx.skill("p:track", "anytime", None)
        self.fx.skill(
            "p:interview",
            "contract",
            "- Locked: /p:design.\n- One unit for later: /p:track add.",
        )
        rc, _, err = self.fx.run()
        self.assertEqual(rc, 0, err)

    def test_pr_stage_is_off_ladder_not_prd(self) -> None:
        # `pr` must not prefix-match `prd`: read as prd, this edge would skip
        # the design stage and fail.
        self.fx.skill("p:pull-request", "pr", "/p:plan")
        self.fx.roster(
            "p:interview | entry: start",
            "p:pull-request | entry: reached by hand in this fixture",
            "p:design",
            "p:plan",
            "p:decompose",
            "p:implement | terminal: end",
        )
        rc, _, err = self.fx.run()
        self.assertEqual(rc, 0, err)
        ladder = ["explore", "prd", "plan", "retrospective"]
        self.assertIsNone(gate.ladder_index("pr", ladder))
        self.assertEqual(gate.ladder_index("prd", ladder), 1)
        self.assertEqual(gate.ladder_index("retro", ladder), 3)

    def test_unresolved_target_fails_anywhere_in_tree(self) -> None:
        # The resolution check covers every skill's Next, not only the roster.
        self.fx.skill("q:outside", "anytime", "/q:renamed-away")
        rc, _, err = self.fx.run()
        self.assertEqual(rc, 1)
        self.assertIn(
            "unresolved: plugins/q/skills/outside/SKILL.md '## Next' names /q:renamed-away",
            err,
        )

    def test_missing_next_without_terminal_reason_fails(self) -> None:
        self.fx.skill("p:design", "design", None)
        self.fx.roster(
            "p:interview | entry: start",
            "p:design",
            "p:plan | entry: reached by hand in this fixture",
            "p:decompose",
            "p:implement | terminal: end",
        )
        rc, _, err = self.fx.run()
        self.assertEqual(rc, 1)
        self.assertIn("no-next: /p:design has no '## Next' section", err)

    def test_orphan_fails_and_entry_declaration_clears_it(self) -> None:
        self.fx.skill("p:questionnaire", "contract", "/p:interview")
        self.fx.roster(
            "p:interview | entry: start",
            "p:questionnaire",
            "p:design",
            "p:plan",
            "p:decompose",
            "p:implement | terminal: end",
        )
        rc, _, err = self.fx.run()
        self.assertEqual(rc, 1)
        self.assertIn("orphan: no chain skill's '## Next' names /p:questionnaire", err)

        self.fx.skill(
            "p:interview",
            "contract",
            "- Locked: /p:design.\n- A person holds it: /p:questionnaire.",
        )
        rc, _, err = self.fx.run()
        self.assertEqual(rc, 0, err)

    def test_self_edge_does_not_count_as_inbound(self) -> None:
        self.fx.skill(
            "p:wayfind", "contract", "- Charted: /p:wayfind work.\n- Closed: /p:design."
        )
        self.fx.roster(
            "p:interview | entry: start",
            "p:wayfind",
            "p:design",
            "p:plan",
            "p:decompose",
            "p:implement | terminal: end",
        )
        rc, _, err = self.fx.run()
        self.assertEqual(rc, 1)
        self.assertIn("orphan: no chain skill's '## Next' names /p:wayfind", err)

    def test_token_outside_next_and_inside_fence_is_ignored(self) -> None:
        self.fx.skill(
            "p:interview",
            "contract",
            "/p:design",
            extra="\nSee /p:nowhere in prose.\n\n```text\n## Next\n/p:also-nowhere\n```\n",
        )
        rc, _, err = self.fx.run()
        self.assertEqual(rc, 0, err)

    def test_stale_roster_line_fails(self) -> None:
        self.fx.roster(
            "p:interview | entry: start",
            "p:design",
            "p:plan",
            "p:decompose",
            "p:implement | terminal: end",
            "p:gone",
        )
        rc, _, err = self.fx.run()
        self.assertEqual(rc, 1)
        self.assertIn("stale-roster: scripts/next-graph-chain.txt names p:gone", err)

    def test_missing_ladder_exits_2(self) -> None:
        (
            self.fx.root / "plugins/session-flow/skills/workflow/context/steps.md"
        ).unlink()
        rc, out, err = self.fx.run()
        self.assertEqual(rc, 2)
        self.assertIn("cannot read the workflow ladder", err)
        self.assertEqual(out, "")

    def test_reshaped_ladder_exits_2(self) -> None:
        self.fx.write(
            "plugins/session-flow/skills/workflow/context/steps.md",
            "# Stages\n\n## Explore\n",
        )
        rc, _, err = self.fx.run()
        self.assertEqual(rc, 2)
        self.assertIn("no longer carries the numbered stage headings", err)

    def test_malformed_roster_declaration_exits_2(self) -> None:
        self.fx.roster("p:interview | start here")
        rc, _, err = self.fx.run()
        self.assertEqual(rc, 2)
        self.assertIn("a declaration is 'entry: <reason>' or 'terminal: <reason>'", err)


if __name__ == "__main__":
    unittest.main()
