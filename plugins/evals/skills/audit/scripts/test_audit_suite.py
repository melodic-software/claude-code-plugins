#!/usr/bin/env python3
# test-scope: plugins/evals/scripts/case_skills.py
# test-scope: plugins/evals/skills/validate/scripts/validate-cases.py
# test-scope: plugins/evals/skills/audit/scripts/audit-suite.py
# test-scope: plugins/evals/evals/*
"""Fixture suite for audit-suite.py.

Run directly with: python3 plugins/evals/skills/audit/scripts/test_audit_suite.py
"""

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from textwrap import dedent

SCRIPT = Path(__file__).resolve().parent / "audit-suite.py"
REPO_ROOT = Path(__file__).resolve().parents[5]
EVALS_PLUGIN = REPO_ROOT / "plugins" / "evals"


def write_file(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def run_audit(*args):
    return subprocess.run(
        [sys.executable, str(SCRIPT), *args],
        capture_output=True,
        text=True,
        encoding="utf-8",
    )


def snapshot_tree(root):
    entries = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames.sort()
        for name in sorted(filenames):
            full = Path(dirpath) / name
            rel = full.relative_to(root).as_posix()
            entries.append((rel, full.read_bytes()))
    return entries


def build_fixture_plugin(root):
    plugin = root / "demo"
    write_file(
        plugin / ".claude-plugin" / "plugin.json",
        json.dumps({"name": "demo", "description": "Fixture plugin"}) + "\n",
    )
    for skill in (
        "bare-skill",
        "covered-skill",
        "judged-only-skill",
        "legacy-only-skill",
        "no-neg-skill",
    ):
        write_file(
            plugin / "skills" / skill / "SKILL.md",
            f"---\ndescription: Fixture {skill}\n---\n\n# {skill}\n",
        )

    write_file(
        plugin / "skills" / "legacy-only-skill" / "evals" / "evals.json",
        json.dumps({"evals": [{"id": 1, "prompt": "legacy prompt"}]}) + "\n",
    )

    write_file(
        plugin / "evals" / "covered-fire" / "prompt.md",
        dedent(
            """\
            ---
            description: Triggering case for covered-skill
            tags: [covered-skill]
            ---

            Run the covered workflow.
            """
        ),
    )
    write_file(
        plugin / "evals" / "covered-fire" / "case.yaml",
        dedent(
            """\
            schema_version: "1.1"
            name: covered-fire
            graders:
              - name: skill-fired
                type: tool_used
                tool: Skill
                input_match: '"skill"\\s*:\\s*"(?:demo:)?covered-skill"'
              - name: calibrated-judge
                type: llm
                focus: last_message
                criteria: Answer mentions the workflow.
            """
        ),
    )
    write_file(
        plugin / "evals" / "covered-fire" / "samples" / "calibrated-judge.json",
        json.dumps(
            {
                "pass": [
                    {"answer": "pass 1", "why": "ok"},
                    {"answer": "pass 2", "why": "ok"},
                    {"answer": "pass 3", "why": "ok"},
                ],
                "fail": [
                    {"answer": "fail 1", "why": "missing"},
                    {"answer": "fail 2", "why": "wrong"},
                ],
            }
        )
        + "\n",
    )

    write_file(
        plugin / "evals" / "covered-no-fire" / "prompt.md",
        dedent(
            """\
            ---
            description: Should-not-fire case for covered-skill
            tags: [covered-skill]
            ---

            Answer an unrelated question.
            """
        ),
    )
    write_file(
        plugin / "evals" / "covered-no-fire" / "graders" / "no-skill.md",
        dedent(
            """\
            ---
            type: tool_used
            tool: Skill
            input_match: '"skill"\\s*:\\s*"(?:demo:)?covered-skill"'
            min: 0
            max: 0
            arm: both
            ---
            """
        ),
    )

    write_file(
        plugin / "evals" / "judged-only-case" / "prompt.md",
        dedent(
            """\
            ---
            description: Judged-only case
            tags: [judged-only-skill]
            ---

            Check the judged-only behavior.
            """
        ),
    )
    write_file(
        plugin / "evals" / "judged-only-case" / "graders" / "uncalibrated-llm.md",
        dedent(
            """\
            ---
            type: llm
            focus: last_message
            ---

            Check quality.
            """
        ),
    )
    write_file(
        plugin / "evals" / "judged-only-case" / "graders" / "empty-samples-llm.md",
        dedent(
            """\
            ---
            type: llm
            focus: last_message
            ---

            Check empty samples.
            """
        ),
    )
    write_file(
        plugin / "evals" / "judged-only-case" / "samples" / "empty-samples-llm.json",
        json.dumps({"pass": [], "fail": []}) + "\n",
    )
    write_file(
        plugin / "evals" / "judged-only-case" / "graders" / "uncalibrated-baseline.md",
        dedent(
            """\
            ---
            type: baseline
            baseline_file: baseline.txt
            ---

            Compare with baseline.
            """
        ),
    )
    write_file(
        plugin / "evals" / "judged-only-case" / "graders" / "calibrated-baseline.md",
        dedent(
            """\
            ---
            type: baseline
            baseline_file: baseline.txt
            ---

            Compare with calibrated baseline.
            """
        ),
    )
    write_file(
        plugin / "evals" / "judged-only-case" / "samples" / "calibrated-baseline.json",
        json.dumps(
            {
                "pass": [
                    {"answer": "ok 1"},
                    {"answer": "ok 2"},
                ],
                "fail": [
                    {"answer": "bad 1"},
                ],
            }
        )
        + "\n",
    )

    write_file(
        plugin / "evals" / "no-neg-fire" / "prompt.md",
        dedent(
            """\
            ---
            description: Triggering case without a should-not-fire counterpart
            tags: [no-neg-skill]
            ---

            Use the no-neg workflow.
            """
        ),
    )
    write_file(
        plugin / "evals" / "no-neg-fire" / "graders" / "skill-fired.md",
        dedent(
            """\
            ---
            type: tool_used
            tool: Skill
            input_match: '"skill"\\s*:\\s*"demo:no-neg-skill"'
            ---
            """
        ),
    )
    return plugin


class AuditSuiteTests(unittest.TestCase):
    def test_fixture_plugin_json_and_text(self):
        with tempfile.TemporaryDirectory() as tmp:
            plugin = build_fixture_plugin(Path(tmp))
            before = snapshot_tree(plugin)

            json_run = run_audit(str(plugin), "--json")
            self.assertEqual(json_run.returncode, 0, json_run.stderr)
            report = json.loads(json_run.stdout)

            self.assertEqual(report["plugin"], "demo")
            self.assertEqual(report["counts"]["no_case"], 1)
            self.assertEqual(
                [item["skill"] for item in report["no_case"]],
                ["demo:bare-skill"],
            )
            self.assertEqual(report["no_case"][0]["route"], "/evals:design")

            self.assertEqual(report["counts"]["no_deterministic_trigger"], 1)
            self.assertEqual(
                [item["skill"] for item in report["no_deterministic_trigger"]],
                ["demo:judged-only-skill"],
            )
            self.assertEqual(
                report["no_deterministic_trigger"][0]["route"], "/evals:design"
            )

            self.assertEqual(report["counts"]["judged_without_samples"], 3)
            self.assertEqual(
                [(i["case"], i["grader"], i["type"]) for i in report["judged_without_samples"]],
                [
                    ("judged-only-case", "empty-samples-llm", "llm"),
                    ("judged-only-case", "uncalibrated-baseline", "baseline"),
                    ("judged-only-case", "uncalibrated-llm", "llm"),
                ],
            )
            for item in report["judged_without_samples"]:
                self.assertEqual(item["route"], "/evals:plugin-eval")

            self.assertEqual(report["counts"]["judged_with_samples"], 2)
            self.assertEqual(
                [
                    (i["case"], i["grader"], i["type"], i["pass"], i["fail"])
                    for i in report["judged_with_samples"]
                ],
                [
                    ("covered-fire", "calibrated-judge", "llm", 3, 2),
                    ("judged-only-case", "calibrated-baseline", "baseline", 2, 1),
                ],
            )

            self.assertEqual(report["counts"]["legacy_only"], 1)
            self.assertEqual(
                [item["skill"] for item in report["legacy_only"]],
                ["demo:legacy-only-skill"],
            )
            self.assertEqual(report["legacy_only"][0]["route"], "/evals:design")

            self.assertEqual(report["counts"]["no_should_not_fire"], 2)
            self.assertEqual(
                [item["skill"] for item in report["no_should_not_fire"]],
                ["demo:judged-only-skill", "demo:no-neg-skill"],
            )
            for item in report["no_should_not_fire"]:
                self.assertEqual(item["route"], "/evals:design")

            all_reported_skills = {
                item["skill"]
                for key in (
                    "no_case",
                    "no_deterministic_trigger",
                    "legacy_only",
                    "no_should_not_fire",
                )
                for item in report[key]
            }
            self.assertNotIn("demo:covered-skill", all_reported_skills)

            text_run = run_audit(str(plugin))
            self.assertEqual(text_run.returncode, 0, text_run.stderr)
            out = text_run.stdout
            self.assertIn("skills with no case: 1\n", out)
            self.assertIn("  demo:bare-skill [/evals:design]\n", out)
            self.assertIn("skills with no deterministic triggering case: 1\n", out)
            self.assertIn("  demo:judged-only-skill [/evals:design]\n", out)
            self.assertIn("judged graders without samples: 3\n", out)
            self.assertIn(
                "  judged-only-case/uncalibrated-llm (llm): no samples/uncalibrated-llm.json [/evals:plugin-eval]\n",
                out,
            )
            self.assertIn(
                "  judged-only-case/uncalibrated-baseline (baseline): no samples/uncalibrated-baseline.json [/evals:plugin-eval]\n",
                out,
            )
            self.assertIn("judged graders with samples: 2\n", out)
            self.assertIn(
                "  covered-fire/calibrated-judge (llm): 3 PASS, 2 FAIL\n", out
            )
            self.assertIn(
                "  judged-only-case/calibrated-baseline (baseline): 2 PASS, 1 FAIL\n",
                out,
            )
            self.assertIn("legacy-only skills: 1\n", out)
            self.assertIn(
                "  demo:legacy-only-skill (skills/legacy-only-skill/evals/evals.json) [/evals:design]\n",
                out,
            )
            self.assertIn("skills with no should-not-fire case (advisory): 2\n", out)
            self.assertIn("  demo:no-neg-skill [/evals:design]\n", out)

            self.assertEqual(before, snapshot_tree(plugin))

    def test_suite_dir_target_resolves_parent_plugin(self):
        with tempfile.TemporaryDirectory() as tmp:
            plugin = build_fixture_plugin(Path(tmp))
            by_plugin = json.loads(run_audit(str(plugin), "--json").stdout)
            by_suite = json.loads(run_audit(str(plugin / "evals"), "--json").stdout)
            self.assertEqual(by_plugin["counts"], by_suite["counts"])
            self.assertEqual(by_plugin["no_case"], by_suite["no_case"])
            self.assertEqual(by_plugin["legacy_only"], by_suite["legacy_only"])

    def test_standalone_suite_dir_without_plugin_manifest(self):
        with tempfile.TemporaryDirectory() as tmp:
            suite = Path(tmp) / "standalone-suite"
            write_file(suite / "nested" / "case-a" / "prompt.md", "Answer plainly.\n")
            write_file(
                suite / "nested" / "case-a" / "graders" / "judge.md",
                "---\ntype: llm\n---\n\nBe accurate.\n",
            )
            run = run_audit(str(suite), "--json")
            self.assertEqual(run.returncode, 0, run.stderr)
            report = json.loads(run.stdout)
            self.assertEqual(report["skills"], [])
            self.assertEqual(report["case_count"], 1)
            self.assertEqual(report["counts"]["judged_without_samples"], 1)
            self.assertEqual(
                report["judged_without_samples"][0]["case"], "nested/case-a"
            )

    def test_other_skill_negation_and_alternation_trigger(self):
        with tempfile.TemporaryDirectory() as tmp:
            plugin = Path(tmp) / "alpha"
            write_file(
                plugin / ".claude-plugin" / "plugin.json",
                json.dumps({"name": "alpha"}) + "\n",
            )
            for skill in ("one", "two"):
                write_file(
                    plugin / "skills" / skill / "SKILL.md",
                    f"---\ndescription: {skill}\n---\n",
                )
            write_file(
                plugin / "skills" / "one" / "evals" / "evals.json",
                json.dumps({"evals": []}) + "\n",
            )
            write_file(
                plugin / "evals" / "one-case" / "prompt.md",
                "---\ntags: [one]\n---\n\n/alpha:one run it\n",
            )
            write_file(
                plugin / "evals" / "one-case" / "case.yaml",
                dedent(
                    """\
                    schema_version: "1.1"
                    name: one-case
                    graders:
                      - name: did-not-call-other
                        type: tool_used
                        tool: Skill
                        input_match: '(?=.*"skill"\\s*:\\s*"other-plugin")(?=.*helper)'
                        min: 0
                        max: 0
                        arm: with-only
                      - name: skill-fired
                        type: tool_used
                        tool: Skill
                        input_match: '"skill"\\s*:\\s*"(?:alpha:)?(?:one|two)"'
                    """
                ),
            )
            write_file(
                plugin / "evals" / "two-case" / "prompt.md",
                "---\ntags: [two]\n---\n\nRun two.\n",
            )
            write_file(
                plugin / "evals" / "two-case" / "case.yaml",
                dedent(
                    """\
                    schema_version: "1.1"
                    name: two-case
                    graders:
                      - name: wrong-skill-fired
                        type: tool_used
                        tool: Skill
                        input_match: '"skill":"other:elsewhere"'
                    """
                ),
            )

            run = run_audit(str(plugin), "--json")
            self.assertEqual(run.returncode, 0, run.stderr)
            report = json.loads(run.stdout)
            self.assertEqual(report["legacy_only"], [])
            self.assertEqual(
                [item["skill"] for item in report["no_deterministic_trigger"]],
                ["alpha:two"],
            )
            self.assertEqual(
                [item["skill"] for item in report["no_should_not_fire"]],
                ["alpha:one", "alpha:two"],
            )

    def test_unconstrained_skill_grader_is_not_trigger_coverage(self):
        with tempfile.TemporaryDirectory() as tmp:
            plugin = Path(tmp) / "loose"
            write_file(
                plugin / ".claude-plugin" / "plugin.json",
                json.dumps({"name": "loose"}) + "\n",
            )
            write_file(
                plugin / "skills" / "only" / "SKILL.md", "---\ndescription: only\n---\n"
            )
            write_file(
                plugin / "evals" / "fire" / "prompt.md",
                "---\ntags: [only]\n---\n\nDo only.\n",
            )
            write_file(
                plugin / "evals" / "fire" / "graders" / "fired.md",
                "---\ntype: tool_used\ntool: Skill\nmin: 1\n---\n",
            )

            run = run_audit(str(plugin), "--json")
            self.assertEqual(run.returncode, 0, run.stderr)
            report = json.loads(run.stdout)
            self.assertEqual(report["counts"]["no_deterministic_trigger"], 1)

    def test_custom_experimental_evals_dir(self):
        with tempfile.TemporaryDirectory() as tmp:
            plugin = Path(tmp) / "custom"
            write_file(
                plugin / ".claude-plugin" / "plugin.json",
                json.dumps({"name": "custom", "experimental": {"evals": "my-evals"}})
                + "\n",
            )
            write_file(
                plugin / "skills" / "only" / "SKILL.md", "---\ndescription: only\n---\n"
            )
            write_file(
                plugin / "my-evals" / "fire" / "prompt.md",
                "---\ntags: [only]\n---\n\nDo only.\n",
            )
            write_file(
                plugin / "my-evals" / "fire" / "graders" / "fired.md",
                '---\ntype: tool_used\ntool: Skill\ninput_match: \'"skill":"custom:only"\'\n---\n',
            )
            write_file(
                plugin / "my-evals" / "no-fire" / "prompt.md",
                "---\ntags: [only]\n---\n\nUnrelated.\n",
            )
            write_file(
                plugin / "my-evals" / "no-fire" / "graders" / "quiet.md",
                '---\ntype: tool_used\ntool: Skill\nmin: 0\nmax: 0\n---\n',
            )

            run = run_audit(str(plugin), "--json")
            self.assertEqual(run.returncode, 0, run.stderr)
            report = json.loads(run.stdout)
            self.assertEqual(report["counts"]["no_case"], 0)
            self.assertEqual(report["counts"]["no_deterministic_trigger"], 0)
            self.assertEqual(report["counts"]["no_should_not_fire"], 0)
            self.assertEqual(report["counts"]["legacy_only"], 0)
            self.assertEqual(report["counts"]["judged_without_samples"], 0)

    def test_usage_errors_exit_two(self):
        with tempfile.TemporaryDirectory() as tmp:
            missing = Path(tmp) / "does-not-exist"
            self.assertEqual(run_audit(str(missing)).returncode, 2)
            a_file = Path(tmp) / "plain.txt"
            a_file.write_text("hi", encoding="utf-8")
            self.assertEqual(run_audit(str(a_file)).returncode, 2)
        self.assertEqual(run_audit().returncode, 2)
        self.assertEqual(run_audit("--unknown-flag").returncode, 2)

    def test_live_evals_plugin_runs_cleanly(self):
        run = run_audit(str(EVALS_PLUGIN), "--json")
        self.assertEqual(run.returncode, 0, run.stderr)
        report = json.loads(run.stdout)
        self.assertEqual(report["plugin"], "evals")
        self.assertGreater(report["case_count"], 0)


if __name__ == "__main__":
    unittest.main()
