#!/usr/bin/env python3
"""Deterministic tests for the inventory extractor.

Every case runs against a synthetic minified fragment rather than a real
Claude Code build, so the suite is fast, hermetic, and does not change its
verdict when the installed CLI updates. The fragments reproduce the shapes
observed in a real bundle, including the ones that broke earlier drafts.

Run: python3 test_inventory.py
"""

from __future__ import annotations

import unittest

import inventory as inv


class TestBraceMap(unittest.TestCase):
    def test_matches_simple_pairs(self) -> None:
        bm = inv.build_brace_map("a={b:{c:1}}")
        self.assertEqual(len(bm.pairs), 2)

    def test_ignores_braces_inside_strings(self) -> None:
        bm = inv.build_brace_map('x={a:"}{"}')
        self.assertEqual(len(bm.pairs), 1)

    def test_ignores_braces_inside_regex(self) -> None:
        # A regex literal containing an unbalanced brace would desync a naive
        # counter and mis-attribute every object after it.
        bm = inv.build_brace_map("x={a:/[{]/g}")
        self.assertEqual(len(bm.pairs), 1)

    def test_ignores_braces_inside_template(self) -> None:
        bm = inv.build_brace_map("x={a:`v${b}`}")
        self.assertEqual(len(bm.pairs), 1)

    def test_division_is_not_a_regex(self) -> None:
        # `a/b` followed by `{` must not swallow the object as a regex body.
        bm = inv.build_brace_map("y=a/b;x={c:1}")
        self.assertEqual(len(bm.pairs), 1)

    def test_enclosing_finds_innermost(self) -> None:
        src = "x={outer:{inner:1}}"
        bm = inv.build_brace_map(src)
        pos = src.index("inner")
        enc = bm.enclosing(pos)
        self.assertIsNotNone(enc)
        assert enc is not None
        self.assertEqual(src[enc[0] : enc[1] + 1], "{inner:1}")


class TestCommandExtraction(unittest.TestCase):
    # Two command literals packed flush together, as the real bundle packs
    # them. A fixed-width text window around the first would capture the
    # second's description; brace depth is what keeps them apart.
    ADJACENT = (
        'var a={type:"local-jsx",name:"artifacts",aliases:[],'
        'description:"Browse your published and shared artifacts",isEnabled:()=>Z9()},'
        'b={type:"local-jsx",name:"btw",description:"Ask a quick side question"};'
    )

    def _extract(self, src: str) -> dict:
        return inv.extract_builtin_commands(src, inv.build_brace_map(src))

    def test_adjacent_literals_do_not_bleed(self) -> None:
        got = self._extract(self.ADJACENT)
        self.assertEqual(
            got["artifacts"]["description"], "Browse your published and shared artifacts"
        )
        self.assertEqual(got["btw"]["description"], "Ask a quick side question")

    def test_gated_and_hidden_flags(self) -> None:
        got = self._extract(self.ADJACENT)
        self.assertTrue(got["artifacts"]["gated"])
        self.assertFalse(got["artifacts"]["hidden"])
        src = 'x={type:"local",name:"heapdump",description:"d",get isHidden(){return!0}};'
        self.assertTrue(self._extract(src)["heapdump"]["hidden"])

    def test_aliases_are_collected(self) -> None:
        src = (
            'x={type:"local-jsx",name:"usage",aliases:["cost","stats"],'
            'description:"Show session cost"};'
        )
        self.assertEqual(self._extract(src)["usage"]["aliases"], ["cost", "stats"])

    def test_shell_builtin_is_not_a_command(self) -> None:
        # `alias` and `todos` carry a name but no `type:` - both were wrongly
        # reported as slash commands by an earlier regex-only pass.
        src = (
            '{name:"alias",description:"Create or list command aliases",'
            'args:{name:"definition"}}'
        )
        self.assertEqual(self._extract(src), {})

    def test_userfacingname_is_a_fallback(self) -> None:
        src = 'x={type:"local-jsx",userFacingName(){return"autofix-pr"},description:"d"};'
        self.assertIn("autofix-pr", self._extract(src))

    def test_internal_names_are_marked(self) -> None:
        src = 'x={type:"prompt",name:"mcp__",description:"d"};'
        self.assertTrue(self._extract(src)["mcp__"]["internal"])


class TestBundledSkills(unittest.TestCase):
    BUNDLE = (
        'pt(Q,{registerBundledSkill:()=>xu,getBundledSkills:()=>dF});'
        'var gme="code-review",lFo="dataviz";'
        'xu({name:gme,aliases:["review"],menuDescription:"Review the current diff"});'
        'xu({name:lFo,menuDescription:"Chart and dashboard design guidance"});'
        'xu({name:"doctor",aliases:["checkup"],menuDescription:"Health-check your setup"});'
    )

    def test_registrar_is_discovered_not_hardcoded(self) -> None:
        self.assertEqual(inv.discover_registrar(self.BUNDLE, "registerBundledSkill"), "xu")

    def test_missing_export_returns_none(self) -> None:
        self.assertIsNone(inv.discover_registrar("var x=1;", "registerBundledSkill"))

    def test_constant_names_resolve(self) -> None:
        # The failure this guards: a literal-only scan silently drops roughly a
        # third of the bundled skills, including code-review and dataviz.
        skills, notes = inv.extract_bundled_skills(self.BUNDLE)
        self.assertEqual(notes["registrar"], "xu")
        self.assertIn("code-review", skills)
        self.assertIn("dataviz", skills)
        self.assertIn("doctor", skills)
        self.assertEqual(skills["code-review"]["aliases"], ["review"])

    def test_ambiguous_constant_is_not_resolved(self) -> None:
        # An identifier bound to two different strings cannot be resolved
        # safely, so it must be reported rather than guessed.
        src = self.BUNDLE + 'var zz="a-one";var zz="a-two";xu({name:zz});'
        _, notes = inv.extract_bundled_skills(src)
        self.assertGreater(notes["registrations_seen"], notes["resolved"])


class TestIntegrity(unittest.TestCase):
    def _src(self, extra: str = "") -> str:
        return (
            'pt(Q,{registerBundledSkill:()=>xu});'
            + "".join(f'x{i}={{type:"local",name:"{n}",description:"d"}};'
                      for i, n in enumerate(inv.CANARY_COMMANDS))
            + extra
        )

    def _commands(self, src: str) -> dict:
        return inv.extract_builtin_commands(src, inv.build_brace_map(src))

    def test_ok_when_everything_resolves(self) -> None:
        src = self._src()
        got = inv.check_integrity(
            src, self._commands(src), {"a": {}}, {"registrations_seen": 1, "resolved": 1}
        )
        self.assertEqual(got["status"], "ok")

    def test_broken_when_canary_missing(self) -> None:
        src = 'x={type:"local",name:"help",description:"d"};'
        got = inv.check_integrity(src, self._commands(src), {"a": {}}, {})
        self.assertEqual(got["status"], "broken")
        self.assertTrue(any("canary" in p for p in got["problems"]))

    def test_broken_when_no_skills_resolve(self) -> None:
        src = self._src()
        got = inv.check_integrity(src, self._commands(src), {}, {})
        self.assertEqual(got["status"], "broken")

    def test_degraded_on_unknown_registrar(self) -> None:
        # The silent-drift signal: a registration path the script does not know.
        src = self._src("pt(Q,{registerSomethingNewSkill:()=>zz});")
        got = inv.check_integrity(
            src, self._commands(src), {"a": {}}, {"registrations_seen": 1, "resolved": 1}
        )
        self.assertEqual(got["status"], "degraded")
        self.assertTrue(any("registerSomethingNewSkill" in a for a in got["advisories"]))

    def test_degraded_when_registrations_exceed_resolved(self) -> None:
        src = self._src()
        got = inv.check_integrity(
            src, self._commands(src), {"a": {}}, {"registrations_seen": 5, "resolved": 3}
        )
        self.assertEqual(got["status"], "degraded")
        self.assertTrue(any("floor" in a for a in got["advisories"]))

    def test_low_yield_is_broken(self) -> None:
        # Many registration tokens present but few commands resolved means the
        # brace reader stopped working - the exact shape of a quiet shortfall.
        src = self._src() + 'type:"local"' * 200
        got = inv.check_integrity(
            src, self._commands(src), {"a": {}}, {"registrations_seen": 1, "resolved": 1}
        )
        self.assertEqual(got["status"], "broken")


class TestContainerAndVersion(unittest.TestCase):
    def test_detects_containers(self) -> None:
        self.assertEqual(inv.detect_container(b"MZ\x90\x00"), "PE")
        self.assertEqual(inv.detect_container(b"\x7fELF\x02"), "ELF")
        self.assertEqual(inv.detect_container(b"\xcf\xfa\xed\xfe"), "Mach-O")
        self.assertEqual(inv.detect_container(b"nope"), "unknown")

    def test_version_needs_repetition(self) -> None:
        # One mention is a dependency's version, not the build's.
        self.assertIsNone(inv.detect_cli_version('"9.9.9"'))
        self.assertEqual(inv.detect_cli_version('"2.1.228"' * 30), "2.1.228")


class TestPluginBacked(unittest.TestCase):
    def test_finds_plugin_name(self) -> None:
        src = (
            'x={name:"security-review",description:"Complete a security review",'
            'pluginName:"security-review",pluginCommand:"security-review"};'
        )
        self.assertEqual(inv.extract_plugin_backed(src), {"security-review": "security-review"})


if __name__ == "__main__":
    unittest.main(verbosity=2)
