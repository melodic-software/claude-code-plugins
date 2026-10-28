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

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

from babysit_risk import (
    AGENT_SURFACE_CODE,
    COST_CODE,
    COST_FINDING_CODE,
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
    "jobs:\n  judge:\n    steps:\n"
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
        self.assertReported(_cost([wf], public=True))
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
        head = "jobs:\n  a:\n    steps:\n      - uses: Anthropics/Claude-Code-Base-Action@v1\n"
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


def _jobs(a: str, b: str = "300", steps: str = "") -> str:
    """Two jobs, `a` with a model leg, at the timeouts given ("" for none)."""
    a_line = f"    timeout-minutes: {a}\n" if a else ""
    b_line = f"    timeout-minutes: {b}\n" if b else ""
    return (
        "jobs:\n  a:\n    runs-on: ubuntu-24.04\n" + a_line + "    steps:\n" + steps
        + "      - uses: anthropics/claude-code-action@v1\n"
        "  b:\n    runs-on: ubuntu-24.04\n" + b_line + "    steps: []\n"
    )  # fmt: skip


class LowRatedShapes(_Finding):
    """S&C's LOW-rated probe rows on #9224 (#9241): the timeout and model-leg
    shapes it held, the secret and runner gaps in checks the hold makes, and
    the accepted move."""

    def assertCharge(self, wf):
        """Billed minutes off a public repository; free ones on it."""
        for public in (False, None):
            with self.subTest(public=public):
                self.assertIn(COST_CODE, _codes(_cost([wf], public=public)))
        self.assertReported(_cost([wf], public=True))

    def test_one_jobs_raise_is_not_hidden_by_another_jobs_value(self):
        # 30 to 200 on `a`, with `b`'s unchanged 300 removed and re-added.
        patch = _patch(
            "-    timeout-minutes: 30",
            "+    timeout-minutes: 200",
            "-    timeout-minutes: 300",
            "+    timeout-minutes: 300",
        )
        self.assertCharge(_file(WORKFLOW, patch=patch, contents=(_jobs("30"), _jobs("200"))))
        unread = _file(WORKFLOW, patch=patch, contents=None)
        self.assertIn(COST_CODE, _codes(_cost([unread], public=False)))

    def test_a_timeout_swapped_between_jobs_counts_at_its_key_path(self):
        patch = _patch(
            "-    timeout-minutes: 30",
            "+    timeout-minutes: 300",
            "-    timeout-minutes: 300",
            "+    timeout-minutes: 30",
        )
        contents = (_jobs("30", "300"), _jobs("300", "30"))
        self.assertCharge(_file(WORKFLOW, patch=patch, contents=contents))

    def test_a_removed_timeout_lets_the_default_apply(self):
        wf = _file(
            WORKFLOW,
            patch=_patch("-    timeout-minutes: 30"),
            contents=(_jobs("30"), _jobs("")),
        )
        self.assertCharge(wf)

    def test_a_removed_job_or_a_removed_timeout_above_the_default_does_not_count(self):
        for base, head in ((_jobs("30") + "  c:\n    timeout-minutes: 5\n", _jobs("30")),
                           (_jobs("400"), _jobs(""))):  # fmt: skip
            with self.subTest(base=base):
                wf = _file(WORKFLOW, patch=_patch("-    x: y"), contents=(base, head))
                codes = _codes(_cost([wf], public=False))
                self.assertNotIn(COST_CODE, codes)

    def test_a_timeout_set_to_an_expression(self):
        line = "+    timeout-minutes: ${{ inputs.minutes }}"
        head = _jobs("${{ inputs.minutes }}")
        self.assertCharge(_file(WORKFLOW, patch=_patch(line), contents=(_jobs("30"), head)))
        self.assertCharge(_file(WORKFLOW, patch=_patch(line), contents=None))

    def test_a_flow_style_timeout(self):
        head = (
            "jobs:\n  a: {runs-on: ubuntu-24.04, timeout-minutes: 90}\n"
            "  b:\n    steps:\n      - uses: anthropics/claude-code-action@v1\n"
        )
        base = head.replace("90", "30")
        patch = _patch(
            "-  a: {runs-on: ubuntu-24.04, timeout-minutes: 30}",
            "+  a: {runs-on: ubuntu-24.04, timeout-minutes: 90}",
        )
        self.assertCharge(_file(WORKFLOW, patch=patch, contents=(base, head)))

    def test_a_raised_timeout_on_a_workflow_calling_a_local_workflow_or_action(self):
        for call in ("./.github/workflows/judge.yml", "./.github/actions/judge"):
            with self.subTest(call=call):
                head = (
                    "jobs:\n  a:\n    timeout-minutes: 90\n"
                    f"    steps:\n      - uses: {call}\n"
                )
                wf = _file(
                    WORKFLOW,
                    patch=_patch("-    timeout-minutes: 30", "+    timeout-minutes: 90"),
                    contents=(head.replace("90", "30"), head),
                )
                self.assertCharge(wf)

    def test_a_step_added_before_a_model_step_does_not_move_its_timeout(self):
        steps = "      - uses: actions/checkout@v4\n"
        leg = (
            "      - uses: o/r/.github/actions/run-claude-cli@abc\n"
            "        with:\n          leg-timeout-minutes: 10\n"
        )
        base = _jobs("30", steps=leg)
        head = _jobs("30", steps=steps + leg)
        wf = _file(WORKFLOW, patch=_patch("+" + steps.rstrip()), contents=(base, head))
        for public in (True, False):
            codes = _codes(_cost([wf], public=public))
            self.assertNotIn(COST_CODE, codes)
            self.assertNotIn(COST_FINDING_CODE, codes)

    def test_a_removed_step_or_a_lowering_timeout_does_not_count(self):
        def leg(n: str) -> str:
            return (
                f"      - uses: o/r/.github/actions/run-claude-cli@{n}\n"
                f"        with:\n          leg-timeout-minutes: {n}\n"
            )

        checkout = "      - uses: actions/checkout@v4\n        with:\n          x: 0\n"
        local = (
            "jobs:\n  a:\n{line}    steps:\n      - uses: ./.github/actions/setup\n"
        )
        for base, head, line in (
            # A whole leg step removed beside steps that remain.
            (_jobs("30", steps=checkout + leg("10") + leg("20")),
             _jobs("30", steps=checkout + leg("20")), "-          leg-timeout-minutes: 10"),
            # A timeout added below the default on a local-call workflow.
            (local.format(line=""), local.format(line="    timeout-minutes: 15\n"),
             "+    timeout-minutes: 15"),
            # A commented-out timeout.
            (_jobs("30"), _jobs("30"), "+    # timeout-minutes: 600"),
        ):  # fmt: skip
            with self.subTest(line=line):
                wf = _file(WORKFLOW, patch=_patch(line), contents=(base, head))
                self.assertNotIn(COST_CODE, _codes(_cost([wf], public=False)))

    def test_a_removed_leg_timeout_counts(self):
        leg = (
            "      - uses: o/r/.github/actions/run-claude-cli@abc\n"
            "        with:\n          prompt: x\n"
        )
        base = _jobs("30", steps=leg + "          leg-timeout-minutes: 10\n")
        wf = _file(
            WORKFLOW,
            patch=_patch("-          leg-timeout-minutes: 10"),
            contents=(base, _jobs("30", steps=leg)),
        )
        self.assertCharge(wf)

    def test_model_settings_on_a_model_step_are_reported(self):
        for line in (
            "+          ANTHROPIC_MODEL: claude-opus",
            "+          model: opus",
            "+          max-turns: 200",
            "+          max_turns: 200",
        ):
            with self.subTest(line=line):
                wf = _file(WORKFLOW, patch=_patch(line), contents=("", "jobs: {}\n"))
                self.assertReported(_cost([wf], public=True))
                codes = _codes(_cost([wf], public=False))
                self.assertIn(COST_FINDING_CODE, codes)
                self.assertNotIn(COST_CODE, codes)

    def test_a_new_local_workflow_or_action_call_is_reported(self):
        for line in (
            "+    uses: ./.github/workflows/judge.yml",
            "+      - uses: ./.github/actions/judge",
        ):
            with self.subTest(line=line):
                wf = _file(WORKFLOW, patch=_patch(line), contents=("", "jobs: {}\n"))
                self.assertReported(_cost([wf], public=True))
        moved = _patch(
            "-      - uses: ./.github/actions/judge", "+        - uses: ./.github/actions/judge"
        )
        wf = _file(WORKFLOW, patch=moved, contents=("", "jobs: {}\n"))
        self.assertNotIn(COST_FINDING_CODE, _codes(_cost([wf], public=True)))

    def test_a_model_leg_in_a_composite_action_holds_for_security(self):
        action = ".github/actions/judge/action.yml"
        for line in (
            "+    - uses: anthropics/claude-code-action@v1",
            "+      run: npx @anthropic-ai/claude-code -p hi",
        ):
            with self.subTest(line=line):
                result = _cost([_file(action, patch=_patch(line))], public=True)
                self.assertSecurityHold(result, AGENT_SURFACE_CODE)
        repin = _patch(
            "-    - uses: anthropics/claude-code-action@aaa",
            "+    - uses: anthropics/claude-code-action@bbb",
        )
        codes = _codes(_cost([_file(action, patch=repin)], public=True))
        self.assertNotIn(AGENT_SURFACE_CODE, codes)

    def test_model_settings_in_actions_and_scripts_are_reported(self):
        for path, line in (
            (".github/actions/judge/action.yml", "+        claude_args: --model opus"),
            (".github/actions/judge/action.yaml", "+        max-turns: 200"),
            (".github/actions/judge/action.yml", "+        ANTHROPIC_MODEL: opus"),
            (".github/scripts/judge/run.sh", "+claude -p --model opus"),
            (".github/scripts/judge/run.mjs", "+  args.push('--max-turns', '200');"),
        ):
            with self.subTest(path=path, line=line):
                result = _cost([_file(path, patch=_patch(line))], public=True)
                self.assertReported(result)

    def test_other_action_and_script_lines_are_not_reported(self):
        for path, line in (
            (".github/actions/judge/action.yml", "+    - run: make"),
            (".github/actions/judge/run.mjs", "+  const model = '--model';"),
            (".github/scripts/judge/run.mjs", "+  const model = config.model;"),
        ):
            with self.subTest(path=path, line=line):
                codes = _codes(_cost([_file(path, patch=_patch(line))], public=True))
                self.assertNotIn(COST_FINDING_CODE, codes)

    def test_new_secret_reference_shapes_hold_for_security(self):
        for lines in (
            ("+  ALL: ${{ secrets }}",),
            ("+    if: ${{ contains(secrets, 'LANE_TOKEN') }}",),
            ("+  K: >-", "+    ${{ secrets", "+    .LANE_TOKEN }}"),
            ("+  K: ${{", "+    secrets.LANE_TOKEN }}"),
            ("+  ALL: ${{ toJSON(secrets.*) }}",),
        ):
            with self.subTest(lines=lines):
                wf = _file(WORKFLOW, patch=_patch(*lines), contents=("", "jobs: {}\n"))
                self.assertSecurityHold(_cost([wf], public=True), SECRET_EXPOSURE_CODE)

    def test_secrets_in_prose_or_as_a_key_does_not_hold(self):
        for line in (
            "+      - name: Rotate keys, secrets, tokens",
            "+    secrets:",
            "+      run: echo secrets are masked",
            "+    if: ${{ contains(fromJSON(needs.a.outputs.jobs || '[]'), 'x-secrets') }}",
            "+    if: ${{ needs.x.outputs.has-secrets }}",
            "+    if: ${{ steps.secrets-check.outputs.ok }}",
        ):
            with self.subTest(line=line):
                wf = _file(WORKFLOW, patch=_patch(line), contents=("", "jobs: {}\n"))
                codes = _codes(_cost([wf], public=True))
                self.assertNotIn(SECRET_EXPOSURE_CODE, codes)

    def test_a_secret_reference_moved_within_one_file_passes(self):
        # Accepted: `_net_added` counts only what the patch gains over what it
        # removes, so a move is net zero.
        moved = (
            "@@ -1,2 +1,1 @@\n context\n-  K: ${{ secrets.LANE_TOKEN }}\n"
            "@@ -40,1 +39,2 @@\n context\n+      K: ${{ secrets.LANE_TOKEN }}"
        )
        split = (
            "@@ -1,2 +1,3 @@\n context\n-  K: ${{ secrets.LANE_TOKEN }}\n"
            "+  K: >-\n+    ${{ secrets\n+    .LANE_TOKEN }}"
        )
        for patch in (moved, split):
            with self.subTest(patch=patch):
                wf = _file(WORKFLOW, patch=patch, contents=("", "jobs: {}\n"))
                codes = _codes(_cost([wf], public=True))
                self.assertNotIn(SECRET_EXPOSURE_CODE, codes)
                self.assertNotIn(COST_CODE, codes)

    def test_a_runner_expression_gaining_a_larger_runner_holds(self):
        matrix = (
            "jobs:\n  build:\n    strategy:\n      matrix:\n        os: [{os}]\n"
            "    runs-on: ${{{{ matrix.os }}}}\n    steps: []\n"
        )
        block = (
            "jobs:\n  build:\n    strategy:\n      matrix:\n        include:\n"
            "          - os: ubuntu-24.04\n{extra}"
            "    runs-on: ${{{{ matrix.os }}}}\n    steps: []\n"
        )
        inputs = (
            "on:\n  workflow_call:\n    inputs:\n      runner:\n"
            "        type: string\n        default: {os}\n"
            "jobs:\n  build:\n    runs-on: ${{{{ inputs.runner }}}}\n    steps: []\n"
        )
        options = (
            "on:\n  workflow_dispatch:\n    inputs:\n      runner:\n"
            "        type: choice\n        options:\n          - ubuntu-24.04\n{extra}"
            "jobs:\n  build:\n    runs-on: ${{{{ inputs.runner }}}}\n    steps: []\n"
        )
        big = "ubuntu-24.04-16-cores"
        for base, head in (
            (matrix.format(os="ubuntu-24.04"), matrix.format(os=f"ubuntu-24.04, {big}")),
            (block.format(extra=""), block.format(extra=f"          - os: {big}\n")),
            (inputs.format(os="ubuntu-24.04"), inputs.format(os=big)),
            (options.format(extra=""), options.format(extra=f"          - {big}\n")),
        ):
            with self.subTest(head=head):
                wf = _file(WORKFLOW, patch=_patch(f"+        - {big}"), contents=(base, head))
                self.assertIn(COST_CODE, _codes(_cost([wf], public=True)))

    def test_a_runner_expression_gaining_a_free_label_does_not_hold(self):
        head = (
            "jobs:\n  build:\n    strategy:\n      matrix:\n"
            "        os: [ubuntu-24.04, macos-26]\n"
            "    runs-on: ${{ matrix.os }}\n    steps: []\n"
        )
        base = head.replace(", macos-26", "")
        wf = _file(WORKFLOW, patch=_patch("+        - macos-26"), contents=(base, head))
        self.assertNotIn(COST_CODE, _codes(_cost([wf], public=True)))

    def test_matrix_growth_behind_another_expression_adds_no_runner_value(self):
        def text(runs_on: str, matrix: str) -> str:
            return (
                f"jobs:\n  build:\n    strategy:\n      matrix:\n        {matrix}\n"
                f"    runs-on: {runs_on}\n    steps: []\n"
            )

        for runs_on, before, after in (
            ("${{ matrix.config.os }}",
             "config:\n          - {os: ubuntu-latest, cc: gcc}",
             "config:\n          - {os: ubuntu-latest, cc: gcc}\n"
             "          - {os: ubuntu-latest, cc: clang}"),
            ("${{ matrix.platform.os }}",
             "platform: [{os: ubuntu-latest, arch: x64}]",
             "platform: [{os: ubuntu-latest, arch: x64}, {os: ubuntu-latest, arch: arm64}]"),
            ("${{ matrix.os == 'win' && 'windows-latest' || 'ubuntu-latest' }}",
             "os: [win]", "os: [win, linux]"),
        ):  # fmt: skip
            with self.subTest(runs_on=runs_on):
                contents = (text(runs_on, before), text(runs_on, after))
                wf = _file(WORKFLOW, patch=_patch("+        - x"), contents=contents)
                self.assertNotIn(COST_CODE, _codes(_cost([wf], public=True)))

    def test_a_flow_style_include_entry_gaining_a_larger_runner_holds(self):
        def text(extra: str) -> str:
            return (
                "jobs:\n  build:\n    strategy:\n      matrix:\n        include:\n"
                f"          - {{os: ubuntu-24.04}}\n{extra}"
                "    runs-on: ${{ matrix.os }}\n    steps: []\n"
            )

        big = "          - {os: ubuntu-24.04-16-cores}\n"
        wf = _file(WORKFLOW, patch=_patch("+" + big.rstrip()), contents=(text(""), text(big)))
        self.assertIn(COST_CODE, _codes(_cost([wf], public=True)))


if __name__ == "__main__":
    unittest.main()
