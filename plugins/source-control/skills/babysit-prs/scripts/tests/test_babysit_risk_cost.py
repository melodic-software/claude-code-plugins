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

    def test_a_moved_secret_does_not_hold(self):
        moved = _patch(
            "-          api-key: ${{ secrets.AUTOMATIONS_CLAUDE_API_KEY }}",
            "+        api-key: ${{ secrets.AUTOMATIONS_CLAUDE_API_KEY }}",
        )
        wf = _file(WORKFLOW, patch=moved)
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

    def test_safe_pipeline_lines_do_not_hold(self):
        config = "docs/conventions/pr-pipeline.yaml"
        for patch in (
            _patch("+  # wip-cap: 9"),
            _patch("+"),
            _patch("+    description: Fixes prose."),
            _patch("-  review-rounds: 3 # old note", "+  review-rounds: 3 # new note"),
        ):
            with self.subTest(patch=patch):
                other = _file(config, patch=patch)
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


def _runner(value: str, public: bool | None = True) -> list[str]:
    """Codes for a workflow whose head text gains `runs-on: <value>`."""
    head = f"jobs:\n  build:\n    runs-on: {value}\n    steps: []\n"
    wf = _file(WORKFLOW, patch=_patch(f"+    runs-on: {value}"), contents=("", head))
    return list(_codes(_cost([wf], public=public)))


class ReviewFindings(unittest.TestCase):
    """poteto's review of the first cut: each evasion it found now holds."""

    def test_adoption_does_not_exempt_a_cost_change(self):
        tf = _file("infra/main.tf")
        codes = _codes(_cost([tf], floor_exempt=frozenset({"infra/main.tf"})))
        self.assertIn(COST_CODE, codes)

    def test_a_file_renamed_into_a_workflow_or_pipeline_path_holds(self):
        for path in (WORKFLOW, "docs/conventions/pr-pipeline.yaml"):
            with self.subTest(path=path):
                moved = _file(
                    path,
                    status="renamed",
                    previous_path="docs/draft.yml",
                    patch=_patch("+  name: x"),
                )
                self.assertIn(COST_CODE, _codes(_cost([moved], public=True)))
        within = _file(
            WORKFLOW,
            status="renamed",
            previous_path=".github/workflows/old.yml",
            patch=_patch("+  name: x"),
            contents=("", "jobs: {}\n"),
        )
        self.assertNotIn(COST_CODE, _codes(_cost([within], public=True)))

    def test_a_flow_style_schedule_holds(self):
        for line in (
            "+  schedule: [{cron: '0 3 * * *'}]",
            "+on: {schedule: [{cron: '0 3 * * *'}]}",
            '+  "cron": "0 3 * * *"',
        ):
            with self.subTest(line=line):
                wf = _file(WORKFLOW, patch=_patch(line))
                self.assertIn(COST_CODE, _codes(_cost([wf], public=True)))

    def test_a_non_literal_or_unlisted_runner_holds_on_a_public_repository(self):
        for value in (
            "${{ vars.RUNNER }}",
            "${{ format('{0}-xl', 'ubuntu') }}",
            "big-runner",
            "ubuntu-24.04-16-cores",
            "[gpu-a100]",
        ):
            with self.subTest(value=value):
                self.assertIn(COST_CODE, _runner(value))

    def test_a_runner_group_or_labels_mapping_holds(self):
        head = (
            "jobs:\n  build:\n    runs-on:\n      group: larger-runners\n"
            "      labels: ubuntu-24.04\n    steps: []\n"
        )
        patch = _patch(
            "+    runs-on:",
            "+      group: larger-runners",
            "+      labels: ubuntu-24.04",
        )
        wf = _file(WORKFLOW, patch=patch, contents=("", head))
        self.assertIn(COST_CODE, _codes(_cost([wf], public=True)))

    def test_free_standard_runners_do_not_hold_on_a_public_repository(self):
        for value in (
            "ubuntu-24.04",
            "ubuntu-latest",
            "ubuntu-24.04-arm",
            "windows-2025",
            "macos-26",
            "melodic-ubuntu-24.04-x64",
            "[ubuntu-24.04]",
            "[self-hosted, gpu-a100]",
        ):
            with self.subTest(value=value):
                self.assertNotIn(COST_CODE, _runner(value))

    def test_an_existing_runner_expression_does_not_hold(self):
        base = "jobs:\n  build:\n    runs-on: ${{ inputs.runner }}\n"
        wf = _file(
            WORKFLOW,
            patch=_patch("+    timeout-minutes: 5"),
            contents=(base, base + "    timeout-minutes: 5\n"),
        )
        self.assertNotIn(COST_CODE, _codes(_cost([wf], public=True)))

    def test_the_runner_check_reads_runs_on_values_only(self):
        wf = _file(
            WORKFLOW,
            patch=_patch("+        run: git lfs pull --include=assets-large"),
            contents=("", "jobs: {}\n"),
        )
        self.assertNotIn(COST_CODE, _codes(_cost([wf], public=True)))

    def test_a_concurrency_group_does_not_hold(self):
        head = "concurrency:\n  group: ${{ github.ref }}\njobs: {}\n"
        wf = _file(
            WORKFLOW, patch=_patch("+  group: ${{ github.ref }}"), contents=("", head)
        )
        self.assertNotIn(COST_CODE, _codes(_cost([wf], public=True)))

    def test_windows_or_macos_in_a_matrix_holds_on_a_private_repository(self):
        for line in ("+        os: [windows-2025]", "+          - macos-26"):
            with self.subTest(line=line):
                wf = _file(WORKFLOW, patch=_patch(line), contents=("", "jobs: {}\n"))
                self.assertIn(COST_CODE, _codes(_cost([wf], public=False)))

    def test_model_flags_in_a_workflow_hold(self):
        for line in (
            "+          claude_args: --model opus",
            "+          claude_args: --max-turns 200",
        ):
            with self.subTest(line=line):
                wf = _file(WORKFLOW, patch=_patch(line), contents=("", "jobs: {}\n"))
                self.assertIn(COST_CODE, _codes(_cost([wf], public=True)))

    def test_a_file_under_a_pulumi_project_holds(self):
        program = _file("infra/Program.cs")
        held = _cost([program], pulumi_dirs=("infra",))
        self.assertIn(COST_CODE, _codes(held))
        root = _cost([_file("README.md")], pulumi_dirs=("",))
        self.assertIn(COST_CODE, _codes(root))
        elsewhere = _cost([_file("docs/x.md")], pulumi_dirs=("infra",))
        self.assertNotIn(COST_CODE, _codes(elsewhere))


class SecurityAndCostHolds(unittest.TestCase):
    """S&C's hold findings at f5d53282: each shape its probe passed now holds."""

    def _wf(self, *lines, contents=("", "jobs: {}\n")):
        return _file(WORKFLOW, patch=_patch(*lines), contents=contents)

    def test_any_pipeline_change_off_the_safe_list_holds(self):
        config = "docs/conventions/pr-pipeline.yaml"
        for patch in (
            _patch("+  review: {review-rounds: 9}"),
            _patch('+      "model": opus'),
            _patch("+    verify-pr: code-xhigh", "-    verify-pr: review"),
            _patch("+        base-turns: 900", "-        base-turns: 75"),
            _patch("+      large: run", "-      large: split"),
            _patch("+    max-in-flight: 50", "-    max-in-flight: 2"),
            _patch("+      - activity: verify-pr"),
            _patch("+      max-turns: *big"),
            _patch("+  quarantine-days: 7"),
        ):
            with self.subTest(patch=patch):
                held = _file(config, patch=patch)
                self.assertIn(COST_CODE, _codes(_cost([held], public=True)))

    def test_a_value_swap_between_pipeline_profiles_holds(self):
        config = "docs/conventions/pr-pipeline.yaml"
        swap = (
            "@@ -10,3 +10,3 @@\n   review:\n-    max-turns: 60\n+    max-turns: 10\n"
            "@@ -20,3 +20,3 @@\n   summary:\n-    max-turns: 10\n+    max-turns: 60"
        )
        held = _file(config, patch=swap)
        self.assertIn(COST_CODE, _codes(_cost([held], public=True)))

    def test_any_net_new_secret_reference_holds(self):
        for line in (
            "+  KEY: ${{ secrets['ANTHROPIC_API_KEY'] }}",
            "+  ALL: ${{ toJSON(secrets) }}",
            "+    secrets: inherit",
            "+  K: ${{ secrets.ANTHROPIC_KEY }}",
            "+  K: ${{ secrets.LANE_TOKEN }}",
            "+  K: ${{ secrets.claude_x }}",
        ):
            with self.subTest(line=line):
                self.assertIn(COST_CODE, _codes(_cost([self._wf(line)], public=True)))

    def test_claude_actions_match_in_any_case_and_any_claude_code_name(self):
        for line in (
            "+      - uses: Anthropics/Claude-Code-Action@v1",
            "+      - uses: anthropics/claude-code-base-action@v1",
            "+      - uses: docker://ghcr.io/anthropics/claude-code:latest",
            "+      - uses: Org/Repo/.github/actions/Run-Claude-CLI@abc",
        ):
            with self.subTest(line=line):
                self.assertIn(COST_CODE, _codes(_cost([self._wf(line)], public=True)))

    def test_a_run_line_invoking_the_claude_code_package_holds(self):
        wf = self._wf("+        run: npx @anthropic-ai/claude-code -p hi")
        self.assertIn(COST_CODE, _codes(_cost([wf], public=True)))

    def test_a_raised_timeout_holds_on_a_claude_code_base_action_workflow(self):
        head = "jobs:\n  a:\n    steps:\n      - uses: Anthropics/Claude-Code-Base-Action@v1\n"
        wf = self._wf(
            "-    timeout-minutes: 30",
            "+    timeout-minutes: 45",
            contents=(head, head),
        )
        self.assertIn(COST_CODE, _codes(_cost([wf], public=True)))

    def test_the_multi_agent_role_defaults_hold(self):
        defaults = _file(
            "plugins/multi-agent/reference/defaults.yaml",
            patch=_patch("+  model: fable", "-  model: opus"),
        )
        self.assertIn(COST_CODE, _codes(_cost([defaults])))

    def test_an_unlisted_base_tree_fails_closed(self):
        result = _cost([_file("infra/Program.cs")], pulumi_dirs=None)
        self.assertIn(COST_CODE, _codes(result))


if __name__ == "__main__":
    unittest.main()
