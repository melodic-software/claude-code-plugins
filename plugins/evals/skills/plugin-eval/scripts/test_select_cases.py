#!/usr/bin/env python3
# test-scope: plugins/evals/skills/plugin-eval/scripts/select-cases.py plugins/evals/skills/plugin-eval/scripts/select_mapping.py plugins/evals/skills/plugin-eval/scripts/no_run_text.py plugins/evals/scripts/case_skills.py plugins/evals/skills/validate/scripts/validate-cases.py
"""Unit tests for plugins/evals/skills/plugin-eval/scripts/select-cases.py.

Builds throwaway two-plugin git repositories in temporary directories so every
change class, file mapping, grader rule and CLI path is tested offline.
"""

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from select_test_helpers import (
    SCRIPT,
    _build_fixture_repo,
    _commit_all,
    _git,
    _parse_blocks,
    _run_select,
    _write,
)

for _leaked_git_var in ("GIT_DIR", "GIT_WORK_TREE", "GIT_CONFIG"):
    os.environ.pop(_leaked_git_var, None)
os.environ.setdefault("GIT_CONFIG_GLOBAL", os.devnull)
os.environ["GIT_CONFIG_NOSYSTEM"] = "1"


class SelectCasesTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.repo = Path(self._tmp.name)
        _build_fixture_repo(self.repo)

    def tearDown(self):
        self._tmp.cleanup()

    def test_reworded_skill_body_is_cut_and_runs(self):
        path = self.repo / "plugins/alpha/skills/one/SKILL.md"
        text = path.read_text(encoding="utf-8").replace("carefully", "strictly")
        path.write_text(text, encoding="utf-8")
        _commit_all(self.repo, "reword skill body")

        res = _run_select(self.repo)
        self.assertEqual(0, res.returncode, res.stderr)
        blocks = _parse_blocks(res.stdout)
        self.assertEqual(["plugins/alpha"], list(blocks))
        self.assertEqual(
            "control-no-fire one-basic one-trigger",
            blocks["plugins/alpha"]["cases"],
        )
        self.assertEqual("14", blocks["plugins/alpha"]["agent-runs"])
        self.assertNotIn("affected-no-run", blocks["plugins/alpha"])

    def test_added_skill_body_line_is_affected_no_run(self):
        path = self.repo / "plugins/alpha/skills/one/SKILL.md"
        text = path.read_text(encoding="utf-8") + "\nAdditional note for readers.\n"
        path.write_text(text, encoding="utf-8")
        _commit_all(self.repo, "add skill body line")

        res = _run_select(self.repo)
        self.assertEqual(0, res.returncode, res.stderr)
        blocks = _parse_blocks(res.stdout)
        self.assertEqual(["plugins/alpha"], list(blocks))
        self.assertNotIn("cases", blocks["plugins/alpha"])
        self.assertEqual(
            "control-no-fire one-basic one-trigger",
            blocks["plugins/alpha"]["affected-no-run"],
        )
        self.assertEqual("0", blocks["plugins/alpha"]["agent-runs"])

    def test_skill_reference_file_cut_runs(self):
        path = self.repo / "plugins/alpha/skills/one/reference/details.md"
        text = path.read_text(encoding="utf-8").replace("input schema", "request payload")
        path.write_text(text, encoding="utf-8")
        _commit_all(self.repo, "cut skill reference")

        res = _run_select(self.repo)
        self.assertEqual(0, res.returncode, res.stderr)
        blocks = _parse_blocks(res.stdout)
        self.assertEqual(
            "control-no-fire one-basic one-trigger",
            blocks["plugins/alpha"]["cases"],
        )
        self.assertEqual("14", blocks["plugins/alpha"]["agent-runs"])

    def test_plugin_level_reference_cited_by_skill(self):
        path = self.repo / "plugins/alpha/reference/shared.md"
        text = path.read_text(encoding="utf-8").replace("concise", "brief")
        path.write_text(text, encoding="utf-8")
        _commit_all(self.repo, "cut plugin reference")

        res = _run_select(self.repo)
        self.assertEqual(0, res.returncode, res.stderr)
        blocks = _parse_blocks(res.stdout)
        self.assertEqual(
            "control-no-fire one-basic one-trigger",
            blocks["plugins/alpha"]["cases"],
        )

    def test_agent_body_change_direct_and_via_workflow(self):
        agent_a = self.repo / "plugins/alpha/agents/helper.md"
        agent_a.write_text(
            agent_a.read_text(encoding="utf-8").replace("target file", "source file"),
            encoding="utf-8",
        )
        agent_b = self.repo / "plugins/beta/agents/worker.md"
        agent_b.write_text(
            agent_b.read_text(encoding="utf-8").replace("deterministically", "uniformly"),
            encoding="utf-8",
        )
        _commit_all(self.repo, "cut agents")

        res = _run_select(self.repo)
        self.assertEqual(0, res.returncode, res.stderr)
        blocks = _parse_blocks(res.stdout)
        self.assertEqual(["plugins/alpha", "plugins/beta"], list(blocks))
        self.assertEqual(
            "control-no-fire one-basic one-trigger",
            blocks["plugins/alpha"]["cases"],
        )
        self.assertEqual("runner-nested", blocks["plugins/beta"]["cases"])
        self.assertEqual("8", blocks["plugins/beta"]["agent-runs"])

    def test_case_file_change_runs(self):
        path = self.repo / "plugins/alpha/evals/one-basic/prompt.md"
        path.write_text("/alpha:one check this updated item\n", encoding="utf-8")
        _commit_all(self.repo, "edit case prompt")

        res = _run_select(self.repo)
        self.assertEqual(0, res.returncode, res.stderr)
        blocks = _parse_blocks(res.stdout)
        self.assertEqual("one-basic", blocks["plugins/alpha"]["cases"])
        self.assertEqual("6", blocks["plugins/alpha"]["agent-runs"])

    def test_description_only_case_edit_is_no_run(self):
        path = self.repo / "plugins/alpha/evals/one-basic/case.yaml"
        text = path.read_text(encoding="utf-8").replace(
            "Basic case for alpha:one",
            "Clarified description only",
        )
        path.write_text(text, encoding="utf-8")
        _commit_all(self.repo, "description-only case edit")

        res = _run_select(self.repo)
        self.assertEqual(0, res.returncode, res.stderr)
        blocks = _parse_blocks(res.stdout)
        self.assertNotIn("cases", blocks["plugins/alpha"])
        self.assertEqual("one-basic", blocks["plugins/alpha"]["affected-no-run"])
        self.assertEqual("0", blocks["plugins/alpha"]["agent-runs"])

    def test_suite_fixture_cited_by_scaffold(self):
        path = self.repo / "plugins/alpha/evals/fixtures/setup.sh"
        path.write_text("#!/usr/bin/env bash\necho updated\n", encoding="utf-8")
        _commit_all(self.repo, "edit suite fixture")

        res = _run_select(self.repo)
        self.assertEqual(0, res.returncode, res.stderr)
        blocks = _parse_blocks(res.stdout)
        self.assertEqual("one-basic", blocks["plugins/alpha"]["cases"])
        self.assertEqual("6", blocks["plugins/alpha"]["agent-runs"])

    def test_sample_only_change_is_no_run(self):
        path = self.repo / "plugins/alpha/evals/one-basic/samples/check.json"
        path.write_text(
            '{"pass": [{"answer": "ok"}, {"answer": "ok 2"}], "fail": [{"answer": "no"}]}\n',
            encoding="utf-8",
        )
        _commit_all(self.repo, "edit samples")

        res = _run_select(self.repo)
        self.assertEqual(0, res.returncode, res.stderr)
        blocks = _parse_blocks(res.stdout)
        self.assertNotIn("cases", blocks["plugins/alpha"])
        self.assertEqual("one-basic", blocks["plugins/alpha"]["affected-no-run"])
        self.assertEqual("0", blocks["plugins/alpha"]["agent-runs"])

    def test_script_change_is_no_run(self):
        path = self.repo / "plugins/alpha/skills/one/scripts/tool.py"
        path.write_text("def run():\n    return 2\n", encoding="utf-8")
        _commit_all(self.repo, "edit skill script")

        res = _run_select(self.repo)
        self.assertEqual(0, res.returncode, res.stderr)
        blocks = _parse_blocks(res.stdout)
        self.assertNotIn("cases", blocks["plugins/alpha"])
        self.assertEqual(
            "control-no-fire one-basic one-trigger",
            blocks["plugins/alpha"]["affected-no-run"],
        )
        self.assertEqual("0", blocks["plugins/alpha"]["agent-runs"])

    def test_judged_only_case(self):
        path = self.repo / "plugins/alpha/skills/judged-skill/SKILL.md"
        text = path.read_text(encoding="utf-8").replace("clearly", "thoroughly")
        path.write_text(text, encoding="utf-8")
        _commit_all(self.repo, "cut judged skill")

        res = _run_select(self.repo)
        self.assertEqual(0, res.returncode, res.stderr)
        blocks = _parse_blocks(res.stdout)
        self.assertNotIn("cases", blocks["plugins/alpha"])
        self.assertEqual("judged-case", blocks["plugins/alpha"]["judged"])
        self.assertEqual("6", blocks["plugins/alpha"]["agent-runs"])

    def test_mixed_case_and_custom_runs(self):
        path = self.repo / "plugins/alpha/skills/mixed-skill/SKILL.md"
        text = path.read_text(encoding="utf-8").replace("summary line", "headline")
        path.write_text(text, encoding="utf-8")
        _commit_all(self.repo, "cut mixed skill")

        res = _run_select(self.repo)
        self.assertEqual(0, res.returncode, res.stderr)
        blocks = _parse_blocks(res.stdout)
        self.assertEqual("mixed-case", blocks["plugins/alpha"]["cases"])
        self.assertNotIn("judged", blocks["plugins/alpha"])
        self.assertEqual("10", blocks["plugins/alpha"]["agent-runs"])

    def test_optional_prefix_skill_grader(self):
        path = self.repo / "plugins/alpha/skills/opt-skill/SKILL.md"
        text = path.read_text(encoding="utf-8").replace("flow", "pipeline")
        path.write_text(text, encoding="utf-8")
        _commit_all(self.repo, "cut opt skill")

        res = _run_select(self.repo)
        self.assertEqual(0, res.returncode, res.stderr)
        blocks = _parse_blocks(res.stdout)
        self.assertEqual("opt-case", blocks["plugins/alpha"]["cases"])
        self.assertEqual("6", blocks["plugins/alpha"]["agent-runs"])

    def test_unreadable_grader_reported(self):
        _write(
            self.repo,
            "plugins/alpha/evals/weird-case/prompt.md",
            """
            ---
            description: "Case with alternation grader"
            ---

            Do something ambiguous.
            """,
        )
        _write(
            self.repo,
            "plugins/alpha/evals/weird-case/graders/ambiguous.md",
            """
            ---
            type: tool_used
            tool: Skill
            input_match: 'alpha:(one|two)'
            ---
            """,
        )
        _commit_all(self.repo, "add weird grader")
        _git(self.repo, "branch", "-f", "base")

        path = self.repo / "plugins/alpha/skills/one/SKILL.md"
        text = path.read_text(encoding="utf-8").replace("carefully", "promptly")
        path.write_text(text, encoding="utf-8")
        _commit_all(self.repo, "cut alpha one")

        res = _run_select(self.repo)
        self.assertEqual(0, res.returncode, res.stderr)
        blocks = _parse_blocks(res.stdout)
        self.assertEqual(
            "weird-case/ambiguous",
            blocks["plugins/alpha"]["unread-graders"],
        )

    def test_changed_skill_with_no_case_is_uncovered(self):
        path = self.repo / "plugins/alpha/skills/uncovered-skill/SKILL.md"
        text = path.read_text(encoding="utf-8").replace("behavior", "actions")
        path.write_text(text, encoding="utf-8")
        _commit_all(self.repo, "cut uncovered skill")

        res = _run_select(self.repo)
        self.assertEqual(0, res.returncode, res.stderr)
        blocks = _parse_blocks(res.stdout)
        self.assertEqual("alpha:uncovered-skill", blocks["plugins/alpha"]["uncovered"])
        self.assertEqual("0", blocks["plugins/alpha"]["agent-runs"])

    def test_unmapped_file(self):
        _write(
            self.repo,
            "plugins/alpha/mystery/notes.md",
            """
            Unmapped file content.
            """,
        )
        _commit_all(self.repo, "add unmapped file")

        res = _run_select(self.repo)
        self.assertEqual(0, res.returncode, res.stderr)
        blocks = _parse_blocks(res.stdout)
        self.assertEqual(
            "plugins/alpha/mystery/notes.md",
            blocks["plugins/alpha"]["unmapped"],
        )
        self.assertEqual("0", blocks["plugins/alpha"]["agent-runs"])

    def test_no_affected_cases(self):
        path = self.repo / "docs/guide.md"
        path.write_text("# Guide\n\nUpdated docs.\n", encoding="utf-8")
        _commit_all(self.repo, "docs only")

        res = _run_select(self.repo)
        self.assertEqual(0, res.returncode, res.stderr)
        self.assertEqual("no affected cases", res.stdout.strip())

        res_json = _run_select(self.repo, as_json=True)
        self.assertEqual(0, res_json.returncode, res_json.stderr)
        self.assertEqual({}, json.loads(res_json.stdout))

    def test_nested_case_file_change(self):
        path = self.repo / "plugins/beta/evals/group/sub/nested-dir/graders/ok.md"
        text = path.read_text(encoding="utf-8").replace("done", "complete")
        path.write_text(text, encoding="utf-8")
        _commit_all(self.repo, "edit nested case grader")

        res = _run_select(self.repo)
        self.assertEqual(0, res.returncode, res.stderr)
        blocks = _parse_blocks(res.stdout)
        self.assertEqual(["plugins/beta"], list(blocks))
        self.assertEqual("runner-nested", blocks["plugins/beta"]["cases"])
        self.assertEqual("8", blocks["plugins/beta"]["agent-runs"])

    def test_additive_only_description_edit_runs_after_merge(self):
        path = self.repo / "plugins/alpha/skills/one/SKILL.md"
        text = path.read_text(encoding="utf-8").replace(
            'description: "Run alpha one checks. Use when checking alpha items."',
            'description: "Run alpha one checks. Use when checking alpha items. Also use for alpha audits."',
        )
        path.write_text(text, encoding="utf-8")
        _commit_all(self.repo, "additive description edit")

        res = _run_select(self.repo)
        self.assertEqual(0, res.returncode, res.stderr)
        blocks = _parse_blocks(res.stdout)
        self.assertNotIn("cases", blocks["plugins/alpha"])
        self.assertEqual(
            "control-no-fire one-trigger opt-case",
            blocks["plugins/alpha"]["run-after-merge"],
        )
        self.assertEqual("14", blocks["plugins/alpha"]["agent-runs"])

    def test_description_edit_skips_slash_invoked_case_with_skill_grader(self):
        grader = self.repo / "plugins/alpha/evals/one-basic/graders/fired.md"
        grader.write_text(
            "---\ntype: tool_used\ntool: Skill\ninput_match: '\"skill\"\\s*:\\s*\"alpha:one\"'\nmin: 1\n---\n",
            encoding="utf-8",
        )
        _commit_all(self.repo, "slash-invoked case with a Skill grader")
        base = _git(self.repo, "rev-parse", "HEAD").strip()
        path = self.repo / "plugins/alpha/skills/one/SKILL.md"
        text = path.read_text(encoding="utf-8").replace(
            'description: "Run alpha one checks. Use when checking alpha items."',
            'description: "Run alpha one checks. Use when checking alpha items. Also use for alpha audits."',
        )
        path.write_text(text, encoding="utf-8")
        _commit_all(self.repo, "additive description edit")

        res = _run_select(self.repo, base)
        self.assertEqual(0, res.returncode, res.stderr)
        blocks = _parse_blocks(res.stdout)
        self.assertNotIn("one-basic", blocks["plugins/alpha"]["run-after-merge"].split())

    def test_reworded_description_is_cut_and_runs_before_merge(self):
        path = self.repo / "plugins/alpha/skills/one/SKILL.md"
        text = path.read_text(encoding="utf-8").replace(
            'description: "Run alpha one checks. Use when checking alpha items."',
            'description: "Run alpha one audits. Use when reviewing alpha items."',
        )
        path.write_text(text, encoding="utf-8")
        _commit_all(self.repo, "reword description")

        res = _run_select(self.repo)
        self.assertEqual(0, res.returncode, res.stderr)
        blocks = _parse_blocks(res.stdout)
        self.assertNotIn("run-after-merge", blocks["plugins/alpha"])
        self.assertEqual(
            "control-no-fire one-basic one-trigger opt-case",
            blocks["plugins/alpha"]["cases"],
        )
        self.assertEqual("20", blocks["plugins/alpha"]["agent-runs"])

    def test_plugin_wide_files(self):
        _write(
            self.repo,
            "plugins/alpha/hooks/guard.sh",
            """
            #!/usr/bin/env bash
            exit 0
            """,
        )
        _write(
            self.repo,
            "plugins/alpha/.mcp.json",
            """
            {"mcpServers": {}}
            """,
        )
        _commit_all(self.repo, "plugin-wide edits")

        res = _run_select(self.repo)
        self.assertEqual(0, res.returncode, res.stderr)
        blocks = _parse_blocks(res.stdout)
        self.assertEqual(
            "plugins/alpha/.mcp.json plugins/alpha/hooks/guard.sh",
            blocks["plugins/alpha"]["plugin-wide"],
        )
        self.assertNotIn("cases", blocks["plugins/alpha"])
        self.assertEqual("0", blocks["plugins/alpha"]["agent-runs"])

    def test_cross_plugin_case_and_json_output(self):
        _write(
            self.repo,
            "plugins/beta/evals/calls-alpha/prompt.md",
            """
            ---
            description: "Cross-plugin case targeting alpha:one"
            runs: 2
            ---

            /alpha:one run from beta
            """,
        )
        _write(
            self.repo,
            "plugins/beta/evals/calls-alpha/graders/ok.md",
            """
            ---
            type: regex
            pattern: "ok"
            ---
            """,
        )
        _commit_all(self.repo, "add cross-plugin case")
        _git(self.repo, "branch", "-f", "base")

        path = self.repo / "plugins/alpha/skills/one/SKILL.md"
        text = path.read_text(encoding="utf-8").replace("carefully", "strictly")
        path.write_text(text, encoding="utf-8")
        _commit_all(self.repo, "cut alpha one")

        res = _run_select(self.repo, as_json=True)
        self.assertEqual(0, res.returncode, res.stderr)
        payload = json.loads(res.stdout)
        self.assertEqual(["plugins/alpha", "plugins/beta"], sorted(payload))
        self.assertEqual(["calls-alpha"], payload["plugins/beta"]["cases"])
        self.assertEqual(4, payload["plugins/beta"]["agent-runs"])
        self.assertEqual(
            ["control-no-fire", "one-basic", "one-trigger"],
            payload["plugins/alpha"]["cases"],
        )
        self.assertEqual(14, payload["plugins/alpha"]["agent-runs"])

    def test_invalid_diff_base_exits_2(self):
        res = _run_select(self.repo, diff_base="refs/heads/does-not-exist")
        self.assertEqual(2, res.returncode)
        self.assertTrue(res.stderr.strip())

    def test_missing_args_exits_2(self):
        res = subprocess.run(
            [sys.executable, str(SCRIPT)],
            capture_output=True,
            text=True,
        )
        self.assertEqual(2, res.returncode)

    def test_rewrapped_skill_body_and_added_line_is_no_run(self):
        path = self.repo / "plugins/alpha/skills/one/SKILL.md"
        text = path.read_text(encoding="utf-8").replace(
            "Follow these steps carefully.\nRead [details](reference/details.md)",
            "Follow these steps carefully. Read [details](reference/details.md)",
        )
        text += "\nExtra additive note.\n"
        path.write_text(text, encoding="utf-8")
        _commit_all(self.repo, "rewrap and add line")

        res = _run_select(self.repo)
        self.assertEqual(0, res.returncode, res.stderr)
        blocks = _parse_blocks(res.stdout)
        self.assertNotIn("cases", blocks["plugins/alpha"])
        self.assertEqual(
            "control-no-fire one-basic one-trigger",
            blocks["plugins/alpha"]["affected-no-run"],
        )
        self.assertEqual("0", blocks["plugins/alpha"]["agent-runs"])

    def test_rewrap_with_an_inserted_word_is_cut(self):
        path = self.repo / "plugins/alpha/skills/one/SKILL.md"
        text = path.read_text(encoding="utf-8").replace(
            "Follow these steps carefully.\nRead [details](reference/details.md)",
            "Do not follow these steps carefully. Read [details](reference/details.md)",
        )
        path.write_text(text, encoding="utf-8")
        _commit_all(self.repo, "rewrap with an inserted word")

        res = _run_select(self.repo)
        self.assertEqual(0, res.returncode, res.stderr)
        blocks = _parse_blocks(res.stdout)
        self.assertEqual(
            "control-no-fire one-basic one-trigger",
            blocks["plugins/alpha"]["cases"],
        )

    def test_when_to_use_additive_and_cut(self):
        path = self.repo / "plugins/alpha/skills/one/SKILL.md"
        text = path.read_text(encoding="utf-8").replace(
            'description: "Run alpha one checks. Use when checking alpha items."',
            'description: "Run alpha one checks. Use when checking alpha items."\nwhen_to_use: "Use on alpha checks."',
        )
        path.write_text(text, encoding="utf-8")
        _commit_all(self.repo, "add when_to_use")

        res_add = _run_select(self.repo)
        self.assertEqual(0, res_add.returncode, res_add.stderr)
        blocks_add = _parse_blocks(res_add.stdout)
        self.assertNotIn("cases", blocks_add["plugins/alpha"])
        self.assertEqual(
            "control-no-fire one-trigger opt-case",
            blocks_add["plugins/alpha"]["run-after-merge"],
        )

        _git(self.repo, "branch", "-f", "base")
        path.write_text(
            path.read_text(encoding="utf-8").replace(
                'when_to_use: "Use on alpha checks."',
                'when_to_use: "Use on alpha audits."',
            ),
            encoding="utf-8",
        )
        _commit_all(self.repo, "reword when_to_use")

        res_cut = _run_select(self.repo)
        self.assertEqual(0, res_cut.returncode, res_cut.stderr)
        blocks_cut = _parse_blocks(res_cut.stdout)
        self.assertNotIn("run-after-merge", blocks_cut["plugins/alpha"])
        self.assertEqual(
            "control-no-fire one-basic one-trigger opt-case",
            blocks_cut["plugins/alpha"]["cases"],
        )

    def test_uncovered_agent_reported(self):
        _write(
            self.repo,
            "plugins/alpha/agents/lone.md",
            """
            ---
            name: lone
            ---

            Handle isolated task.
            """,
        )
        _commit_all(self.repo, "add lone agent")

        res = _run_select(self.repo)
        self.assertEqual(0, res.returncode, res.stderr)
        blocks = _parse_blocks(res.stdout)
        self.assertEqual("alpha:lone", blocks["plugins/alpha"]["uncovered"])
        self.assertEqual("0", blocks["plugins/alpha"]["agent-runs"])

    def test_uncited_plugin_reference_is_unmapped(self):
        _write(
            self.repo,
            "plugins/alpha/reference/orphan.md",
            """
            # Orphan

            Cited by no skill.
            """,
        )
        _commit_all(self.repo, "add uncited reference")

        res = _run_select(self.repo)
        self.assertEqual(0, res.returncode, res.stderr)
        blocks = _parse_blocks(res.stdout)
        self.assertEqual(
            "plugins/alpha/reference/orphan.md",
            blocks["plugins/alpha"]["unmapped"],
        )

    def test_plugin_level_script_change_is_no_run_and_not_unmapped(self):
        path = self.repo / "plugins/alpha/scripts/util.py"
        path.write_text("def helper():\n    return False\n", encoding="utf-8")
        _commit_all(self.repo, "edit plugin-level script")

        res = _run_select(self.repo)
        self.assertEqual(0, res.returncode, res.stderr)
        self.assertEqual("no affected cases", res.stdout.strip())

    def test_inserted_word_is_a_cut_only_when_it_flips_meaning(self):
        _write(
            self.repo,
            "plugins/alpha/skills/check/SKILL.md",
            """
            ---
            description: "Check failures."
            ---

            # Check

            Do continue on failure.
            """,
        )
        _write(
            self.repo,
            "plugins/alpha/evals/check/prompt.md",
            """
            /alpha:check inspect this run
            """,
        )
        _write(
            self.repo,
            "plugins/alpha/evals/check/graders/ok.md",
            """
            ---
            type: regex
            pattern: "ok"
            ---
            """,
        )
        _commit_all(self.repo, "add check skill")
        _git(self.repo, "branch", "-f", "base")

        path = self.repo / "plugins/alpha/skills/check/SKILL.md"
        original = path.read_text(encoding="utf-8")
        flips = ["not", "never", "no", "don't", "only", "except", "unless", "cannot", "can't", "won't",
                 "shouldn't", "mustn't", "don\u2019t"]
        for word, expected in [(w, "cases") for w in flips] + [("quietly", "affected-no-run")]:
            with self.subTest(word=word):
                path.write_text(
                    original.replace("Do continue on failure.", "Do %s continue on failure." % word),
                    encoding="utf-8",
                )
                _commit_all(self.repo, "insert %s" % word)

                res = _run_select(self.repo)
                self.assertEqual(0, res.returncode, res.stderr)
                blocks = _parse_blocks(res.stdout)
                self.assertEqual("check", blocks["plugins/alpha"].get(expected))
                _git(self.repo, "reset", "-q", "--hard", "base")


    def test_flip_word_on_a_wholly_new_line_stays_additive(self):
        path = self.repo / "plugins/alpha/skills/one/SKILL.md"
        text = path.read_text(encoding="utf-8").replace(
            "Follow these steps carefully.",
            "Follow these steps very carefully.\nNever write to the source file.",
        )
        path.write_text(text, encoding="utf-8")
        _commit_all(self.repo, "edit a line and add a new one beside it")

        res = _run_select(self.repo)
        self.assertEqual(0, res.returncode, res.stderr)
        blocks = _parse_blocks(res.stdout)
        self.assertNotIn("cases", blocks["plugins/alpha"])

if __name__ == "__main__":
    unittest.main()
