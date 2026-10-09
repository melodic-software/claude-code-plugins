#!/usr/bin/env python3
"""Tests for compare_reports.py.

Run: python3 -m unittest test_compare_reports
"""

from __future__ import annotations

import contextlib
import io
import json
import pathlib
import shutil
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

    def test_a_key_that_only_starts_with_sources_is_compared(self) -> None:
        old, new = _report(), _report()
        old["sources_summary"] = {"path": "/a", "elapsed_seconds": 1.0}
        new["sources_summary"] = {"path": "/b", "elapsed_seconds": 2.0}
        self.assertEqual(
            _classes(old, new),
            {
                "/sources_summary/path": "value->value",
                "/sources_summary/elapsed_seconds": "value->value",
            },
        )

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
        old, new = {"names": ["…", "Agent"]}, {"names": ["Agent", "Edit"]}
        self.assertEqual(_classes(old, new), {"/names": "unresolved->resolved"})

    def test_a_literal_value_holding_an_ellipsis_is_resolved(self) -> None:
        # The source says the text was read as written, so `…` is a
        # character in it, not the reader's placeholder (#5754 review).
        old = _report(description="Wait…", description_source="literal")
        new = _report(description="Wait!", description_source="literal")
        result = cr.compare(old, new)
        self.assertEqual(
            {r["pointer"]: r["class"] for r in result["changes"]},
            {AGENT + "/description": "value->value"},
        )
        self.assertTrue(result["failed"])
        old = _report(description="More…", description_source="frontmatter")
        new = _report(description="Less", description_source="frontmatter")
        self.assertEqual(_classes(old, new), {AGENT + "/description": "value->value"})

    def test_a_constant_holding_an_ellipsis_stays_unresolved(self) -> None:
        # A constant can carry a template substitution, so its `…` is still
        # the placeholder.
        old = _report(description="Use … here", description_source="constant")
        self.assertEqual(
            _classes(old, _report(description="Use Grep here")),
            {AGENT + "/description": "unresolved->resolved"},
        )

    def test_an_element_holding_an_ellipsis_marks_a_list_unresolved(self) -> None:
        old = {"description_variants": ["Use … here", "Short"]}
        new = {"description_variants": ["Use Grep here", "Short"]}
        self.assertEqual(
            _classes(old, new), {"/description_variants": "unresolved->resolved"}
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

    def test_a_type_change_inside_a_scalar_list_is_a_change(self) -> None:
        # Python has [1] == [True] and [0] == [0.0]; JSON does not.
        self.assertEqual(_classes({"n": [1]}, {"n": [True]}), {"/n": "value->value"})
        self.assertEqual(_classes({"n": [0]}, {"n": [0.0]}), {"/n": "value->value"})
        self.assertEqual(_classes({"n": [1, "a"]}, {"n": [1, "a"]}), {})

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

    def test_allow_pointers_keep_rfc_6901_meaning(self) -> None:
        old, new = {"a": {"": 1, "b": 1}}, {"a": {"": 2, "b": 2}}
        result = cr.compare(old, new, [{"pointer": "/a/", "reason": "empty key"}])
        self.assertEqual(
            {r["pointer"]: "allowed" in r for r in result["changes"]},
            {"/a/": True, "/a/b": False},
        )
        result = cr.compare(old, new, [{"pointer": "/", "reason": "not all"}])
        self.assertEqual(result["disallowed"], 2)
        self.assertEqual(result["unused_allow"], ["/"])

    def test_a_narrower_entry_under_a_broader_one_is_used(self) -> None:
        allow = [
            {"pointer": AGENT, "reason": "broad"},
            {"pointer": AGENT + "/description", "reason": "narrow"},
        ]
        result = cr.compare(_report(), _report(description="x"), allow)
        self.assertFalse(result["failed"])
        self.assertEqual(result["unused_allow"], [])

    def test_an_unused_allow_entry_is_reported(self) -> None:
        allow = [{"pointer": "/nowhere", "reason": "stale"}]
        self.assertEqual(
            cr.compare(_report(), _report(), allow)["unused_allow"], ["/nowhere"]
        )


class TestCli(unittest.TestCase):
    def setUp(self) -> None:
        self.dir = pathlib.Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.dir, True)

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
