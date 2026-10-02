#!/usr/bin/env python3
"""The open wrong-value and unresolved-only findings on #5640 in the bundle
reader of inventory.py, pinned. Naming inventory.py here is what makes
scripts/affected-tests.sh select this suite when the reader changes.

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

    # Finding 3: mutation of the spread array is not modelled, so the literal
    # keeps the initializer. The call-argument case follows the operator
    # decision that any call argument counts as possible mutation.

    @unittest.expectedFailure
    def test_finding_3_push(self) -> None:
        """https://github.com/melodic-software/claude-code-plugins/issues/5640#issuecomment-5934412887"""
        self.assert_not_wrong(
            'var pY=[xt,"Artifact"];pY.push("B");', ["Agent", "Edit", "Artifact", "B"]
        )

    @unittest.expectedFailure
    def test_finding_3_unshift(self) -> None:
        """https://github.com/melodic-software/claude-code-plugins/issues/5640#issuecomment-5934412887"""
        self.assert_not_wrong(
            'var pY=[xt,"Artifact"];pY.unshift("B");',
            ["Agent", "B", "Edit", "Artifact"],
        )

    @unittest.expectedFailure
    def test_finding_3_splice(self) -> None:
        """https://github.com/melodic-software/claude-code-plugins/issues/5640#issuecomment-5934412887"""
        self.assert_not_wrong(
            'var pY=[xt,"Artifact"];pY.splice(0,1);', ["Agent", "Artifact"]
        )

    @unittest.expectedFailure
    def test_finding_3_length_assignment(self) -> None:
        """https://github.com/melodic-software/claude-code-plugins/issues/5640#issuecomment-5934412887"""
        self.assert_not_wrong('var pY=[xt,"Artifact"];pY.length=0;', ["Agent"])

    @unittest.expectedFailure
    def test_finding_3_call_argument(self) -> None:
        """https://github.com/melodic-software/claude-code-plugins/issues/5640#issuecomment-5934412887"""
        self.assert_not_wrong(
            'var pY=[xt,"Artifact"];function g(a){a.push("B")}g(pY);',
            ["Agent", "Edit", "Artifact", "B"],
        )

    @unittest.expectedFailure
    def test_finding_3_push_in_a_called_function(self) -> None:
        """https://github.com/melodic-software/claude-code-plugins/issues/5640#issuecomment-5934412887"""
        self.assert_not_wrong(
            'var pY=[xt,"Artifact"];function g(){pY.push("B")}g();',
            ["Agent", "Edit", "Artifact", "B"],
        )

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

    # Finding 5: `_written_elsewhere` scans raw source for shadowing
    # declarations, so `let pY` inside quoted text hides the function's write
    # to the outer `pY`.

    def assert_text_does_not_shadow(self, inner: str) -> None:
        prelude = 'var pY=[xt,"Artifact"];function f(){' + inner + 'pY=["B"]}f();'
        self.assert_not_wrong(prelude, ["Agent", "B"])

    @unittest.expectedFailure
    def test_finding_5_declaration_text_in_a_string(self) -> None:
        """https://github.com/melodic-software/claude-code-plugins/issues/5640#issuecomment-5936100666"""
        self.assert_text_does_not_shadow('"let pY";')

    @unittest.expectedFailure
    def test_finding_5_declaration_text_in_a_comment(self) -> None:
        """https://github.com/melodic-software/claude-code-plugins/issues/5640#issuecomment-5936100666"""
        self.assert_text_does_not_shadow("/*let pY*/")

    @unittest.expectedFailure
    def test_finding_5_declaration_text_in_a_template(self) -> None:
        """https://github.com/melodic-software/claude-code-plugins/issues/5640#issuecomment-5936100666"""
        self.assert_text_does_not_shadow("`let pY`;")


if __name__ == "__main__":
    unittest.main()
