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

# One test builds a git fixture: clear the inherited git environment so an
# absolute GIT_DIR can never redirect that fixture into the caller's clone.
os.environ.pop("GIT_DIR", None)
os.environ.pop("GIT_WORK_TREE", None)
os.environ.pop("GIT_CONFIG", None)

SCRIPT_DIR = Path(__file__).resolve().parent
SCRIPT = SCRIPT_DIR / "setup-apply.py"
YAML_SUBSET = SCRIPT_DIR.parents[2] / "scripts" / "yaml_subset.py"
DEFAULTS = SCRIPT_DIR.parents[2] / "scripts" / "config-defaults.json"
RESOLVER = SCRIPT_DIR.parents[2] / "scripts" / "resolve-config.py"

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
            target = Path(tmp) / "docs" / "conventions" / "code-metrics.yaml"
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
            subprocess.run(["git", "init", "-q", tmp], check=True)
            sub = Path(tmp) / "sub"
            sub.mkdir()
            result = run("size.file_lines=500", cwd=str(sub))
            self.assertEqual(result.returncode, 0, result.stderr)
            target = Path(tmp) / "docs" / "conventions" / "code-metrics.yaml"
            self.assertTrue(target.is_file(), "written at the repository root")
            self.assertFalse((sub / "docs").exists())
            outside = Path(tmp) / "plain"
            outside.mkdir()
            result = run("size.file_lines=500", cwd=str(outside))
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(
                Path(result.stdout.split()[-1]).resolve().parents[2],
                Path(tmp).resolve(),
                "inside the repository, a plain subdirectory still resolves to the root",
            )

    def test_a_claude_file_is_carried_whole_into_the_docs_file(self) -> None:
        # With only the older .claude file present, the first apply writes
        # every key it holds into the docs file in the same write, so the
        # resolved configuration is the same before and after the move.
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / ".claude").mkdir()
            (root / ".claude" / "code-metrics.yaml").write_text(
                "complexity:\n  cyclomatic:\n    reference: 12\n"
                'scope:\n  exclude: ["gen/**"]\n'
                "lanes:\n  go:\n    enabled: false\n",
                encoding="utf-8",
            )

            def resolved() -> dict:
                out = subprocess.run(
                    [sys.executable, str(RESOLVER), "--home", tmp, "--repo-root", tmp],
                    capture_output=True,
                    text=True,
                    check=True,
                ).stdout
                # The resolved values; which file supplied them is expected
                # to change.
                return {
                    k: v for k, v in json.loads(out).items() if not k.startswith("_")
                }

            before = resolved()
            # size.mode=file-lines restates the bundled default, so the
            # apply itself changes no resolved value.
            result = run("--dir", tmp, "size.mode=file-lines")
            self.assertEqual(result.returncode, 0, result.stderr)
            target = root / "docs" / "conventions" / "code-metrics.yaml"
            self.assertEqual(
                yaml_subset.parse(target.read_text(encoding="utf-8")),
                {
                    "complexity": {"cyclomatic": {"reference": 12}},
                    "scope": {"exclude": ["gen/**"]},
                    "lanes": {"go": {"enabled": False}},
                    "size": {"mode": "file-lines"},
                },
            )
            self.assertIn(".claude/code-metrics.yaml", result.stdout)
            self.assertEqual(resolved(), before)

    def test_with_no_key_a_claude_file_is_moved_and_nothing_else_is_an_error(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.assertEqual(run("--dir", tmp).returncode, 2)
            (root / ".claude").mkdir()
            (root / ".claude" / "code-metrics.yaml").write_text(
                "size:\n  file_lines: 450\n", encoding="utf-8"
            )
            result = run("--dir", tmp)
            self.assertEqual(result.returncode, 0, result.stderr)
            target = root / "docs" / "conventions" / "code-metrics.yaml"
            self.assertEqual(
                yaml_subset.parse(target.read_text(encoding="utf-8")),
                {"size": {"file_lines": 450}},
            )
            # Once the docs file exists the .claude file is no longer carried.
            again = run("--dir", tmp)
            self.assertEqual(again.returncode, 2)

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
