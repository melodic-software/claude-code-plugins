"""The HIGH floor also holds every path a plugin declares as executable.

Each declaration text below is written here, in the shape Claude Code reads
(`.mcp.json` servers, `hooks/hooks.json` commands, inline `plugin.json`
servers), and handed in as the base side. Expected scores come from the scorer
contract: a floor path is HIGH, an ordinary file stays LOW, and anything the
scorer cannot read rates HIGH as `high-path:**`.
"""

from __future__ import annotations

import json
import pathlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

from babysit_risk import ChangedFile, LaneEvidence, Risk, RiskInput, Rung, score

MCP = json.dumps(
    {
        "mcpServers": {
            "miro": {
                "command": "node",
                "args": ["${CLAUDE_PLUGIN_ROOT}/server/src/launch.ts"],
            }
        }
    }
)
HOOKS = json.dumps(
    {
        "hooks": {
            "PreToolUse": [
                {
                    "matcher": "Bash",
                    "hooks": [
                        {
                            "type": "command",
                            "command": 'python3 "${CLAUDE_PLUGIN_ROOT}'
                            '/skills/clean/scripts/guard.py" --strict',
                        }
                    ],
                }
            ]
        }
    }
)
PLUGIN = json.dumps(
    {
        "name": "tool",
        "types": "./types/index.d.ts",
        "mcpServers": {"tool": {"command": "${CLAUDE_PLUGIN_ROOT}/bin/serve"}},
        "hooks": "./config/hooks.json",
    }
)
DECLARATIONS = (
    ("plugins/miro/.mcp.json", MCP),
    ("plugins/disk/hooks/hooks.json", HOOKS),
    ("plugins/tool/.claude-plugin/plugin.json", PLUGIN),
)


def _risk(path, declarations=DECLARATIONS, **kw):
    changed = ChangedFile(
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
    return score(
        RiskInput(
            work_class="C2",
            rung=Rung.C2,
            files=(changed,),
            files_complete=True,
            max_changed_lines=200,
            high_paths=(),
            lanes=(
                LaneEvidence("claude-review", True, None, 0),
                LaneEvidence("claude-security-review", True, None, 0),
            ),
            blast_radius=None,
            declarations=declarations,
            **kw,
        )
    )


def _codes(result):
    return {reason.code for reason in result.reasons}


class DeclaredExecutableTests(unittest.TestCase):
    def test_declared_executable_mcp_server_file_scores_high(self):
        result = _risk("plugins/miro/server/src/launch.ts")
        self.assertIs(result.score, Risk.HIGH)

    def test_declared_executable_mcp_server_sibling_scores_high(self):
        # The entry point runs the code beside it.
        result = _risk("plugins/miro/server/src/board.ts")
        self.assertIs(result.score, Risk.HIGH)

    def test_declared_executable_hook_command_script_scores_high(self):
        result = _risk("plugins/disk/skills/clean/scripts/guard.py")
        self.assertIs(result.score, Risk.HIGH)

    def test_declared_executable_inline_plugin_json_server_scores_high(self):
        self.assertIs(_risk("plugins/tool/bin/serve").score, Risk.HIGH)

    def test_declared_executable_plugin_json_config_pointer_scores_high(self):
        self.assertIs(_risk("plugins/tool/config/hooks.json").score, Risk.HIGH)

    def test_declared_executable_undeclared_file_stays_low(self):
        for path in (
            "plugins/miro/README.md",
            "plugins/disk/skills/clean/SKILL-notes.md",
            "plugins/disk/skills/clean/reference/usage.md",
            "plugins/tool/types/index.d.ts",
        ):
            with self.subTest(path=path):
                result = _risk(path)
                self.assertIs(result.score, Risk.LOW, result.reasons)

    def test_declared_executable_unreadable_declaration_fails_closed(self):
        for text in (None, "{not json", "[]"):
            with self.subTest(text=text):
                result = _risk(
                    "plugins/miro/README.md",
                    declarations=(("plugins/miro/.mcp.json", text),),
                )
                self.assertIs(result.score, Risk.HIGH)
                self.assertIn("high-path:**", _codes(result))

    def test_declared_executable_path_outside_its_plugin_fails_closed(self):
        escaping = json.dumps(
            {"mcpServers": {"x": {"command": "${CLAUDE_PLUGIN_ROOT}/../../x.js"}}}
        )
        result = _risk(
            "plugins/miro/README.md",
            declarations=(("plugins/miro/.mcp.json", escaping),),
        )
        self.assertIs(result.score, Risk.HIGH)
        self.assertIn("high-path:**", _codes(result))

    def test_declared_executable_unknown_declaration_file_fails_closed(self):
        result = _risk(
            "plugins/miro/README.md",
            declarations=(("plugins/miro/notes/servers.json", MCP),),
        )
        self.assertIs(result.score, Risk.HIGH)
        self.assertIn("high-path:**", _codes(result))

    def test_declared_executable_off_with_the_floor(self):
        result = _risk("plugins/miro/server/src/launch.ts", high_floor=False)
        self.assertIs(result.score, Risk.LOW, result.reasons)


if __name__ == "__main__":
    unittest.main()
