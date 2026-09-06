#!/usr/bin/env python3
"""Output-based tests for yaml_subset.py: the pure parser through the module
loaded by path, the command line through subprocess."""

from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
SCRIPT = SCRIPT_DIR / "yaml_subset.py"

_spec = importlib.util.spec_from_file_location("yaml_subset", SCRIPT)
assert _spec is not None and _spec.loader is not None
yaml_subset = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(yaml_subset)


def parse(text: str):
    return yaml_subset.parse(textwrap.dedent(text))


class ParseTests(unittest.TestCase):
    def test_nested_block_mappings_with_typed_scalars(self) -> None:
        doc = parse(
            """
            # a comment
            complexity:
              cyclomatic:
                reference: 20   # trailing comment
              cognitive:
                reference: null
              halstead:
                difficulty: ~
            size:
              mode: file-lines
              ratio: 2.5
              enabled: true
              disabled: false
              name: "quoted # not a comment"
              other: 'it''s'
              empty:
            """
        )
        self.assertEqual(doc["complexity"]["cyclomatic"]["reference"], 20)
        self.assertIsNone(doc["complexity"]["cognitive"]["reference"])
        self.assertIsNone(doc["complexity"]["halstead"]["difficulty"])
        self.assertEqual(doc["size"]["mode"], "file-lines")
        self.assertEqual(doc["size"]["ratio"], 2.5)
        self.assertIs(doc["size"]["enabled"], True)
        self.assertIs(doc["size"]["disabled"], False)
        self.assertEqual(doc["size"]["name"], "quoted # not a comment")
        self.assertEqual(doc["size"]["other"], "it's")
        self.assertIsNone(doc["size"]["empty"])

    def test_flow_and_block_sequences(self) -> None:
        doc = parse(
            """
            globs: ["*.sh", '*.bash', plain]
            none: []
            registries:
              - scripts/a.txt
              - scripts/b.txt
            lanes:
            - typescript
            - python
            """
        )
        self.assertEqual(doc["globs"], ["*.sh", "*.bash", "plain"])
        self.assertEqual(doc["none"], [])
        self.assertEqual(doc["registries"], ["scripts/a.txt", "scripts/b.txt"])
        self.assertEqual(doc["lanes"], ["typescript", "python"])

    def test_sequence_of_mappings_starting_on_the_dash_line(self) -> None:
        doc = parse(
            """
            sites:
              - surface: CLAUDE.md
                anchor/v1: "e:1145aa93c681:070ee98f"
              - surface: other.md
              - name: nested
                values:
                  - 1
                  - 2
            """
        )
        self.assertEqual(
            doc["sites"][0],
            {"surface": "CLAUDE.md", "anchor/v1": "e:1145aa93c681:070ee98f"},
        )
        self.assertEqual(doc["sites"][1], {"surface": "other.md"})
        self.assertEqual(doc["sites"][2], {"name": "nested", "values": [1, 2]})

    def test_the_contract_example_round_trips(self) -> None:
        doc = parse(
            """
            lanes:
              typescript:
                enabled: true
                collectors:            # measure -> ordered tool list
                  cyclomatic: [lizard, eslint-complexity]
              dotnet:
                enabled: true          # detected, reported as deferred in V1
            """
        )
        self.assertEqual(
            doc["lanes"]["typescript"]["collectors"]["cyclomatic"],
            ["lizard", "eslint-complexity"],
        )
        self.assertIs(doc["lanes"]["dotnet"]["enabled"], True)

    def test_empty_document_is_none(self) -> None:
        self.assertIsNone(parse("# only a comment\n\n"))

    def assert_error(self, text: str, line: int, fragment: str) -> None:
        with self.assertRaises(yaml_subset.YamlSubsetError) as ctx:
            parse(text)
        self.assertEqual(ctx.exception.line, line, str(ctx.exception))
        self.assertIn(fragment, str(ctx.exception))

    def test_constructs_outside_the_subset_are_named_with_their_line(self) -> None:
        self.assert_error("a: 1\nb: { x: 1 }\n", 2, "flow mapping")
        self.assert_error("a: &anchor 1\n", 1, "anchors")
        self.assert_error("a: 1\nb: *anchor\n", 2, "aliases")
        self.assert_error("a: !!str 1\n", 1, "tags")
        self.assert_error("a: |\n  text\n", 1, "block scalars")
        self.assert_error("---\na: 1\n", 1, "document markers")
        self.assert_error("a:\n\tb: 1\n", 2, "tab indentation")
        self.assert_error("a: 1\na: 2\n", 2, "duplicate key")
        self.assert_error("a: [1, [2]]\n", 1, "nested flow sequences")
        self.assert_error("a: 'unterminated\n", 1, "unterminated")
        self.assert_error("a:\n  b: 1\n c: 2\n", 3, "unexpected indent")


class CommandLineTests(unittest.TestCase):
    def test_prints_json_and_exit_codes(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            good = Path(tmp) / "good.yaml"
            good.write_text("size:\n  file_lines: 500\n", encoding="utf-8")
            result = subprocess.run(
                [sys.executable, str(SCRIPT), str(good)],
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(json.loads(result.stdout), {"size": {"file_lines": 500}})
            bad = Path(tmp) / "bad.yaml"
            bad.write_text(
                "lanes:\n  typescript: { enabled: true }\n", encoding="utf-8"
            )
            result = subprocess.run(
                [sys.executable, str(SCRIPT), str(bad)],
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(result.returncode, 2)
            self.assertIn("flow mapping", result.stderr)
            self.assertIn("line 2", result.stderr)
        self.assertEqual(
            subprocess.run(
                [sys.executable, str(SCRIPT)],
                capture_output=True,
                text=True,
                check=False,
            ).returncode,
            2,
        )


if __name__ == "__main__":
    unittest.main()
