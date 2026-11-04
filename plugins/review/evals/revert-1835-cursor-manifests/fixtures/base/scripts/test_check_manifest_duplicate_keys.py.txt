#!/usr/bin/env python3
"""Behavioral tests for the manifest duplicate-key detector (issue #1498).

#1492 shipped `plugins/skill-quality/.claude-plugin/plugin.json` with two
`"version"` members through a fully green CI suite — JSON Schema validation
and every standard JSON parser resolve a duplicate key last-wins and never
see the conflict. These tests prove the new detector actually sees it: the
central fixture in `test_catches_the_1492_shaped_duplicate_version_key`
reproduces that exact shape (two top-level `"version"` members) and asserts
the gate fails on it, byte for byte the manifest #1492 shipped.
"""

from __future__ import annotations

import importlib.util
import io
import json
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from unittest import mock

SCRIPT_DIR = Path(__file__).resolve().parent


def load_module(name: str, filename: str):
    spec = importlib.util.spec_from_file_location(name, SCRIPT_DIR / filename)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


detector = load_module(
    "check_manifest_duplicate_keys", "check-manifest-duplicate-keys.py"
)


class FindDuplicateKeysTests(unittest.TestCase):
    """Unit-level coverage of the object_pairs_hook detector itself."""

    def test_no_duplicates_returns_empty(self) -> None:
        text = json.dumps({"name": "x", "version": "1.0.0", "description": "d"})
        self.assertEqual([], detector.find_duplicate_keys(text))

    def test_top_level_duplicate_key_detected(self) -> None:
        # The actual #1492 shape: two "version" members at the top level.
        text = '{"name": "skill-quality", "version": "0.11.0", "version": "0.12.0"}'
        self.assertEqual(["version"], detector.find_duplicate_keys(text))

    def test_last_value_wins_same_as_every_other_consumer(self) -> None:
        # The detector must not crash or reject the document -- it reports
        # the conflict AND still resolves last-wins internally, exactly like
        # json.load, JSON.parse, and jq do, so its own read of "the version"
        # (if it ever needed one) would never disagree with theirs.
        collector = detector._DuplicateKeyCollector()
        result = json.loads(
            '{"version": "0.11.0", "version": "0.12.0"}',
            object_pairs_hook=collector,
        )
        self.assertEqual("0.12.0", result["version"])
        self.assertEqual(["version"], collector.duplicates)

    def test_nested_duplicate_key_detected(self) -> None:
        # A repeated key inside a nested object (e.g. userConfig) is not the
        # top-level case #1492 was, but the same defect class, and
        # object_pairs_hook is called once per object at every depth.
        text = '{"name": "x", "userConfig": {"scope": "a", "scope": "b"}}'
        self.assertEqual(["scope"], detector.find_duplicate_keys(text))

    def test_duplicate_only_flagged_within_same_object(self) -> None:
        # The same key name in TWO SIBLING objects (not the same object) is
        # not a duplicate -- duplication is scoped to one JSON object
        # literal, matching what "last-wins" actually means.
        text = json.dumps(
            {"a": {"name": "inner-a"}, "b": {"name": "inner-b"}, "name": "outer"}
        )
        self.assertEqual([], detector.find_duplicate_keys(text))

    def test_multiple_distinct_duplicate_keys_all_reported(self) -> None:
        text = '{"version": "1.0.0", "version": "2.0.0", "name": "x", "name": "y"}'
        self.assertEqual(["version", "name"], detector.find_duplicate_keys(text))

    def test_repeated_more_than_twice_reported_once(self) -> None:
        text = '{"version": "1.0.0", "version": "2.0.0", "version": "3.0.0"}'
        self.assertEqual(["version"], detector.find_duplicate_keys(text))

    def test_malformed_json_raises_decode_error_not_swallowed(self) -> None:
        with self.assertRaises(json.JSONDecodeError):
            detector.find_duplicate_keys("{not json")


class CliTests(unittest.TestCase):
    """End-to-end coverage of main(): the shape the hygiene CI step invokes."""

    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.tmp_path = Path(self.tmp.name)

    def write(self, relpath: str, text: str) -> Path:
        path = self.tmp_path / relpath
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        return path

    def run_cli(self, argv: list[str]) -> tuple[int, str, str]:
        stdout, stderr = io.StringIO(), io.StringIO()
        with redirect_stdout(stdout), redirect_stderr(stderr):
            code = detector.main(argv)
        return code, stdout.getvalue(), stderr.getvalue()

    def test_catches_the_1492_shaped_duplicate_version_key(self) -> None:
        # Fixture reproducing #1492's actual defect: two "version" members in
        # a plugin.json. This is the fixture the issue asked for: a real
        # duplicate key the gate must catch.
        manifest = self.write(
            "plugin.json",
            '{\n'
            '  "name": "skill-quality",\n'
            '  "version": "0.11.0",\n'
            '  "description": "Skill authoring QA.",\n'
            '  "version": "0.12.0"\n'
            '}\n',
        )
        code, _out, err = self.run_cli([str(manifest)])
        self.assertEqual(1, code)
        self.assertIn("DUPLICATE KEY", err)
        self.assertIn("'version'", err)
        self.assertIn(str(manifest), err)

    def test_well_formed_manifest_passes(self) -> None:
        manifest = self.write(
            "plugin.json",
            json.dumps({"name": "x", "version": "1.0.0"}),
        )
        code, out, err = self.run_cli([str(manifest)])
        self.assertEqual(0, code)
        self.assertIn("No duplicate", out)
        self.assertEqual("", err)

    def test_multiple_files_one_bad_one_good_fails_overall(self) -> None:
        good = self.write("good.json", json.dumps({"name": "ok"}))
        bad = self.write(
            "bad.json", '{"name": "x", "name": "y"}'
        )
        code, _out, err = self.run_cli([str(good), str(bad)])
        self.assertEqual(1, code)
        self.assertIn(str(bad), err)
        self.assertNotIn(str(good), err)

    def test_missing_file_fails_with_error(self) -> None:
        code, _out, err = self.run_cli([str(self.tmp_path / "absent.json")])
        self.assertEqual(1, code)
        self.assertIn("does not exist", err)

    def test_malformed_json_does_not_double_report(self) -> None:
        # A parse failure is the schema-validation step's job to report, not
        # this gate's -- it must not also fail (or crash) on unparsable input.
        manifest = self.write("plugin.json", "{not json")
        code, out, err = self.run_cli([str(manifest)])
        self.assertEqual(0, code)
        self.assertEqual("", err)
        self.assertIn("No duplicate", out)

    def test_no_files_and_no_default_matches_errors_with_exit_2(self) -> None:
        with mock.patch.object(detector, "REPO_ROOT", self.tmp_path):
            code, _out, err = self.run_cli([])
        self.assertEqual(2, code)
        self.assertIn("no manifest files found", err)

    def test_default_discovery_covers_plugin_and_marketplace_manifests(self) -> None:
        self.write(
            "plugins/alpha/.claude-plugin/plugin.json",
            json.dumps({"name": "alpha", "version": "1.0.0"}),
        )
        self.write(
            "plugins/beta/.claude-plugin/plugin.json",
            '{"name": "beta", "version": "1.0.0", "version": "1.0.1"}',
        )
        self.write(
            ".claude-plugin/marketplace.json",
            '{"name": "marketplace", "name": "dup"}',
        )
        with mock.patch.object(detector, "REPO_ROOT", self.tmp_path):
            code, _out, err = self.run_cli([])
        self.assertEqual(1, code)
        self.assertIn("beta", err)
        self.assertIn("marketplace.json", err)
        self.assertNotIn(
            str(self.tmp_path / "plugins/alpha/.claude-plugin/plugin.json"), err
        )

    def test_default_discovery_all_clean_passes(self) -> None:
        self.write(
            "plugins/alpha/.claude-plugin/plugin.json",
            json.dumps({"name": "alpha", "version": "1.0.0"}),
        )
        self.write(
            ".claude-plugin/marketplace.json",
            json.dumps({"name": "marketplace"}),
        )
        with mock.patch.object(detector, "REPO_ROOT", self.tmp_path):
            code, out, err = self.run_cli([])
        self.assertEqual(0, code)
        self.assertEqual("", err)
        self.assertIn("2 manifest file(s)", out)

    def test_output_reports_every_distinct_duplicate_key_in_one_message(self) -> None:
        manifest = self.write(
            "plugin.json",
            '{"version": "1.0.0", "version": "2.0.0", "name": "x", "name": "y"}',
        )
        code, _out, err = self.run_cli([str(manifest)])
        self.assertEqual(1, code)
        self.assertIn("'version'", err)
        self.assertIn("'name'", err)


if __name__ == "__main__":
    unittest.main()
