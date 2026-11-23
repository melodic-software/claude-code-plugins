"""Shared fixture helpers for select-cases unit test suites."""

import os
import subprocess
import sys
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
