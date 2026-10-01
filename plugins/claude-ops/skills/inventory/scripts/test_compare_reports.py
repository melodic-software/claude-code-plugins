#!/usr/bin/env python3
"""Tests for compare_reports.py.

Run: python3 -m unittest test_compare_reports
"""

from __future__ import annotations

import contextlib
import io
import json
import pathlib
import tempfile
import unittest

import compare_reports as cr


def _report(**agent: object) -> dict:
    rec = {
        "description": "Fast search",
        "description_source": "constant",
        "disallowed_tools": ["Agent", "Edit"],
        "disallowed_tools_source": "literal",
    }
    rec.update(agent)
    return {
        "schema": 1,
        "host": {"python": "3.14.0"},
        "sources": {
            "binary": {
                "path": "/a",
                "elapsed_seconds": 1.0,
                "selected_by": "x",
                "size": 9,
            }
        },
        "builtin_agents": {"Explore": rec},
    }


def _classes(old: dict, new: dict, allow: list | None = None) -> dict[str, str]:
    result = cr.compare(old, new, allow)
    return {r["pointer"]: r["class"] for r in result["changes"]}


AGENT = "/builtin_agents/Explore"


class TestClassification(unittest.TestCase):
    def test_identical_reports_have_no_change(self) -> None:
        result = cr.compare(_report(), _report())
        self.assertEqual(result["changes"], [])
        self.assertFalse(result["failed"])

    def test_run_metadata_is_ignored(self) -> None:
        new = _report()
        new["host"] = {"python": "3.15.0"}
        new["sources"]["binary"].update(path="/b", elapsed_seconds=2.0, selected_by="y")
        self.assertEqual(cr.compare(_report(), new)["changes"], [])

    def test_metadata_keys_outside_sources_are_compared(self) -> None:
        old, new = _report(path="/a"), _report(path="/b")
        self.assertEqual(_classes(old, new), {AGENT + "/path": "value->value"})

    def test_a_concrete_value_that_changes_is_value_to_value_and_fails(self) -> None:
        result = cr.compare(_report(), _report(description="Slow search"))
        self.assertEqual(
            {r["pointer"]: r["class"] for r in result["changes"]},
            {AGENT + "/description": "value->value"},
        )
        self.assertTrue(result["failed"])

    def test_a_list_that_turns_partial_is_wrong_to_unresolved(self) -> None:
        new = _report(disallowed_tools=["Agent"], disallowed_tools_source="partial")
        result = cr.compare(_report(), new)
        self.assertEqual(
            {r["pointer"]: r["class"] for r in result["changes"]},
            {
                AGENT + "/disallowed_tools": "wrong->unresolved",
                AGENT + "/disallowed_tools_source": "wrong->unresolved",
            },
        )
        self.assertFalse(result["failed"])

    def test_a_partial_list_that_resolves_is_unresolved_to_resolved(self) -> None:
        old = _report(disallowed_tools=["Agent"], disallowed_tools_source="partial")
        new = _report(disallowed_tools=["Agent", "Edit", "Artifact"])
        self.assertEqual(set(_classes(old, new).values()), {"unresolved->resolved"})

    def test_an_ellipsis_placeholder_marks_a_string_unresolved(self) -> None:
        old = _report(description="Use … here")
        new = _report(description="Use Grep here")
        self.assertEqual(
            _classes(old, new), {AGENT + "/description": "unresolved->resolved"}
        )

    def test_an_ellipsis_element_marks_a_list_unresolved(self) -> None:
        old = _report(disallowed_tools=["…", "Agent"])
        self.assertEqual(
            _classes(old, _report()),
            {AGENT + "/disallowed_tools": "unresolved->resolved"},
        )

    def test_two_different_partial_values_are_value_to_value(self) -> None:
        old = _report(disallowed_tools=["A"], disallowed_tools_source="partial")
        new = _report(disallowed_tools=["B"], disallowed_tools_source="partial")
        self.assertEqual(
            _classes(old, new), {AGENT + "/disallowed_tools": "value->value"}
        )

    def test_an_inserted_name_is_one_change_not_a_shift(self) -> None:
        new = _report(disallowed_tools=["Agent", "Artifact", "Edit"])
        self.assertEqual(
            _classes(_report(), new), {AGENT + "/disallowed_tools": "value->value"}
        )

    def test_added_and_removed_keys(self) -> None:
        old, new = _report(), _report()
        del old["builtin_agents"]["Explore"]["description"]
        new["builtin_agents"]["Plan"] = {"tools": []}
        self.assertEqual(
            _classes(old, new),
            {
                AGENT + "/description": "added",
                "/builtin_agents/Plan": "added",
            },
        )
        self.assertEqual(
            _classes(new, old),
            {AGENT + "/description": "removed", "/builtin_agents/Plan": "removed"},
        )
        self.assertFalse(cr.compare(old, new)["failed"])

    def test_list_items_of_objects_diff_by_index(self) -> None:
        old = {"rows": [{"a": 1}, {"a": 2}]}
        new = {"rows": [{"a": 1}, {"a": 3}, {"a": 4}]}
        self.assertEqual(
            _classes(old, new), {"/rows/1/a": "value->value", "/rows/2": "added"}
        )

    def test_a_type_change_is_a_change(self) -> None:
        self.assertEqual(_classes({"n": 1}, {"n": True}), {"/n": "value->value"})

    def test_pointer_segments_are_escaped(self) -> None:
        self.assertEqual(
            _classes({"a/b~c": 1}, {"a/b~c": 2}), {"/a~1b~0c": "value->value"}
        )


class TestAllow(unittest.TestCase):
    def test_an_allowed_pointer_does_not_fail(self) -> None:
        allow = [{"pointer": AGENT + "/description", "reason": "fix 5"}]
        result = cr.compare(_report(), _report(description="Slow"), allow)
        self.assertFalse(result["failed"])
        self.assertEqual(result["changes"][0]["allowed"], "fix 5")
        self.assertEqual(result["unused_allow"], [])

    def test_an_allowed_prefix_covers_its_subtree_only(self) -> None:
        allow = [{"pointer": AGENT, "reason": "fix"}]
        self.assertFalse(
            cr.compare(_report(), _report(description="x"), allow)["failed"]
        )
        old, new = {"Explorer": 1, "Explore": 1}, {"Explorer": 2, "Explore": 1}
        allow = [{"pointer": "/Explore", "reason": "fix"}]
        self.assertTrue(cr.compare(old, new, allow)["failed"])

    def test_an_unused_allow_entry_is_reported(self) -> None:
        allow = [{"pointer": "/nowhere", "reason": "stale"}]
        self.assertEqual(
            cr.compare(_report(), _report(), allow)["unused_allow"], ["/nowhere"]
        )


class TestCli(unittest.TestCase):
    def setUp(self) -> None:
        self.dir = pathlib.Path(tempfile.mkdtemp())

    def _write(self, name: str, data: object) -> str:
        path = self.dir / name
        path.write_text(json.dumps(data), encoding="utf-8")
        return str(path)

    def _run(self, *argv: str) -> tuple[int, str, str]:
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = cr.main(list(argv))
        return code, out.getvalue(), err.getvalue()

    def test_exit_codes_and_text_output(self) -> None:
        a = self._write("a.json", _report())
        b = self._write("b.json", _report(description="Slow"))
        code, out, _ = self._run(a, a)
        self.assertEqual(code, 0)
        self.assertIn("OK: no disallowed value->value change", out)
        code, out, _ = self._run(a, b)
        self.assertEqual(code, 1)
        self.assertIn("FAIL: 1 value->value change(s) not in --allow", out)
        self.assertIn(AGENT + "/description", out)
        allow = self._write(
            "allow.json", [{"pointer": AGENT + "/description", "reason": "fix"}]
        )
        self.assertEqual(self._run(a, b, "--allow", allow)[0], 0)

    def test_json_output(self) -> None:
        a = self._write("a.json", _report())
        b = self._write("b.json", _report(description="…"))
        code, out, _ = self._run(a, b, "--json")
        self.assertEqual(code, 0)
        data = json.loads(out)
        self.assertEqual(data["counts"]["wrong->unresolved"], 1)
        self.assertEqual(data["changes"][0]["new"], "…")

    def test_bad_input_exits_2(self) -> None:
        a = self._write("a.json", _report())
        bad = self._write("bad.json", [{"pointer": "/x"}])
        self.assertEqual(self._run(a, a, "--allow", bad)[0], 2)
        self.assertEqual(self._run(a, str(self.dir / "missing.json"))[0], 2)


if __name__ == "__main__":
    unittest.main()
