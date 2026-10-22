"""The `cost-review-required` hold: a change that could add or raise a charge
waits for the owner (owner rule, 2026-10-22) unless the caller verified an
owner decision. Expected codes come from that rule, never from running the
scorer."""

from __future__ import annotations

import pathlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

from babysit_risk import COST_CODE, Risk, score
from test_babysit_risk import _codes, _file, _input

WORKFLOW = ".github/workflows/nightly.yml"
DECISION = "https://github.com/owner/repo/issues/40#issuecomment-1"


def _patch(*lines: str) -> str:
    return "@@ -1,1 +1,2 @@\n context\n" + "\n".join(lines)


def _cost(files, **kw):
    # The floor off: the cost hold must stand without it.
    return score(_input(files=tuple(files), high_floor=False, **kw))


class CostHold(unittest.TestCase):
    def test_infrastructure_as_code_holds_floor_or_not(self):
        for path in (
            "infra/Pulumi.yaml",
            "infra/Pulumi.prod.yaml",
            "infra/main.tf",
            "infra/prod.tfvars",
            "infra/main.bicep",
            "infra/main.bicepparam",
        ):
            with self.subTest(path=path):
                result = _cost([_file(path)])
                self.assertEqual(result.score, Risk.HIGH)
                self.assertIn(COST_CODE, _codes(result))

    def test_a_cited_owner_decision_clears_it(self):
        result = _cost([_file("infra/Pulumi.yaml")], cost_decision=DECISION)
        self.assertEqual(result.score, Risk.LOW)
        self.assertEqual(result.reasons, ())

    def test_a_non_cost_change_is_unchanged(self):
        self.assertEqual(score(_input()).reasons, ())
        docs = _file("docs/guide.md", patch=_patch("+runs-on: macos-26", "+cron: x"))
        self.assertNotIn(COST_CODE, _codes(_cost([docs])))

    def test_a_new_schedule_holds_on_a_public_repository(self):
        wf = _file(WORKFLOW, patch=_patch("+    - cron: '0 3 * * *'"))
        self.assertIn(COST_CODE, _codes(_cost([wf], public=True)))

    def test_a_larger_runner_holds_on_a_public_repository(self):
        for label in ("ubuntu-24.04-16-cores", "ubuntu-24.04-xlarge", "linux-gpu"):
            with self.subTest(label=label):
                wf = _file(WORKFLOW, patch=_patch(f"+    runs-on: {label}"))
                self.assertIn(COST_CODE, _codes(_cost([wf], public=True)))

    def test_standard_runners_are_free_on_a_public_repository(self):
        for label in ("ubuntu-24.04", "macos-26", "windows-2025"):
            with self.subTest(label=label):
                wf = _file(WORKFLOW, patch=_patch(f"+    runs-on: {label}"))
                self.assertNotIn(COST_CODE, _codes(_cost([wf], public=True)))

    def test_any_runner_or_macos_holds_unless_public(self):
        for public in (False, None):
            for line in ("+    runs-on: ubuntu-24.04", "+        os: [macos-26]"):
                with self.subTest(public=public, line=line):
                    wf = _file(WORKFLOW, patch=_patch(line))
                    self.assertIn(COST_CODE, _codes(_cost([wf], public=public)))

    def test_a_removed_line_does_not_hold(self):
        wf = _file(WORKFLOW, patch=_patch("-    - cron: '0 3 * * *'"))
        self.assertNotIn(COST_CODE, _codes(_cost([wf])))

    def test_a_workflow_with_no_patch_holds(self):
        wf = _file(WORKFLOW, has_patch=False)
        self.assertIn(COST_CODE, _codes(_cost([wf], public=True)))

    def test_model_spend_in_the_pipeline_config_holds(self):
        config = "docs/conventions/pr-pipeline.yaml"
        for line in (
            "+      model: opus",
            "+      effort: xhigh",
            "+    max-turns: 80",
        ):
            with self.subTest(line=line):
                held = _file(config, patch=_patch(line))
                self.assertIn(COST_CODE, _codes(_cost([held], public=True)))
        other = _file(config, patch=_patch("+  rung: C2"))
        self.assertNotIn(COST_CODE, _codes(_cost([other], public=True)))


MODEL_WORKFLOW = (
    "jobs:\n  judge:\n    steps:\n"
    "      - uses: melodic-software/ci-workflows/.github/actions/run-claude-cli@abc\n"
)


class ModelSpendDetections(unittest.TestCase):
    """S&C's four detections: credential reach, pipeline spend limits, a raised
    model-leg timeout, and a new model leg. Each holds only on a line that
    moves spend."""

    def test_an_added_model_credential_reference_holds(self):
        for name in (
            "AUTOMATIONS_CLAUDE_API_KEY",
            "LANES_CLAUDE_TOKEN",
            "CLAUDE_CODE_OAUTH_TOKEN",
            "OPENAI_API_KEY",
        ):
            with self.subTest(name=name):
                line = f"+          api-key: ${{{{ secrets.{name} }}}}"
                wf = _file(WORKFLOW, patch=_patch(line))
                self.assertIn(COST_CODE, _codes(_cost([wf], public=True)))

    def test_a_moved_or_unrelated_secret_does_not_hold(self):
        moved = _patch(
            "-          api-key: ${{ secrets.AUTOMATIONS_CLAUDE_API_KEY }}",
            "+        api-key: ${{ secrets.AUTOMATIONS_CLAUDE_API_KEY }}",
        )
        other = _patch("+          token: ${{ secrets.GITHUB_TOKEN }}")
        for patch in (moved, other):
            with self.subTest(patch=patch):
                wf = _file(WORKFLOW, patch=patch)
                self.assertNotIn(COST_CODE, _codes(_cost([wf], public=True)))

    def test_a_changed_spend_limit_in_the_pipeline_config_holds(self):
        config = "docs/conventions/pr-pipeline.yaml"
        for line in (
            "+  review-rounds: 4",
            "-  turn-cap-restarts: 1",
            "+  restarts-per-run: 6",
            "+  fix-ci-restarts: 2",
            "+  admission-factor: 1.0",
            "+  admission-min-per-hour: 3",
            "+  wip-cap: 20",
            "+  min-cap: 20",
            "+  held-cap: 20",
            '+  pause-from: ""',
            "+    leg-timeout-minutes: 60",
            "+    credential: subscription",
        ):
            with self.subTest(line=line):
                held = _file(config, patch=_patch(line))
                self.assertIn(COST_CODE, _codes(_cost([held], public=True)))

    def test_other_pipeline_keys_do_not_hold(self):
        config = "docs/conventions/pr-pipeline.yaml"
        for line in (
            "+  quarantine-days: 7",
            "+  report-only: false",
            "+  # wip-cap: 9",
        ):
            with self.subTest(line=line):
                other = _file(config, patch=_patch(line))
                self.assertNotIn(COST_CODE, _codes(_cost([other], public=True)))

    def test_a_raised_timeout_on_a_model_workflow_holds(self):
        for patch in (
            _patch("+    timeout-minutes: 45"),
            _patch("-    timeout-minutes: 30", "+    timeout-minutes: 45"),
            _patch(
                "-          leg-timeout-minutes: 10",
                "+          leg-timeout-minutes: 20",
            ),
        ):
            with self.subTest(patch=patch):
                wf = _file(WORKFLOW, patch=patch, contents=("", MODEL_WORKFLOW))
                self.assertIn(COST_CODE, _codes(_cost([wf], public=True)))

    def test_a_lowered_timeout_or_a_timeout_on_another_workflow_does_not_hold(self):
        lowered = _patch("-    timeout-minutes: 45", "+    timeout-minutes: 30")
        wf = _file(WORKFLOW, patch=lowered, contents=("", MODEL_WORKFLOW))
        self.assertNotIn(COST_CODE, _codes(_cost([wf], public=True)))
        raised = _patch("+    timeout-minutes: 45")
        plain = _file(WORKFLOW, patch=raised, contents=("", "jobs: {}\n"))
        self.assertNotIn(COST_CODE, _codes(_cost([plain], public=True)))

    def test_a_raised_timeout_on_an_unread_workflow_holds(self):
        raised = _patch("+    timeout-minutes: 45")
        wf = _file(WORKFLOW, patch=raised, contents=None)
        self.assertIn(COST_CODE, _codes(_cost([wf], public=True)))

    def test_a_new_model_leg_holds(self):
        for action in (
            "melodic-software/ci-workflows/.github/actions/run-claude-cli@abc",
            "anthropics/claude-code-action@abc",
        ):
            with self.subTest(action=action):
                wf = _file(WORKFLOW, patch=_patch(f"+      - uses: {action}"))
                self.assertIn(COST_CODE, _codes(_cost([wf], public=True)))

    def test_a_repinned_model_leg_does_not_hold(self):
        bump = _patch(
            "-      - uses: anthropics/claude-code-action@aaa # v1",
            "+      - uses: anthropics/claude-code-action@bbb # v1.1",
        )
        wf = _file(WORKFLOW, patch=bump, contents=("", MODEL_WORKFLOW))
        self.assertNotIn(COST_CODE, _codes(_cost([wf], public=True)))


if __name__ == "__main__":
    unittest.main()
