"""babysit_run_cache: one process parses the file once until it changes on
disk, and what it serves never aliases the parsed copy."""

from __future__ import annotations

import json
import os
import pathlib
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))

import babysit_run_cache as run_cache  # noqa: E402


class ParsesOncePerProcess(unittest.TestCase):
    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.path = pathlib.Path(tmp.name, "run.json")
        patcher = mock.patch.dict("os.environ", {run_cache.ENV: str(self.path)})
        patcher.start()
        self.addCleanup(patcher.stop)
        self.parses = 0
        real = run_cache._load

        def counting(path: pathlib.Path) -> dict:
            self.parses += 1
            return real(path)

        patcher = mock.patch.object(run_cache, "_load", counting)
        patcher.start()
        self.addCleanup(patcher.stop)

    def other_process_writes(self, data: dict) -> None:
        """Another gate process's write: a new file renamed into place."""
        tmp = self.path.with_name("other.tmp")
        tmp.write_text(json.dumps(data), encoding="utf-8")
        os.replace(tmp, self.path)

    def test_gets_and_puts_parse_the_file_once(self) -> None:
        run_cache.put("s", "a", 1)
        for _ in range(50):
            self.assertEqual(run_cache.get("s", "a", None), 1)
            self.assertIsNone(run_cache.get("s", "missing", None))
        for i in range(20):
            run_cache.put("s", f"k{i}", i)
            self.assertEqual(run_cache.get("s", f"k{i}", None), i)
        self.assertLessEqual(self.parses, 1)
        stored = json.loads(self.path.read_text(encoding="utf-8"))
        self.assertEqual(stored["s"]["k19"]["value"], 19)
        self.assertEqual(stored["s"]["a"]["value"], 1)

    def test_another_process_write_is_seen_on_the_next_get(self) -> None:
        run_cache.put("s", "a", 1)
        self.assertEqual(run_cache.get("s", "a", None), 1)
        at = run_cache.now().isoformat()
        self.other_process_writes({"s": {"a": {"at": at, "value": 2}}})
        self.assertEqual(run_cache.get("s", "a", None), 2)
        # A put merges into the other process's file, not the stale copy.
        run_cache.put("s", "b", 3)
        stored = json.loads(self.path.read_text(encoding="utf-8"))
        self.assertEqual(stored["s"]["a"]["value"], 2)
        self.assertEqual(stored["s"]["b"]["value"], 3)

    def test_a_removed_file_is_a_miss(self) -> None:
        run_cache.put("s", "a", 1)
        self.assertEqual(run_cache.get("s", "a", None), 1)
        self.path.unlink()
        self.assertIsNone(run_cache.get("s", "a", None))

    def test_a_failed_write_is_not_served(self) -> None:
        run_cache.put("s", "a", 1)
        with mock.patch.object(run_cache.os, "replace", side_effect=OSError):
            run_cache.put("s", "b", 2)
        self.assertIsNone(run_cache.get("s", "b", None))
        self.assertEqual(run_cache.get("s", "a", None), 1)

    def test_a_served_value_is_not_the_cached_copy(self) -> None:
        value = {"list": [1]}
        run_cache.put("s", "a", value)
        value["list"].append(2)
        got = run_cache.get("s", "a", None)
        self.assertEqual(got, {"list": [1]})
        got["list"].append(3)
        self.assertEqual(run_cache.get("s", "a", None), {"list": [1]})

    def test_an_unserializable_value_raises_as_before(self) -> None:
        with self.assertRaises(TypeError):
            run_cache.put("s", "a", object())
        self.assertIsNone(run_cache.get("s", "a", None))


if __name__ == "__main__":
    unittest.main()
