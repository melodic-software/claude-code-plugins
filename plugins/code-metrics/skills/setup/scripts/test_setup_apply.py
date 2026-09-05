#!/usr/bin/env python3
"""Output-based tests for setup-apply.py at its command line."""

from __future__ import annotations

import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
SCRIPT = SCRIPT_DIR / "setup-apply.py"
YAML_SUBSET = SCRIPT_DIR.parents[2] / "scripts" / "yaml_subset.py"
DEFAULTS = SCRIPT_DIR.parents[2] / "scripts" / "config-defaults.json"

_spec = importlib.util.spec_from_file_location("yaml_subset", YAML_SUBSET)
assert _spec is not None and _spec.loader is not None
yaml_subset = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(yaml_subset)


def run(*args: str, cwd: str | None = None) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, str(SCRIPT), *args],
        capture_output=True,
        text=True,
        check=False,
        cwd=cwd,
    )


class SetupApplyTests(unittest.TestCase):
    def test_writes_then_reports_already_configured_byte_identical(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            first = run("--dir", tmp, "size.file_lines=500")
            self.assertEqual(first.returncode, 0, first.stderr)
            target = Path(tmp) / ".claude" / "code-metrics.yaml"
            self.assertIn("written", first.stdout)
            written = target.read_bytes()
            self.assertEqual(
                yaml_subset.parse(written.decode()), {"size": {"file_lines": 500}}
            )
            second = run("--dir", tmp, "size.file_lines=500")
            self.assertEqual(second.returncode, 0, second.stderr)
            self.assertIn("already configured", second.stdout)
            self.assertEqual(target.read_bytes(), written)

    def test_merges_per_key_and_preserves_unknown_keys(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp) / "cm.yaml"
            target.write_text(
                "# hand-written\ncomplexity:\n  cyclomatic:\n    reference: 10\ncustom_key: keep\n",
                encoding="utf-8",
            )
            result = run(
                "--file",
                str(target),
                "size.file_lines=500",
                'scope.exclude=["vendor/**", "gen/**"]',
                "lanes.dotnet.enabled=false",
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            doc = yaml_subset.parse(target.read_text(encoding="utf-8"))
            self.assertEqual(doc["complexity"]["cyclomatic"]["reference"], 10)
            self.assertEqual(doc["custom_key"], "keep")
            self.assertEqual(doc["size"]["file_lines"], 500)
            self.assertEqual(doc["scope"]["exclude"], ["vendor/**", "gen/**"])
            self.assertIs(doc["lanes"]["dotnet"]["enabled"], False)
            self.assertIn(
                "custom_key is not a key the contract declares",
                run("--file", str(target), "custom_key=keep").stderr,
            )

    def test_quoting_round_trips_awkward_strings(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp) / "cm.yaml"
            run(
                "--file",
                str(target),
                'coverage.artifacts=["a: b.info", "#hash", "true"]',
            )
            doc = yaml_subset.parse(target.read_text(encoding="utf-8"))
            self.assertEqual(
                doc["coverage"]["artifacts"], ["a: b.info", "#hash", "true"]
            )

    def test_no_dir_targets_the_repository_root_from_a_subdirectory(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            env = {**os.environ, "GIT_DIR": "", "GIT_WORK_TREE": ""}
            env.pop("GIT_DIR")
            env.pop("GIT_WORK_TREE")
            subprocess.run(["git", "init", "-q", tmp], check=True, env=env)
            sub = Path(tmp) / "sub"
            sub.mkdir()
            result = run("size.file_lines=500", cwd=str(sub))
            self.assertEqual(result.returncode, 0, result.stderr)
            target = Path(tmp) / ".claude" / "code-metrics.yaml"
            self.assertTrue(target.is_file(), "written at the repository root")
            self.assertFalse((sub / ".claude").exists())
            outside = Path(tmp) / "plain"
            outside.mkdir()
            result = run("size.file_lines=500", cwd=str(outside))
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(
                Path(result.stdout.split()[-1]).resolve().parent.parent,
                Path(tmp).resolve(),
                "inside the repository, a plain subdirectory still resolves to the root",
            )

    def test_errors(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            self.assertEqual(run("--dir", tmp).returncode, 2)
            self.assertEqual(run("--dir", tmp, "size.file_lines").returncode, 2)
            result = run("--dir", tmp, "lanes.typescript={ enabled: true }")
            self.assertEqual(result.returncode, 2)
            self.assertIn("outside the YAML subset", result.stderr)
            bad = Path(tmp) / "bad.yaml"
            bad.write_text("a: { b: 1 }\n", encoding="utf-8")
            result = run("--file", str(bad), "size.file_lines=1")
            self.assertEqual(result.returncode, 2)
            self.assertIn("fix it by hand", result.stderr)

    def test_template_is_in_the_subset_and_names_only_contract_keys(self) -> None:
        template = SCRIPT_DIR.parent / "templates" / "config-template.yaml"
        doc = yaml_subset.load(template)
        defaults = json.loads(DEFAULTS.read_text(encoding="utf-8"))
        contract_keys = {k for k in defaults if not k.startswith("_")} - {"thresholds"}
        self.assertTrue(set(doc), "the template names at least one key")
        self.assertLessEqual(set(doc), contract_keys, sorted(set(doc) - contract_keys))
        for key in doc:
            self.assertEqual(
                sorted(doc[key]),
                sorted(defaults[key]),
                "template keys under %s differ from the contract" % key,
            )

        # The template's values are the bundled defaults, leaf for leaf, so
        # the two surfaces cannot drift apart without this test saying so.
        def leaves(node, prefix=""):
            if isinstance(node, dict):
                for k, v in node.items():
                    yield from leaves(v, f"{prefix}{k}.")
            else:
                yield prefix[:-1], node

        template_leaves = dict(leaves(doc))
        default_leaves = dict(leaves(defaults))
        for path, value in template_leaves.items():
            self.assertIn(path, default_leaves, path)
            self.assertEqual(value, default_leaves[path], path)


if __name__ == "__main__":
    unittest.main()
