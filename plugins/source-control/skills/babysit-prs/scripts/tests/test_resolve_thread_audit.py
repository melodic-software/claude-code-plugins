#!/usr/bin/env python3
"""Tests for resolve-thread wrapper audit logging (#2139)."""

from __future__ import annotations

import json
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


if __name__ == "__main__":
    unittest.main()
