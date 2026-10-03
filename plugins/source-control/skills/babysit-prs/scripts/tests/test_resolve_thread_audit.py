"""Tests for resolve-thread wrapper audit logging (#2139)."""

from __future__ import annotations

import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import babysit_resolve_thread as resolver


class ResolveThreadAuditTests(unittest.TestCase):
    def test_append_writes_jsonl_with_timestamp(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            log_path = Path(tmp) / "audit.jsonl"
            with mock.patch.dict(
                "os.environ",
                {"SOURCE_CONTROL_RESOLVE_THREAD_AUDIT_LOG": str(log_path)},
                clear=False,
            ):
                resolver.append_resolve_thread_audit(
                    {"thread_id": "RT_1", "pr": "o/r#1", "route": "wrapper"}
                )
            lines = log_path.read_text(encoding="utf-8").strip().splitlines()
            self.assertEqual(len(lines), 1)
            row = json.loads(lines[0])
            self.assertEqual(row["thread_id"], "RT_1")
            self.assertIn("recorded_at", row)


class ResolveThreadAuditPathTests(unittest.TestCase):
    """Another plugin's SessionStart hook can export its own data dir into every
    Bash call as CLAUDE_PLUGIN_DATA; the audit log must never land there."""

    def path_with(self, plugin_data: str, home: str) -> Path:
        env = {"CLAUDE_PLUGIN_DATA": plugin_data, "HOME": home}
        with mock.patch.dict("os.environ", env, clear=False):
            os.environ.pop("SOURCE_CONTROL_RESOLVE_THREAD_AUDIT_LOG", None)
            return resolver.resolve_thread_audit_log_path()

    def test_inherited_value_naming_this_plugin_is_used(self) -> None:
        own = "/d/source-control-melodic-software"
        self.assertEqual(
            self.path_with(own, "/h"),
            Path(own) / "source-control" / "resolve-thread-audit.jsonl",
        )

    def test_inherited_value_naming_another_plugin_is_ignored(self) -> None:
        self.assertEqual(
            self.path_with("/d/codex-openai-codex", "/h"),
            Path("/h") / ".claude" / "source-control" / "resolve-thread-audit.jsonl",
        )


if __name__ == "__main__":
    unittest.main()
