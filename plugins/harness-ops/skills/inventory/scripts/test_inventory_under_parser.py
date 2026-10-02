#!/usr/bin/env python3
"""Every test_inventory.py case again, with inventory.py's binding lookups
answered by the parser reader (parser_reader.py driving
js/parser_helper.cjs) instead of the regex reader. Naming those three files
here is what makes scripts/affected-tests.sh select this suite when any of
them changes.

Each test_inventory TestCase gets a subclass here whose class setup turns the
parser on for its tests and whose teardown turns it off, so the same
assertions hold under both readers. One helper process serves the module.

Needs the pinned parser packages (`python3 parser_reader.py --install`) and
skips without them, unless INVENTORY_REQUIRE_ACORN is set, as CI sets it,
which makes it fail.

Run: python3 -m unittest test_inventory_under_parser
"""

from __future__ import annotations

import contextlib
import unittest

import inventory as inv
import parser_reader as pr
import test_inventory
from test_parser_reader import _require_live

_reader: list[pr.ParserReader] = []


class _UnderParser(unittest.TestCase):
    _switch: contextlib.ExitStack

    @classmethod
    def setUpClass(cls) -> None:
        if not _reader:
            _reader.append(pr.ParserReader(_require_live(cls("run"))))
        super().setUpClass()
        cls._switch = contextlib.ExitStack()
        cls._switch.enter_context(inv.use_reader(_reader[0]))

    @classmethod
    def tearDownClass(cls) -> None:
        cls._switch.close()
        super().tearDownClass()


class TestTheParserAnswers(_UnderParser):
    def test_binding_lookups_go_to_the_parser(self) -> None:
        self.assertIs(inv._PARSER, _reader[0])


def tearDownModule() -> None:
    while _reader:
        _reader.pop().close()


globals().update(
    (name, type(name, (_UnderParser, case), {"__module__": __name__}))
    for name, case in vars(test_inventory).items()
    if isinstance(case, type) and issubclass(case, unittest.TestCase)
)


if __name__ == "__main__":
    unittest.main()
