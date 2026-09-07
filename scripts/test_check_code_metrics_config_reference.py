#!/usr/bin/env python3
"""Tests for the code-metrics config reference gate.

Every case runs the gate at its command line against a mutated COPY of the
shipped pair, so what is asserted is the exit code and the message an author
would actually see. The point of the gate is that drift is impossible, so the
suite is written as drift injections: each one must FAIL, and the message must
name the key, or the gate is decorative.
"""

from __future__ import annotations

import copy
import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
GATE = SCRIPT_DIR / "check-code-metrics-config-reference.py"
REPO_ROOT = SCRIPT_DIR.parent
SHIPPED_DEFAULTS = (
    REPO_ROOT / "plugins" / "code-metrics" / "scripts" / "config-defaults.json"
)
SHIPPED_DOC = REPO_ROOT / "plugins" / "code-metrics" / "reference" / "config.md"

_spec = importlib.util.spec_from_file_location("cm_config_reference_gate", GATE)
assert _spec is not None and _spec.loader is not None
gate = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(gate)


def run(defaults: Path, doc: Path) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, str(GATE), "--defaults", str(defaults), "--doc", str(doc)],
        capture_output=True,
        text=True,
        check=False,
    )


class GateHarness(unittest.TestCase):
    """A scratch copy of the shipped pair that each case mutates."""

    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.dir = Path(self._tmp.name)
        self.defaults_path = self.dir / "config-defaults.json"
        self.doc_path = self.dir / "config.md"
        self.defaults = json.loads(SHIPPED_DEFAULTS.read_text(encoding="utf-8"))
        self.doc = SHIPPED_DOC.read_text(encoding="utf-8")

    def write(self) -> subprocess.CompletedProcess:
        self.defaults_path.write_text(
            json.dumps(self.defaults, indent=2) + "\n", encoding="utf-8"
        )
        self.doc_path.write_text(self.doc, encoding="utf-8")
        return run(self.defaults_path, self.doc_path)

    def assert_clean(self, result: subprocess.CompletedProcess) -> None:
        self.assertEqual(result.returncode, 0, result.stderr)

    def assert_drift(
        self, result: subprocess.CompletedProcess, *must_name: str
    ) -> None:
        self.assertEqual(
            result.returncode, 1, f"stdout={result.stdout} stderr={result.stderr}"
        )
        for token in must_name:
            self.assertIn(token, result.stderr)


class ShippedPairTests(GateHarness):
    def test_the_shipped_pair_agrees(self) -> None:
        result = run(SHIPPED_DEFAULTS, SHIPPED_DOC)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("documents all", result.stdout)

    def test_the_unmutated_copy_agrees(self) -> None:
        # The harness itself must clear the gate, or every "this fails" case
        # below would pass for the wrong reason.
        self.assert_clean(self.write())


class DriftFailsTests(GateHarness):
    def test_a_new_defaults_key_fails_and_names_it(self) -> None:
        self.defaults["size"]["max_params"] = 7
        self.assert_drift(self.write(), "size.max_params")

    def test_a_new_top_level_defaults_section_fails_and_names_it(self) -> None:
        self.defaults["churn"] = {"window_days": 30}
        self.assert_drift(self.write(), "churn.window_days")

    def test_a_changed_default_value_fails_and_names_both_values(self) -> None:
        self.defaults["size"]["file_lines"] = 500
        self.assert_drift(self.write(), "size.file_lines", "`1000`", "`500`")

    def test_a_changed_default_type_fails(self) -> None:
        self.defaults["complexity"]["cyclomatic"]["reference"] = None
        self.assert_drift(self.write(), "complexity.cyclomatic.reference", "`null`")

    def test_a_removed_defaults_key_still_documented_fails(self) -> None:
        del self.defaults["duplication"]["min_lines"]
        self.assert_drift(self.write(), "duplication.min_lines")

    def test_a_row_deleted_from_the_document_fails(self) -> None:
        self.doc = "\n".join(
            line
            for line in self.doc.splitlines()
            if not line.startswith("| `duplication.min_lines`")
        )
        self.assert_drift(self.write(), "duplication.min_lines")

    def test_a_key_documented_by_two_rows_fails_as_ambiguous(self) -> None:
        self.doc = self.doc.replace(
            "| `type_debt.reference` | `null` |",
            "| `type_debt.reference` | `null` | a second row |\n"
            "| `type_debt.reference` | `null` |",
        )
        self.assert_drift(self.write(), "type_debt.reference", "ambiguous")

    def test_a_wildcard_row_whose_leaves_stop_agreeing_fails(self) -> None:
        self.defaults["lanes"]["go"]["enabled"] = False
        result = self.write()
        self.assert_drift(result, "lanes.<lane>.enabled", "lanes.go.enabled")

    def test_a_documented_undefaulted_key_that_gains_a_default_fails(self) -> None:
        self.defaults["lanes"]["python"]["collectors"] = {"cyclomatic": ["lizard"]}
        self.assert_drift(
            self.write(),
            "lanes.<lane>.collectors.<measure>",
            "lanes.python.collectors.cyclomatic",
        )

    def test_a_key_cell_that_is_not_a_code_span_fails(self) -> None:
        self.doc = self.doc.replace(
            "| `type_debt.reference` | `null` |", "| type_debt.reference | `null` |"
        )
        self.assert_drift(self.write(), "code span")


class MarkdownSignificantValueTests(GateHarness):
    """A default carrying `|`, a backtick, or a newline.

    A pipe ends a table cell even inside a code span, so a gate that compared
    a naively written cell would either mis-read the row or clear a document
    that renders broken. Each case is pinned here.
    """

    def test_a_pipe_in_a_value_must_be_escaped_and_then_passes(self) -> None:
        self.defaults["scope"]["base"] = "auto|HEAD"
        self.doc = self.doc.replace(
            "| `scope.base` | `auto` |", "| `scope.base` | `auto\\|HEAD` |"
        )
        self.assert_clean(self.write())

    def test_a_pipe_written_raw_in_the_cell_fails(self) -> None:
        self.defaults["scope"]["base"] = "auto|HEAD"
        self.doc = self.doc.replace(
            "| `scope.base` | `auto` |", "| `scope.base` | `auto|HEAD` |"
        )
        result = self.write()
        self.assert_drift(result, "scope.base", "auto\\|HEAD")

    def test_a_pipe_value_left_undocumented_fails(self) -> None:
        self.defaults["scope"]["base"] = "auto|HEAD"
        self.assert_drift(self.write(), "scope.base", "auto\\|HEAD")

    def test_a_backtick_in_a_value_needs_a_widened_fence(self) -> None:
        self.defaults["scope"]["base"] = "`HEAD`"
        self.assert_drift(self.write(), "scope.base")
        self.doc = self.doc.replace(
            "| `scope.base` | `auto` |", "| `scope.base` | `` `HEAD` `` |"
        )
        self.assert_clean(self.write())

    def test_a_newline_in_a_value_is_reported_as_unrepresentable(self) -> None:
        self.defaults["scope"]["base"] = "auto\nHEAD"
        result = self.write()
        self.assert_drift(result, "scope.base", "line break")

    def test_render_default_covers_every_shipped_value_shape(self) -> None:
        self.assertEqual(gate.render_default("change"), "`change`")
        self.assertEqual(gate.render_default(20), "`20`")
        self.assertEqual(gate.render_default(None), "`null`")
        self.assertEqual(gate.render_default(True), "`true`")
        self.assertEqual(gate.render_default([]), "`[]`")
        self.assertEqual(gate.render_default(["a", "b"]), '`["a", "b"]`')
        self.assertEqual(gate.render_default("a|b"), "`a\\|b`")
        self.assertEqual(gate.render_default("a`b"), "``a`b``")
        self.assertEqual(gate.render_default("`b`"), "`` `b` ``")
        self.assertEqual(gate.render_default("a``b"), "```a``b```")
        with self.assertRaises(gate.Unrepresentable):
            gate.render_default("a\nb")


class ToleratedTests(GateHarness):
    """What the gate deliberately does NOT fail on."""

    def test_reordering_the_defaults_file_is_not_drift(self) -> None:
        # The document orders keys for a reader and the defaults file orders
        # them for the resolver. Pinning the two orders together would fail a
        # harmless reformat while preventing no disagreement.
        self.defaults = dict(reversed(list(self.defaults.items())))
        self.defaults["size"] = dict(reversed(list(self.defaults["size"].items())))
        self.assert_clean(self.write())

    def test_reserved_members_need_no_row(self) -> None:
        # `thresholds` and any `_`-prefixed member belong to the bundled
        # defaults and the resolver's output, not to the consumer surface.
        self.defaults["_generated_at"] = "2026-01-01"
        self.defaults["thresholds"] = copy.deepcopy(self.defaults["thresholds"])
        self.defaults["thresholds"].append(
            {"measure": "invented", "config_key": "nope.nope", "value_key": "x"}
        )
        self.assert_clean(self.write())

    def test_prose_outside_the_keys_table_is_ignored(self) -> None:
        self.doc = self.doc.replace(
            "## Example",
            "## Example\n\nAn added paragraph mentioning `size.file_lines`.\n",
        )
        self.assert_clean(self.write())


class FailClosedTests(GateHarness):
    def test_a_missing_defaults_file_cannot_clear_the_gate(self) -> None:
        self.write()
        self.defaults_path.unlink()
        result = run(self.defaults_path, self.doc_path)
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn("CANNOT RUN", result.stderr)

    def test_malformed_defaults_json_cannot_clear_the_gate(self) -> None:
        self.write()
        self.defaults_path.write_text("{not json", encoding="utf-8")
        result = run(self.defaults_path, self.doc_path)
        self.assertEqual(result.returncode, 2, result.stderr)

    def test_a_document_without_the_keys_section_cannot_clear_the_gate(self) -> None:
        self.doc = self.doc.replace("## Keys", "## Configuration keys")
        result = self.write()
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn("CANNOT RUN", result.stderr)

    def test_a_keys_section_without_a_table_cannot_clear_the_gate(self) -> None:
        head, _, tail = self.doc.partition("## Keys")
        self.doc = (
            head
            + "## Keys\n\nNo table here.\n\n## Example"
            + tail.split("## Example", 1)[1]
        )
        result = self.write()
        self.assertEqual(result.returncode, 2, result.stderr)


if __name__ == "__main__":
    unittest.main()
