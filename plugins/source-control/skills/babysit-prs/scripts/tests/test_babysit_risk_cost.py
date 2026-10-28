"""The `cost-review-required` hold: a change that could start a real charge
(billed infrastructure or billed runner minutes) waits for the owner unless
the caller verified an owner decision. Spend that draws only on a
subscription or prepaid credit (a schedule, a model flag or leg, a secret
reference, a pipeline spend line, a raised timeout on a public repository) is
the reported, non-holding `cost-finding` (owner rule 2026-10-26: cost is not
a stop, only a real new charge is). Expected codes come from those rules,
never from running the scorer."""

from __future__ import annotations

import pathlib
import sys
import unittest
from unittest import mock

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

import babysit_risk
from babysit_risk import (
    AGENT_SURFACE_CODE,
    COST_CODE,
    COST_FINDING_CODE,
    PERMISSION_WIDENING_CODE,
    PRIVILEGED_TRIGGER_CODE,
    SECRET_EXPOSURE_CODE,
    Risk,
    holding,
    holds,
    person_reasons,
    score,
)
from test_babysit_risk import _codes, _file, _input

WORKFLOW = ".github/workflows/nightly.yml"
DECISION = "https://github.com/owner/repo/issues/40#issuecomment-1"


def _patch(*lines: str) -> str:
    return "@@ -1,1 +1,2 @@\n context\n" + "\n".join(lines)


def _cost(files, **kw):
    # The floor off: the cost hold must stand without it.
    return score(_input(files=tuple(files), high_floor=False, **kw))


class _Finding(unittest.TestCase):
    def assertReported(self, result):
        """Subscription or prepaid spend: reported, never a hold. This
        repository's own pr-pipeline.yaml is also a floor path, which holds on
        its own account."""
        codes = _codes(result)
        self.assertIn(COST_FINDING_CODE, codes)
        self.assertNotIn(COST_CODE, codes)
        held = [r.code for r in holding(result)]
        self.assertNotIn(COST_FINDING_CODE, held)
        self.assertEqual(
            [c for c in held if not c.startswith("high-path:")], [], result.reasons
        )

    def assertSecurityHold(self, result, code):
        """A credential or agent-surface change: a person's hold, never cost."""
        codes = _codes(result)
        self.assertIn(code, codes)
        self.assertNotIn(COST_CODE, codes)
        self.assertNotIn(COST_FINDING_CODE, codes)
        self.assertIn(code, [r.code for r in person_reasons(holding(result))])


class CostHold(_Finding):
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

    def test_a_new_schedule_holds_unless_public(self):
        # A schedule runs hosted minutes, billed off a public repository.
        wf = _file(WORKFLOW, patch=_patch("+    - cron: '0 3 * * *'"))
        self.assertReported(_cost([wf], public=True))
        for public in (False, None):
            with self.subTest(public=public):
                self.assertIn(COST_CODE, _codes(_cost([wf], public=public)))

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

    def test_model_spend_in_the_pipeline_config_is_reported(self):
        config = "docs/conventions/pr-pipeline.yaml"
        for line in (
            "+      model: opus",
            "+      effort: xhigh",
            "+    max-turns: 80",
        ):
            with self.subTest(line=line):
                reported = _file(config, patch=_patch(line))
                self.assertReported(_cost([reported], public=True))


MODEL_WORKFLOW = (
    "permissions: {}\njobs:\n  judge:\n    steps:\n"
    "      - uses: melodic-software/ci-workflows/.github/actions/run-claude-cli@abc\n"
)


class ModelSpendDetections(_Finding):
    """S&C's four detections: credential reach, pipeline spend limits, a raised
    model-leg timeout, and a new model leg. Each reports only a line that
    moves spend, and holds only where it starts a real charge."""

    def test_an_added_model_credential_reference_holds_for_security(self):
        for name in (
            "AUTOMATIONS_CLAUDE_API_KEY",
            "LANES_CLAUDE_TOKEN",
            "CLAUDE_CODE_OAUTH_TOKEN",
            "OPENAI_API_KEY",
        ):
            with self.subTest(name=name):
                line = f"+          api-key: ${{{{ secrets.{name} }}}}"
                wf = _file(WORKFLOW, patch=_patch(line))
                self.assertSecurityHold(_cost([wf], public=True), SECRET_EXPOSURE_CODE)

    def test_a_moved_secret_does_not_hold(self):
        moved = _patch(
            "-          api-key: ${{ secrets.AUTOMATIONS_CLAUDE_API_KEY }}",
            "+        api-key: ${{ secrets.AUTOMATIONS_CLAUDE_API_KEY }}",
        )
        wf = _file(WORKFLOW, patch=moved)
        codes = _codes(_cost([wf], public=True))
        self.assertNotIn(COST_CODE, codes)
        self.assertNotIn(COST_FINDING_CODE, codes)
        self.assertNotIn(SECRET_EXPOSURE_CODE, codes)

    def test_a_changed_spend_limit_in_the_pipeline_config_is_reported(self):
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
                reported = _file(config, patch=_patch(line))
                self.assertReported(_cost([reported], public=True))

    def test_a_turn_share_line_as_in_10224_is_reported_not_held(self):
        # #10224 added a tidy activity whose `turn-share: 25` moves only
        # subscription spend; it was held as a cost.
        config = "docs/conventions/pr-pipeline.yaml"
        patch = _patch(
            "+    tidy:",
            "+      entry: code-tidying:tidy-diff",
            "+      turn-share: 25",
            "+      cutoffs:",
            "+        max-files: 10",
        )
        result = _cost([_file(config, patch=patch)], public=True)
        self.assertReported(result)
        self.assertEqual(
            [r.code for r in person_reasons(holding(result))],
            [f"high-path:{config}"],
        )
        consumer = _file("conventions/pr-pipeline.yaml", patch=patch)
        result = _cost([consumer], public=True)
        self.assertReported(result)
        self.assertFalse(holds(result), result.reasons)

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
                codes = _codes(_cost([other], public=True))
                self.assertNotIn(COST_CODE, codes)
                self.assertNotIn(COST_FINDING_CODE, codes)

    def test_a_raised_timeout_on_a_model_workflow(self):
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
                # Free minutes on a public repository; billed ones elsewhere.
                self.assertReported(_cost([wf], public=True))
                for public in (False, None):
                    self.assertIn(COST_CODE, _codes(_cost([wf], public=public)))

    def test_a_lowered_timeout_or_a_timeout_on_another_workflow_does_not_hold(self):
        lowered = _patch("-    timeout-minutes: 45", "+    timeout-minutes: 30")
        wf = _file(WORKFLOW, patch=lowered, contents=("", MODEL_WORKFLOW))
        self.assertNotIn(COST_CODE, _codes(_cost([wf], public=True)))
        raised = _patch("+    timeout-minutes: 45")
        plain = _file(WORKFLOW, patch=raised, contents=("", "jobs: {}\n"))
        self.assertNotIn(COST_CODE, _codes(_cost([plain], public=True)))

    def test_a_raised_timeout_on_an_unread_workflow(self):
        raised = _patch("+    timeout-minutes: 45")
        wf = _file(WORKFLOW, patch=raised, contents=None)
        result = _cost([wf], public=True)
        self.assertIn(COST_FINDING_CODE, _codes(result))
        self.assertNotIn(COST_CODE, _codes(result))
        # Unread text cannot show the token did not widen: a person's hold.
        self.assertIn(
            PERMISSION_WIDENING_CODE, [r.code for r in person_reasons(holding(result))]
        )
        self.assertIn(COST_CODE, _codes(_cost([wf], public=None)))

    def test_a_raised_artifact_retention_holds_unless_public(self):
        # Artifact storage past the free quota bills on a private repository;
        # Actions use on a public one is free.
        for patch in (
            _patch("+          retention-days: 120"),
            _patch("-          retention-days: 5", "+          retention-days: 30"),
        ):
            with self.subTest(patch=patch):
                wf = _file(WORKFLOW, patch=patch, contents=("", "jobs: {}\n"))
                for public in (False, None):
                    self.assertIn(COST_CODE, _codes(_cost([wf], public=public)))
                self.assertReported(_cost([wf], public=True))

    def test_an_added_retention_within_the_default_does_not_count(self):
        # GitHub keeps artifacts 90 days by default, so 7 stores less.
        wf = _file(
            WORKFLOW,
            patch=_patch("+          retention-days: 7"),
            contents=("", "jobs: {}\n"),
        )
        for public in (True, False, None):
            codes = _codes(_cost([wf], public=public))
            self.assertNotIn(COST_CODE, codes)
            self.assertNotIn(COST_FINDING_CODE, codes)

    def test_a_lowered_artifact_retention_does_not_count(self):
        lowered = _patch(
            "-          retention-days: 30", "+          retention-days: 5"
        )
        wf = _file(WORKFLOW, patch=lowered, contents=("", "jobs: {}\n"))
        for public in (True, False):
            codes = _codes(_cost([wf], public=public))
            self.assertNotIn(COST_CODE, codes)
            self.assertNotIn(COST_FINDING_CODE, codes)

    def test_a_new_model_leg_holds_for_security(self):
        for action in (
            "melodic-software/ci-workflows/.github/actions/run-claude-cli@abc",
            "anthropics/claude-code-action@abc",
        ):
            with self.subTest(action=action):
                wf = _file(WORKFLOW, patch=_patch(f"+      - uses: {action}"))
                self.assertSecurityHold(_cost([wf], public=True), AGENT_SURFACE_CODE)

    def test_a_repinned_model_leg_does_not_hold(self):
        bump = _patch(
            "-      - uses: anthropics/claude-code-action@aaa # v1",
            "+      - uses: anthropics/claude-code-action@bbb # v1.1",
        )
        wf = _file(WORKFLOW, patch=bump, contents=("", MODEL_WORKFLOW))
        codes = _codes(_cost([wf], public=True))
        self.assertNotIn(COST_CODE, codes)
        self.assertNotIn(AGENT_SURFACE_CODE, codes)


def _runner(value: str, public: bool | None = True) -> list[str]:
    """Codes for a workflow whose head text gains `runs-on: <value>`."""
    head = f"jobs:\n  build:\n    runs-on: {value}\n    steps: []\n"
    wf = _file(WORKFLOW, patch=_patch(f"+    runs-on: {value}"), contents=("", head))
    return list(_codes(_cost([wf], public=public)))


class ReviewFindings(_Finding):
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

    def test_a_flow_style_schedule_is_reported(self):
        for line in (
            "+  schedule: [{cron: '0 3 * * *'}]",
            "+on: {schedule: [{cron: '0 3 * * *'}]}",
            '+  "cron": "0 3 * * *"',
        ):
            with self.subTest(line=line):
                wf = _file(WORKFLOW, patch=_patch(line))
                self.assertReported(_cost([wf], public=True))

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

    def test_model_flags_in_a_workflow_are_reported(self):
        for line in (
            "+          claude_args: --model opus",
            "+          claude_args: --max-turns 200",
        ):
            with self.subTest(line=line):
                wf = _file(WORKFLOW, patch=_patch(line), contents=("", "jobs: {}\n"))
                self.assertReported(_cost([wf], public=True))

    def test_a_file_under_a_pulumi_project_holds(self):
        program = _file("infra/Program.cs")
        held = _cost([program], pulumi_dirs=("infra",))
        self.assertIn(COST_CODE, _codes(held))
        root = _cost([_file("README.md")], pulumi_dirs=("",))
        self.assertIn(COST_CODE, _codes(root))
        elsewhere = _cost([_file("docs/x.md")], pulumi_dirs=("infra",))
        self.assertNotIn(COST_CODE, _codes(elsewhere))


class SecurityAndCostHolds(_Finding):
    """S&C's hold findings at f5d53282: each shape its probe passed now holds."""

    def _wf(self, *lines, contents=("", "jobs: {}\n")):
        return _file(WORKFLOW, patch=_patch(*lines), contents=contents)

    def test_any_pipeline_change_off_the_safe_list_is_reported(self):
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
                reported = _file(config, patch=patch)
                self.assertReported(_cost([reported], public=True))

    def test_a_value_swap_between_pipeline_profiles_is_reported(self):
        config = "docs/conventions/pr-pipeline.yaml"
        swap = (
            "@@ -10,3 +10,3 @@\n   review:\n-    max-turns: 60\n+    max-turns: 10\n"
            "@@ -20,3 +20,3 @@\n   summary:\n-    max-turns: 10\n+    max-turns: 60"
        )
        self.assertReported(_cost([_file(config, patch=swap)], public=True))

    def test_any_net_new_secret_reference_holds_for_security(self):
        for line in (
            "+  KEY: ${{ secrets['ANTHROPIC_API_KEY'] }}",
            "+  ALL: ${{ toJSON(secrets) }}",
            "+    secrets: inherit",
            "+  K: ${{ secrets.ANTHROPIC_KEY }}",
            "+  K: ${{ secrets.LANE_TOKEN }}",
            "+  K: ${{ secrets.claude_x }}",
        ):
            with self.subTest(line=line):
                result = _cost([self._wf(line)], public=True)
                self.assertSecurityHold(result, SECRET_EXPOSURE_CODE)

    def test_claude_actions_match_in_any_case_and_any_claude_code_name(self):
        for line in (
            "+      - uses: Anthropics/Claude-Code-Action@v1",
            "+      - uses: anthropics/claude-code-base-action@v1",
            "+      - uses: docker://ghcr.io/anthropics/claude-code:latest",
            "+      - uses: Org/Repo/.github/actions/Run-Claude-CLI@abc",
        ):
            with self.subTest(line=line):
                result = _cost([self._wf(line)], public=True)
                self.assertSecurityHold(result, AGENT_SURFACE_CODE)

    def test_a_run_line_invoking_the_claude_code_package_holds_for_security(self):
        wf = self._wf("+        run: npx @anthropic-ai/claude-code -p hi")
        self.assertSecurityHold(_cost([wf], public=True), AGENT_SURFACE_CODE)

    def test_a_raised_timeout_on_a_claude_code_base_action_workflow(self):
        head = "permissions: {}\njobs:\n  a:\n    steps:\n      - uses: Anthropics/Claude-Code-Base-Action@v1\n"
        wf = self._wf(
            "-    timeout-minutes: 30",
            "+    timeout-minutes: 45",
            contents=(head, head),
        )
        self.assertReported(_cost([wf], public=True))
        self.assertIn(COST_CODE, _codes(_cost([wf], public=False)))

    def test_the_multi_agent_role_defaults_are_no_charge(self):
        # Owner ruling 2026-10-24: only a real charge holds; the review lanes
        # judge a model or effort default.
        defaults = _file(
            "plugins/multi-agent/reference/defaults.yaml",
            patch=_patch("+  model: fable", "-  model: opus"),
        )
        self.assertNotIn(COST_CODE, _codes(_cost([defaults])))
        self.assertIn(COST_CODE, _codes(_cost([_file("infra/main.tf")])))

    def test_a_real_charge_beside_subscription_spend_holds_and_reports(self):
        wf = _file(WORKFLOW, patch=_patch("+    - cron: '0 3 * * *'"))
        result = _cost([wf, _file("infra/main.tf")], public=True)
        self.assertIn(COST_CODE, _codes(result))
        self.assertIn(COST_FINDING_CODE, _codes(result))
        self.assertTrue(holds(result))

    def test_an_owner_decision_clears_the_hold_and_keeps_the_finding(self):
        wf = _file(WORKFLOW, patch=_patch("+    - cron: '0 3 * * *'"))
        files = [wf, _file("infra/main.tf")]
        result = _cost(files, public=True, cost_decision=DECISION)
        self.assertEqual(_codes(result), (COST_FINDING_CODE,))
        self.assertFalse(holds(result))

    def test_an_owner_cost_decision_does_not_clear_a_security_hold(self):
        wf = self._wf(
            "+  K: ${{ secrets.LANE_TOKEN }}",
            "+      - uses: anthropics/claude-code-action@abc",
        )
        result = _cost([wf], public=True, cost_decision=DECISION)
        self.assertSecurityHold(result, SECRET_EXPOSURE_CODE)
        self.assertSecurityHold(result, AGENT_SURFACE_CODE)

    def test_an_unlisted_base_tree_fails_closed(self):
        result = _cost([_file("infra/Program.cs")], pulumi_dirs=None)
        self.assertIn(COST_CODE, _codes(result))


def _workflow(perms: str, job_perms: str = "", on: str = "on: push\n") -> str:
    """Workflow text: `perms` at the top level, `job_perms` on its one job."""
    return f"{on}{perms}jobs:\n  build:\n{job_perms}    runs-on: ubuntu-24.04\n"


READ_ONLY = _workflow("permissions:\n  contents: read\n")


class WorkflowPrivilegeHolds(_Finding):
    """A workflow change that widens its token or adds a privileged trigger is
    a person's hold (owner direction 2026-10-28: an AI review alone must not
    clear it), and no cost decision clears it."""

    def _change(self, base, head, patch="", status="modified", **kw):
        wf = _file(WORKFLOW, status=status, patch=patch, contents=(base, head))
        return _cost([wf], public=True, **kw)

    def assertHeld(self, result, code):
        self.assertIn(code, [r.code for r in person_reasons(holding(result))])

    def assertNotHeld(self, result, code):
        self.assertNotIn(code, _codes(result))

    def test_a_scope_raised_to_write_holds(self):
        head = _workflow("permissions:\n  contents: write\n")
        self.assertHeld(self._change(READ_ONLY, head), PERMISSION_WIDENING_CODE)

    def test_write_all_and_a_flow_mapping_grant_hold(self):
        for head in (
            _workflow("permissions: write-all\n"),
            _workflow("permissions: { contents: read, issues: write }\n"),
            _workflow("permissions: {}\n", "    permissions:\n      id-token: write\n"),
        ):
            with self.subTest(head=head):
                self.assertHeld(self._change(READ_ONLY, head), PERMISSION_WIDENING_CODE)

    def test_dropping_the_permissions_block_holds(self):
        # The job then runs on the repository default, which may write.
        self.assertHeld(
            self._change(READ_ONLY, _workflow("")), PERMISSION_WIDENING_CODE
        )

    def test_a_new_workflow_that_writes_holds_and_a_read_only_one_does_not(self):
        added = self._change(
            None, _workflow("permissions:\n  pull-requests: write\n"), status="added"
        )
        self.assertHeld(added, PERMISSION_WIDENING_CODE)
        quiet = self._change(None, _workflow("permissions: read-all\n"), status="added")
        self.assertNotHeld(quiet, PERMISSION_WIDENING_CODE)
        self.assertNotHeld(quiet, PRIVILEGED_TRIGGER_CODE)

    def test_lowering_or_keeping_a_scope_does_not_hold(self):
        writes = _workflow("permissions:\n  contents: write\n")
        self.assertNotHeld(self._change(writes, READ_ONLY), PERMISSION_WIDENING_CODE)
        same = writes.replace("on: push\n", "on: push\nname: renamed\n")
        self.assertNotHeld(self._change(writes, same), PERMISSION_WIDENING_CODE)

    def test_an_added_privileged_trigger_holds(self):
        for on in (
            "on: pull_request_target\n",
            "on: [push, workflow_run]\n",
            "on:\n  push:\n  workflow_run:\n    workflows: [ci]\n",
        ):
            with self.subTest(on=on):
                head = _workflow("permissions: {}\n", on=on)
                base = _workflow("permissions: {}\n")
                self.assertHeld(self._change(base, head), PRIVILEGED_TRIGGER_CODE)

    def test_an_existing_trigger_its_expressions_and_comments_do_not_hold(self):
        on = "on:\n  workflow_run:\n    workflows: [ci]\n"
        base = _workflow("permissions: {}\n", on=on)
        patch = _patch(
            "+    if: github.event.workflow_run.conclusion == 'success'",
            "+# pull_request_target would run the base copy; we do not use it",
        )
        result = self._change(base, base, patch=patch)
        self.assertNotHeld(result, PRIVILEGED_TRIGGER_CODE)
        self.assertNotHeld(result, PERMISSION_WIDENING_CODE)

    def test_an_added_trigger_line_holds_even_when_the_text_reads_alike(self):
        # The raw-text backstop: the patch adds the trigger whatever the text.
        base = _workflow("permissions: {}\n")
        result = self._change(base, base, patch=_patch("+  pull_request_target:"))
        self.assertHeld(result, PRIVILEGED_TRIGGER_CODE)
        result = self._change(base, base, patch=_patch("+      issues: write"))
        self.assertHeld(result, PERMISSION_WIDENING_CODE)

    def test_unreadable_text_holds(self):
        for head in (
            "on: push\non: pull_request\njobs: {}\n",
            "x: &a 1\ny: *a\njobs: {}\n",
            "on: push\njobs: [1]\n",
        ):
            with self.subTest(head=head):
                self.assertHeld(self._change(READ_ONLY, head), PERMISSION_WIDENING_CODE)

    def test_a_cost_decision_or_a_skipped_cost_branch_does_not_clear_it(self):
        head = _workflow("permissions: write-all\n", on="on: pull_request_target\n")
        for kw in ({"cost_decision": DECISION}, {"pulumi_dirs": None}):
            with self.subTest(kw=kw):
                result = self._change(READ_ONLY, head, **kw)
                self.assertHeld(result, PERMISSION_WIDENING_CODE)
                self.assertHeld(result, PRIVILEGED_TRIGGER_CODE)

    def test_a_secret_the_head_text_gains_holds_without_a_patch(self):
        head = READ_ONLY + "    env:\n      K: ${{ secrets.DEPLOY_KEY }}\n"
        wf = _file(WORKFLOW, has_patch=False, patch=None, contents=(READ_ONLY, head))
        result = _cost([wf], public=True, cost_decision=DECISION)
        self.assertHeld(result, SECRET_EXPOSURE_CODE)


class WorkflowPrivilegeHoldsWithoutYaml(WorkflowPrivilegeHolds):
    """The same holds where PyYAML is not installed: the raw-text reading."""

    def setUp(self):
        patcher = mock.patch.object(babysit_risk, "_yaml", return_value=None)
        patcher.start()
        self.addCleanup(patcher.stop)


if __name__ == "__main__":
    unittest.main()
