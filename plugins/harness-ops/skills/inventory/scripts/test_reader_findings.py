#!/usr/bin/env python3
"""The open wrong-value and unresolved-only findings on #5640 in the bundle
reader of inventory.py, pinned. Naming inventory.py here is what makes
scripts/affected-tests.sh select this suite when the reader changes.

Each test builds a synthetic bundle the way test_inventory.py does and pins
what the regex reader returns TODAY, which is not what JavaScript computes.
Any change to that result fails the test, naming the JavaScript result: a
reader fix lands by replacing the pin with that result (or `partial`, since
declining to read is honest and a wrong literal is the bug). An exception
during extraction errors the test; it is never counted as the known finding.

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
# The initializer the reader keeps when it misses a later write.
INITIAL = (["Agent", "Edit", "Artifact"], "literal")


def _probe(prelude: str) -> tuple[list[str], str]:
    src = AGENT_SRC + prelude + PROBE
    rec = inv.extract_builtin_agents(src, inv.build_brace_map(src))[0]["spread-probe"]
    return rec["disallowed_tools"], rec["disallowed_tools_source"]


class TestOpenFindings(unittest.TestCase):
    def assert_still_open(
        self, prelude: str, today: tuple[list[str], str], js_value: list[str]
    ) -> None:
        self.assertEqual(
            _probe(prelude),
            today,
            f"the reader's result for {prelude!r} changed. JavaScript gives "
            f"{js_value}: if the reader now returns that or `partial`, the "
            "#5640 finding is fixed, so replace this pin with that result.",
        )

    # Finding 3: mutation of the spread array is not modeled, so the literal
    # keeps the initializer. The call-argument case follows the operator
    # decision that any call argument counts as possible mutation.

    def test_finding_3_push(self) -> None:
        """https://github.com/melodic-software/claude-code-plugins/issues/5640#issuecomment-5934412887"""
        self.assert_still_open(
            'var pY=[xt,"Artifact"];pY.push("B");',
            INITIAL,
            ["Agent", "Edit", "Artifact", "B"],
        )

    def test_finding_3_unshift(self) -> None:
        """https://github.com/melodic-software/claude-code-plugins/issues/5640#issuecomment-5934412887"""
        self.assert_still_open(
            'var pY=[xt,"Artifact"];pY.unshift("B");',
            INITIAL,
            ["Agent", "B", "Edit", "Artifact"],
        )

    def test_finding_3_splice(self) -> None:
        """https://github.com/melodic-software/claude-code-plugins/issues/5640#issuecomment-5934412887"""
        self.assert_still_open(
            'var pY=[xt,"Artifact"];pY.splice(0,1);', INITIAL, ["Agent", "Artifact"]
        )

    def test_finding_3_length_assignment(self) -> None:
        """https://github.com/melodic-software/claude-code-plugins/issues/5640#issuecomment-5934412887"""
        self.assert_still_open(
            'var pY=[xt,"Artifact"];pY.length=0;', INITIAL, ["Agent"]
        )

    def test_finding_3_call_argument(self) -> None:
        """https://github.com/melodic-software/claude-code-plugins/issues/5640#issuecomment-5934412887"""
        self.assert_still_open(
            'var pY=[xt,"Artifact"];function g(a){a.push("B")}g(pY);',
            INITIAL,
            ["Agent", "Edit", "Artifact", "B"],
        )

    def test_finding_3_push_in_a_called_function(self) -> None:
        """https://github.com/melodic-software/claude-code-plugins/issues/5640#issuecomment-5934412887"""
        self.assert_still_open(
            'var pY=[xt,"Artifact"];function g(){pY.push("B")}g();',
            INITIAL,
            ["Agent", "Edit", "Artifact", "B"],
        )

    def test_finding_4_an_arrow_earlier_in_the_statement_leaves_a_spread_partial(
        self,
    ) -> None:
        """Unresolved-only: `=>` anywhere earlier in the statement counts as
        the binding sitting in an arrow body, so `...pY` stays partial though
        JavaScript has a constant list; the fix reads it as a literal.
        https://github.com/melodic-software/claude-code-plugins/issues/5640#issuecomment-5934863409
        """
        self.assert_still_open(
            'var f=()=>0,pY=[xt,"Artifact"];',
            (["Agent"], "partial"),
            ["Agent", "Edit", "Artifact"],
        )

    # Finding 5: `_written_elsewhere` scans raw source for shadowing
    # declarations, so `let pY` inside quoted text hides the function's write
    # to the outer `pY`.

    def assert_text_still_shadows(self, inner: str) -> None:
        prelude = 'var pY=[xt,"Artifact"];function f(){' + inner + 'pY=["B"]}f();'
        self.assert_still_open(prelude, INITIAL, ["Agent", "B"])

    def test_finding_5_declaration_text_in_a_string(self) -> None:
        """https://github.com/melodic-software/claude-code-plugins/issues/5640#issuecomment-5936100666"""
        self.assert_text_still_shadows('"let pY";')

    def test_finding_5_declaration_text_in_a_comment(self) -> None:
        """https://github.com/melodic-software/claude-code-plugins/issues/5640#issuecomment-5936100666"""
        self.assert_text_still_shadows("/*let pY*/")

    def test_finding_5_declaration_text_in_a_template(self) -> None:
        """https://github.com/melodic-software/claude-code-plugins/issues/5640#issuecomment-5936100666"""
        self.assert_text_still_shadows("`let pY`;")


if __name__ == "__main__":
    unittest.main()
