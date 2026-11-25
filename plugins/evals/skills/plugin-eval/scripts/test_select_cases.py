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

    def _base_with_next_section(self):
        path = self.repo / "plugins/alpha/skills/one/SKILL.md"
        text = path.read_text(encoding="utf-8") + (
            "\n## Next\n\n- Done, when available: /alpha:two\n- Stuck: /alpha:three\n"
            "\n## Gotchas\n\n- Keep it short.\n"
        )
        path.write_text(text, encoding="utf-8")
        _commit_all(self.repo, "add Next section")
        _git(self.repo, "branch", "-f", "base", "HEAD")
        return path

    def test_next_section_edit_is_no_run(self):
        path = self._base_with_next_section()
        text = path.read_text(encoding="utf-8").replace(
            "- Done, when available: /alpha:two\n", "- Done: /alpha:two.\n"
        )
        path.write_text(text.replace("- Stuck: /alpha:three\n", ""), encoding="utf-8")
        _commit_all(self.repo, "trim Next")

        res = _run_select(self.repo)
        self.assertEqual(0, res.returncode, res.stderr)
        blocks = _parse_blocks(res.stdout)
        self.assertNotIn("cases", blocks["plugins/alpha"])
        self.assertEqual("0", blocks["plugins/alpha"]["agent-runs"])

    def test_edit_outside_next_section_still_cuts(self):
        path = self._base_with_next_section()
        text = path.read_text(encoding="utf-8").replace("- Keep it short.\n", "- Keep it long.\n")
        path.write_text(text.replace("- Stuck: /alpha:three\n", ""), encoding="utf-8")
        _commit_all(self.repo, "trim Next and reword a gotcha")

        res = _run_select(self.repo)
        self.assertEqual(0, res.returncode, res.stderr)
        blocks = _parse_blocks(res.stdout)
        self.assertEqual(
            "control-no-fire one-basic one-trigger",
            blocks["plugins/alpha"]["cases"],
        )

    def _base_with_sections(self, headings):
        path = self.repo / "plugins/alpha/skills/one/SKILL.md"
        extra = "".join("\n## %s\n\n- Sibling: /alpha:two\n" % h for h in headings)
        path.write_text(
            path.read_text(encoding="utf-8") + extra + "\n## Gotchas\n\n- Keep it short.\n",
            encoding="utf-8",
        )
        _commit_all(self.repo, "add sections")
        _git(self.repo, "branch", "-f", "base", "HEAD")
        return path

    def _edit_and_select(self, path, old, new):
        text = path.read_text(encoding="utf-8")
        self.assertIn(old, text)
        path.write_text(text.replace(old, new), encoding="utf-8")
        _commit_all(self.repo, "edit skill")
        res = _run_select(self.repo)
        self.assertEqual(0, res.returncode, res.stderr)
        return _parse_blocks(res.stdout)["plugins/alpha"]

    def test_related_and_see_also_section_edits_are_no_run(self):
        path = self._base_with_sections(["Related", "See also"])
        block = self._edit_and_select(
            path, "- Sibling: /alpha:two\n", "- Sibling, for audits: /alpha:three\n"
        )
        self.assertNotIn("cases", block, "Related and See also edits must run no case")
        self.assertEqual("0", block["agent-runs"])

    def test_routing_heading_renamed_to_related_is_no_run(self):
        path = self._base_with_sections(["Boundaries", "What this skill does not do"])
        block = self._edit_and_select(path, "## Boundaries\n", "## Related\n")
        self.assertNotIn("cases", block, "a Boundaries-to-Related rename must run no case")
        block = self._edit_and_select(
            path, "## What this skill does not do\n", "## Scope boundary\n"
        )
        self.assertNotIn("cases", block, "a rename between routing headings must run no case")

    def test_non_routing_heading_renamed_to_related_still_cuts(self):
        path = self._base_with_sections([])
        block = self._edit_and_select(path, "## Gotchas\n", "## Related\n")
        self.assertEqual(
            "control-no-fire one-basic one-trigger",
            block.get("cases"),
            "renaming Gotchas is a cut: only routing headings are exempt",
        )

    def _set_base_description(self, description):
        path = self.repo / "plugins/alpha/skills/one/SKILL.md"
        text = path.read_text(encoding="utf-8").replace(
            'description: "Run alpha one checks. Use when checking alpha items."',
            'description: "%s"' % description,
        )
        path.write_text(text, encoding="utf-8")
        _commit_all(self.repo, "set base description")
        _git(self.repo, "branch", "-f", "base", "HEAD")
        return path

    def _write_glossary(self):
        _write(
            self.repo,
            "docs/glossary.md",
            """
            # Glossary

            ## Rejected terms

            | Rejected | Owned by |
            |---|---|
            | lane *(the slice a hunt rotates through)* | focus area, the word hunts use |
            | lane *(one concern an audit judges)* | concern, the word audits use |
            | stage runner | **lane** above |
            """,
        )

    def _assert_exempt(self, block):
        self.assertNotIn("cases", block, "an exempt description edit must run no case")
        self.assertNotIn("run-after-merge", block, "an exempt edit schedules no later run")
        self.assertEqual(
            "control-no-fire one-trigger opt-case",
            block.get("affected-no-run"),
            "the triggering and no-fire cases are listed as affected but not run",
        )
        exempt, _, reason = block.get("no-run-exempt", "").partition(";")
        self.assertEqual("alpha:one", exempt)
        self.assertIn("routing clauses", reason, "the line states why nothing runs")
        self.assertEqual("0", block["agent-runs"])

    def test_added_not_for_clause_is_exempt(self):
        path = self.repo / "plugins/alpha/skills/one/SKILL.md"
        self._assert_exempt(
            self._edit_and_select(
                path,
                "Use when checking alpha items.",
                "Use when checking alpha items. Not for beta sweeps: /beta:runner.",
            )
        )

    def test_reworded_skip_clause_is_exempt(self):
        path = self._set_base_description(
            "Run alpha one checks. Use when checking alpha items. Skip when sweeping (beta:runner)."
        )
        self._assert_exempt(
            self._edit_and_select(
                path,
                "Skip when sweeping (beta:runner).",
                "Skip when a sweep is asked for: /beta:runner.",
            )
        )

    def test_removed_prefer_clause_is_exempt(self):
        path = self._set_base_description(
            "Run alpha one checks; prefer /beta:runner for sweeps. Use when checking alpha items."
        )
        self._assert_exempt(
            self._edit_and_select(
                path,
                "Run alpha one checks; prefer /beta:runner for sweeps.",
                "Run alpha one checks.",
            )
        )

    def test_skill_token_form_and_rename_are_exempt(self):
        path = self._set_base_description(
            "Run alpha one checks after beta:runner. Use when checking alpha items."
        )
        self._assert_exempt(
            self._edit_and_select(path, "after beta:runner.", "after /beta:sweeper.")
        )

    def test_glossary_decided_term_swap_is_exempt(self):
        self._write_glossary()
        path = self._set_base_description(
            "Run alpha one checks over a rotated lane, one concern lane at a time."
            " Use when checking alpha lanes."
        )
        self._assert_exempt(
            self._edit_and_select(
                path,
                "over a rotated lane, one concern lane at a time. Use when checking alpha lanes.",
                "over a rotated focus area, one concern at a time."
                " Use when checking alpha focus areas.",
            )
        )

    def test_swap_to_an_undecided_term_is_cut(self):
        self._write_glossary()
        path = self._set_base_description(
            "Run alpha one checks over a rotated lane. Use when checking alpha items."
        )
        block = self._edit_and_select(path, "rotated lane.", "rotated track.")
        self.assertNotIn("no-run-exempt", block, "track is not the glossary's decided word")
        self.assertEqual("control-no-fire one-basic one-trigger opt-case", block.get("cases"))

    def test_rewording_beside_a_routing_clause_is_cut(self):
        path = self.repo / "plugins/alpha/skills/one/SKILL.md"
        block = self._edit_and_select(
            path,
            'description: "Run alpha one checks. Use when checking alpha items."',
            'description: "Run alpha one audits. Use when checking alpha items.'
            ' Not for beta sweeps: /beta:runner."',
        )
        self.assertNotIn("no-run-exempt", block, "checks to audits is a real rewording")
        self.assertEqual("control-no-fire one-basic one-trigger opt-case", block.get("cases"))
        self.assertEqual("20", block["agent-runs"])

    def test_trigger_rewording_in_a_prefer_sentence_is_cut(self):
        path = self.repo / "plugins/alpha/skills/one/SKILL.md"
        path.write_text(
            path.read_text(encoding="utf-8").replace(
                'alpha items."', 'alpha items, and prefer /beta:runner for sweeps."'
            ),
            encoding="utf-8",
        )
        _commit_all(self.repo, "add a prefer clause")
        _git(self.repo, "branch", "-f", "base", "HEAD")
        block = self._edit_and_select(path, "checking alpha items,", "deploying services,")
        self.assertNotIn("no-run-exempt", block, "the Use when trigger was rewritten")
        self.assertEqual("control-no-fire one-basic one-trigger opt-case", block.get("cases"))

    def _base_with_lane_text(self):
        self._write_glossary()
        path = self.repo / "plugins/alpha/skills/one/SKILL.md"
        text = path.read_text(encoding="utf-8").replace(
            'alpha items."\n', 'alpha items."\nargument-hint: "[--lane <lane>]"\n'
        )
        path.write_text(
            text.replace(
                "Follow these steps carefully.\n",
                "Follow these steps carefully.\nHunt one rotated lane at a time.\n",
            ),
            encoding="utf-8",
        )
        _write(self.repo, "plugins/alpha/evals/one-basic/prompt.md", "/alpha:one check this lane\n")
        _commit_all(self.repo, "add lane wording")
        _git(self.repo, "branch", "-f", "base", "HEAD")
        return path

    def test_decided_term_swap_in_body_hunk_is_no_run(self):
        path = self._base_with_lane_text()
        block = self._edit_and_select(path, "rotated lane at", "rotated focus area at")
        self.assertNotIn("cases", block, "a body hunk that only swaps a decided term runs nothing")
        self.assertEqual("control-no-fire one-basic one-trigger", block.get("affected-no-run"))
        self.assertEqual("0", block["agent-runs"])

    def test_decided_term_flag_rename_in_argument_hint_is_no_run(self):
        path = self._base_with_lane_text()
        block = self._edit_and_select(path, "[--lane <lane>]", "[--area <area>]")
        self.assertNotIn(
            "cases", block, "--lane to --area takes the last word of the decided focus area"
        )
        self.assertEqual("control-no-fire one-basic one-trigger", block.get("affected-no-run"))
        self.assertEqual("0", block["agent-runs"])

    def test_decided_term_swap_in_eval_prompt_is_no_run(self):
        self._base_with_lane_text()
        prompt = self.repo / "plugins/alpha/evals/one-basic/prompt.md"
        block = self._edit_and_select(prompt, "this lane", "this focus area")
        self.assertNotIn("cases", block, "a prompt that only swaps a decided term runs nothing")
        self.assertEqual("one-basic", block.get("affected-no-run"))
        self.assertEqual("0", block["agent-runs"])

    def test_hunk_with_a_swap_and_another_change_still_runs(self):
        path = self._base_with_lane_text()
        block = self._edit_and_select(
            path, "Hunt one rotated lane at a time.", "Hunt two rotated focus areas at a time."
        )
        self.assertEqual(
            "control-no-fire one-basic one-trigger",
            block.get("cases"),
            "one to two is a real change beside the swap, so the hunk is a cut",
        )

    def _base_with_comments(self):
        _write(
            self.repo,
            "plugins/alpha/skills/one/config.yaml",
            "# Defaults for alpha one.\n# Reviewed yearly.\nlimit: 3\n",
        )
        scaffold = self.repo / "plugins/alpha/evals/one-basic/scaffold.sh"
        scaffold.write_text(
            scaffold.read_text(encoding="utf-8").replace(
                "#!/usr/bin/env bash\n", "#!/usr/bin/env bash\n# Seeds the shared fixture.\n"
            ),
            encoding="utf-8",
        )
        details = self.repo / "plugins/alpha/skills/one/reference/details.md"
        details.write_text(
            details.read_text(encoding="utf-8")
            + "<!-- Validate the schema before anything else. -->\n",
            encoding="utf-8",
        )
        _commit_all(self.repo, "add comments")
        _git(self.repo, "branch", "-f", "base", "HEAD")

    def test_yaml_comment_line_deletion_is_no_run(self):
        self._base_with_comments()
        config = self.repo / "plugins/alpha/skills/one/config.yaml"
        block = self._edit_and_select(config, "# Defaults for alpha one.\n# Reviewed yearly.\n", "")
        self.assertNotIn("cases", block, "deleting YAML comment lines changes no behavior")
        self.assertEqual("control-no-fire one-basic one-trigger", block.get("affected-no-run"))
        self.assertEqual("0", block["agent-runs"])

    def test_scaffold_header_comment_deletion_is_no_run(self):
        self._base_with_comments()
        scaffold = self.repo / "plugins/alpha/evals/one-basic/scaffold.sh"
        block = self._edit_and_select(scaffold, "# Seeds the shared fixture.\n", "")
        self.assertNotIn("cases", block, "a scaffold header comment deletion runs nothing")
        self.assertEqual("one-basic", block.get("affected-no-run"))
        self.assertEqual("0", block["agent-runs"])

    def test_comment_shaped_line_in_a_heredoc_still_runs(self):
        scaffold = self.repo / "plugins/alpha/evals/one-basic/scaffold.sh"
        scaffold.write_text(
            scaffold.read_text(encoding="utf-8") + "cat > status.md <<'MD'\n# Project status\nMD\n",
            encoding="utf-8",
        )
        _commit_all(self.repo, "seed a heredoc")
        _git(self.repo, "branch", "-f", "base", "HEAD")
        block = self._edit_and_select(scaffold, "# Project status\n", "")
        self.assertEqual("one-basic", block.get("cases"), "a heredoc line is fixture content")

    def _base_with_block_scalar(self):
        self._base_with_comments()
        config = self.repo / "plugins/alpha/skills/one/config.yaml"
        config.write_text(
            config.read_text(encoding="utf-8") + "prompt: |\n  # Heading the model reads\n  body\n",
            encoding="utf-8",
        )
        _commit_all(self.repo, "add a block scalar")
        _git(self.repo, "branch", "-f", "base", "HEAD")
        return config

    def test_comment_deletion_outside_a_block_scalar_is_no_run(self):
        config = self._base_with_block_scalar()
        block = self._edit_and_select(config, "# Reviewed yearly.\n", "")
        self.assertNotIn("cases", block, "only lines inside the block scalar are content")

    def test_comment_shaped_line_inside_a_block_scalar_still_runs(self):
        config = self._base_with_block_scalar()
        block = self._edit_and_select(config, "  # Heading the model reads\n", "")
        self.assertEqual("control-no-fire one-basic one-trigger", block.get("cases"))

    def _assert_string_line_runs(self, rel, base_text, line):
        path = self.repo / rel
        _write(self.repo, rel, base_text)
        _commit_all(self.repo, "seed a multi-line string")
        _git(self.repo, "branch", "-f", "base", "HEAD")
        block = self._edit_and_select(path, line, "")
        self.assertEqual("control-no-fire one-basic one-trigger", block.get("cases"))

    def test_comment_shaped_line_in_a_toml_string_still_runs(self):
        self._assert_string_line_runs(
            "plugins/alpha/skills/one/config.toml",
            'prompt = """\n# Heading the model reads\nbody\n"""\n',
            "# Heading the model reads\n",
        )

    def test_powershell_here_string_lines_are_content(self):
        import no_run_text

        text = '# Seeds it.\n$text = @"\n# Heading the model reads\nbody\n"@\n'
        self.assertEqual(("hash", frozenset({3, 4, 5})), no_run_text.comment_style("a.ps1", text))

    def test_markdown_html_comment_deletion_still_runs(self):
        self._base_with_comments()
        details = self.repo / "plugins/alpha/skills/one/reference/details.md"
        block = self._edit_and_select(
            details, "<!-- Validate the schema before anything else. -->\n", ""
        )
        self.assertEqual(
            "control-no-fire one-basic one-trigger",
            block.get("cases"),
            "a markdown HTML comment can carry instructions a model reads",
        )

    def test_comment_deletion_beside_a_code_change_still_runs(self):
        self._base_with_comments()
        config = self.repo / "plugins/alpha/skills/one/config.yaml"
        block = self._edit_and_select(config, "# Reviewed yearly.\nlimit: 3\n", "limit: 4\n")
        self.assertEqual(
            "control-no-fire one-basic one-trigger",
            block.get("cases"),
            "the hunk also changes limit, so it is a cut",
        )

    def test_whitespace_change_in_scaffold_still_runs(self):
        self._write_glossary()
        scaffold = self.repo / "plugins/alpha/evals/one-basic/scaffold.sh"
        scaffold.write_text(
            scaffold.read_text(encoding="utf-8") + 'printf "a b" # lane\n', encoding="utf-8"
        )
        _commit_all(self.repo, "add printf")
        _git(self.repo, "branch", "-f", "base", "HEAD")
        block = self._edit_and_select(
            scaffold, 'printf "a b" # lane\n', 'printf "a  b" # focus area\n'
        )
        self.assertEqual(
            "one-basic", block.get("cases"), "a whitespace change beside a swap is not swap-only"
        )

    def test_block_comment_with_trailing_code_still_runs(self):
        _write(
            self.repo,
            "plugins/alpha/evals/one-basic/seed.js",
            '/* setup */ console.log("seed");\n// plain comment\n',
        )
        _commit_all(self.repo, "add seed.js")
        _git(self.repo, "branch", "-f", "base", "HEAD")
        seed = self.repo / "plugins/alpha/evals/one-basic/seed.js"
        block = self._edit_and_select(seed, '/* setup */ console.log("seed");\n', "")
        self.assertEqual(
            "one-basic",
            block.get("cases"),
            "a line with code after its comment is not a whole-line comment",
        )

    def test_js_comment_lines_and_closed_block_deletion_is_no_run(self):
        _write(
            self.repo,
            "plugins/alpha/evals/one-basic/seed.js",
            '/* one-line */\n/*\n * block\n */\n// plain\nconsole.log("seed");\n',
        )
        _commit_all(self.repo, "add seed.js")
        _git(self.repo, "branch", "-f", "base", "HEAD")
        seed = self.repo / "plugins/alpha/evals/one-basic/seed.js"
        block = self._edit_and_select(
            seed, '/* one-line */\n/*\n * block\n */\n// plain\n', ""
        )
        self.assertNotIn("cases", block, "deleting only JS comment lines runs nothing")
        self.assertEqual("one-basic", block.get("affected-no-run"))

    def test_exempt_skill_is_listed_in_json(self):
        path = self.repo / "plugins/alpha/skills/one/SKILL.md"
        path.write_text(
            path.read_text(encoding="utf-8").replace(
                "alpha items.", "alpha items. Not for beta sweeps: /beta:runner."
            ),
            encoding="utf-8",
        )
        _commit_all(self.repo, "add routing clause")
        res = _run_select(self.repo, as_json=True)
        self.assertEqual(0, res.returncode, res.stderr)
        data = json.loads(res.stdout)["plugins/alpha"]
        self.assertEqual(["alpha:one"], data["no-run-exempt"])
        self.assertEqual([], data["cases"])

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
