#!/usr/bin/env python3
"""The open wrong-value and unresolved-only findings on #5640 in the bundle
reader of inventory.py, pinned under both readers. Naming inventory.py,
parser_reader.py and js/parser_helper.cjs here is what makes
scripts/affected-tests.sh select this suite when the reader changes.

Each test builds a synthetic bundle the way test_inventory.py does and pins
what each reader returns TODAY: the regex reader, and the parser reader
(`--reader=parser`), whose binding lookups go through acorn and
eslint-scope. A pin that is not what JavaScript computes is an open finding.
Any change to a result fails the test, naming the JavaScript result: a
reader fix lands by replacing that reader's pin with that result (or
`partial`, since declining to read is honest and a wrong literal is the
bug). An exception during extraction errors the test; it is never counted
as the known finding.

The parser half needs the pinned parser packages (`python3 parser_reader.py
--install`) and skips without them, unless INVENTORY_REQUIRE_ACORN is set,
as CI sets it, which makes it fail.

Run: python3 -m unittest test_reader_findings
"""

from __future__ import annotations

import unittest

import inventory as inv
import parser_reader as pr
from test_inventory import AGENT_SRC, _tool
from test_parser_reader import _require_live

# AGENT_SRC binds xt="Edit", yt="Agent".
PROBE = (
    'var SP={agentType:"spread-probe",whenToUse:"s",source:"built-in",'
    'disallowedTools:[yt,...pY],getSystemPrompt:()=>""};'
)
# The initializer the reader keeps when it misses a later write.
INITIAL = (["Agent", "Edit", "Artifact"], "literal")
PARTIAL = (["Agent"], "partial")


def _probe(prelude: str) -> tuple[list[str], str]:
    src = AGENT_SRC + prelude + PROBE
    rec = inv.extract_builtin_agents(src, inv.build_brace_map(src))[0]["spread-probe"]
    return rec["disallowed_tools"], rec["disallowed_tools_source"]


class TestOpenFindings(unittest.TestCase):
    reader: pr.ParserReader | None = None

    @classmethod
    def tearDownClass(cls) -> None:
        if cls.reader is not None:
            cls.reader.close()
            cls.reader = None

    def assert_pinned(
        self,
        prelude: str,
        regex: tuple[list[str], str],
        js_value: list[str],
        parser: tuple[list[str], str] | None = None,
    ) -> None:
        """`regex` and `parser` (default: the same as `regex`) are what each
        reader returns for `prelude` today. Without the parser packages the
        regex half still runs before the test skips."""
        for name, run, pinned in (
            ("regex", _probe, regex),
            ("parser", self._parsed, parser or regex),
        ):
            got = run(prelude)
            self.assertEqual(
                got,
                pinned,
                f"the {name} reader's result for {prelude!r} changed. "
                f"JavaScript gives {js_value}: if the reader now returns that or "
                "`partial`, the #5640 finding is fixed for it, so replace its pin "
                "with that result.",
            )

    def _parsed(self, prelude: str) -> tuple[list[str], str]:
        if type(self).reader is None:
            type(self).reader = pr.ParserReader(_require_live(self))
        with inv.use_reader(type(self).reader):
            return _probe(prelude)

    # Finding 3: the regex reader does not model mutation of the spread
    # array, so the literal keeps the initializer. The parser reader counts
    # a member write, a mutating method call, and (by the operator decision)
    # any call the array is passed to, so the list reads as partial: fixed
    # there.
    #
    # https://github.com/melodic-software/claude-code-plugins/issues/5640#issuecomment-5934412887

    def test_finding_3_push(self) -> None:
        self.assert_pinned(
            'var pY=[xt,"Artifact"];pY.push("B");',
            INITIAL,
            ["Agent", "Edit", "Artifact", "B"],
            parser=PARTIAL,
        )

    def test_finding_3_unshift(self) -> None:
        self.assert_pinned(
            'var pY=[xt,"Artifact"];pY.unshift("B");',
            INITIAL,
            ["Agent", "B", "Edit", "Artifact"],
            parser=PARTIAL,
        )

    def test_finding_3_splice(self) -> None:
        self.assert_pinned(
            'var pY=[xt,"Artifact"];pY.splice(0,1);',
            INITIAL,
            ["Agent", "Artifact"],
            parser=PARTIAL,
        )

    def test_finding_3_length_assignment(self) -> None:
        self.assert_pinned(
            'var pY=[xt,"Artifact"];pY.length=0;', INITIAL, ["Agent"], parser=PARTIAL
        )

    def test_finding_3_call_argument(self) -> None:
        self.assert_pinned(
            'var pY=[xt,"Artifact"];function g(a){a.push("B")}g(pY);',
            INITIAL,
            ["Agent", "Edit", "Artifact", "B"],
            parser=PARTIAL,
        )

    def test_finding_3_push_in_a_called_function(self) -> None:
        self.assert_pinned(
            'var pY=[xt,"Artifact"];function g(){pY.push("B")}g();',
            INITIAL,
            ["Agent", "Edit", "Artifact", "B"],
            parser=PARTIAL,
        )

    def test_finding_3_other_mutations(self) -> None:
        """Every other mutation shape the parser counts. Each changes the
        list in JavaScript, so a literal would be wrong. The regex reader
        reads an index write as a destructuring write (`]=`) by accident."""
        for mutation, regex in (
            ("pY[0]=xt", PARTIAL),
            ("pY[1]+=xt", INITIAL),
            ("delete pY[0]", INITIAL),
            ("[pY[0]]=[xt]", PARTIAL),
            ("for(pY[0] of[xt]);", INITIAL),
            ("pY.sort()", INITIAL),
            ('pY["reverse"]()', INITIAL),
            ("pY[k]()", INITIAL),
            ("pY?.pop()", INITIAL),
            ("Object.assign(pY,[xt])", INITIAL),
            ("new G(pY)", INITIAL),
            ("t`${pY}`", INITIAL),
        ):
            with self.subTest(mutation=mutation):
                self.assert_pinned(
                    'var pY=[xt,"Artifact"];' + mutation + ";",
                    regex,
                    ["(changed)"],
                    parser=PARTIAL,
                )

    def test_a_known_safe_read_keeps_the_literal(self) -> None:
        """The parser's only safe reads: a spread into an array or a call,
        which copies the elements, and a member read used as a value. Both
        readers keep the literal."""
        for read in (
            "pY.length",
            "x=pY[0]",
            "f(pY.length)",
            "f(...pY)",
            "var c=[...pY];c.push(xt)",
        ):
            with self.subTest(read=read):
                self.assert_pinned(
                    'var pY=[xt,"Artifact"];' + read + ";", INITIAL, INITIAL[0]
                )

    def test_an_escaping_binding_may_be_mutated_later(self) -> None:
        """Every other reference lets the array escape to code that may
        change it, so the parser reads the list as partial. These are the
        #5828 verifier's shapes plus any method call; JavaScript changes
        the list in each mutating one, so the regex reader's literal is a
        known regex gap, pinned here."""
        for shape in (
            'var q=pY;q.push("B")',
            'var q;q=pY;q.push("B")',
            'var o={};o.a=pY;o.a.push("B")',
            'var o={a:pY};o.a.push("B")',
            '[pY][0].push("B")',
            '(0,pY).push("B")',
            '(0,pY.push)("B")',
            '(pY||[]).push("B")',
            '(c?pY:pY).push("B")',
            'pY.valueOf().push("B")',
            'function r(){return pY}r().push("B")',
            'for(const e of[pY])e.push("B")',
            'var{a:q}={a:pY};q.push("B")',
            'async function g(){(await pY).push("B")}g()',
            "export{pY}",
            "pY.map(f)",
            "pY()",
        ):
            with self.subTest(shape=shape):
                self.assert_pinned(
                    'var pY=[xt,"Artifact"];' + shape + ";",
                    INITIAL,
                    ["(changed)"],
                    parser=PARTIAL,
                )

    def test_finding_4_an_arrow_earlier_in_the_statement_leaves_a_spread_partial(
        self,
    ) -> None:
        """Unresolved-only: the regex reader counts `=>` anywhere earlier in
        the statement as the binding sitting in an arrow body, so `...pY`
        stays partial though JavaScript has a constant list. The parser
        reads the declarator, which no arrow body holds: fixed there.
        https://github.com/melodic-software/claude-code-plugins/issues/5640#issuecomment-5934863409
        """
        self.assert_pinned(
            'var f=()=>0,pY=[xt,"Artifact"];',
            PARTIAL,
            INITIAL[0],
            parser=INITIAL,
        )

    def test_assignment_text_in_a_string_is_no_write(self) -> None:
        """#5825 review: the regex reader finds `pY=[` inside the string and
        reads the list as partial. The parser takes writes from the AST,
        where the string holds no reference, so the literal stands.
        https://github.com/melodic-software/claude-code-plugins/pull/5825#discussion_r4167326386
        """
        self.assert_pinned(
            'var pY=[xt,"Artifact"];var s="let pY;pY=[\\"B\\"]";',
            PARTIAL,
            INITIAL[0],
            parser=INITIAL,
        )

    # Finding 5: the regex reader's `_written_elsewhere` scans raw source for
    # shadowing declarations, so `let pY` inside quoted text hides the
    # function's write to the outer `pY`. The parser reader resolves the
    # write to the outer binding, so the list reads as partial: fixed there.

    def assert_text_shadows_only_for_regex(self, inner: str) -> None:
        prelude = 'var pY=[xt,"Artifact"];function f(){' + inner + 'pY=["B"]}f();'
        self.assert_pinned(prelude, INITIAL, ["Agent", "B"], parser=PARTIAL)

    def test_finding_5_declaration_text_in_a_string(self) -> None:
        """https://github.com/melodic-software/claude-code-plugins/issues/5640#issuecomment-5936100666"""
        self.assert_text_shadows_only_for_regex('"let pY";')

    def test_finding_5_declaration_text_in_a_comment(self) -> None:
        """https://github.com/melodic-software/claude-code-plugins/issues/5640#issuecomment-5936100666"""
        self.assert_text_shadows_only_for_regex("/*let pY*/")

    def test_finding_5_declaration_text_in_a_template(self) -> None:
        """https://github.com/melodic-software/claude-code-plugins/issues/5640#issuecomment-5936100666"""
        self.assert_text_shadows_only_for_regex("`let pY`;")

    def test_a_real_shadowing_declaration_still_shadows(self) -> None:
        """The write goes to the function's own `pY`, so the outer list is
        the initializer under both readers, as in JavaScript."""
        prelude = 'var pY=[xt,"Artifact"];function f(){let pY;pY=["B"]}f();'
        self.assert_pinned(prelude, INITIAL, INITIAL[0])

    def test_a_parameter_write_does_not_touch_the_outer_binding(self) -> None:
        """Fixed under the parser: the regex reader counts a write to a
        parameter of the same name as a write to the outer `pY`, so the
        list reads partial; JavaScript and the parser keep the literal."""
        for head in ("function g(pY){", "try{}catch(pY){", "function g({pY}){"):
            with self.subTest(head=head):
                prelude = 'var pY=[xt,"Artifact"];' + head + 'pY=["B"]}'
                self.assert_pinned(prelude, PARTIAL, INITIAL[0], parser=INITIAL)

    def test_a_nested_functions_own_parameter_does_not_reassign_the_outer(
        self,
    ) -> None:
        """Fixed under the parser: the regex reader searches the whole body
        for a write to `x`, so the nested `h`'s own `x=1` drops the bound
        argument; the parser takes the outer parameter's writes, and
        JavaScript returns `Use REAL`. A write through a closure still
        counts under both, and under the parser so does a function
        declaration named `x`, which replaces the parameter."""
        cases = (
            ("function h(x){x=1}", "Use …", "Use REAL"),
            ("function h(){x=1}", "Use …", "Use …"),
            # A function declaration of the parameter's name replaces it
            # (#5828 verifier F3); the regex reader's `Use REAL` is wrong.
            ("function x(){}", "Use REAL", "Use …"),
        )
        for nested, regex, parser in cases:
            with self.subTest(nested=nested):
                src = (
                    'var Qz="Probe";function ff(x){' + nested + "return`Use ${x}`}"
                    '$t({name:Qz,maxResultSizeChars:1,description:ff("REAL")});'
                )
                self.assertEqual(_tool(src, "Probe")["description"], regex)
                if type(self).reader is None:
                    type(self).reader = pr.ParserReader(_require_live(self))
                with inv.use_reader(type(self).reader):
                    self.assertEqual(_tool(src, "Probe")["description"], parser)

    def test_a_direct_eval_leaves_the_module_unresolved_for_the_parser(self) -> None:
        """Known parser-only unresolved case: eslint-scope marks the scopes
        around a direct `eval` dynamic and resolves nothing through them,
        and `optimistic` stays off because `eval` can rebind names. No
        module in 2.1.284-2.1.287 has one; P4 of #5640 weighs it."""
        self.assert_pinned(
            'var pY=[xt,"Artifact"];function e(){eval("")}',
            INITIAL,
            INITIAL[0],
            parser=([], "partial"),
        )

    def test_a_reader_switch_leaves_no_stale_answer(self) -> None:
        """Regex, parser, regex again on one source in one process, as
        --reader=compare runs them: each run gives its own reader's answer,
        so no cache carries one reader's result into the other's run."""
        prelude = 'var pY=[xt,"Artifact"];function f(){"let pY";pY=["B"]}f();'
        self.assertEqual(_probe(prelude), INITIAL)
        self.assertEqual(self._parsed(prelude), PARTIAL)
        self.assertEqual(_probe(prelude), INITIAL)
        self.assertEqual(self._parsed(prelude), PARTIAL)


if __name__ == "__main__":
    unittest.main()
