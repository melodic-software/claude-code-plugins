"""Tests for question_shape.py: the one definition both servers use for a restating alternative
and a withheld recommendation.

Expected values come from the interview's written rules: an alternative never restates the
recommendation (whole-word containment either way, after case, spacing, trailing punctuation and a
(recommended) marker are folded), and a recommendation that opens `Withheld:` is no recommendation.
"""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

from question_shape import restates, withheld  # noqa: E402


class TestRestates(unittest.TestCase):
    def test_equal_text_after_folding_restates(self):
        self.assertTrue(restates("ship it now", "Ship  it now."))

    def test_an_alternative_containing_the_recommendation_restates(self):
        self.assertTrue(restates("Yes, but only for X", "Yes."))

    def test_an_alternative_contained_in_the_recommendation_restates(self):
        self.assertTrue(restates("Ship it now", "Ship it now.\nReasons follow."))

    def test_containment_is_whole_word(self):
        self.assertFalse(restates("Not yet", "No."))
        self.assertFalse(restates("now", "Not knowing"))

    def test_the_recommended_marker_is_folded_away(self):
        self.assertTrue(restates("Yes (Recommended)", "Yes. It keeps things simple."))
        self.assertFalse(restates("Later (recommended)", "Yes. It keeps things simple."))

    def test_distinct_text_does_not_restate(self):
        self.assertFalse(restates("Later", "Yes. It keeps things simple."))

    def test_empty_sides_never_restate(self):
        self.assertFalse(restates("", "Yes."))
        self.assertFalse(restates("Yes", ""))
        self.assertFalse(restates("Yes", None))

    def test_a_withheld_recommendation_has_nothing_to_restate(self):
        self.assertFalse(restates("Ship now", "Withheld: whether we ship now depends on the load test."))


class TestWithheld(unittest.TestCase):
    def test_a_recommendation_opening_withheld_is_withheld(self):
        self.assertTrue(withheld("Withheld: the DBA's row counts would settle it."))
        self.assertTrue(withheld("  Withheld: leading space is allowed"))

    def test_other_recommendations_are_not(self):
        self.assertFalse(withheld("Use Postgres. Withheld: nothing"))
        self.assertFalse(withheld("withheld: lower case is not the marker"))
        self.assertFalse(withheld(""))
        self.assertFalse(withheld(None))


if __name__ == "__main__":
    unittest.main()
