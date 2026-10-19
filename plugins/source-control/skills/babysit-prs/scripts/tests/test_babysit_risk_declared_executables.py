"""The HIGH floor also holds every path a plugin declares as executable.

Each declaration text below is written here, in the shape Claude Code reads
(`.mcp.json` servers, `hooks/hooks.json` commands, inline `plugin.json`
servers), and handed in as the base side. Expected scores come from the scorer
contract: a floor path is HIGH, an ordinary file stays LOW, and anything the
scorer cannot read rates HIGH as `high-path:**`.
"""

from __future__ import annotations

import base64
import json
import pathlib
import sys
import types
import unittest
from unittest import mock

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import babysit_merge as merge
import babysit_merge_policy as policy
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


BASE = "b" * 40
HEAD = "c" * 40
REPO = "o/r"
TREE = [
    {"path": "plugins", "mode": "040000"},
    {"path": "plugins/miro/.mcp.json", "mode": "100644"},
    {"path": "plugins/miro/README.md", "mode": "100644"},
    {"path": "plugins/miro/server/src/launch.ts", "mode": "100644"},
]


def _fake_get(tree_status=200, contents_status=200):
    def get(endpoint):
        if endpoint == f"repos/{REPO}/git/trees/{BASE}?recursive=1":
            return tree_status, {"truncated": False, "tree": TREE}
        if endpoint == f"repos/{REPO}/contents/plugins/miro/.mcp.json?ref={BASE}":
            content = base64.b64encode(MCP.encode()).decode()
            payload = {"type": "file", "encoding": "base64", "content": content}
            return contents_status, payload
        return 500, None

    return get


def _api_only(get):
    """The contents and trees API stand in for GitHub; no local clone."""
    return (
        mock.patch.object(policy, "_history_checkouts", return_value=[]),
        mock.patch.object(policy, "_get", side_effect=get),
        mock.patch.dict(policy._TEXT_AT, clear=True),
    )


PR = {"number": 7, "base": {"sha": BASE}, "head": {"sha": HEAD}}


class DeclarationsAtTests(unittest.TestCase):
    def _read(self, get, pr=PR):
        a, b, c = _api_only(get)
        with a, b, c:
            return policy.declarations_at(REPO, pr)

    def test_declared_executable_reader_returns_base_declarations(self):
        self.assertEqual(self._read(_fake_get()), (("plugins/miro/.mcp.json", MCP),))

    def test_declared_executable_reader_unreadable_file_is_none(self):
        self.assertEqual(
            self._read(_fake_get(contents_status=500)),
            (("plugins/miro/.mcp.json", None),),
        )

    def test_declared_executable_reader_unreadable_tree_is_none(self):
        self.assertIsNone(self._read(_fake_get(tree_status=500)))

    def test_declared_executable_reader_no_base_sha_is_none(self):
        self.assertIsNone(self._read(_fake_get(), pr={"number": 7, "head": {}}))


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
    )


class ScoreUnattendedTests(unittest.TestCase):
    """The gate end to end: score_unattended reads the declarations at the
    base SHA and hands them to the scorer."""

    def _score(self, path, get):
        config = types.SimpleNamespace(
            require_verifier_verdict=False,
            high_path_floor=True,
            c2_contradictions=True,
            max_changed_files=8,
            max_changed_lines=200,
            denied_paths=(),
            floor_paths=(),
            floor_script_scopes=(),
        )
        eligible = types.SimpleNamespace(
            eligible=True, dependabot=None, work_class="C2"
        )
        start = policy.UnattendedPolicy(
            None,
            enabled=True,
            inputs={
                "eligibility": eligible,
                "pr": PR,
                "config": config,
                "authority": policy.PR_MERGE,
                "identity": "lane[bot]",
                "permission": "write",
                "rung": "c2",
                "branch": "main",
            },
        )
        lanes = (
            LaneEvidence("claude-review", True, None, 0),
            LaneEvidence("claude-security-review", True, None, 0),
        )
        a, b, c = _api_only(get)
        with (
            a,
            b,
            c,
            mock.patch.object(merge, "_lane_evidence", return_value=(lanes, [])),
            mock.patch.object(
                policy, "changed_files", return_value=((_changed(path),), True)
            ),
            mock.patch.object(
                policy, "with_capability_contents", side_effect=lambda r, p, f: f
            ),
        ):
            return merge.score_unattended(REPO, 7, start, frozenset())

    def test_declared_executable_gate_holds_a_declared_mcp_file(self):
        result = self._score("plugins/miro/server/src/launch.ts", _fake_get())
        self.assertEqual(result.reason, "risk:HIGH")
        codes = {r["code"] for r in result.details["risk"]["reasons"]}
        self.assertIn("high-path:plugins/miro/server/src", codes)

    def test_declared_executable_gate_leaves_an_undeclared_file_low(self):
        result = self._score("plugins/miro/README.md", _fake_get())
        self.assertIsNone(result.reason, result.details)
        self.assertEqual(result.details["risk"]["score"], "LOW")

    def test_declared_executable_gate_holds_when_the_base_tree_is_unread(self):
        result = self._score("plugins/miro/README.md", _fake_get(tree_status=500))
        self.assertEqual(result.reason, "risk:HIGH")


if __name__ == "__main__":
    unittest.main()
