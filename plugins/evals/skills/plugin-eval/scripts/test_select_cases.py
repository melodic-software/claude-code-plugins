#!/usr/bin/env python3
# test-scope: plugins/evals/skills/plugin-eval/scripts/select-cases.py plugins/evals/scripts/case_skills.py plugins/evals/skills/validate/scripts/validate-cases.py
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
from textwrap import dedent

SCRIPT = Path(__file__).resolve().parent / "select-cases.py"

for _leaked_git_var in ("GIT_DIR", "GIT_WORK_TREE", "GIT_CONFIG"):
    os.environ.pop(_leaked_git_var, None)
os.environ.setdefault("GIT_CONFIG_GLOBAL", os.devnull)
os.environ["GIT_CONFIG_NOSYSTEM"] = "1"


def _git(repo, *args):
    cmd = [
        "git",
        "-C",
        str(repo),
        "-c",
        "commit.gpgsign=false",
        "-c",
        "core.hooksPath=/dev/null",
        "-c",
        "user.name=Test",
        "-c",
        "user.email=test@example.com",
    ] + list(args)
    return subprocess.run(cmd, capture_output=True, text=True, check=True).stdout


def _write(root, rel_path, content):
    path = Path(root) / rel_path
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(dedent(content).lstrip("\n"), encoding="utf-8")


def _commit_all(repo, message):
    _git(repo, "add", "-A")
    _git(repo, "commit", "-q", "-m", message)


def _run_select(repo, diff_base="base", as_json=False):
    cmd = [sys.executable, str(SCRIPT), diff_base, "--repo", str(repo)]
    if as_json:
        cmd.append("--json")
    return subprocess.run(cmd, capture_output=True, text=True)


def _parse_blocks(stdout):
    text = stdout.strip()
    if text == "no affected cases":
        return {}
    blocks = {}
    for chunk in text.split("\n\n"):
        lines = [line for line in chunk.splitlines() if line.strip()]
        header = lines[0]
        if not header.startswith("plugin: "):
            raise AssertionError("unexpected block header: %r" % header)
        plugin = header[len("plugin: ") :]
        data = {}
        for line in lines[1:]:
            key, _, rest = line.partition(":")
            data[key.strip()] = rest.strip()
        blocks[plugin] = data
    return blocks


def _build_fixture_repo(root):
    _git(root, "init", "-q")
    _write(
        root,
        "plugins/alpha/.claude-plugin/plugin.json",
        """
        {"name": "alpha", "version": "1.0.0"}
        """,
    )
    _write(
        root,
        "plugins/beta/.claude-plugin/plugin.json",
        """
        {"name": "beta", "version": "1.0.0"}
        """,
    )
    _write(
        root,
        "plugins/alpha/skills/one/SKILL.md",
        """
        ---
        description: "Run alpha one checks. Use when checking alpha items."
        ---

        # Alpha One

        Follow these steps carefully.
        Read [details](reference/details.md) and [shared](../../reference/shared.md).
        Dispatch `alpha:helper` when deep analysis is needed.
        """,
    )
    _write(
        root,
        "plugins/alpha/skills/one/reference/details.md",
        """
        # Details

        Always validate the input schema first.
        """,
    )
    _write(
        root,
        "plugins/alpha/skills/one/scripts/tool.py",
        """
        def run():
            return 1
        """,
    )
    _write(
        root,
        "plugins/alpha/scripts/util.py",
        """
        def helper():
            return True
        """,
    )
    _write(
        root,
        "plugins/alpha/reference/shared.md",
        """
        # Shared Reference

        Keep all shared outputs concise.
        """,
    )
    _write(
        root,
        "plugins/alpha/agents/helper.md",
        """
        ---
        name: helper
        description: "Helper agent"
        ---

        Inspect the target file and report findings.
        """,
    )
    _write(
        root,
        "plugins/alpha/skills/judged-skill/SKILL.md",
        """
        ---
        description: "Explain architectural trade-offs."
        ---

        # Judged Skill

        Explain the trade-offs clearly.
        """,
    )
    _write(
        root,
        "plugins/alpha/skills/mixed-skill/SKILL.md",
        """
        ---
        description: "Check mixed criteria."
        ---

        # Mixed Skill

        Output the summary line and explain why.
        """,
    )
    _write(
        root,
        "plugins/alpha/skills/opt-skill/SKILL.md",
        """
        ---
        description: "Optional prefix skill."
        ---

        # Opt Skill

        Run optional prefix flow.
        """,
    )
    _write(
        root,
        "plugins/alpha/skills/uncovered-skill/SKILL.md",
        """
        ---
        description: "Skill without any eval cases."
        ---

        # Uncovered

        Perform uncovered behavior.
        """,
    )
    _write(
        root,
        "plugins/alpha/evals/fixtures/setup.sh",
        """
        #!/usr/bin/env bash
        echo fixture
        """,
    )
    _write(
        root,
        "plugins/alpha/evals/one-basic/case.yaml",
        """
        schema_version: "1.1"
        name: one-basic
        description: "Basic case for alpha:one"
        tags: [alpha:one]
        context:
          scaffold_script: scaffold.sh
        """,
    )
    _write(
        root,
        "plugins/alpha/evals/one-basic/prompt.md",
        """
        /alpha:one check this item
        """,
    )
    _write(
        root,
        "plugins/alpha/evals/one-basic/scaffold.sh",
        """
        #!/usr/bin/env bash
        bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/setup.sh"
        """,
    )
    _write(
        root,
        "plugins/alpha/evals/one-basic/graders/check.md",
        """
        ---
        type: regex
        pattern: "ok"
        ---
        """,
    )
    _write(
        root,
        "plugins/alpha/evals/one-basic/samples/check.json",
        """
        {"pass": [{"answer": "ok"}], "fail": [{"answer": "no"}]}
        """,
    )
    _write(
        root,
        "plugins/alpha/evals/one-trigger/prompt.md",
        """
        ---
        description: "Triggering case for alpha:one"
        tags: [triggering]
        runs: 2
        ---

        Please check my alpha items for issues.
        """,
    )
    _write(
        root,
        "plugins/alpha/evals/one-trigger/graders/skill-fired.md",
        """
        ---
        type: tool_used
        tool: Skill
        input_match: '"skill":"alpha:one"'
        ---
        """,
    )
    _write(
        root,
        "plugins/alpha/evals/control-no-fire/prompt.md",
        """
        ---
        description: "No-fire control case"
        tags: [control]
        runs: 2
        ---

        How do I sort a list in Python?
        """,
    )
    _write(
        root,
        "plugins/alpha/evals/control-no-fire/graders/no-skill.md",
        """
        ---
        type: tool_used
        tool: Skill
        input_match: '"skill":"alpha:one"'
        min: 0
        max: 0
        arm: both
        ---
        """,
    )
    _write(
        root,
        "plugins/alpha/evals/judged-case/case.yaml",
        """
        schema_version: "1.1"
        name: judged-case
        tags: [judged-skill]
        graders:
          - name: quality
            type: llm
            criteria: "Clearly explains trade-offs."
        """,
    )
    _write(
        root,
        "plugins/alpha/evals/judged-case/prompt.md",
        """
        /alpha:judged-skill compare A and B
        """,
    )
    _write(
        root,
        "plugins/alpha/evals/mixed-case/case.yaml",
        """
        schema_version: "1.1"
        name: mixed-case
        tags: [mixed-skill]
        runs: 5
        graders:
          - name: has-summary
            type: regex
            pattern: "SUMMARY:"
          - name: quality
            type: llm
            criteria: "Explains the rationale."
        """,
    )
    _write(
        root,
        "plugins/alpha/evals/mixed-case/prompt.md",
        """
        /alpha:mixed-skill run check
        """,
    )
    _write(
        root,
        "plugins/alpha/evals/opt-case/prompt.md",
        """
        ---
        description: "Optional prefix grader test"
        ---

        Trigger optional prefix flow now.
        """,
    )
    _write(
        root,
        "plugins/alpha/evals/opt-case/graders/fired.md",
        """
        ---
        type: tool_used
        tool: Skill
        input_match: '"skill"\\s*:\\s*"(?:alpha:)?opt-skill"'
        ---
        """,
    )
    _write(
        root,
        "plugins/beta/skills/runner/SKILL.md",
        """
        ---
        description: "Run beta sweep workflow."
        allowed-tools: ["Workflow(beta:sweep)"]
        ---

        # Runner

        Launch the `beta:sweep` workflow.
        """,
    )
    _write(
        root,
        "plugins/beta/workflows/sweep.js",
        """
        const AGENT = 'beta:worker'
        export const meta = { name: 'sweep' }
        """,
    )
    _write(
        root,
        "plugins/beta/agents/worker.md",
        """
        ---
        name: worker
        description: "Worker agent"
        ---

        Process each slice deterministically.
        """,
    )
    _write(
        root,
        "plugins/beta/evals/group/sub/nested-dir/case.yaml",
        """
        schema_version: "1.1"
        name: runner-nested
        tags: [beta:runner]
        runs: 4
        """,
    )
    _write(
        root,
        "plugins/beta/evals/group/sub/nested-dir/prompt.md",
        """
        /beta:runner execute sweep
        """,
    )
    _write(
        root,
        "plugins/beta/evals/group/sub/nested-dir/graders/ok.md",
        """
        ---
        type: regex
        pattern: "done"
        ---
        """,
    )
    _write(
        root,
        "docs/guide.md",
        """
        # Guide

        General documentation outside plugins.
        """,
    )
    _commit_all(root, "initial")
    _git(root, "branch", "base")


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

    def test_pure_word_insertion_follows_the_word_diff_rule(self):
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
        path.write_text(
            path.read_text(encoding="utf-8").replace(
                "Do continue on failure.",
                "Do not continue on failure.",
            ),
            encoding="utf-8",
        )
        _commit_all(self.repo, "insert negating word")

        res = _run_select(self.repo)
        self.assertEqual(0, res.returncode, res.stderr)
        blocks = _parse_blocks(res.stdout)
        self.assertEqual("check", blocks["plugins/alpha"]["affected-no-run"])
        self.assertNotIn("cases", blocks["plugins/alpha"])

    def test_finding_02_cut_description_includes_skill_linked_cases(self):
        path = self.repo / "plugins/alpha/skills/one/SKILL.md"
        path.write_text(
            path.read_text(encoding="utf-8").replace(
                'description: "Run alpha one checks. Use when checking alpha items."',
                'description: "Run alpha one checks only."',
            ),
            encoding="utf-8",
        )
        _commit_all(self.repo, "shorten description")

        res = _run_select(self.repo)
        self.assertEqual(0, res.returncode, res.stderr)
        blocks = _parse_blocks(res.stdout)
        self.assertEqual(
            "control-no-fire one-basic one-trigger opt-case",
            blocks["plugins/alpha"]["cases"],
        )
        self.assertEqual("20", blocks["plugins/alpha"]["agent-runs"])

    def test_finding_03_description_addition_with_repeated_tokens_is_additive(self):
        _write(
            self.repo,
            "plugins/alpha/skills/logs/SKILL.md",
            """
            ---
            description: check check logs
            ---

            # Logs

            Read the logs.
            """,
        )
        _write(
            self.repo,
            "plugins/alpha/evals/logs-case/prompt.md",
            """
            /alpha:logs inspect
            """,
        )
        _write(
            self.repo,
            "plugins/alpha/evals/logs-case/graders/ok.md",
            """
            ---
            type: regex
            pattern: "ok"
            ---
            """,
        )
        _commit_all(self.repo, "add logs skill")
        _git(self.repo, "branch", "-f", "base")

        path = self.repo / "plugins/alpha/skills/logs/SKILL.md"
        path.write_text(
            path.read_text(encoding="utf-8").replace(
                "description: check check logs",
                "description: check logs and check logs",
            ),
            encoding="utf-8",
        )
        _commit_all(self.repo, "additive repeated tokens")

        res = _run_select(self.repo)
        self.assertEqual(0, res.returncode, res.stderr)
        blocks = _parse_blocks(res.stdout)
        self.assertNotIn("cases", blocks["plugins/alpha"])
        self.assertEqual(
            "control-no-fire one-trigger opt-case",
            blocks["plugins/alpha"]["run-after-merge"],
        )

    def test_case_owned_scaffold_selects_the_cases_that_call_it(self):
        for name, scaffold in (
            ("posture-necessary", 'mkdir -p out\necho "$1" > out/mode\n'),
            ("posture-none", 'bash "$(dirname "${BASH_SOURCE[0]}")/../posture-necessary/scaffold.sh" none\n'),
        ):
            _write(
                self.repo,
                "plugins/alpha/evals/%s/case.yaml" % name,
                'schema_version: "1.1"\nname: %s\ncontext:\n  scaffold_script: scaffold.sh\n' % name,
            )
            _write(self.repo, "plugins/alpha/evals/%s/prompt.md" % name, "/alpha:one check\n")
            _write(
                self.repo,
                "plugins/alpha/evals/%s/scaffold.sh" % name,
                "#!/usr/bin/env bash\n" + scaffold,
            )
            _write(
                self.repo,
                "plugins/alpha/evals/%s/graders/ok.md" % name,
                '---\ntype: regex\npattern: "ok"\n---\n',
            )
        _commit_all(self.repo, "add a scaffold another case calls")
        _git(self.repo, "branch", "-f", "base")

        path = self.repo / "plugins/alpha/evals/posture-necessary/scaffold.sh"
        path.write_text(path.read_text(encoding="utf-8") + "touch out/ready\n", encoding="utf-8")
        _commit_all(self.repo, "edit the shared scaffold")

        res = _run_select(self.repo)
        self.assertEqual(0, res.returncode, res.stderr)
        blocks = _parse_blocks(res.stdout)
        self.assertEqual("posture-necessary posture-none", blocks["plugins/alpha"]["cases"])

    def test_finding_04_transitive_fixture_dependency_through_helper(self):
        _write(
            self.repo,
            "plugins/alpha/evals/fixtures/checkout-service/src/pricing.js",
            """
            export const price = 10;
            """,
        )
        _write(
            self.repo,
            "plugins/alpha/evals/fixtures/seed-checkout-service.sh",
            """
            #!/usr/bin/env bash
            src="$(dirname "${BASH_SOURCE[0]}")/checkout-service"
            mkdir -p src
            cp "$src/src/pricing.js" src/pricing.js
            """,
        )
        _write(
            self.repo,
            "plugins/alpha/evals/find-unattended-run-cap-from-config/case.yaml",
            """
            schema_version: "1.1"
            name: find-unattended-run-cap-from-config
            context:
              scaffold_script: scaffold.sh
            """,
        )
        _write(
            self.repo,
            "plugins/alpha/evals/find-unattended-run-cap-from-config/prompt.md",
            """
            /alpha:one check checkout
            """,
        )
        _write(
            self.repo,
            "plugins/alpha/evals/find-unattended-run-cap-from-config/scaffold.sh",
            """
            #!/usr/bin/env bash
            bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/seed-checkout-service.sh"
            """,
        )
        _write(
            self.repo,
            "plugins/alpha/evals/find-unattended-run-cap-from-config/graders/ok.md",
            """
            ---
            type: regex
            pattern: "ok"
            ---
            """,
        )
        _commit_all(self.repo, "add transitive fixture")
        _git(self.repo, "branch", "-f", "base")

        path = self.repo / "plugins/alpha/evals/fixtures/checkout-service/src/pricing.js"
        path.write_text("export const price = 20;\n", encoding="utf-8")
        _commit_all(self.repo, "edit nested fixture file")

        res = _run_select(self.repo)
        self.assertEqual(0, res.returncode, res.stderr)
        blocks = _parse_blocks(res.stdout)
        self.assertEqual(
            "find-unattended-run-cap-from-config",
            blocks["plugins/alpha"]["cases"],
        )
        self.assertNotIn("unmapped", blocks["plugins/alpha"])

    def test_finding_05_fixture_path_resolved_not_substring(self):
        _write(
            self.repo,
            "plugins/alpha/evals/fixtures/data.json",
            """
            {"source": "suite"}
            """,
        )
        _write(
            self.repo,
            "plugins/alpha/evals/group/local-fix/fixtures/data.json",
            """
            {"source": "case"}
            """,
        )
        _write(
            self.repo,
            "plugins/alpha/evals/group/local-fix/prompt.md",
            """
            /alpha:one read local fixture
            """,
        )
        _write(
            self.repo,
            "plugins/alpha/evals/group/local-fix/scaffold.sh",
            """
            #!/usr/bin/env bash
            cp ./fixtures/data.json data.json
            """,
        )
        _write(
            self.repo,
            "plugins/alpha/evals/group/local-fix/graders/ok.md",
            """
            ---
            type: regex
            pattern: "ok"
            ---
            """,
        )
        _commit_all(self.repo, "add local and suite fixtures")
        _git(self.repo, "branch", "-f", "base")

        path = self.repo / "plugins/alpha/evals/fixtures/data.json"
        path.write_text('{"source": "suite-updated"}\n', encoding="utf-8")
        _commit_all(self.repo, "edit suite fixture")

        res = _run_select(self.repo)
        self.assertEqual(0, res.returncode, res.stderr)
        blocks = _parse_blocks(res.stdout)
        self.assertNotIn("cases", blocks["plugins/alpha"])
        self.assertEqual(
            "plugins/alpha/evals/fixtures/data.json",
            blocks["plugins/alpha"]["unmapped"],
        )

    def test_finding_06_cross_plugin_reference_consumer(self):
        _write(
            self.repo,
            "plugins/alpha/reference/rules.md",
            """
            # Rules

            Keep rules exact.
            """,
        )
        _write(
            self.repo,
            "plugins/beta/skills/check/SKILL.md",
            """
            ---
            description: "Check beta rules."
            ---

            # Check

            Follow [rules](../../../alpha/reference/rules.md).
            """,
        )
        _write(
            self.repo,
            "plugins/beta/evals/check/prompt.md",
            """
            /beta:check verify
            """,
        )
        _write(
            self.repo,
            "plugins/beta/evals/check/graders/ok.md",
            """
            ---
            type: regex
            pattern: "ok"
            ---
            """,
        )
        _commit_all(self.repo, "add cross-plugin reference")
        _git(self.repo, "branch", "-f", "base")

        path = self.repo / "plugins/alpha/reference/rules.md"
        path.write_text(
            path.read_text(encoding="utf-8").replace("exact", "strict"),
            encoding="utf-8",
        )
        _commit_all(self.repo, "reword alpha rules")

        res = _run_select(self.repo)
        self.assertEqual(0, res.returncode, res.stderr)
        blocks = _parse_blocks(res.stdout)
        self.assertEqual(["plugins/beta"], list(blocks))
        self.assertEqual("check", blocks["plugins/beta"]["cases"])

    def test_finding_07_relative_reference_path_with_spaces(self):
        _write(
            self.repo,
            "plugins/alpha/context/shared rules.md",
            """
            # Shared Rules

            Always report errors.
            """,
        )
        _write(
            self.repo,
            "plugins/alpha/skills/check/SKILL.md",
            """
            ---
            description: "Check with spaced context."
            ---

            # Check

            Read [rules](<../../context/shared rules.md>).
            """,
        )
        _write(
            self.repo,
            "plugins/alpha/evals/check/prompt.md",
            """
            /alpha:check verify rules
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
        _commit_all(self.repo, "add spaced context reference")
        _git(self.repo, "branch", "-f", "base")

        path = self.repo / "plugins/alpha/context/shared rules.md"
        path.write_text(
            path.read_text(encoding="utf-8").replace("errors", "warnings"),
            encoding="utf-8",
        )
        _commit_all(self.repo, "reword spaced context")

        res = _run_select(self.repo)
        self.assertEqual(0, res.returncode, res.stderr)
        blocks = _parse_blocks(res.stdout)
        self.assertEqual("check", blocks["plugins/alpha"]["cases"])
        self.assertNotIn("unmapped", blocks["plugins/alpha"])

    def test_finding_08_relative_workflow_link_for_agent_cut(self):
        _write(
            self.repo,
            "plugins/alpha/agents/rel-helper.md",
            """
            ---
            name: rel-helper
            ---

            Inspect targets carefully.
            """,
        )
        _write(
            self.repo,
            "plugins/alpha/workflows/check.js",
            """
            const AGENT = 'alpha:rel-helper'
            """,
        )
        _write(
            self.repo,
            "plugins/alpha/skills/check/SKILL.md",
            """
            ---
            description: "Run relative workflow."
            ---

            # Check

            Run `../../workflows/check.js`.
            """,
        )
        _write(
            self.repo,
            "plugins/alpha/evals/check/prompt.md",
            """
            /alpha:check run now
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
        _commit_all(self.repo, "add relative workflow link")
        _git(self.repo, "branch", "-f", "base")

        path = self.repo / "plugins/alpha/agents/rel-helper.md"
        path.write_text(
            path.read_text(encoding="utf-8").replace("carefully", "strictly"),
            encoding="utf-8",
        )
        _commit_all(self.repo, "reword rel-helper")

        res = _run_select(self.repo)
        self.assertEqual(0, res.returncode, res.stderr)
        blocks = _parse_blocks(res.stdout)
        self.assertEqual("check", blocks["plugins/alpha"]["cases"])
        self.assertNotIn("uncovered", blocks["plugins/alpha"])

    def test_finding_09_grader_prefix_covers_matching_skill(self):
        _write(
            self.repo,
            "plugins/alpha/skills/check-files/SKILL.md",
            """
            ---
            description: "Check files in workspace."
            ---

            # Check Files

            Inspect all files.
            """,
        )
        _write(
            self.repo,
            "plugins/alpha/evals/prefix-case/prompt.md",
            """
            Please check the files in this repo.
            """,
        )
        _write(
            self.repo,
            "plugins/alpha/evals/prefix-case/graders/fired.md",
            """
            ---
            type: tool_used
            tool: Skill
            input_match: 'alpha:check'
            ---
            """,
        )
        _commit_all(self.repo, "add prefix grader case")
        _git(self.repo, "branch", "-f", "base")

        path = self.repo / "plugins/alpha/skills/check-files/SKILL.md"
        path.write_text(
            path.read_text(encoding="utf-8").replace("all files", "staged files"),
            encoding="utf-8",
        )
        _commit_all(self.repo, "cut check-files")

        res = _run_select(self.repo)
        self.assertEqual(0, res.returncode, res.stderr)
        blocks = _parse_blocks(res.stdout)
        self.assertEqual("prefix-case", blocks["plugins/alpha"]["cases"])
        self.assertNotIn("uncovered", blocks["plugins/alpha"])

    def test_finding_10_agent_rename_preserves_cut_classification(self):
        _write(
            self.repo,
            "plugins/alpha/agents/rename-helper.md",
            """
            ---
            name: rename-helper
            description: "Helper for check workflow"
            ---

            Inspect the target file and report every finding clearly.
            """,
        )
        _write(
            self.repo,
            "plugins/alpha/workflows/check.js",
            """
            const AGENT = 'alpha:rename-helper'
            export const meta = { name: 'check' }
            """,
        )
        _write(
            self.repo,
            "plugins/alpha/skills/check/SKILL.md",
            """
            ---
            description: "Run check workflow."
            ---

            # Check

            Launch `alpha:check`.
            """,
        )
        _write(
            self.repo,
            "plugins/alpha/evals/check/prompt.md",
            """
            /alpha:check run
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
        _commit_all(self.repo, "add renameable agent")
        _git(self.repo, "branch", "-f", "base")

        (self.repo / "plugins/alpha/agents/rename-helper.md").unlink()
        _write(
            self.repo,
            "plugins/alpha/agents/rename-worker.md",
            """
            ---
            name: rename-worker
            description: "Helper for check workflow"
            ---

            Inspect the source file and report every finding strictly.
            """,
        )
        _write(
            self.repo,
            "plugins/alpha/workflows/check.js",
            """
            const AGENT = 'alpha:rename-worker'
            export const meta = { name: 'check' }
            """,
        )
        _commit_all(self.repo, "rename and reword agent")

        res = _run_select(self.repo)
        self.assertEqual(0, res.returncode, res.stderr)
        blocks = _parse_blocks(res.stdout)
        self.assertEqual("check", blocks["plugins/alpha"]["cases"])
        self.assertNotIn("uncovered", blocks["plugins/alpha"])
        self.assertNotIn("affected-no-run", blocks["plugins/alpha"])

    def test_finding_11_case_name_uses_case_yaml_not_prompt_frontmatter(self):
        _write(
            self.repo,
            "plugins/alpha/evals/nested/dir-name/case.yaml",
            """
            schema_version: "1.1"
            name: registered
            """,
        )
        _write(
            self.repo,
            "plugins/alpha/evals/nested/dir-name/prompt.md",
            """
            ---
            name: display
            ---

            /alpha:one check
            """,
        )
        _write(
            self.repo,
            "plugins/alpha/evals/nested/dir-name/graders/ok.md",
            """
            ---
            type: regex
            pattern: "ok"
            ---
            """,
        )
        _commit_all(self.repo, "add case with prompt frontmatter name")
        _git(self.repo, "branch", "-f", "base")

        path = self.repo / "plugins/alpha/evals/nested/dir-name/graders/ok.md"
        path.write_text(
            path.read_text(encoding="utf-8").replace("ok", "done"),
            encoding="utf-8",
        )
        _commit_all(self.repo, "edit grader")

        res = _run_select(self.repo)
        self.assertEqual(0, res.returncode, res.stderr)
        blocks = _parse_blocks(res.stdout)
        self.assertEqual("registered", blocks["plugins/alpha"]["cases"])

    def test_finding_12_markdown_grader_body_paid_marker_classified_judged(self):
        _write(
            self.repo,
            "plugins/alpha/evals/check/prompt.md",
            """
            /alpha:one verify output
            """,
        )
        _write(
            self.repo,
            "plugins/alpha/evals/check/graders/rule.md",
            """
            ---
            type: regex
            pattern: "ok"
            ---

            Example note documenting type: llm in prose.
            """,
        )
        _commit_all(self.repo, "add grader with paid marker in body")
        _git(self.repo, "branch", "-f", "base")

        path = self.repo / "plugins/alpha/evals/check/prompt.md"
        path.write_text("/alpha:one verify updated output\n", encoding="utf-8")
        _commit_all(self.repo, "edit prompt")

        res = _run_select(self.repo)
        self.assertEqual(0, res.returncode, res.stderr)
        blocks = _parse_blocks(res.stdout)
        self.assertNotIn("cases", blocks["plugins/alpha"])
        self.assertEqual("check", blocks["plugins/alpha"]["judged"])

    def test_finding_13_duplicate_case_names_counted_in_agent_runs(self):
        _write(
            self.repo,
            "plugins/alpha/evals/group-a/check/case.yaml",
            """
            schema_version: "1.1"
            runs: 2
            """,
        )
        _write(
            self.repo,
            "plugins/alpha/evals/group-a/check/prompt.md",
            """
            /alpha:one check A
            """,
        )
        _write(
            self.repo,
            "plugins/alpha/evals/group-a/check/graders/ok.md",
            """
            ---
            type: regex
            pattern: "ok"
            ---
            """,
        )
        _write(
            self.repo,
            "plugins/alpha/evals/group-b/check/case.yaml",
            """
            schema_version: "1.1"
            runs: 4
            """,
        )
        _write(
            self.repo,
            "plugins/alpha/evals/group-b/check/prompt.md",
            """
            /alpha:one check B
            """,
        )
        _write(
            self.repo,
            "plugins/alpha/evals/group-b/check/graders/ok.md",
            """
            ---
            type: regex
            pattern: "ok"
            ---
            """,
        )
        _commit_all(self.repo, "add duplicate case names")
        _git(self.repo, "branch", "-f", "base")

        path_a = self.repo / "plugins/alpha/evals/group-a/check/prompt.md"
        path_a.write_text("/alpha:one check A updated\n", encoding="utf-8")
        _commit_all(self.repo, "edit only group-a check")

        res_one = _run_select(self.repo)
        self.assertEqual(0, res_one.returncode, res_one.stderr)
        blocks_one = _parse_blocks(res_one.stdout)
        self.assertEqual("check", blocks_one["plugins/alpha"]["cases"])
        self.assertEqual("12", blocks_one["plugins/alpha"]["agent-runs"])

        path_b = self.repo / "plugins/alpha/evals/group-b/check/prompt.md"
        path_b.write_text("/alpha:one check B updated\n", encoding="utf-8")
        _commit_all(self.repo, "edit group-b check too")

        res_both = _run_select(self.repo)
        self.assertEqual(0, res_both.returncode, res_both.stderr)
        blocks_both = _parse_blocks(res_both.stdout)
        self.assertEqual("check", blocks_both["plugins/alpha"]["cases"])
        self.assertEqual("12", blocks_both["plugins/alpha"]["agent-runs"])

    def test_finding_14_uncommitted_plugin_changes_exit_2(self):
        path = self.repo / "plugins/alpha/evals/one-basic/graders/check.md"
        path.write_text(
            path.read_text(encoding="utf-8").replace("ok", "passed"),
            encoding="utf-8",
        )
        _commit_all(self.repo, "edit grader")

        case_yaml = self.repo / "plugins/alpha/evals/one-basic/case.yaml"
        original_yaml = case_yaml.read_text(encoding="utf-8")
        case_yaml.write_text(
            original_yaml.replace("name: one-basic", "name: draft"),
            encoding="utf-8",
        )

        res = _run_select(self.repo)
        self.assertEqual(2, res.returncode)
        self.assertIn("committed", res.stderr.lower())

        case_yaml.write_text(original_yaml, encoding="utf-8")
        (self.repo / "docs/guide.md").write_text("# Uncommitted outside plugins\n", encoding="utf-8")
        res_outside = _run_select(self.repo)
        self.assertEqual(0, res_outside.returncode, res_outside.stderr)
        blocks = _parse_blocks(res_outside.stdout)
        self.assertEqual("one-basic", blocks["plugins/alpha"]["cases"])

    def test_finding_15_quoted_and_trailing_space_paths_from_git(self):
        quoted = self.repo / 'plugins/alpha/evals/one-basic/fixtures/input "quoted".txt'
        quoted.parent.mkdir(parents=True, exist_ok=True)
        quoted.write_text("v1\n", encoding="utf-8")
        trailing = self.repo / "plugins/alpha/evals/one-basic/fixtures/trailing "
        trailing.write_text("t1\n", encoding="utf-8")
        _commit_all(self.repo, "add special-char fixtures")
        _git(self.repo, "branch", "-f", "base")

        quoted.write_text("v2\n", encoding="utf-8")
        _commit_all(self.repo, "edit quoted fixture")

        res_quoted = _run_select(self.repo)
        self.assertEqual(0, res_quoted.returncode, res_quoted.stderr)
        blocks_quoted = _parse_blocks(res_quoted.stdout)
        self.assertEqual("one-basic", blocks_quoted["plugins/alpha"]["cases"])

        _git(self.repo, "branch", "-f", "base")
        trailing.write_text("t2\n", encoding="utf-8")
        _commit_all(self.repo, "edit trailing-space fixture")

        res_trailing = _run_select(self.repo)
        self.assertEqual(0, res_trailing.returncode, res_trailing.stderr)
        blocks_trailing = _parse_blocks(res_trailing.stdout)
        self.assertEqual("one-basic", blocks_trailing["plugins/alpha"]["cases"])


if __name__ == "__main__":
    unittest.main()
