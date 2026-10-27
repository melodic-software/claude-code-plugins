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

    def test_the_multi_agent_role_defaults_are_no_charge(self):
        # Owner ruling 2026-10-24: only a real charge holds; the review lanes
        # judge a model or effort default.
        defaults = _file(
            "plugins/multi-agent/reference/defaults.yaml",
            patch=_patch("+  model: fable", "-  model: opus"),
        )
        self.assertNotIn(COST_CODE, _codes(_cost([defaults])))
        self.assertIn(COST_CODE, _codes(_cost([_file("infra/main.tf")])))

    def test_an_unlisted_base_tree_fails_closed(self):
        result = _cost([_file("infra/Program.cs")], pulumi_dirs=None)
        self.assertIn(COST_CODE, _codes(result))


LEG = "      - uses: anthropics/claude-code-action@v1\n"
MATRIX = (
    "jobs:\n  build:\n    runs-on: ${{ matrix.os }}\n    strategy:\n      matrix:\n"
)


def _jobs(**timeouts: str) -> str:
    """A model workflow: a judge job, then one job per timeout ("" for none)."""
    text = "jobs:\n  judge:\n    steps:\n" + LEG
    for job, value in timeouts.items():
        text += f"  {job}:\n    runs-on: ubuntu-24.04\n"
        if value:
            text += f"    timeout-minutes: {value}\n"
    return text


class ProbeShapes(unittest.TestCase):
    """The shapes S&C's probe of #9224 still passed that the owner's decision
    on #9241 holds, and the move it accepts."""

    def _held(self, wf, public=True):
        return COST_CODE in _codes(_cost([wf], public=public))

    def test_a_timeout_raised_beside_a_local_reusable_workflow_or_action_holds(self):
        for leg in (
            "  judge:\n    uses: ./.github/workflows/judge.yml\n",
            "  judge:\n    steps:\n      - uses: ./.github/actions/run-judge\n",
        ):
            with self.subTest(leg=leg):
                base = f"jobs:\n{leg}  build:\n    timeout-minutes: 30\n"
                head = f"jobs:\n{leg}  build:\n    timeout-minutes: 45\n"
                patch = _patch("-    timeout-minutes: 30", "+    timeout-minutes: 45")
                wf = _file(WORKFLOW, patch=patch, contents=(base, head))
                self.assertTrue(self._held(wf))

    def test_a_removed_timeout_holds(self):
        patch = _patch("-    timeout-minutes: 30")
        read = _file(WORKFLOW, patch=patch, contents=(_jobs(a="30"), _jobs(a="")))
        self.assertTrue(self._held(read))
        unread = _file(WORKFLOW, patch=patch, contents=None)
        self.assertTrue(self._held(unread))

    def test_a_removed_job_or_workflow_does_not_hold_for_its_timeout(self):
        base, head = _jobs(a="30", b="60"), _jobs(a="30")
        patch = _patch(
            "-  b:", "-    runs-on: ubuntu-24.04", "-    timeout-minutes: 60"
        )
        job = _file(WORKFLOW, patch=patch, contents=(base, head))
        self.assertFalse(self._held(job))
        gone = _file(WORKFLOW, status="removed", patch=patch, contents=None)
        self.assertFalse(self._held(gone))

    def test_a_timeout_set_to_an_expression_holds(self):
        value = "${{ inputs.minutes }}"
        patch = _patch("-    timeout-minutes: 30", f"+    timeout-minutes: {value}")
        wf = _file(WORKFLOW, patch=patch, contents=(_jobs(a="30"), _jobs(a=value)))
        self.assertTrue(self._held(wf))

    def test_a_raise_beside_a_higher_timeout_removed_and_re_added_holds(self):
        base, head = _jobs(a="30", b="300"), _jobs(a="200", b="300")
        patch = _patch(
            "-    timeout-minutes: 30",
            "+    timeout-minutes: 200",
            "-  b:",
            "-    runs-on: ubuntu-24.04",
            "-    timeout-minutes: 300",
            "+  b:",
            "+    runs-on: ubuntu-24.04",
            "+    timeout-minutes: 300",
        )
        wf = _file(WORKFLOW, patch=patch, contents=(base, head))
        self.assertTrue(self._held(wf))

    def test_timeouts_swapped_between_jobs_hold(self):
        base, head = _jobs(a="30", b="300"), _jobs(a="300", b="30")
        patch = _patch(
            "-    timeout-minutes: 30",
            "+    timeout-minutes: 300",
            "-    timeout-minutes: 300",
            "+    timeout-minutes: 30",
        )
        wf = _file(WORKFLOW, patch=patch, contents=(base, head))
        self.assertTrue(self._held(wf))

    def test_a_job_moved_with_its_timeout_does_not_hold(self):
        base, head = _jobs(a="30", b="300"), _jobs(b="300", a="30")
        patch = _patch(
            "-  a:",
            "-    runs-on: ubuntu-24.04",
            "-    timeout-minutes: 30",
            "+  a:",
            "+    runs-on: ubuntu-24.04",
            "+    timeout-minutes: 30",
        )
        wf = _file(WORKFLOW, patch=patch, contents=(base, head))
        self.assertFalse(self._held(wf))

    def test_a_flow_style_timeout_raise_holds(self):
        def flow(value):
            return f"  a: {{runs-on: ubuntu-24.04, timeout-minutes: {value}}}"

        base, head = _jobs() + flow(30) + "\n", _jobs() + flow(300) + "\n"
        wf = _file(
            WORKFLOW,
            patch=_patch(f"-{flow(30)}", f"+{flow(300)}"),
            contents=(base, head),
        )
        self.assertTrue(self._held(wf))

    def test_a_raise_paired_with_a_larger_cut_holds_and_two_cuts_do_not(self):
        raise_one = _patch(
            "-    timeout-minutes: 30",
            "+    timeout-minutes: 200",
            "-    timeout-minutes: 300",
            "+    timeout-minutes: 250",
        )
        self.assertTrue(self._held(_file(WORKFLOW, patch=raise_one, contents=None)))
        cut_both = _patch(
            "-    timeout-minutes: 30",
            "+    timeout-minutes: 20",
            "-    timeout-minutes: 300",
            "+    timeout-minutes: 250",
        )
        self.assertFalse(self._held(_file(WORKFLOW, patch=cut_both, contents=None)))

    def test_timeouts_swapped_on_one_flow_line_hold(self):
        def line(a, b):
            return (
                "jobs: {judge: {steps: [{uses: anthropics/claude-code-action@v1}]},"
                f" a: {{timeout-minutes: {a}}}, b: {{timeout-minutes: {b}}}}}"
            )

        wf = _file(
            WORKFLOW,
            patch=_patch(f"-{line(30, 300)}", f"+{line(300, 30)}"),
            contents=(line(30, 300) + "\n", line(300, 30) + "\n"),
        )
        self.assertTrue(self._held(wf))

    def test_a_timeout_raised_through_what_its_expression_reads_holds(self):
        def text(default):
            return (
                "on:\n  workflow_call:\n    inputs:\n      minutes:\n"
                f"        type: number\n        default: {default}\n"
                "jobs:\n  judge:\n    timeout-minutes: ${{ inputs.minutes }}\n"
                "    steps:\n" + LEG
            )

        patch = _patch("-        default: 30", "+        default: 300")
        wf = _file(WORKFLOW, patch=patch, contents=(text(30), text(300)))
        self.assertTrue(self._held(wf))

    def test_a_timeout_below_its_key_or_behind_an_alias_holds_when_raised(self):
        for form, old, new in (
            ("    timeout-minutes:\n      {}\n", "      30", "      300"),
            ("    timeout-minutes: >-\n      {}\n", "      30", "      300"),
            (
                "    env: {{T: &t {}}}\n    timeout-minutes: *t\n",
                "    env: {T: &t 30}",
                "    env: {T: &t 300}",
            ),
        ):
            with self.subTest(form=form):
                base = _jobs() + "  a:\n" + form.format(30)
                head = _jobs() + "  a:\n" + form.format(300)
                patch = _patch(f"-{old}", f"+{new}")
                wf = _file(WORKFLOW, patch=patch, contents=(base, head))
                self.assertTrue(self._held(wf))

    def test_a_timeout_raised_through_an_env_value_or_a_later_anchor_holds(self):
        for form, old, new in (
            (
                "    env: {{T: {}}}\n    timeout-minutes: ${{{{ fromJSON(env.T) }}}}\n",
                "    env: {T: 30}",
                "    env: {T: 300}",
            ),
            (
                "    env: {{A: &t 30, B: &t {}}}\n    timeout-minutes: *t\n",
                "    env: {A: &t 30, B: &t 30}",
                "    env: {A: &t 30, B: &t 300}",
            ),
        ):
            with self.subTest(form=form):
                base = _jobs() + "  a:\n" + form.format(30)
                head = _jobs() + "  a:\n" + form.format(300)
                patch = _patch(f"-{old}", f"+{new}")
                wf = _file(WORKFLOW, patch=patch, contents=(base, head))
                self.assertTrue(self._held(wf))

    def test_a_file_renamed_into_an_action_or_script_path_holds(self):
        for path in (".github/actions/judge/action.yml", ".github/scripts/judge.sh"):
            with self.subTest(path=path):
                moved = _file(path, status="renamed", previous_path="tools/judge.sh")
                self.assertTrue(self._held(moved))
        within = _file(
            ".github/scripts/judge.sh",
            status="renamed",
            previous_path=".github/scripts/old.sh",
        )
        self.assertFalse(self._held(within))

    def test_a_timeout_removed_with_its_with_block_holds(self):
        call = "jobs:\n  judge:\n    uses: ./.github/workflows/judge.yml\n"
        base = call + "    with:\n      leg-timeout-minutes: 10\n"
        patch = _patch("-    with:", "-      leg-timeout-minutes: 10")
        wf = _file(WORKFLOW, patch=patch, contents=(base, call))
        self.assertTrue(self._held(wf))

    def test_an_empty_quoted_key_is_read_without_failing(self):
        tail = '  b:\n    "": x\n'
        patch = _patch("-    timeout-minutes: 30", "+    timeout-minutes: 45")
        wf = _file(
            WORKFLOW,
            patch=patch,
            contents=(_jobs(a="30") + tail, _jobs(a="45") + tail),
        )
        codes = _codes(_cost([wf], public=True))
        self.assertIn(COST_CODE, codes)
        self.assertNotIn("high-path:**", codes)

    def test_a_secrets_word_in_a_comment_does_not_offset_a_new_reference(self):
        for lines in (
            ("-  # forwards secrets", "+  ALL: ${{ toJSON(secrets) }}"),
            ("-  # reads org secrets.", "+  KEY: >-", "+    ${{ secrets.", "+    K }}"),
            ("+  ALL: ${{ toJSON(secrets.*) }}",),
        ):
            with self.subTest(lines=lines):
                wf = _file(WORKFLOW, patch=_patch(*lines), contents=("", "jobs: {}\n"))
                self.assertTrue(self._held(wf))

    def test_a_flow_style_matrix_gaining_a_larger_label_holds(self):
        head = "jobs:\n  build:\n    runs-on: ${{ matrix.os }}\n    strategy:\n"
        for old, new in (
            (
                "      matrix: {os: [ubuntu-24.04]}",
                "      matrix: {os: [ubuntu-24.04, ubuntu-24.04-16-cores]}",
            ),
            (
                "      matrix: {include: [{os: ubuntu-24.04}]}",
                "      matrix: {include: [{os: ubuntu-24.04}, {os: big-runner}]}",
            ),
        ):
            with self.subTest(new=new):
                wf = _file(
                    WORKFLOW,
                    patch=_patch(f"-{old}", f"+{new}"),
                    contents=(f"{head}{old}\n", f"{head}{new}\n"),
                )
                self.assertTrue(self._held(wf))

    def test_an_action_reads_like_a_workflow_and_a_script_holds_a_package_run(self):
        action = ".github/actions/judge/action.yml"
        for line in (
            "+    - uses: anthropics/claude-code-action@v1",
            "+        model: opus",
            "+      run: npx @anthropic-ai/claude-code -p hi",
        ):
            with self.subTest(line=line):
                self.assertTrue(self._held(_file(action, patch=_patch(line))))
        script = _file(".github/scripts/x.sh", patch=_patch("+npx @anthropic-ai/claude-code"))
        self.assertTrue(self._held(script))

    def test_a_new_local_reusable_workflow_or_composite_action_holds(self):
        for line in (
            "+    uses: ./.github/workflows/judge.yml",
            "+      - uses: ./.github/actions/run-judge",
            "+      - uses: './.github/actions/run-judge'",
        ):
            with self.subTest(line=line):
                wf = _file(WORKFLOW, patch=_patch(line), contents=("", "jobs: {}\n"))
                self.assertTrue(self._held(wf))

    def test_model_inputs_and_environment_hold(self):
        for line in (
            "+          ANTHROPIC_MODEL: opus",
            "+          ANTHROPIC_DEFAULT_OPUS_MODEL: opus",
            "+          model: opus",
            "+          max-turns: 200",
            "+          max_turns: 200",
            "+        with: {model: opus}",
            '+          "model": opus',
        ):
            with self.subTest(line=line):
                wf = _file(WORKFLOW, patch=_patch(line), contents=("", "jobs: {}\n"))
                self.assertTrue(self._held(wf))

    def test_model_flags_in_action_and_script_files_hold(self):
        for path in (
            ".github/actions/judge/action.yml",
            ".github/actions/judge/action.yaml",
            ".github/scripts/judge/run.mjs",
            ".github/scripts/judge.sh",
        ):
            for line in (
                "+        run: claude --model opus -p hi",
                "+  args.push('--max-turns', '200');",
                "+    ANTHROPIC_MODEL: opus",
            ):
                with self.subTest(path=path, line=line):
                    self.assertTrue(self._held(_file(path, patch=_patch(line))))

    def test_other_action_and_script_changes_do_not_hold(self):
        for path in (".github/actions/judge/action.yml", ".github/scripts/x.mjs"):
            with self.subTest(path=path):
                other = _file(path, patch=_patch("+  const turns = 1;", "-  x();"))
                self.assertFalse(self._held(other))
        self.assertTrue(self._held(_file(".github/scripts/x.mjs", patch=None)))

    def test_whole_context_and_folded_secret_references_hold(self):
        for lines in (
            ("+  ALL: ${{ secrets }}",),
            ("+    if: ${{ contains(secrets, 'API_KEY') }}",),
            ("+  KEY: >-", "+    ${{ secrets.", "+    API_KEY }}"),
            ("+  KEY: >-", "+    ${{ secrets", "+    .API_KEY }}"),
        ):
            with self.subTest(lines=lines):
                wf = _file(WORKFLOW, patch=_patch(*lines), contents=("", "jobs: {}\n"))
                self.assertTrue(self._held(wf))

    def test_the_whole_context_after_an_operator_holds(self):
        for line in (
            "+  ALL: ${{ toJSON(a && secrets) }}",
            "+  ALL: ${{ toJSON(github.event_name == 'push' && secrets) }}",
            "+  ALL: ${{ toJSON(inputs.x || secrets) }}",
            "+  ALL: ${{ (x || secrets) }}",
            "+  ALL: ${{ toJSON(x == secrets) }}",
            "+  ALL: ${{ inputs.x && secrets }}",
            "+  ALL: ${{ inputs.x || secrets }}",
        ):
            with self.subTest(line=line):
                wf = _file(WORKFLOW, patch=_patch(line), contents=("", "jobs: {}\n"))
                self.assertTrue(self._held(wf))

    def test_a_secret_reference_moved_within_a_file_does_not_hold(self):
        for ref in (
            "${{ secrets.API_KEY }}",
            "${{ secrets }}",
            "${{ contains(secrets, 'API_KEY') }}",
            "${{ toJSON(a && secrets) }}",
        ):
            with self.subTest(ref=ref):
                moved = _patch(f"-      KEY: {ref}", "   b:", f"+      KEY: {ref}")
                wf = _file(WORKFLOW, patch=moved, contents=("", "jobs: {}\n"))
                self.assertFalse(self._held(wf))

    def test_a_larger_label_behind_a_runner_expression_holds(self):
        inputs = (
            "on:\n  workflow_call:\n    inputs:\n      runner:\n        type: string\n"
            "        default: {}\njobs:\n  build:\n    runs-on: ${{{{ inputs.runner }}}}\n"
        )
        for base, head, patch in (
            (
                MATRIX + "        os: [ubuntu-24.04]\n",
                MATRIX + "        os: [ubuntu-24.04, ubuntu-24.04-16-cores]\n",
                _patch(
                    "-        os: [ubuntu-24.04]",
                    "+        os: [ubuntu-24.04, ubuntu-24.04-16-cores]",
                ),
            ),
            (
                MATRIX + "        os:\n          - ubuntu-24.04\n",
                MATRIX + "        os:\n          - ubuntu-24.04\n          - big-runner\n",
                _patch("+          - big-runner"),
            ),
            (
                inputs.format("ubuntu-24.04"),
                inputs.format("ubuntu-24.04-xlarge"),
                _patch(
                    "-        default: ubuntu-24.04",
                    "+        default: ubuntu-24.04-xlarge",
                ),
            ),
        ):
            with self.subTest(head=head):
                wf = _file(WORKFLOW, patch=patch, contents=(base, head))
                self.assertTrue(self._held(wf))

    def test_a_free_label_behind_a_runner_expression_does_not_hold(self):
        wf = _file(
            WORKFLOW,
            patch=_patch(
                "-        os: [ubuntu-24.04]", "+        os: [ubuntu-24.04, windows-2025]"
            ),
            contents=(
                MATRIX + "        os: [ubuntu-24.04]\n",
                MATRIX + "        os: [ubuntu-24.04, windows-2025]\n",
            ),
        )
        self.assertFalse(self._held(wf))
        self.assertTrue(self._held(wf, public=False))


if __name__ == "__main__":
    unittest.main()
