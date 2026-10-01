#!/usr/bin/env python3
"""The open wrong-value and unresolved-only findings on #5640, pinned.

Each test builds a synthetic bundle the way test_inventory.py does and
asserts what JavaScript computes. They are expected failures while the regex
reader stands; a reader fix flips one to an unexpected success, which fails
the run until its `@unittest.expectedFailure` is removed.

A wrong-value test accepts either the JavaScript result or the reader
declining to read (`partial`): an unresolved value is honest, a wrong
literal is the bug.

Run: python3 -m unittest test_reader_findings
"""

from __future__ import annotations

import unittest

import inventory as inv
from test_inventory import AGENT_SRC

# AGENT_SRC binds xt="Edit", yt="Agent".
PROBE = (
    'var SP={agentType:"spread-probe",whenToUse:"s",source:"built-in",'
    'disallowedTools:[yt,...pY],getSystemPrompt:()=>""};'
)


def _probe(prelude: str) -> dict:
    src = AGENT_SRC + prelude + PROBE
    return inv.extract_builtin_agents(src, inv.build_brace_map(src))[0]["spread-probe"]


class TestOpenFindings(unittest.TestCase):
    def assert_not_wrong(self, prelude: str, js_value: list[str]) -> None:
        rec = _probe(prelude)
        if rec["disallowed_tools_source"] != "literal":
            return
        self.assertEqual(rec["disallowed_tools"], js_value, prelude)

    @unittest.expectedFailure
    def test_finding_3_push_mutates_a_spread_array(self) -> None:
        """A `push` on the spread binding is not modelled, so the literal
        misses the pushed name.
        https://github.com/melodic-software/claude-code-plugins/issues/5640#issuecomment-5934412887
        """
        self.assert_not_wrong(
            'var pY=[xt,"Artifact"];pY.push("B");',
            ["Agent", "Edit", "Artifact", "B"],
        )

    @unittest.expectedFailure
    def test_finding_3_other_mutations_of_a_spread_array(self) -> None:
        """The other mutating shapes finding 3 names, plus a call argument
        (operator decision: any call argument counts as possible mutation)
        and a push inside a called function.
        https://github.com/melodic-software/claude-code-plugins/issues/5640#issuecomment-5934412887
        """
        for prelude, js_value in (
            (
                'var pY=[xt,"Artifact"];pY.unshift("B");',
                ["Agent", "B", "Edit", "Artifact"],
            ),
            ('var pY=[xt,"Artifact"];pY.splice(0,1);', ["Agent", "Artifact"]),
            ('var pY=[xt,"Artifact"];pY.length=0;', ["Agent"]),
            (
                'var pY=[xt,"Artifact"];function g(a){a.push("B")}g(pY);',
                ["Agent", "Edit", "Artifact", "B"],
            ),
            (
                'var pY=[xt,"Artifact"];function g(){pY.push("B")}g();',
                ["Agent", "Edit", "Artifact", "B"],
            ),
        ):
            with self.subTest(prelude=prelude):
                self.assert_not_wrong(prelude, js_value)

    @unittest.expectedFailure
    def test_finding_4_an_arrow_earlier_in_the_statement_leaves_a_spread_partial(
        self,
    ) -> None:
        """Unresolved-only: `=>` anywhere earlier in the statement counts as
        the binding sitting in an arrow body, so `...pY` stays partial though
        JavaScript has a constant list. Pinned as expected-partial today.
        https://github.com/melodic-software/claude-code-plugins/issues/5640#issuecomment-5934863409
        """
        rec = _probe('var f=()=>0,pY=[xt,"Artifact"];')
        self.assertEqual(
            (rec["disallowed_tools"], rec["disallowed_tools_source"]),
            (["Agent", "Edit", "Artifact"], "literal"),
        )

    @unittest.expectedFailure
    def test_finding_5_declaration_text_in_a_string_suppresses_a_write(self) -> None:
        """`_written_elsewhere` scans raw source for shadowing declarations,
        so `let pY` inside a string or comment hides the function's write to
        the outer `pY`.
        https://github.com/melodic-software/claude-code-plugins/issues/5640#issuecomment-5936100666
        """
        for inner in ('"let pY";', "/*let pY*/", "`let pY`;"):
            prelude = 'var pY=[xt,"Artifact"];function f(){' + inner + 'pY=["B"]}f();'
            with self.subTest(inner=inner):
                self.assert_not_wrong(prelude, ["Agent", "B"])


if __name__ == "__main__":
    unittest.main()
