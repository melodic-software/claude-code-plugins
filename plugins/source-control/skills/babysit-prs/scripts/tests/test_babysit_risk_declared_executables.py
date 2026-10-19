"""The HIGH floor also holds every path a plugin declares as executable.

Each declaration text below is written here, in the shape Claude Code reads
(`.mcp.json` and `.lsp.json` servers, `hooks/hooks.json` and
`monitors/monitors.json` commands, `plugin.json` inline entries and pointers),
and handed in as the base side. Expected scores come from the scorer contract:
a floor path is HIGH, an ordinary file stays LOW, and anything the scorer
cannot read rates HIGH as `high-path:**`.
"""

from __future__ import annotations

import base64
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import types
import unittest
from unittest import mock

# An inherited GIT_DIR, GIT_WORK_TREE or GIT_CONFIG would send the git
# fixtures' identity writes into the caller's repository
# (scripts/check-fixture-git-isolation.sh). Cleared before any test spawns git.
for _leaked_git_var in (
    "GIT_DIR",
    "GIT_WORK_TREE",
    "GIT_INDEX_FILE",
    "GIT_COMMON_DIR",
    "GIT_PREFIX",
    "GIT_OBJECT_DIRECTORY",
    "GIT_CONFIG",
):
    os.environ.pop(_leaked_git_var, None)
del _leaked_git_var

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import babysit_merge as merge  # noqa: E402  (follows the git-env clear above)
import babysit_merge_policy as policy  # noqa: E402
from babysit_risk import (  # noqa: E402
    ChangedFile,
    LaneEvidence,
    Risk,
    RiskInput,
    Rung,
    score,
)

MCP = json.dumps(
    {
        "mcpServers": {
            "example": {
                "command": "node",
                "args": ["${CLAUDE_PLUGIN_ROOT}/server/main.js"],
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
        "name": "example-tool",
        "types": "./types/index.d.ts",
        "mcpServers": {"tool": {"command": "${CLAUDE_PLUGIN_ROOT}/bin/serve"}},
        "hooks": "./config/hooks.json",
    }
)
POINTED = json.dumps(
    {"hooks": {"Stop": [{"hooks": [{"command": "${CLAUDE_PLUGIN_ROOT}/run/stop.sh"}]}]}}
)
# The documented monitors file: a top-level array of strict entries.
MONITORS = [
    {
        "name": "tail-log",
        "command": "${CLAUDE_PLUGIN_ROOT}/watch/tail.sh",
        "description": "Log lines as they arrive",
    }
]
DECLARATIONS = (
    ("plugins/example-plugin/.mcp.json", MCP),
    ("plugins/example-hooks/hooks/hooks.json", HOOKS),
    ("plugins/example-tool/.claude-plugin/plugin.json", PLUGIN),
    ("plugins/example-tool/config/hooks.json", POINTED),
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


LANES = (
    LaneEvidence("claude-review", True, None, 0),
    LaneEvidence("claude-security-review", True, None, 0),
)


def _risk(path, declarations=DECLARATIONS, **kw):
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
            declarations=declarations,
            **kw,
        )
    )


def _codes(result):
    return {reason.code for reason in result.reasons}


def _one(path, document):
    """One plugin's declarations: a single file holding `document`."""
    return ((path, json.dumps(document)),)


def _server(command, *args):
    return {"mcpServers": {"x": {"command": command, "args": list(args)}}}


class DeclaredExecutableTests(unittest.TestCase):
    def assertHeldUnsafe(self, declarations, path="plugins/example-plugin/README.md"):
        result = _risk(path, declarations=declarations)
        self.assertIs(result.score, Risk.HIGH)
        self.assertIn("high-path:**", _codes(result))

    def test_declared_executable_mcp_server_file_scores_high(self):
        result = _risk("plugins/example-plugin/server/main.js")
        self.assertIs(result.score, Risk.HIGH)

    def test_declared_executable_mcp_server_sibling_scores_high(self):
        # The entry point runs the code beside it.
        result = _risk("plugins/example-plugin/server/board.js")
        self.assertIs(result.score, Risk.HIGH)

    def test_declared_executable_hook_command_script_scores_high(self):
        result = _risk("plugins/example-hooks/skills/clean/scripts/guard.py")
        self.assertIs(result.score, Risk.HIGH)

    def test_declared_executable_inline_plugin_json_server_scores_high(self):
        self.assertIs(_risk("plugins/example-tool/bin/serve").score, Risk.HIGH)

    def test_declared_executable_plugin_json_pointer_file_scores_high(self):
        result = _risk("plugins/example-tool/config/hooks.json")
        self.assertIs(result.score, Risk.HIGH)

    def test_declared_executable_pointed_config_entries_score_high(self):
        self.assertIs(_risk("plugins/example-tool/run/stop.sh").score, Risk.HIGH)

    def test_declared_executable_undeclared_file_stays_low(self):
        for path in (
            "plugins/example-plugin/README.md",
            "plugins/example-hooks/skills/clean/SKILL-notes.md",
            "plugins/example-hooks/skills/clean/reference/usage.md",
            "plugins/example-tool/types/index.d.ts",
        ):
            with self.subTest(path=path):
                result = _risk(path)
                self.assertIs(result.score, Risk.LOW, result.reasons)

    def test_declared_executable_unreadable_declaration_fails_closed(self):
        for text in (None, "{not json", "[]"):
            with self.subTest(text=text):
                self.assertHeldUnsafe((("plugins/example-plugin/.mcp.json", text),))

    def test_declared_executable_path_outside_its_plugin_fails_closed(self):
        self.assertHeldUnsafe(
            _one(
                "plugins/example-plugin/.mcp.json",
                _server("${CLAUDE_PLUGIN_ROOT}/../../x.js"),
            )
        )

    def test_declared_executable_unknown_declaration_file_fails_closed(self):
        self.assertHeldUnsafe((("plugins/example-plugin/notes/servers.json", MCP),))

    def test_declared_executable_off_with_the_floor(self):
        result = _risk("plugins/example-plugin/server/main.js", high_floor=False)
        self.assertIs(result.score, Risk.LOW, result.reasons)

    def _unconsumed(self, command):
        self.assertHeldUnsafe(
            _one("plugins/example-plugin/.mcp.json", _server(command))
        )

    def test_declared_executable_root_with_a_default_fails_closed(self):
        self._unconsumed("${CLAUDE_PLUGIN_ROOT:-/x}/server/main.js")

    def test_declared_executable_root_with_a_trim_fails_closed(self):
        self._unconsumed("${CLAUDE_PLUGIN_ROOT%/}/server/main.js")

    def test_declared_executable_powershell_root_fails_closed(self):
        self._unconsumed("$env:CLAUDE_PLUGIN_ROOT/server/main.js")

    def test_declared_executable_cmd_root_fails_closed(self):
        self._unconsumed("%CLAUDE_PLUGIN_ROOT%\\server\\main.js")

    def test_declared_executable_relative_mcp_arg_scores_high(self):
        declarations = _one(
            "plugins/example-plugin/.mcp.json", _server("node", "./srv/a.js")
        )
        result = _risk("plugins/example-plugin/srv/a.js", declarations=declarations)
        self.assertIs(result.score, Risk.HIGH)

    def test_declared_executable_monitors_array_scores_high(self):
        declarations = _one("plugins/example-plugin/monitors/monitors.json", MONITORS)
        result = _risk(
            "plugins/example-plugin/watch/tail.sh", declarations=declarations
        )
        self.assertIs(result.score, Risk.HIGH)

    def test_declared_executable_monitors_object_form_scores_high(self):
        declarations = _one(
            "plugins/example-plugin/monitors/monitors.json", {"monitors": MONITORS}
        )
        result = _risk(
            "plugins/example-plugin/watch/tail.sh", declarations=declarations
        )
        self.assertIs(result.score, Risk.HIGH)

    def test_declared_executable_monitors_array_leaves_other_files_low(self):
        declarations = _one("plugins/example-plugin/monitors/monitors.json", MONITORS)
        result = _risk("plugins/example-plugin/README.md", declarations=declarations)
        self.assertIs(result.score, Risk.LOW, result.reasons)

    def test_declared_executable_pointed_monitors_array_scores_high(self):
        declarations = (
            (
                "plugins/example-plugin/.claude-plugin/plugin.json",
                json.dumps({"experimental": {"monitors": "./config/monitors.json"}}),
            ),
            ("plugins/example-plugin/config/monitors.json", json.dumps(MONITORS)),
        )
        result = _risk(
            "plugins/example-plugin/watch/tail.sh", declarations=declarations
        )
        self.assertIs(result.score, Risk.HIGH)

    def test_declared_executable_array_mcp_file_fails_closed(self):
        # Only a monitors file holds an array.
        self.assertHeldUnsafe(
            (("plugins/example-plugin/.mcp.json", json.dumps(MONITORS)),)
        )

    def test_declared_executable_plugin_bin_scores_high_undeclared(self):
        result = _risk("plugins/example-plugin/bin/example-tool", declarations=())
        self.assertIs(result.score, Risk.HIGH)
        self.assertIn("high-path:plugins/*/bin/**", _codes(result))

    def test_declared_executable_changed_lsp_declaration_scores_high(self):
        # The declaration file itself, added or edited, with no base declaration.
        result = _risk("plugins/x/.lsp.json", declarations=())
        self.assertIs(result.score, Risk.HIGH)
        self.assertIn("high-path:**/.lsp.json", _codes(result))

    def test_declared_executable_lsp_file_scores_high(self):
        declarations = _one(
            "plugins/example-plugin/.lsp.json",
            {"lspServers": {"py": {"command": "${CLAUDE_PLUGIN_ROOT}/lsp/serve"}}},
        )
        result = _risk("plugins/example-plugin/lsp/serve", declarations=declarations)
        self.assertIs(result.score, Risk.HIGH)

    def test_declared_executable_experimental_monitors_score_high(self):
        declarations = _one(
            "plugins/example-plugin/.claude-plugin/plugin.json",
            {"experimental": {"monitors": [{"command": "./watch/poll.sh"}]}},
        )
        result = _risk(
            "plugins/example-plugin/watch/poll.sh", declarations=declarations
        )
        self.assertIs(result.score, Risk.HIGH)

    def test_declared_executable_pointer_not_read_fails_closed(self):
        self.assertHeldUnsafe(
            _one(
                "plugins/example-plugin/.claude-plugin/plugin.json",
                {"mcpServers": ["./config/servers.json"]},
            )
        )

    def test_declared_executable_unreadable_pointer_fails_closed(self):
        self.assertHeldUnsafe(
            (
                (
                    "plugins/example-plugin/.claude-plugin/plugin.json",
                    json.dumps({"lspServers": "./config/lsp.json"}),
                ),
                ("plugins/example-plugin/config/lsp.json", None),
            )
        )

    def test_declared_executable_pointer_outside_its_plugin_fails_closed(self):
        self.assertHeldUnsafe(
            _one(
                "plugins/example-plugin/.claude-plugin/plugin.json",
                {"monitors": "../other/monitors.json"},
            )
        )


BASE = "b" * 40
HEAD = "c" * 40
REPO = "o/r"
OTHER_MCP = json.dumps(_server("${CLAUDE_PLUGIN_ROOT}/srv/main.js"))
FILES = {
    "plugins/example-plugin/.mcp.json": MCP,
    "plugins/example-plugin/README.md": "# Example\n",
    "plugins/example-plugin/server/main.js": "run();\n",
    "plugins/other-plugin/.mcp.json": OTHER_MCP,
    "plugins/other-plugin/hooks/hooks.json": HOOKS,
    "plugins/example-tool/.claude-plugin/plugin.json": PLUGIN,
    "plugins/example-tool/config/hooks.json": POINTED,
}


def _fake_get(tree_status=200, contents_status=200, files=FILES):
    tree = [{"path": "plugins", "mode": "040000"}] + [
        {"path": path, "mode": "100644"} for path in files
    ]

    def get(endpoint):
        if endpoint == f"repos/{REPO}/git/trees/{BASE}?recursive=1":
            return tree_status, {"truncated": False, "tree": tree}
        for path, text in files.items():
            if endpoint == f"repos/{REPO}/contents/{path}?ref={BASE}":
                content = base64.b64encode(text.encode()).decode()
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
IN_EXAMPLE = ["plugins/example-plugin/server/main.js", None]


class DeclarationsAtTests(unittest.TestCase):
    def _read(self, get, pr=PR, changed=IN_EXAMPLE):
        a, b, c = _api_only(get)
        with a, b, c:
            return policy.declarations_at(REPO, pr, changed)

    def test_declared_executable_reader_returns_base_declarations(self):
        self.assertEqual(
            self._read(_fake_get()), (("plugins/example-plugin/.mcp.json", MCP),)
        )

    def test_declared_executable_reader_reads_only_the_touched_plugin(self):
        a, b, c = _api_only(_fake_get())
        with (
            a,
            b,
            c,
            mock.patch.object(policy, "_text_at", wraps=policy._text_at) as text_at,
        ):
            policy.declarations_at(REPO, PR, IN_EXAMPLE)
        read = [call.args[2] for call in text_at.call_args_list]
        self.assertEqual(read, ["plugins/example-plugin/.mcp.json"])

    def test_declared_executable_reader_reads_nothing_outside_plugins(self):
        get = mock.Mock(side_effect=_fake_get())
        a, b, c = _api_only(get)
        with a, b, c:
            found = policy.declarations_at(REPO, PR, ["docs/guide.md", None])
        self.assertEqual(found, ())
        get.assert_not_called()

    def test_declared_executable_reader_follows_a_plugin_json_pointer(self):
        found = self._read(_fake_get(), changed=["plugins/example-tool/run/stop.sh"])
        self.assertEqual(
            found,
            (
                ("plugins/example-tool/.claude-plugin/plugin.json", PLUGIN),
                ("plugins/example-tool/config/hooks.json", POINTED),
            ),
        )

    def test_declared_executable_reader_missing_pointer_is_none(self):
        files = {"plugins/example-tool/.claude-plugin/plugin.json": PLUGIN}
        found = self._read(
            _fake_get(files=files), changed=["plugins/example-tool/run/stop.sh"]
        )
        self.assertEqual(
            found,
            (
                ("plugins/example-tool/.claude-plugin/plugin.json", PLUGIN),
                ("plugins/example-tool/config/hooks.json", None),
            ),
        )

    def test_declared_executable_reader_unreadable_file_is_none(self):
        self.assertEqual(
            self._read(_fake_get(contents_status=500)),
            (("plugins/example-plugin/.mcp.json", None),),
        )

    def test_declared_executable_reader_unreadable_tree_is_none(self):
        self.assertIsNone(self._read(_fake_get(tree_status=500)))

    def test_declared_executable_reader_no_base_sha_is_none(self):
        self.assertIsNone(self._read(_fake_get(), pr={"number": 7, "head": {}}))


def _git(cwd, *args):
    return subprocess.run(
        ["git", "-c", "user.name=t", "-c", "user.email=t@example.com", *args],
        cwd=cwd,
        check=True,
        capture_output=True,
        text=True,
    ).stdout


class DeclarationsFromACloneTests(unittest.TestCase):
    """A clone holding the base answers every plugin's declarations through
    git, with no API call."""

    def setUp(self):
        escaping = _server("node", "${CLAUDE_PLUGIN_ROOT}/../example-plugin/x.js")
        self._commit(
            {
                "plugins/example-plugin/.mcp.json": MCP,
                "plugins/example-plugin/x.js": "run();\n",
                "plugins/other-plugin/.mcp.json": json.dumps(escaping),
            }
        )

    def _commit(self, files):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = pathlib.Path(tmp.name)
        _git(self.root, "init", "-q")
        self.files = files
        for path, text in self.files.items():
            target = self.root / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(text)
        _git(self.root, "add", ".")
        _git(self.root, "commit", "-q", "-m", "base")
        self.base = _git(self.root, "rev-parse", "HEAD").strip()

    def _read(self, changed):
        get = mock.Mock(side_effect=AssertionError("API call"))
        pr = {"number": 7, "base": {"sha": self.base}, "head": {"sha": HEAD}}
        with (
            mock.patch.object(policy, "_history_checkouts", return_value=[self.root]),
            mock.patch.object(policy, "_get", get),
        ):
            return policy.declarations_at(REPO, pr, changed)

    def test_declared_executable_clone_reads_every_plugin(self):
        found = self._read(["plugins/example-plugin/x.js"])
        self.assertEqual(
            found,
            (
                ("plugins/example-plugin/.mcp.json", MCP),
                (
                    "plugins/other-plugin/.mcp.json",
                    self.files["plugins/other-plugin/.mcp.json"],
                ),
            ),
        )

    def test_declared_executable_clone_docs_change_with_monitors_array_low(self):
        self._commit(
            {
                "docs/guide.md": "# Guide\n",
                "plugins/example-plugin/monitors/monitors.json": json.dumps(MONITORS),
            }
        )
        declarations = self._read(["docs/guide.md", None])
        self.assertEqual(
            declarations,
            (
                (
                    "plugins/example-plugin/monitors/monitors.json",
                    json.dumps(MONITORS),
                ),
            ),
        )
        result = _risk("docs/guide.md", declarations=declarations)
        self.assertIs(result.score, Risk.LOW, result.reasons)

    def test_declared_executable_clone_catches_an_untouched_plugin_escaping(self):
        declarations = self._read(["plugins/example-plugin/x.js"])
        result = _risk("plugins/example-plugin/x.js", declarations=declarations)
        self.assertIs(result.score, Risk.HIGH)
        self.assertIn("high-path:**", _codes(result))


class ScoreUnattendedTests(unittest.TestCase):
    """The gate end to end: score_unattended reads the declarations of the
    changed plugins at the base SHA and hands them to the scorer."""

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
        a, b, c = _api_only(get)
        with (
            a,
            b,
            c,
            mock.patch.object(merge, "_lane_evidence", return_value=(LANES, [])),
            mock.patch.object(
                policy, "changed_files", return_value=((_changed(path),), True)
            ),
            mock.patch.object(
                policy, "with_capability_contents", side_effect=lambda r, p, f: f
            ),
        ):
            return merge.score_unattended(REPO, 7, start, frozenset())

    def test_declared_executable_gate_holds_a_declared_mcp_file(self):
        result = self._score("plugins/example-plugin/server/main.js", _fake_get())
        self.assertEqual(result.reason, "risk:HIGH")
        codes = {r["code"] for r in result.details["risk"]["reasons"]}
        self.assertIn("high-path:plugins/example-plugin/server", codes)

    def test_declared_executable_gate_leaves_an_undeclared_file_low(self):
        result = self._score("plugins/example-plugin/README.md", _fake_get())
        self.assertIsNone(result.reason, result.details)
        self.assertEqual(result.details["risk"]["score"], "LOW")

    def test_declared_executable_gate_holds_when_the_base_tree_is_unread(self):
        result = self._score(
            "plugins/example-plugin/README.md", _fake_get(tree_status=500)
        )
        self.assertEqual(result.reason, "risk:HIGH")

    def test_declared_executable_gate_holds_a_plugin_whose_path_escapes(self):
        files = {
            "plugins/example-plugin/.mcp.json": json.dumps(
                _server("node", "${CLAUDE_PLUGIN_ROOT}/../other-plugin/x.js")
            )
        }
        result = self._score("plugins/example-plugin/README.md", _fake_get(files=files))
        self.assertEqual(result.reason, "risk:HIGH")
        codes = {r["code"] for r in result.details["risk"]["reasons"]}
        self.assertIn("high-path:**", codes)


if __name__ == "__main__":
    unittest.main()
