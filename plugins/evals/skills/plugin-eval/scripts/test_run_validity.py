#!/usr/bin/env python3
# test-scope: plugins/evals/skills/plugin-eval/scripts/fixtures/run-validity/traces/*
"""Fixture suite for run-validity.py.

fixtures/run-validity/ holds two result files trimmed from one real
`claude plugin eval` run (Claude Code 2.1.287, --runs 2, --keep-temp) and the
structural lines of its kept traces, with no answer text:

    r2-invalid.json     the whole run: 3 denied Reads of the methodology skill's
                        reference files and one with-arm run whose skill never
                        fired, so it must come out INVALID
    r2-clean-runs.json  one run per arm per case, taken from the runs of that same
                        result that pass every check, so it must come out VALID
    traces/             clean.jsonl stands in for every trace with no denial

The other tests copy a fixture into a temporary directory and change one field.

The suite is executed by run-validity.test.sh, which run-plugin-tests.sh
discovers. Run it directly with: python3 test_run_validity.py
"""

import copy
import importlib.util
import json
import ntpath
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from typing import Optional
from unittest import mock

HERE = Path(__file__).resolve().parent
SCRIPT = HERE / "run-validity.py"
FIXTURES = HERE / "fixtures" / "run-validity"
TRACES = FIXTURES / "traces"
INVALID = FIXTURES / "r2-invalid.json"
CLEAN = FIXTURES / "r2-clean-runs.json"


def load(path):
    return json.loads(path.read_text(encoding="utf-8"))


def runs_of(result):
    for case in result["cases"]:
        for arm in ("with", "without"):
            yield from case["arms"].get(arm, [])


class RunValidityTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.dir = Path(self.tmp.name)

    def run_script(self, path, *args):
        return subprocess.run(
            [sys.executable, str(SCRIPT), str(path), *args],
            capture_output=True,
            text=True,
            check=False,
        )

    def write(self, result, absolute_traces=True):
        """Write a result into the temp dir, its tracePaths pointed at the fixture traces."""
        result = copy.deepcopy(result)
        if absolute_traces:
            for run in (r for r in runs_of(result) if "tracePath" in r):
                run["tracePath"] = str(FIXTURES / run["tracePath"])
        path = self.dir / "aggregate-result.json"
        path.write_text(json.dumps(result), encoding="utf-8")
        return path

    def clean(self):
        return load(CLEAN)

    def assertVerdict(self, proc, verdict, code):
        self.assertEqual(proc.returncode, code, proc.stdout + proc.stderr)
        self.assertTrue(
            proc.stdout.strip().splitlines()[-1].startswith("verdict: " + verdict),
            proc.stdout,
        )

    def test_r2_is_invalid_for_its_denials_and_its_unfired_skill(self):
        proc = self.run_script(INVALID, "--runs", "2")
        self.assertVerdict(proc, "INVALID", 1)
        self.assertIn(
            "check permission denials: FAIL (3 denials in 3 runs)", proc.stdout
        )
        for run, file in (
            ("case grading-method-choice, with-arm run 1", "grading.md"),
            ("case grading-method-choice, with-arm run 2", "grading.md"),
            ("case measurable-criterion, with-arm run 1", "success-criteria.md"),
        ):
            self.assertIn(
                "  %s: Read /tmp/eval-r2/plugins/evals/skills/methodology/reference/%s"
                % (run, file),
                proc.stdout,
            )
        self.assertIn(
            "check skill fired: FAIL (1 of 6 with-arm runs of should-trigger cases did not fire;"
            " exempt as no-trigger controls: control-no-trigger)",
            proc.stdout,
        )
        self.assertIn("  unfired: case noise-before-gain, with-arm run 1", proc.stdout)
        self.assertIn(
            "verdict: INVALID (3 permission denials in the traces; the skill did not fire"
            " in 1 with-arm run of a should-trigger case)",
            proc.stdout,
        )

    def test_r2_reads_rows_not_runs_per_case(self):
        proc = self.run_script(INVALID, "--runs", "2")
        self.assertIn(
            "check row count: PASS (2 rows per arm in every case, as --runs 2 asked;"
            " runsPerCase reads 3 and is not used)",
            proc.stdout,
        )
        proc = self.run_script(INVALID, "--runs", "3")
        self.assertIn(
            "check row count: FAIL (8 arms off the requested count)", proc.stdout
        )
        self.assertIn(
            "  case noise-before-gain, without-arm: 2 rows, --runs asked for 3",
            proc.stdout,
        )
        self.assertIn("8 arms hold a row count other than --runs 3", proc.stdout)

    def test_r2_warnings_do_not_decide_the_verdict(self):
        proc = self.run_script(INVALID, "--runs", "2")
        self.assertIn(
            "check models: WARN (model claude-opus-5-5 in 16 of 16 traces; Claude Code 2.1.287;"
            " judge model not recorded in the result or the traces",
            proc.stdout,
        )
        self.assertIn(
            "  case noise-before-gain, with-arm run 2, grader noise-verdict: FAIL FAIL PASS",
            proc.stdout,
        )
        self.assertIn(
            "check ceiling: WARN (without-arm already at 1.00 in control-no-trigger,"
            " measurable-criterion; excluded from the delta, and the delta over the other"
            " 2 cases is -0.25)",
            proc.stdout,
        )
        verdict = proc.stdout.strip().splitlines()[-1]
        self.assertNotIn("model", verdict)
        self.assertNotIn("ceiling", verdict)

    def test_clean_runs_are_valid_with_their_warnings_named(self):
        proc = self.run_script(CLEAN, "--runs", "1")
        self.assertVerdict(proc, "VALID", 0)
        self.assertIn("traces: 6 of 6 tracePaths resolve", proc.stdout)
        self.assertIn(
            "check permission denials: PASS (no denied tool call in 6 traces)",
            proc.stdout,
        )
        self.assertIn(
            "check skill fired: PASS (fired in all 2 with-arm runs", proc.stdout
        )
        self.assertIn("the delta over the other 1 case is +0.00", proc.stdout)
        self.assertIn(
            "verdict: VALID (warnings: models, judge votes, ceiling)", proc.stdout
        )

    def test_unresolved_traces_leave_denials_unchecked_and_invalid(self):
        path = self.write(self.clean(), absolute_traces=False)
        proc = self.run_script(path, "--runs", "1")
        self.assertVerdict(proc, "INVALID", 1)
        self.assertIn("traces: 6 of 6 tracePaths do not resolve", proc.stdout)
        self.assertIn("check permission denials: UNCHECKED", proc.stdout)
        self.assertIn(
            "permission denials unchecked in 6 runs with no readable trace", proc.stdout
        )
        self.assertNotIn("check permission denials: PASS", proc.stdout)

    def test_a_missing_trace_path_is_named(self):
        result = self.clean()
        del result["cases"][0]["arms"]["with"][0]["tracePath"]
        proc = self.run_script(self.write(result), "--runs", "1")
        self.assertVerdict(proc, "INVALID", 1)
        self.assertIn(
            "  case control-no-trigger, with-arm run 1: no tracePath", proc.stdout
        )

    def test_a_result_with_no_runs_is_invalid(self):
        result = self.clean()
        result["cases"] = []
        proc = self.run_script(self.write(result), "--runs", "1")
        self.assertVerdict(proc, "INVALID", 1)
        self.assertIn("check complete: FAIL (the result holds no runs)", proc.stdout)

    def test_an_empty_trace_leaves_denials_unchecked(self):
        empty = self.dir / "empty.jsonl"
        empty.write_text("", encoding="utf-8")
        result = self.write(self.clean())
        data = json.loads(result.read_text(encoding="utf-8"))
        data["cases"][0]["arms"]["with"][0]["tracePath"] = str(empty)
        result.write_text(json.dumps(data), encoding="utf-8")
        proc = self.run_script(result, "--runs", "1")
        self.assertVerdict(proc, "INVALID", 1)
        self.assertIn("check permission denials: UNCHECKED", proc.stdout)

    def test_partial_run_is_invalid(self):
        result = self.clean()
        result["partial"], result["partialReason"] = True, "cost_ceiling"
        proc = self.run_script(self.write(result), "--runs", "1")
        self.assertVerdict(proc, "INVALID", 1)
        self.assertIn("check complete: FAIL", proc.stdout)
        self.assertIn("the run is partial (cost_ceiling)", proc.stdout)

    def test_skipped_paid_graders_are_invalid(self):
        result = self.clean()
        result["cases"][1]["arms"]["without"][0]["skippedPaidGraders"] = True
        proc = self.run_script(self.write(result), "--runs", "1")
        self.assertVerdict(proc, "INVALID", 1)
        self.assertIn("  case measurable-criterion, without-arm run 1", proc.stdout)
        self.assertIn("1 run skipped paid graders", proc.stdout)

    def test_errored_or_aborted_runs_are_invalid(self):
        result = self.clean()
        result["cases"][0]["arms"]["with"][0]["error"] = "rate limited"
        result["cases"][2]["arms"]["with"][0]["aborted"] = {
            "server": "s",
            "tool": "t",
            "reason": "r",
        }
        proc = self.run_script(self.write(result), "--runs", "1")
        self.assertVerdict(proc, "INVALID", 1)
        self.assertIn(
            "  case control-no-trigger, with-arm run 1: error rate limited", proc.stdout
        )
        self.assertIn("  case noise-before-gain, with-arm run 1: aborted", proc.stdout)
        self.assertIn("2 run errors", proc.stdout)

    def test_a_trace_that_ends_in_an_error_is_invalid(self):
        trace = self.dir / "errored.jsonl"
        trace.write_text(
            '{"type":"system","subtype":"init","model":"claude-opus-5-5"}\n'
            '{"type":"result","subtype":"error_during_execution","is_error":true}\n',
            encoding="utf-8",
        )
        result = self.write(self.clean())
        data = load(result)
        data["cases"][0]["arms"]["without"][0]["tracePath"] = str(trace)
        result.write_text(json.dumps(data), encoding="utf-8")
        proc = self.run_script(result, "--runs", "1")
        self.assertVerdict(proc, "INVALID", 1)
        self.assertIn(
            "case control-no-trigger, without-arm run 1: its trace ends in an error",
            proc.stdout,
        )

    def test_a_denial_seen_only_as_a_tool_result_is_counted(self):
        trace = self.dir / "denied.jsonl"
        trace.write_text(
            '{"type":"system","subtype":"init","model":"claude-opus-5-5"}\n'
            '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1","name":"Grep","input":{"pattern":"x"}}]}}\n'
            '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t1","is_error":true,'
            '"content":[{"type":"text","text":"Path is denied by your permission settings."}]}]}}\n',
            encoding="utf-8",
        )
        result = self.write(self.clean())
        data = load(result)
        data["cases"][1]["arms"]["with"][0]["tracePath"] = str(trace)
        result.write_text(json.dumps(data), encoding="utf-8")
        proc = self.run_script(result, "--runs", "1")
        self.assertVerdict(proc, "INVALID", 1)
        self.assertIn("check permission denials: FAIL (1 denial in 1 run)", proc.stdout)
        self.assertIn(
            "  case measurable-criterion, with-arm run 1: Grep x", proc.stdout
        )

    def test_a_denial_names_the_path_it_was_aimed_at(self):
        trace = self.dir / "denied-paths.jsonl"
        trace.write_text(
            '{"type":"system","subtype":"init","model":"claude-opus-5-5"}\n'
            '{"type":"result","is_error":false,"permission_denials":['
            '{"tool_name":"Grep","tool_use_id":"g1","tool_input":'
            '{"pattern":"GRADER_TYPES","path":"/p/validate-cases.py"}},'
            '{"tool_name":"Glob","tool_use_id":"g2","tool_input":'
            '{"pattern":"**/package.json","path":"/usr"}},'
            '{"tool_name":"Read","tool_use_id":"r1","tool_input":'
            '{"limit":40,"file_path":"/p/reference/ci.md"}}]}\n',
            encoding="utf-8",
        )
        result = self.write(self.clean())
        data = load(result)
        data["cases"][1]["arms"]["with"][0]["tracePath"] = str(trace)
        result.write_text(json.dumps(data), encoding="utf-8")
        proc = self.run_script(result, "--runs", "1")
        self.assertVerdict(proc, "INVALID", 1)
        self.assertIn(
            "check permission denials: FAIL (3 denials in 1 run)", proc.stdout
        )
        where = "  case measurable-criterion, with-arm run 1: "
        self.assertIn(where + "Grep /p/validate-cases.py (", proc.stdout)
        self.assertIn(where + "Glob /usr (", proc.stdout)
        self.assertIn(where + "Read /p/reference/ci.md (", proc.stdout)

    def denied_second_run(
        self,
        arm,
        score,
        first_denied=False,
        also_with=None,
        missing=None,
        path: Optional[str] = "/tmp/claude-eval-x",
        root=None,
    ):
        """The clean result at two runs per arm, measurable-criterion's second
        `arm` run denied a Grep aimed at `path` (None: no path) and scoring
        `score`; with first_denied, its first run of that arm is denied too; with
        also_with, the second with-arm run of the case at that index is denied as
        well; with missing, a (case index, arm, run index) whose tracePath does
        not resolve; with root, the suite.root the plugin's directory is."""
        tool_input = {"pattern": "judge"}
        if path is not None:
            tool_input["path"] = path
        trace = self.dir / "denied-root.jsonl"
        trace.write_text(
            '{"type":"system","subtype":"init","model":"claude-opus-5-5"}\n'
            '{"type":"result","is_error":false,"permission_denials":['
            '{"tool_name":"Grep","tool_use_id":"g1","tool_input":%s}]}\n'
            % json.dumps(tool_input),
            encoding="utf-8",
        )
        data = load(self.write(self.clean()))
        if root is not None:
            data["suite"]["root"] = root
        for case in data["cases"]:
            for name in ("with", "without"):
                case["arms"][name].append(copy.deepcopy(case["arms"][name][0]))
        rows = data["cases"][1]["arms"][arm]
        rows[1]["tracePath"], rows[1]["score"] = str(trace), score
        if first_denied:
            rows[0]["tracePath"] = str(trace)
        if also_with is not None:
            data["cases"][also_with]["arms"]["with"][1]["tracePath"] = str(trace)
        if missing is not None:
            index, name, run = missing
            data["cases"][index]["arms"][name][run]["tracePath"] = str(
                self.dir / "absent.jsonl"
            )
        result = self.dir / "aggregate-result.json"
        result.write_text(json.dumps(data), encoding="utf-8")
        return self.run_script(result, "--runs", "2")

    def test_a_with_arm_denial_with_no_plugin_root_is_a_fail_even_when_its_score_matches(
        self,
    ):
        proc = self.denied_second_run("with", 1)
        self.assertVerdict(proc, "INVALID", 1)
        self.assertIn("check permission denials: FAIL (1 denial in 1 run)", proc.stdout)

    PLUGIN = "/tmp/eval-r2/plugins/evals"

    def test_a_with_arm_denial_outside_the_plugin_scoring_the_same_is_a_warning(self):
        proc = self.denied_second_run("with", 1, root=self.PLUGIN)
        self.assertVerdict(proc, "VALID", 0)
        self.assertIn("check permission denials: WARN (1 denial in 1 run", proc.stdout)

    def test_a_with_arm_denial_outside_the_plugin_scoring_differently_is_a_fail(self):
        proc = self.denied_second_run("with", 0, root=self.PLUGIN)
        self.assertVerdict(proc, "INVALID", 1)
        self.assertIn("check permission denials: FAIL (1 denial in 1 run)", proc.stdout)

    def test_a_with_arm_denial_inside_the_plugin_is_a_fail(self):
        proc = self.denied_second_run(
            "with",
            1,
            root=self.PLUGIN,
            path=self.PLUGIN + "/skills/methodology/reference/grading.md",
        )
        self.assertVerdict(proc, "INVALID", 1)
        self.assertIn("check permission denials: FAIL (1 denial in 1 run)", proc.stdout)

    def test_a_with_arm_denial_above_the_plugin_is_a_fail(self):
        for ancestor in ("/", "/tmp", "/tmp/eval-r2/plugins"):
            proc = self.denied_second_run("with", 1, root=self.PLUGIN, path=ancestor)
            self.assertVerdict(proc, "INVALID", 1)
            self.assertIn(
                "check permission denials: FAIL (1 denial in 1 run)", proc.stdout
            )

    def test_a_with_arm_denial_beside_the_plugin_name_prefix_is_a_warning(self):
        proc = self.denied_second_run(
            "with", 1, root=self.PLUGIN, path=self.PLUGIN + "-other"
        )
        self.assertVerdict(proc, "VALID", 0)

    def test_a_with_arm_denial_with_no_path_is_a_fail(self):
        proc = self.denied_second_run("with", 1, root=self.PLUGIN, path=None)
        self.assertVerdict(proc, "INVALID", 1)
        self.assertIn("check permission denials: FAIL (1 denial in 1 run)", proc.stdout)

    def test_a_without_arm_denial_scoring_like_its_clean_runs_is_a_warning(self):
        proc = self.denied_second_run("without", 1)
        self.assertVerdict(proc, "VALID", 0)
        self.assertIn("check permission denials: WARN (1 denial in 1 run", proc.stdout)
        self.assertIn(
            "  case measurable-criterion, without-arm run 2: Grep /tmp/claude-eval-x",
            proc.stdout,
        )
        self.assertIn(
            "permission denials in case measurable-criterion",
            proc.stdout.splitlines()[-1],
        )

    def test_an_invalid_verdict_still_names_the_warned_case(self):
        proc = self.denied_second_run("without", 1, also_with=2)
        self.assertVerdict(proc, "INVALID", 1)
        self.assertIn(
            "check permission denials: FAIL (2 denials in 2 runs", proc.stdout
        )
        self.assertIn(
            "1 permission denial in the traces (warnings only, not counted:"
            " case measurable-criterion)",
            proc.stdout.splitlines()[-1],
        )

    def test_a_without_arm_denial_scoring_differently_is_a_fail(self):
        proc = self.denied_second_run("without", 0)
        self.assertVerdict(proc, "INVALID", 1)
        self.assertIn("check permission denials: FAIL (1 denial in 1 run)", proc.stdout)

    def test_a_without_arm_denial_with_no_denial_free_run_is_a_fail(self):
        proc = self.denied_second_run("without", 1, first_denied=True)
        self.assertVerdict(proc, "INVALID", 1)
        self.assertIn(
            "check permission denials: FAIL (2 denials in 2 runs)", proc.stdout
        )

    def test_a_warned_denial_beside_an_unread_trace_is_unchecked(self):
        proc = self.denied_second_run("without", 1, missing=(2, "with", 0))
        self.assertVerdict(proc, "INVALID", 1)
        self.assertIn(
            "check permission denials: UNCHECKED (1 denial in 1 run", proc.stdout
        )

    def test_a_without_arm_denial_with_an_unread_sibling_is_a_fail(self):
        proc = self.denied_second_run("without", 1, missing=(1, "without", 0))
        self.assertVerdict(proc, "INVALID", 1)
        self.assertIn("check permission denials: FAIL (1 denial in 1 run)", proc.stdout)

    def test_skill_text_quoting_the_denial_is_not_a_denial(self):
        trace = self.dir / "quoted.jsonl"
        trace.write_text(
            '{"type":"system","subtype":"init","model":"claude-opus-5-5"}\n'
            '{"type":"user","message":{"content":[{"type":"text","text":"a Read is refused with'
            ' File is in a directory that is denied by your permission settings"}]}}\n',
            encoding="utf-8",
        )
        result = self.write(self.clean())
        data = load(result)
        data["cases"][2]["arms"]["with"][0]["tracePath"] = str(trace)
        result.write_text(json.dumps(data), encoding="utf-8")
        proc = self.run_script(result, "--runs", "1")
        self.assertVerdict(proc, "VALID", 0)

    def test_runs_on_different_models_are_invalid(self):
        trace = self.dir / "other-model.jsonl"
        trace.write_text(
            '{"type":"system","subtype":"init","model":"claude-sonnet-5"}\n',
            encoding="utf-8",
        )
        result = self.write(self.clean())
        data = load(result)
        data["cases"][1]["arms"]["without"][0]["tracePath"] = str(trace)
        result.write_text(json.dumps(data), encoding="utf-8")
        proc = self.run_script(result, "--runs", "1")
        self.assertVerdict(proc, "INVALID", 1)
        self.assertIn("check models: FAIL (runs used 2 different models", proc.stdout)
        self.assertIn(
            "  claude-sonnet-5: case measurable-criterion, without-arm run 1",
            proc.stdout,
        )

    def test_a_recorded_judge_model_clears_the_models_warning(self):
        result = self.clean()
        result["suite"]["judgeModel"] = "sonnet"
        proc = self.run_script(self.write(result), "--runs", "1")
        self.assertIn(
            "check models: PASS (model claude-opus-5-5 in 6 of 6 traces;", proc.stdout
        )
        self.assertIn("judge model sonnet)", proc.stdout)

    def fired_case_with_tags(self, tags_line):
        result = self.clean()
        noise = result["cases"][2]
        noise["arms"]["with"][0]["graders"][1]["passed"] = False
        noise["dir"] = "evals/noise-before-gain"
        result["suite"]["root"] = "suite"
        prompt = self.dir / "suite" / "evals" / "noise-before-gain" / "prompt.md"
        prompt.parent.mkdir(parents=True, exist_ok=True)
        prompt.write_text(
            "---\ndescription: d\n%s\nruns: 1\n---\n\nQ\n" % tags_line, encoding="utf-8"
        )
        return self.run_script(self.write(result), "--runs", "1")

    def test_a_case_tagged_control_is_exempt(self):
        proc = self.fired_case_with_tags("tags: [knowledge, control]")
        self.assertVerdict(proc, "VALID", 0)
        self.assertIn(
            "exempt as no-trigger controls: control-no-trigger, noise-before-gain",
            proc.stdout,
        )
        proc = self.fired_case_with_tags("tags:\n  - knowledge\n  - no-trigger")
        self.assertVerdict(proc, "VALID", 0)

    def test_an_untagged_unfired_case_is_invalid(self):
        proc = self.fired_case_with_tags("tags: [knowledge, hard]")
        self.assertVerdict(proc, "INVALID", 1)
        self.assertIn("  unfired: case noise-before-gain, with-arm run 1", proc.stdout)

    def suite_with_guard(self, case, guard_match):
        """Give a case a max-0 Skill guard whose input_match is read from its grader file."""
        result = self.clean()
        case_result = result["cases"][case]
        case_result["dir"] = "evals/" + case_result["name"]
        case_result["graders"].insert(
            0,
            {
                "name": "guard",
                "type": "tool_used",
                "config": {"tool": "Skill", "min": 0, "max": 0},
            },
        )
        result["suite"]["root"] = "suite"
        suite = self.dir / "suite"
        (suite / "skills" / "methodology").mkdir(parents=True)
        graders = suite / case_result["dir"] / "graders"
        graders.mkdir(parents=True)
        (graders / "guard.md").write_text(
            "---\ntype: tool_used\ntool: Skill\ninput_match: %s\nmin: 0\nmax: 0\n---\n"
            % json.dumps(guard_match),
            encoding="utf-8",
        )
        return result

    def test_a_should_trigger_case_with_a_guard_on_another_skill_is_not_exempt(self):
        result = self.suite_with_guard(2, '"skill"\\s*:\\s*"claude-api".*build-eval')
        result["cases"][2]["arms"]["with"][0]["graders"][1]["passed"] = False
        proc = self.run_script(self.write(result), "--runs", "1")
        self.assertVerdict(proc, "INVALID", 1)
        self.assertIn("  unfired: case noise-before-gain, with-arm run 1", proc.stdout)
        self.assertNotIn("control-no-trigger, noise-before-gain", proc.stdout)

    def test_a_case_with_a_guard_on_its_own_skills_and_no_min_grader_is_exempt(self):
        result = self.suite_with_guard(0, '"skill"\\s*:\\s*"(?:evals:)?methodology"')
        proc = self.run_script(self.write(result), "--runs", "1")
        self.assertVerdict(proc, "VALID", 0)
        self.assertIn("exempt as no-trigger controls: control-no-trigger", proc.stdout)

    def test_a_with_run_missing_its_skill_fired_result_is_unchecked(self):
        result = self.clean()
        del result["cases"][1]["arms"]["with"][0]["graders"][1]
        proc = self.run_script(self.write(result), "--runs", "1")
        self.assertVerdict(proc, "INVALID", 1)
        self.assertIn("check skill fired: UNCHECKED", proc.stdout)

    def test_a_case_with_no_skill_grader_is_a_warning(self):
        result = self.clean()
        result["cases"][1]["graders"] = result["cases"][1]["graders"][:1]
        proc = self.run_script(self.write(result), "--runs", "1")
        self.assertVerdict(proc, "VALID", 0)
        self.assertIn("check skill fired: WARN", proc.stdout)
        self.assertIn(
            "no skill-fired grader, so not checked: measurable-criterion", proc.stdout
        )

    def test_one_arm_run_expects_no_without_rows(self):
        result = self.clean()
        result["suite"]["ablation"] = "none"
        for case in result["cases"]:
            del case["arms"]["without"]
        proc = self.run_script(self.write(result), "--runs", "1")
        self.assertIn("check row count: PASS", proc.stdout)
        self.assertIn("check ceiling: PASS (no without-arm in this run", proc.stdout)
        self.assertVerdict(proc, "VALID", 0)

    def test_a_two_arm_case_missing_its_without_arm_is_invalid(self):
        result = self.clean()
        del result["cases"][0]["arms"]["without"]
        proc = self.run_script(self.write(result), "--runs", "1")
        self.assertVerdict(proc, "INVALID", 1)
        self.assertIn(
            "  case control-no-trigger, without-arm: 0 rows, --runs asked for 1",
            proc.stdout,
        )

    def test_usage_and_unreadable_input_exit_2(self):
        broken = self.dir / "broken.json"
        broken.write_text("{not json", encoding="utf-8")
        for args in (
            [str(broken), "--runs", "1"],
            [str(self.dir / "missing.json"), "--runs", "1"],
            [str(CLEAN)],
            [str(CLEAN), "--runs", "0"],
        ):
            proc = subprocess.run(
                [sys.executable, str(SCRIPT), *args],
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(proc.returncode, 2, args)
            self.assertNotIn("verdict:", proc.stdout)
        listed = self.dir / "list.json"
        listed.write_text("[]", encoding="utf-8")
        self.assertEqual(self.run_script(listed, "--runs", "1").returncode, 2)


class WindowsPathTest(unittest.TestCase):
    """inside() under Windows path rules, on any host: a driveless rooted path
    such as /tmp/x, which Python 3.13+ ntpath.isabs calls relative, is still
    classified against the plugin root."""

    ROOT = "/tmp/eval-r2/plugins/evals"

    @classmethod
    def setUpClass(cls):
        spec = importlib.util.spec_from_file_location("run_validity", SCRIPT)
        cls.module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.module)

    def inside(self, path, root=ROOT):
        windows = SimpleNamespace(path=ntpath, sep="\\", altsep="/")
        with mock.patch.object(self.module, "os", windows):
            return self.module.inside(path, [root])

    def test_a_rooted_path_outside_the_plugin_is_outside(self):
        for path in ("/tmp/claude-eval-x", self.ROOT + "-other"):
            self.assertFalse(self.inside(path), path)

    def test_a_rooted_path_under_or_above_the_plugin_is_inside(self):
        for path in (self.ROOT + "/skills/x.md", "/tmp", "\\tmp\\eval-r2"):
            self.assertTrue(self.inside(path), path)

    def test_a_path_on_another_drive_than_the_plugin_is_outside(self):
        self.assertFalse(self.inside("D:\\tmp\\x", "C:\\eval\\plugins\\evals"))
        self.assertTrue(self.inside("c:\\eval", "C:\\eval\\plugins\\evals"))

    def test_a_drive_relative_or_relative_path_is_inside(self):
        for path in ("C:tmp\\x", "tmp/x"):
            self.assertTrue(self.inside(path, "C:\\eval\\plugins\\evals"), path)


if __name__ == "__main__":
    unittest.main()
