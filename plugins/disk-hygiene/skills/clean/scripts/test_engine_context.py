#!/usr/bin/env python3
# test-scope: plugins/disk-hygiene/hooks/hooks.json
"""Tests for the ``UserPromptExpansion`` context hook of ``/disk-hygiene:clean`` (#4215).

The contract under test: the values the hook hands the skill are values the
skill-frontmatter guard admits, so the first engine call needs no denial to
discover them.
"""

from __future__ import annotations

import io
import json
import os
import re
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest import mock

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))

import destructive_guard as guard  # noqa: E402  (path set above)
import engine_context  # noqa: E402  (path set above)

HOOKS_JSON = SCRIPT_DIR.parents[2] / "hooks" / "hooks.json"


class EngineContextTest(unittest.TestCase):
    def setUp(self) -> None:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        config = Path(temporary.name).resolve()
        self.plugin_root = (
            config / "plugins" / "cache" / "melodic-software" / "disk-hygiene" / "1.2.3"
        )
        self.plugin_root.mkdir(parents=True)
        self.managed = config / "managed-settings.json"
        guard._directory_marketplace_install.cache_clear()
        self.addCleanup(guard._directory_marketplace_install.cache_clear)
        for patch in (
            mock.patch.dict(os.environ, {}, clear=True),
            mock.patch.object(guard, "_trusted_config_dir", lambda: None),
            mock.patch.object(
                guard.killswitch_config, "managed_settings_path", lambda: self.managed
            ),
        ):
            patch.start()
            self.addCleanup(patch.stop)

    def run_hook(self, argv: list[str]) -> tuple[int, str]:
        stdout = io.StringIO()
        with (
            mock.patch(
                "sys.stdin", io.StringIO('{"command_name":"disk-hygiene:clean"}')
            ),
            mock.patch.object(guard.sys, "argv", argv),
            redirect_stdout(stdout),
        ):
            code = engine_context.main()
        return code, stdout.getvalue()

    def context(self, argv: list[str]) -> str:
        code, out = self.run_hook(argv)
        self.assertEqual(0, code)
        output = json.loads(out)["hookSpecificOutput"]
        self.assertEqual("UserPromptExpansion", output["hookEventName"])
        return output["additionalContext"]

    def guard_decision(self, command: str) -> str:
        argv = ["destructive_guard.py", "--plugin-root", str(self.plugin_root)]
        stdout = io.StringIO()
        with (
            mock.patch(
                "sys.stdin",
                io.StringIO(json.dumps({"tool_input": {"command": command}})),
            ),
            mock.patch.object(guard.sys, "argv", argv),
            redirect_stdout(stdout),
        ):
            self.assertEqual(0, guard.main())
        return json.loads(stdout.getvalue())["hookSpecificOutput"]["permissionDecision"]

    def test_reported_values_pass_the_skill_guard_on_the_first_call(self) -> None:
        text = self.context(
            ["engine_context.py", "--plugin-root", str(self.plugin_root)]
        )
        python = re.search(r'^hook_python: "([^"]+)"$', text, re.MULTILINE)
        data_root = re.search(r'^data_root: "([^"]+)"$', text, re.MULTILINE)
        assert python and data_root, text
        engine = SCRIPT_DIR / "hygiene.py"
        command = (
            f'"{python.group(1)}" "{engine}" scan --target t --output "{data_root.group(1)}/runs/r/snapshot.json" '
            f'--data-root "{data_root.group(1)}"'
        )
        self.assertEqual("allow", self.guard_decision(command))

    def test_bare_python_with_the_same_values_is_still_denied(self) -> None:
        text = self.context(
            ["engine_context.py", "--plugin-root", str(self.plugin_root)]
        )
        data_root = re.search(r'^data_root: "([^"]+)"$', text, re.MULTILINE)
        assert data_root, text
        engine = SCRIPT_DIR / "hygiene.py"
        command = (
            f'python "{engine}" scan --target t --output s '
            f'--data-root "{data_root.group(1)}"'
        )
        self.assertEqual("deny", self.guard_decision(command))

    def test_note_names_the_engine_path_the_guard_admits(self) -> None:
        text = self.context(
            ["engine_context.py", "--plugin-root", str(self.plugin_root)]
        )
        engine = re.search(r'^engine: "([^"]+)"$', text, re.MULTILINE)
        python = re.search(r'^hook_python: "([^"]+)"$', text, re.MULTILINE)
        data_root = re.search(r'^data_root: "([^"]+)"$', text, re.MULTILINE)
        assert engine and python and data_root, text
        self.assertEqual(
            (SCRIPT_DIR / "hygiene.py").resolve(), Path(engine.group(1)).resolve()
        )
        command = (
            f'"{python.group(1)}" "{engine.group(1)}" scan --target t --output '
            f'"{data_root.group(1)}/runs/r/snapshot.json" --data-root "{data_root.group(1)}"'
        )
        self.assertEqual("allow", self.guard_decision(command))

    def test_note_reports_the_data_root_each_channel_supplies(self) -> None:
        derived = (self.plugin_root.parents[3] / "data").as_posix()
        cases = {
            "plugin-cache layout": (
                ["engine_context.py", "--plugin-root", str(self.plugin_root)],
                f"{derived}/disk-hygiene-melodic-software",
            ),
            "--authorized-data-root argument": (
                [
                    "engine_context.py",
                    "--plugin-root",
                    str(self.plugin_root),
                    "--authorized-data-root",
                    str(self.plugin_root.parent / "direct"),
                ],
                (self.plugin_root.parent / "direct").as_posix(),
            ),
        }
        for channel, (argv, expected) in cases.items():
            with self.subTest(channel=channel):
                self.assertIn(f'data_root: "{expected}"\n', self.context(argv) + "\n")

    def test_env_data_root_is_never_reported(self) -> None:
        elsewhere = self.plugin_root.parents[4] / "checkout"
        elsewhere.mkdir()
        os.environ["CLAUDE_PLUGIN_DATA"] = str(elsewhere / "from-env")
        text = self.context(["engine_context.py", "--plugin-root", str(elsewhere)])
        self.assertIn("data_root: none", text)
        self.assertNotIn("from-env", text)

    def test_no_resolvable_data_root_says_so_and_still_exits_zero(self) -> None:
        text = self.context(["engine_context.py"])
        self.assertIn("data_root: none", text)
        self.assertRegex(text, r'(?m)^hook_python: "[^"]+"$')

    def test_a_failure_prints_nothing_and_never_blocks(self) -> None:
        with mock.patch.object(
            engine_context, "context_text", side_effect=RuntimeError("boom")
        ):
            code, out = self.run_hook(["engine_context.py"])
        self.assertEqual((0, ""), (code, out))


class HooksJsonRegistrationTest(unittest.TestCase):
    def rows(self) -> list[dict]:
        config = json.loads(HOOKS_JSON.read_text(encoding="utf-8"))
        return config["hooks"]["UserPromptExpansion"]

    def test_row_passes_the_same_plugin_root_argument_as_the_skill_guard(self) -> None:
        (row,) = self.rows()
        (hook,) = row["hooks"]
        args = hook["args"]
        self.assertEqual("node", hook["command"])
        self.assertTrue(
            any(str(arg).endswith("/engine_context.py") for arg in args),
            args,
        )
        root_at = args.index("--plugin-root")
        self.assertEqual("${CLAUDE_PLUGIN_ROOT}", args[root_at + 1])
        self.assertNotIn("--authorized-data-root", args)

    def test_matcher_fires_only_for_the_clean_command(self) -> None:
        (row,) = self.rows()
        matcher = re.compile(row["matcher"])
        for name in ("disk-hygiene:clean", "/disk-hygiene:clean"):
            self.assertTrue(matcher.search(name), name)
        for name in ("disk-hygiene:setup", "repo-hygiene:clean", "clean"):
            self.assertFalse(matcher.search(name), name)


if __name__ == "__main__":
    unittest.main()
