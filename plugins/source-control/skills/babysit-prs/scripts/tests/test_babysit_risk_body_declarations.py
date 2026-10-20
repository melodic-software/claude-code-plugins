"""The HIGH floor also holds the paths skill, command and agent bodies run.

Each body below is handed in as base-side declaration text, in the shapes
Claude Code reads: an inline !`command`, a ```! block, and plugin-root or
skill-directory references in prose. A path a body runs is HIGH, an ordinary
file stays LOW, and a `!` command the scorer cannot place rates HIGH as
`high-path:**`.
"""

from __future__ import annotations

import base64
import pathlib
import sys
import unittest
from unittest import mock

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import babysit_merge_policy as policy  # noqa: E402
from babysit_risk import (  # noqa: E402
    ChangedFile,
    LaneEvidence,
    Risk,
    RiskInput,
    Rung,
    score,
)

SKILL = "plugins/example/skills/probe/SKILL.md"
FRONT = "---\nname: probe\ndescription: Probe.\n---\n\n"
LANES = (
    LaneEvidence("claude-review", True, None, 0),
    LaneEvidence("claude-security-review", True, None, 0),
)


def _changed(path):
    return ChangedFile(
        path=path,
        previous_path=None,
        status="modified",
        additions=3,
        deletions=1,
        has_patch=True,
        mode="100644",
        previous_mode="100644",
        patch="",
        contents=("", ""),
    )


def _risk(path, body, declared=SKILL):
    return score(
        RiskInput(
            work_class="C2",
            rung=Rung.C2,
            files=(_changed(path),),
            files_complete=True,
            max_changed_lines=200,
            high_paths=(),
            lanes=LANES,
            blast_radius=None,
            declarations=((declared, None if body is None else FRONT + body),),
        )
    )


def _codes(result):
    return {reason.code for reason in result.reasons}


class BangRunTests(unittest.TestCase):
    def assertHigh(self, path, body, code, declared=SKILL):
        result = _risk(path, body, declared)
        self.assertIs(result.score, Risk.HIGH, result.reasons)
        self.assertIn(code, _codes(result))

    def assertLow(self, path, body, declared=SKILL):
        result = _risk(path, body, declared)
        self.assertIs(result.score, Risk.LOW, result.reasons)

    def test_script_a_bang_line_runs_scores_high(self):
        body = 'Gotchas:\n!`bash "${CLAUDE_PLUGIN_ROOT}/scripts/gotchas.sh" || echo none`\n'
        self.assertHigh(
            "plugins/example/scripts/gotchas.sh",
            body,
            "high-path:plugins/example/scripts",
        )

    def test_sibling_of_a_run_script_scores_high(self):
        body = '!`"${CLAUDE_PLUGIN_ROOT}/scripts/gotchas.sh"`\n'
        self.assertHigh(
            "plugins/example/scripts/helper.py",
            body,
            "high-path:plugins/example/scripts",
        )

    def test_unrelated_plugin_script_stays_low(self):
        body = '!`bash "${CLAUDE_PLUGIN_ROOT}/scripts/gotchas.sh"`\n'
        self.assertLow("plugins/example/tools/other.sh", body)
        self.assertLow("plugins/other/scripts/gotchas.sh", body)

    def test_skill_dir_reference_resolves_to_the_skill(self):
        body = "Ecosystems: !`${CLAUDE_SKILL_DIR}/scripts/detect.sh 2>/dev/null || echo none`\n"
        self.assertHigh(
            "plugins/example/skills/probe/scripts/detect.sh",
            body,
            "high-path:plugins/example/skills/probe/scripts",
        )
        self.assertLow("plugins/example/skills/other/scripts/detect.sh", body)

    def test_fenced_bang_block_script_scores_high(self):
        body = (
            "```!\n"
            'echo "PY=$(bash "${CLAUDE_PLUGIN_ROOT}/lib/resolve.sh" || echo none)"\n'
            "```\n"
        )
        self.assertHigh(
            "plugins/example/lib/resolve.sh", body, "high-path:plugins/example/lib"
        )

    def test_shell_dash_c_source_scores_high(self):
        body = (
            "!`bash -c 'source \"${CLAUDE_PLUGIN_ROOT}/otel/probe.sh\" && port 4318'`\n"
        )
        self.assertHigh(
            "plugins/example/otel/probe.sh", body, "high-path:plugins/example/otel"
        )

    def test_prose_reference_floors_the_script_directory(self):
        body = 'Run `bash "${CLAUDE_PLUGIN_ROOT}/context/words/scripts/lookup.sh" <word>`.\n'
        self.assertHigh(
            "plugins/example/context/words/scripts/lookup.sh",
            body,
            "high-path:plugins/example/context/words/scripts",
        )

    def test_prose_reference_in_an_agent_body_floors_its_script(self):
        body = 'Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/fetch.sh" <url>`.\n'
        self.assertHigh(
            "plugins/example/scripts/fetch.sh",
            body,
            "high-path:plugins/example/scripts",
            declared="plugins/example/agents/fetcher.md",
        )

    def test_prose_reference_to_a_document_floors_only_that_file(self):
        body = "Read ${CLAUDE_PLUGIN_ROOT}/reference/config.md#resolution first.\n"
        self.assertHigh(
            "plugins/example/reference/config.md",
            body,
            "high-path:plugins/example/reference/config.md",
        )
        self.assertLow("plugins/example/reference/other.md", body)

    def test_placeholders_and_permission_patterns_read_as_their_prefix(self):
        body = (
            "allowed: Bash(${CLAUDE_SKILL_DIR}/scripts/check.sh:*)\n"
            "Say ${CLAUDE_PLUGIN_ROOT}, or ${CLAUDE_PLUGIN_ROOT}/<path>.\n"
        )
        self.assertHigh(
            "plugins/example/skills/probe/scripts/check.sh",
            body,
            "high-path:plugins/example/skills/probe/scripts",
        )
        self.assertLow("plugins/example/README.md", body)

    def test_bang_lines_that_run_no_plugin_file_stay_low(self):
        body = (
            "- `jq`: !`command -v jq 2>/dev/null || echo absent`\n"
            "Branch: !`git branch --show-current 2>/dev/null || echo unknown`\n"
            'Config: !`test -f "$HOME/.claude/x.md" && echo present || echo absent`\n'
            'Lanes: !`ls "${CLAUDE_PROJECT_DIR:-.}/.claude/bugs.md" 2>/dev/null`\n'
            "Repo: !`gh repo view 2>/dev/null | sed -E 's#.*github\\.com[:/]##'`\n"
            "```!\n"
            'echo "D=$(d="${X:-}"; case "$d" in "") ;; /*) echo "$d" ;; '
            '*) echo "$PWD/$d" ;; esac || true)"\n'
            'node -e "console.log(require(\'fs\'))" "${CLAUDE_PLUGIN_DATA}"\n'
            "```\n"
            "A `!` in a code span runs nothing: `!`echo x`` reads as text.\n"
        )
        self.assertLow("plugins/example/README.md", body)

    def test_change_to_the_body_itself_is_not_floored_by_its_own_reference(self):
        body = '!`"${CLAUDE_SKILL_DIR}/scripts/detect.sh"`\n'
        self.assertLow("plugins/example/skills/probe/reference/usage.md", body)


class BangFailsClosedTests(unittest.TestCase):
    def assertHeldUnsafe(self, body, declared=SKILL):
        result = _risk("plugins/example/README.md", body, declared)
        self.assertIs(result.score, Risk.HIGH, result.reasons)
        self.assertIn("high-path:**", _codes(result))

    def test_relative_or_other_variable_script_path_fails_closed(self):
        for command in (
            "./scripts/run.sh",
            "bash scripts/run.sh",
            "python3 tools/run.py --flag",
            'bash "$HOME/run.sh"',
            '"${OTHER_ROOT}/scripts/run.sh"',
            "run.sh",
            "env X=1 ./run.sh",
            "$(echo ./run.sh)",
            "pwsh -File ./run.ps1",
        ):
            with self.subTest(command=command):
                self.assertHeldUnsafe(f"!`{command}`\n")

    def test_unread_variable_spelling_fails_closed(self):
        for command in (
            'bash "${CLAUDE_PLUGIN_ROOT:-.}/scripts/run.sh"',
            'bash "${CLAUDE_SKILL_DIR%/}/run.sh"',
            "bash $env:CLAUDE_PLUGIN_ROOT/run.sh",
        ):
            with self.subTest(command=command):
                self.assertHeldUnsafe(f"!`{command}`\n")

    def test_reference_leaving_the_plugin_fails_closed(self):
        self.assertHeldUnsafe('!`bash "${CLAUDE_PLUGIN_ROOT}/../other/run.sh"`\n')

    def test_shell_text_the_reader_cannot_follow_fails_closed(self):
        for command in ("echo 'unclosed", "echo $((1 + 2))"):
            with self.subTest(command=command):
                self.assertHeldUnsafe(f"!`{command}`\n")

    def test_skill_dir_in_a_command_file_fails_closed(self):
        self.assertHeldUnsafe(
            '!`"${CLAUDE_SKILL_DIR}/run.sh"`\n',
            declared="plugins/example/commands/go.md",
        )

    def test_non_bash_shell_with_bang_commands_fails_closed(self):
        body = "!`Get-Date`\n"
        result = score(
            RiskInput(
                work_class="C2",
                rung=Rung.C2,
                files=(_changed("plugins/example/README.md"),),
                files_complete=True,
                max_changed_lines=200,
                high_paths=(),
                lanes=LANES,
                blast_radius=None,
                declarations=(
                    (SKILL, "---\nname: probe\nshell: powershell\n---\n\n" + body),
                ),
            )
        )
        self.assertIs(result.score, Risk.HIGH)
        self.assertIn("high-path:**", _codes(result))

    def test_unreadable_body_fails_closed(self):
        self.assertHeldUnsafe(None)


BASE = "a" * 40
REPO = "o/r"
BODY = FRONT + '!`bash "${CLAUDE_PLUGIN_ROOT}/scripts/gotchas.sh"`\n'
FILES = {
    SKILL: BODY,
    "plugins/example/scripts/gotchas.sh": "echo hi\n",
    "plugins/example/agents/fetcher.md": FRONT,
    "plugins/other/skills/x/SKILL.md": FRONT,
}


def _get(endpoint):
    if endpoint == f"repos/{REPO}/git/trees/{BASE}?recursive=1":
        tree = [{"path": p, "mode": "100644"} for p in FILES]
        return 200, {"truncated": False, "tree": tree}
    for path, text in FILES.items():
        if endpoint == f"repos/{REPO}/contents/{path}?ref={BASE}":
            content = base64.b64encode(text.encode()).decode()
            return 200, {"type": "file", "encoding": "base64", "content": content}
    return 500, None


class BodyDeclarationsAtTests(unittest.TestCase):
    def test_reader_returns_the_touched_plugins_bodies_at_the_base(self):
        pr = {"number": 7, "base": {"sha": BASE}, "head": {"sha": "c" * 40}}
        with (
            mock.patch.object(policy, "_history_checkouts", return_value=[]),
            mock.patch.object(policy, "_get", side_effect=_get),
            mock.patch.dict(policy._TEXT_AT, clear=True),
        ):
            found = policy.declarations_at(
                REPO, pr, ["plugins/example/scripts/gotchas.sh"]
            )
        self.assertEqual(
            found, (("plugins/example/agents/fetcher.md", FRONT), (SKILL, BODY))
        )
        result = score(
            RiskInput(
                work_class="C2",
                rung=Rung.C2,
                files=(_changed("plugins/example/scripts/gotchas.sh"),),
                files_complete=True,
                max_changed_lines=200,
                high_paths=(),
                lanes=LANES,
                blast_radius=None,
                declarations=found,
            )
        )
        self.assertIs(result.score, Risk.HIGH)


if __name__ == "__main__":
    unittest.main()
