from __future__ import annotations

import pathlib
import sys
import unittest
from collections import OrderedDict

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import babysit_util as util


class IsJsonObjectTests(unittest.TestCase):
    def test_accepts_an_object_including_an_empty_one(self) -> None:
        self.assertTrue(util.is_json_object({}))
        self.assertTrue(util.is_json_object({"a": 1}))

    def test_accepts_a_dict_subclass(self) -> None:
        self.assertTrue(util.is_json_object(OrderedDict(a=1)))

    def test_rejects_every_other_json_shape(self) -> None:
        for value in ([], [{"a": 1}], "a", 0, 1, 1.5, True, False, None):
            with self.subTest(value=value):
                self.assertFalse(util.is_json_object(value))

    def test_does_not_inspect_keys(self) -> None:
        self.assertTrue(util.is_json_object({1: "a"}))


class IsJsonArrayTests(unittest.TestCase):
    def test_accepts_an_array_including_an_empty_one(self) -> None:
        self.assertTrue(util.is_json_array([]))
        self.assertTrue(util.is_json_array([1, 2]))

    def test_rejects_every_other_json_shape(self) -> None:
        for value in ({}, {"a": 1}, "ab", (1, 2), 0, 1, True, False, None):
            with self.subTest(value=value):
                self.assertFalse(util.is_json_array(value))

    def test_does_not_inspect_elements(self) -> None:
        self.assertTrue(util.is_json_array([None, {"a": 1}, "x"]))


class DigTests(unittest.TestCase):
    def test_walks_nested_objects(self) -> None:
        payload = {"a": {"b": {"c": 7}}}
        self.assertEqual(util.dig(payload, "a", "b", "c"), 7)
        self.assertEqual(util.dig(payload, "a", "b"), {"c": 7})

    def test_no_keys_returns_the_value_untouched(self) -> None:
        self.assertEqual(util.dig({"a": 1}), {"a": 1})
        self.assertIsNone(util.dig(None))

    def test_missing_key_is_none(self) -> None:
        self.assertIsNone(util.dig({"a": {"b": 1}}, "a", "zz"))

    def test_a_non_object_level_stops_the_walk(self) -> None:
        self.assertIsNone(util.dig({"a": [{"b": 1}]}, "a", "b"))
        self.assertIsNone(util.dig({"a": "text"}, "a", "b"))
        self.assertIsNone(util.dig(None, "a"))

    def test_a_null_level_stops_the_walk(self) -> None:
        self.assertIsNone(util.dig({"a": None}, "a", "b"))


if __name__ == "__main__":
    unittest.main()
