#!/usr/bin/env python3
"""Unit and cross-language parity tests for ``lib/data_root_state.py``."""

from __future__ import annotations

import json
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

LIB_DIR = Path(__file__).resolve().parent
PLUGIN_ROOT = LIB_DIR.parent
SCRIPTS_DIR = PLUGIN_ROOT / "skills" / "clean" / "scripts"
for _dir in (LIB_DIR, SCRIPTS_DIR):
    if str(_dir) not in sys.path:
        sys.path.insert(0, str(_dir))

import data_root_state  # noqa: E402
import engine_grammar  # noqa: E402
import guard_launch_monitor  # noqa: E402

HOOKS_JSON = PLUGIN_ROOT / "hooks" / "hooks.json"
RESUME_NOTICE_MJS = PLUGIN_ROOT / "hooks" / "resume-notice.mjs"
RUN_PYTHON_HOOK_SH = PLUGIN_ROOT / "hooks" / "run-python-hook.sh"


class CrossLanguageParityTests(unittest.TestCase):
    def test_every_hook_marker_subdir_is_engine_owned(self) -> None:
        discovered: set[str] = set()

        hooks_cfg = json.loads(HOOKS_JSON.read_text(encoding="utf-8"))
        for rows in hooks_cfg.get("hooks", {}).values():
            for row in rows:
                for hook in row.get("hooks", []):
                    args = hook.get("args", [])
                    for idx, token in enumerate(args):
                        if token in ("--launch-marker", "--skip-unless-marker"):
                            if idx + 1 < len(args):
                                discovered.add(args[idx + 1])

        mjs_text = RESUME_NOTICE_MJS.read_text(encoding="utf-8")
        for match in re.finditer(
            r"""export\s+const\s+SUBDIR\s*=\s*['"]([^'"]+)['"]""", mjs_text
        ):
            discovered.add(match.group(1))

        sh_text = RUN_PYTHON_HOOK_SH.read_text(encoding="utf-8")
        for match in re.finditer(
            r"(?m)^\s*_marker_candidates\s+([A-Za-z0-9_-]+)\b", sh_text
        ):
            discovered.add(match.group(1))

        self.assertIn("clean-invoked", discovered)
        self.assertIn("guard-no-interpreter", discovered)
        self.assertIn("guard-launch-monitor", discovered)

        for subdir in sorted(discovered):
            self.assertIn(subdir, data_root_state.ENGINE_OWNED_DIRS)
            self.assertIn(subdir, engine_grammar.ENGINE_OWNED_DIRS)
            self.assertTrue(data_root_state.is_engine_owned(subdir))
            self.assertTrue(data_root_state.is_engine_owned(f"{subdir}/s.launched"))
            self.assertTrue(engine_grammar.is_engine_owned(f"{subdir}/s.launched"))

        self.assertEqual(
            {
                "guard-decisions",
                "guard-launch-monitor",
                "clean-runs",
                "inventory",
                "clean-invoked",
                "guard-no-interpreter",
            },
            set(data_root_state.ENGINE_OWNED_DIRS),
        )
        self.assertEqual(
            data_root_state.ENGINE_OWNED_DIRS, engine_grammar.ENGINE_OWNED_DIRS
        )

    def test_ascii_session_id_sanitization_matches_bash_and_node(self) -> None:
        cases = (
            "abc-123_Z",
            "a/b:c.d",
            "../escape",
            "space and\ttab",
            "café",
            "sess-αβγ",
            "id-日本語",
            "id-٢",
        )
        sh_text = RUN_PYTHON_HOOK_SH.read_text(encoding="utf-8")
        self.assertIn('${session//[^a-zA-Z0-9_-]/_}', sh_text)

        bash_bin = shutil.which("bash")
        self.assertIsNotNone(bash_bin, "bash required for cross-language parity test")
        bash_script = (
            'for session in "$@"; do printf "%s\\n" "${session//[^a-zA-Z0-9_-]/_}"; done'
        )
        bash_run = subprocess.run(
            [bash_bin, "-c", bash_script, "_", *cases],
            capture_output=True,
            text=True,
            encoding="utf-8",
            check=True,
        )
        bash_results = bash_run.stdout.splitlines()
        self.assertEqual(len(cases), len(bash_results))

        node_bin = shutil.which("node")
        self.assertIsNotNone(node_bin, "node required for cross-language parity test")
        node_script = (
            "import { pathToFileURL } from 'node:url';\n"
            "import { basename } from 'node:path';\n"
            "const mod = await import(pathToFileURL(process.argv[1]).href);\n"
            "const cases = JSON.parse(process.argv[2]);\n"
            "const out = cases.map((s) => {\n"
            "  const c = mod.markerCandidates(s, { markerRoot: '/r', env: {}, platform: 'linux' });\n"
            "  return basename(c[0], '.launched');\n"
            "});\n"
            "process.stdout.write(JSON.stringify(out));\n"
        )
        node_run = subprocess.run(
            [
                node_bin,
                "--input-type=module",
                "-e",
                node_script,
                str(RESUME_NOTICE_MJS),
                json.dumps(list(cases)),
            ],
            capture_output=True,
            text=True,
            encoding="utf-8",
            check=True,
        )
        node_results = json.loads(node_run.stdout)
        self.assertEqual(len(cases), len(node_results))

        for raw, bash_safe, node_safe in zip(cases, bash_results, node_results):
            with self.subTest(session_id=raw):
                py_safe = data_root_state.sanitize_session_id(raw)
                self.assertEqual(bash_safe, py_safe)
                self.assertEqual(node_safe, py_safe)
                self.assertEqual(f"{py_safe}.json", engine_grammar.run_marker_filename(raw))
                monitor_path = guard_launch_monitor._marker_path_candidates(
                    "/r", raw, ".warned"
                )[0]
                self.assertEqual(f"{py_safe}.warned", monitor_path.name)


class DataRootAndCleanRunStoreTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name).resolve() / "data"
        self.root.mkdir()
        self.dr = data_root_state.DataRoot(self.root)

    def test_data_root_refuses_clean_invoked_and_guard_no_interpreter(self) -> None:
        for rel in (
            "clean-invoked/s.launched",
            "CLEAN-INVOKED/s.launched",
            "clean-invoked./s.launched",
            "clean-invoked::$DATA/s.launched",
            "guard-no-interpreter/s.noticed",
            "guard-decisions/decisions.jsonl",
            "catalog.json",
        ):
            target = self.root / rel
            with self.subTest(relative=rel):
                self.assertFalse(self.dr.is_authorized_file(str(target)))
                with self.assertRaises(data_root_state.DataRootError):
                    self.dr.model_output_path(target)
                with self.assertRaises(data_root_state.DataRootError):
                    self.dr.state_input_path(target)

    def test_data_root_admits_user_run_artifacts(self) -> None:
        target = self.root / "runs" / "r1" / "snapshot.json"
        self.assertTrue(self.dr.is_authorized_file(str(target)))
        self.assertEqual(target, self.dr.model_output_path(target))
        self.assertEqual(target, self.dr.state_input_path(target))

    def test_clean_run_store_lifecycle(self) -> None:
        store = self.dr.clean_runs()
        self.assertFalse(store.is_open("sess-1"))
        plan = str(self.root / "runs" / "plan-high.json")
        store.record_step("sess-1", ends_with=plan)
        self.assertTrue(store.is_open("sess-1"))

        store.close_if_ended("sess-1", ended=self.root / "runs" / "other.json")
        self.assertTrue(store.is_open("sess-1"))

        store.close_if_ended("sess-1", ended=Path(plan))
        self.assertFalse(store.is_open("sess-1"))

    def test_manual_lane_survives_preview_step(self) -> None:
        store = self.dr.clean_runs()
        store.record_step("sess-m", ends_with=None)
        self.assertTrue(store.manual_lane_open("sess-m"))
        plan = str(self.root / "runs" / "plan-high.json")
        store.record_step("sess-m", ends_with=plan)
        self.assertTrue(store.manual_lane_open("sess-m"))
        store.close_if_ended("sess-m", ended=Path(plan))
        self.assertTrue(store.is_open("sess-m"))


if __name__ == "__main__":
    unittest.main()
