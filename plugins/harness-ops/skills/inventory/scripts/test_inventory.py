#!/usr/bin/env python3
"""Deterministic tests for the inventory extractor.

Every case runs against a synthetic minified fragment rather than a real
Claude Code build, so the suite is fast, hermetic, and does not change its
verdict when the installed CLI updates. The fragments reproduce the shapes
observed in a real bundle, including the ones that broke earlier drafts.

Run: python3 test_inventory.py
"""

from __future__ import annotations

import json
import os
import pathlib
import tempfile
import unittest
from unittest import mock

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
        # counter and misattribute every object after it.
        bm = inv.build_brace_map("x={a:/[{]/g}")
        self.assertEqual(len(bm.pairs), 1)

    def test_ignores_braces_inside_template(self) -> None:
        bm = inv.build_brace_map("x={a:`v${b}`}")
        self.assertEqual(len(bm.pairs), 1)

    def test_regex_inside_a_template_substitution_does_not_desync(self) -> None:
        # 2.1.284: `\`prints ${to(fn.replace(/^(["'])(.*)\1$/,"$2"))}\`` - a
        # substitution holding a regex with quote characters. Skipping the
        # substitution as quoted text swallowed 21 MB into one brace pair and
        # left /clear, /help, and most commands unresolved.
        src = (
            'if(a){x=`p ${f(/^(["\'])(.*)\\1$/,"$2")}`}'
            'var c={type:"local",name:"clear"};'
        )
        bm = inv.build_brace_map(src)
        enc = bm.enclosing(src.index('name:"clear"'))
        assert enc is not None
        self.assertEqual(src[enc[0] : enc[1] + 1], '{type:"local",name:"clear"}')

    def test_object_literal_inside_a_template_substitution_is_paired(self) -> None:
        bm = inv.build_brace_map("x=`a ${f({k:`b ${c}`})} d`;y={e:1}")
        self.assertEqual(len(bm.pairs), 2)

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
            got["artifacts"]["description"],
            "Browse your published and shared artifacts",
        )
        self.assertEqual(got["btw"]["description"], "Ask a quick side question")

    def test_gated_and_hidden_flags(self) -> None:
        got = self._extract(self.ADJACENT)
        self.assertTrue(got["artifacts"]["gated"])
        self.assertFalse(got["artifacts"]["hidden"])
        src = (
            'x={type:"local",name:"heapdump",description:"d",get isHidden(){return!0}};'
        )
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
            'x={name:"alias",description:"Create or list command aliases",'
            'args:{name:"definition"}}'
        )
        self.assertEqual(self._extract(src), {})

    def test_userfacingname_is_a_fallback(self) -> None:
        src = (
            'x={type:"local-jsx",userFacingName(){return"autofix-pr"},description:"d"};'
        )
        self.assertIn("autofix-pr", self._extract(src))

    def test_hoisted_constant_name_resolves(self) -> None:
        src = (
            'var EMr="commit-push-pr";'
            'var pGo={type:"prompt",name:EMr,description:"Commit, push, and open a PR"};'
        )
        self.assertEqual(
            self._extract(src)["commit-push-pr"]["description"],
            "Commit, push, and open a PR",
        )

    def test_factory_parameter_name_is_not_resolved(self) -> None:
        # `name:e` in a factory is whatever the caller passes, never the
        # nearest `e="..."` in scope.
        src = 'var e="wrong";function t1t(e,n){return{type:"local-jsx",name:e,description:n}}'
        self.assertEqual(self._extract(src), {})

    def test_a_name_bound_to_a_conditional_is_not_resolved(self) -> None:
        # The 2.1.286 skill loader: `Vt` is bound to a conditional in the
        # loader's own scope, so an unrelated `Vt="string"` far ahead is not
        # what the literal reads.
        src = (
            'var Vt="string";'
            + "z" * 5000
            + ";"
            + 'function ld(e,xe){let $t=xe==="syncedSkills",Vt=$t?smt(e):e,'
            'Jt={type:"prompt",name:Vt,description:"d"};return Jt}'
        )
        self.assertEqual(self._extract(src), {})

    def test_a_name_bound_to_a_call_is_not_resolved(self) -> None:
        src = (
            'var Vt="string";function ld(e){let Vt=smt(e);'
            'return{type:"prompt",name:Vt,description:"d"}}'
        )
        self.assertEqual(self._extract(src), {})

    def test_a_constant_in_another_module_is_not_resolved(self) -> None:
        src = _modules(
            'var Vt="string";',
            'var x={type:"prompt",name:Vt,description:"d"};',
        )
        self.assertEqual(self._extract(src), {})

    def test_a_constant_in_scope_or_imported_resolves(self) -> None:
        local = (
            'var Vt="string";function ld(){let Vt="review";'
            'return{type:"prompt",name:Vt,description:"d"}}'
        )
        self.assertEqual(list(self._extract(local)), ["review"])
        imported = _modules(
            'var Vt="review";export{Vt};',
            'import{Vt}from"/$bunfs/root/chunk-a.js";'
            'var x={type:"prompt",name:Vt,description:"d"};',
        )
        self.assertEqual(list(self._extract(imported)), ["review"])

    def test_internal_names_are_marked(self) -> None:
        src = 'x={type:"prompt",name:"mcp__",description:"d"};'
        self.assertTrue(self._extract(src)["mcp__"]["internal"])


class TestBundledSkills(unittest.TestCase):
    BUNDLE = (
        "pt(Q,{registerBundledSkill:()=>xu,getBundledSkills:()=>dF});"
        'var gme="code-review",dvz="dataviz";'
        'xu({name:gme,aliases:["review"],menuDescription:"Review the current diff"});'
        'xu({name:dvz,menuDescription:"Chart and dashboard design guidance"});'
        'xu({name:"doctor",aliases:["checkup"],menuDescription:"Health-check your setup"});'
    )

    def test_registrar_is_discovered_not_hardcoded(self) -> None:
        self.assertEqual(
            inv.discover_registrar(self.BUNDLE, "registerBundledSkill"), "xu"
        )

    def test_missing_export_returns_none(self) -> None:
        self.assertIsNone(inv.discover_registrar("var x=1;", "registerBundledSkill"))

    def test_constant_names_resolve(self) -> None:
        # The failure this guards: a literal-only scan silently drops roughly a
        # third of the bundled skills, including code-review and dataviz.
        skills, notes = inv.extract_bundled_skills(
            self.BUNDLE, inv.build_brace_map(self.BUNDLE)
        )
        self.assertEqual(notes["registrar"], "xu")
        self.assertIn("code-review", skills)
        self.assertIn("dataviz", skills)
        self.assertIn("doctor", skills)
        self.assertEqual(skills["code-review"]["aliases"], ["review"])

    def test_a_rebound_constant_resolves_to_its_nearest_binding(self) -> None:
        # An identifier bound to two different strings resolves by locality:
        # the binding nearest before the registration is the one in scope.
        src = self.BUNDLE + 'var zz="a-one";var zz="a-two";xu({name:zz});'
        skills, notes = inv.extract_bundled_skills(src, inv.build_brace_map(src))
        self.assertIn("a-two", skills)
        self.assertNotIn("a-one", skills)
        self.assertEqual(notes["registrations_seen"], notes["resolved"])


class TestIntegrity(unittest.TestCase):
    def _src(self, extra: str = "") -> str:
        # The version literal has to repeat: detect_cli_version deliberately
        # ignores a version mentioned only once, since that is a dependency's
        # version rather than the build's.
        return (
            "pt(Q,{registerBundledSkill:()=>xu});"
            + f'"{inv.VALIDATED_AGAINST}";' * 30
            + "".join(
                f'x{i}={{type:"local",name:"{n}",description:"d"}};'
                for i, n in enumerate(inv.CANARY_COMMANDS)
            )
            + extra
        )

    def _commands(self, src: str) -> dict:
        return inv.extract_builtin_commands(src, inv.build_brace_map(src))

    def test_ok_when_everything_resolves(self) -> None:
        src = self._src()
        got = inv.check_integrity(
            src,
            self._commands(src),
            {"a": {}},
            {"registrations_seen": 1, "resolved": 1},
        )
        self.assertEqual(got["status"], "ok")

    def test_canary_missing_breaks_the_builtin_lane_only(self) -> None:
        # One rule for one state: a broken lane beside a healthy one is a
        # degraded run whose advisory names the lane, never a broken run that
        # voids the healthy lane's counts.
        src = (
            'x={type:"local",name:"help",description:"d"};'
            + f'"{inv.VALIDATED_AGAINST}";' * 30
        )
        got = inv.check_integrity(
            src,
            self._commands(src),
            {"a": {}},
            {},
            {"security-review": "security-review"},
        )
        self.assertEqual(got["lanes"]["builtin_commands"]["status"], "broken")
        self.assertEqual(got["lanes"]["bundled_skills"]["status"], "ok")
        self.assertEqual(got["lanes"]["plugin_backed"]["status"], "ok")
        self.assertEqual(got["status"], "degraded")
        self.assertEqual(got["problems"], [])
        self.assertTrue(
            any(
                a.startswith("builtin_commands lane broken: canary")
                for a in got["advisories"]
            )
        )

    def test_no_skills_breaks_the_bundled_lane_only(self) -> None:
        src = self._src()
        got = inv.check_integrity(
            src, self._commands(src), {}, {}, {"security-review": "security-review"}
        )
        self.assertEqual(got["lanes"]["bundled_skills"]["status"], "broken")
        self.assertEqual(got["status"], "degraded")
        self.assertTrue(
            any(a.startswith("bundled_skills lane broken:") for a in got["advisories"])
        )

    def test_every_lane_broken_is_broken(self) -> None:
        src = (
            'x={type:"local",name:"help",description:"d"};'
            + f'"{inv.VALIDATED_AGAINST}";' * 30
        )
        got = inv.check_integrity(src, self._commands(src), {}, {}, {})
        self.assertEqual(
            [got["lanes"][lane]["status"] for lane in inv.LANES],
            ["broken", "broken", "broken"],
        )
        self.assertEqual(got["status"], "broken")
        self.assertTrue(all(":" in p for p in got["problems"]))

    def test_missing_plugin_backed_canary_breaks_that_lane(self) -> None:
        src = self._src()
        got = inv.check_integrity(
            src,
            self._commands(src),
            {"a": {}},
            {"registrations_seen": 1, "resolved": 1},
            {},
        )
        self.assertEqual(got["lanes"]["plugin_backed"]["status"], "broken")
        self.assertEqual(got["status"], "degraded")

    def test_dynamic_roster_is_an_advisory_not_an_unresolved_name(self) -> None:
        src = self._src()
        got = inv.check_integrity(
            src,
            self._commands(src),
            {"a": {}},
            {"registrations_seen": 2, "resolved": 1, "dynamic_roster": 1},
            {"security-review": "security-review"},
        )
        self.assertEqual(got["status"], "degraded")
        self.assertTrue(any("dynamic roster" in a for a in got["advisories"]))
        self.assertFalse(any("computed name" in a for a in got["advisories"]))

    def test_registrations_below_the_floor_degrade_the_bundled_lane(self) -> None:
        # A literal in a run under the floor was never read, so the roster is
        # a floor even when every read registration resolved.
        src = self._src()
        got = inv.check_integrity(
            src,
            self._commands(src),
            {"a": {}},
            {"registrations_seen": 1, "resolved": 1},
            {"security-review": "security-review"},
            runs_below_floor=2,
        )
        self.assertEqual(got["lanes"]["bundled_skills"]["status"], "degraded")
        self.assertEqual(got["status"], "degraded")
        self.assertTrue(
            any("shorter than" in a and "floor" in a for a in got["advisories"])
        )

    def test_esm_export_list_feeds_the_registrar_advisory(self) -> None:
        src = self._src("function zz(){}export{zz as registerSomethingNewSkill};")
        got = inv.check_integrity(
            src,
            self._commands(src),
            {"a": {}},
            {"registrations_seen": 1, "resolved": 1},
            {"security-review": "security-review"},
        )
        self.assertTrue(
            any("registerSomethingNewSkill" in a for a in got["advisories"])
        )
        self.assertEqual(got["lanes"]["bundled_skills"]["status"], "degraded")

    def test_degraded_on_unknown_registrar(self) -> None:
        # The silent-drift signal: a registration path the script does not know.
        src = self._src("pt(Q,{registerSomethingNewSkill:()=>zz});")
        got = inv.check_integrity(
            src,
            self._commands(src),
            {"a": {}},
            {"registrations_seen": 1, "resolved": 1},
        )
        self.assertEqual(got["status"], "degraded")
        self.assertTrue(
            any("registerSomethingNewSkill" in a for a in got["advisories"])
        )

    def test_degraded_when_registrations_exceed_resolved(self) -> None:
        src = self._src()
        got = inv.check_integrity(
            src,
            self._commands(src),
            {"a": {}},
            {"registrations_seen": 5, "resolved": 3},
        )
        self.assertEqual(got["status"], "degraded")
        self.assertTrue(any("floor" in a for a in got["advisories"]))

    def test_low_yield_breaks_the_builtin_lane(self) -> None:
        # Many registration tokens present but few commands resolved means the
        # brace reader stopped working - the exact shape of a quiet shortfall.
        src = self._src() + 'x={type:"local"};' * 200
        got = inv.check_integrity(
            src,
            self._commands(src),
            {"a": {}},
            {"registrations_seen": 1, "resolved": 1},
            {"security-review": "security-review"},
        )
        self.assertEqual(got["lanes"]["builtin_commands"]["status"], "broken")
        self.assertEqual(got["status"], "degraded")


class TestReadBundleRegionRule(unittest.TestCase):
    """Region selection against synthetic byte layouts.

    A bytecode-fragmented build scatters the readable source across thousands
    of printable runs; the doctor registration sat in a 1.3 KB run on the
    build that broke the previous single-longest-run rule.
    """

    MARKER = b"// @bun @bytecode @bun-cjs\n"
    BIG = b'x={type:"local",name:"help",description:"d"};' * 30_000  # > 1 MB
    GAP = bytes(range(0x80, 0x100)) * 8  # non-printable bytes
    DOCTOR = b'eo({name:"doctor",aliases:["checkup"],menuDescription:"Health-check"});'
    CONST = b'var kYe="simplify";' + b"a" * 300

    def _write(self, layout: bytes) -> pathlib.Path:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".bin")
        self.addCleanup(lambda: pathlib.Path(tmp.name).unlink(missing_ok=True))
        tmp.write(layout)
        tmp.close()
        return pathlib.Path(tmp.name)

    def _fragmented(self) -> bytes:
        return (
            self.MARKER
            + self.BIG
            + self.GAP
            + self.DOCTOR
            + b"b" * 2000
            + self.GAP
            + self.CONST
            + b"c" * 300
        )

    def test_read_bundle_joins_every_run_above_the_floor(self) -> None:
        src, meta = inv.read_bundle(self._write(self._fragmented()))
        self.assertIsNotNone(src)
        assert src is not None
        self.assertIn('name:"help"', src)
        self.assertIn('name:"doctor"', src)
        self.assertIn('kYe="simplify"', src)
        self.assertEqual(meta["runs"], 3)
        self.assertEqual(meta["runs_below_floor"], 0)
        self.assertIn("256", meta["region_rule"])
        self.assertGreaterEqual(meta["elapsed_seconds"], 0)

    def test_read_bundle_pe_container_uses_the_same_rule(self) -> None:
        src, meta = inv.read_bundle(self._write(b"MZ" + self.GAP + self._fragmented()))
        self.assertEqual(meta["container"], "PE")
        assert src is not None
        self.assertIn('name:"doctor"', src)
        self.assertEqual(meta["runs"], 3)

    def test_read_bundle_legacy_single_run_is_unchanged(self) -> None:
        legacy = self.MARKER + b"registerBundledSkill:()=>xu;" + self.BIG + self.DOCTOR
        src, meta = inv.read_bundle(self._write(legacy))
        assert src is not None
        self.assertEqual(src.encode("latin1"), legacy)
        self.assertEqual(meta["runs"], 1)

    def test_read_bundle_without_a_marker_falls_back_to_the_longest_run(self) -> None:
        legacy = b"registerBundledSkill:()=>xu;" + self.BIG + self.DOCTOR
        src, meta = inv.read_bundle(
            self._write(self.GAP + legacy + self.GAP + b"tail" * 100)
        )
        assert src is not None
        self.assertEqual(src.encode("latin1"), legacy)
        self.assertIn("no bundle marker", meta["region_rule"])

    def test_read_bundle_counts_a_registration_below_the_floor(self) -> None:
        # A run shorter than the floor carrying a registration is counted,
        # never silently lost.
        tiny = b'eo({name:"tiny"});'
        layout = (
            self.MARKER
            + self.BIG
            + self.GAP
            + tiny
            + self.GAP
            + self.DOCTOR
            + b"b" * 300
        )
        src, meta = inv.read_bundle(self._write(layout))
        assert src is not None
        self.assertNotIn('name:"tiny"', src)
        self.assertEqual(meta["runs_below_floor"], 1)

    def test_read_bundle_does_not_count_prose_in_the_string_table(self) -> None:
        # The bytecode string table holds message text such as
        # `or Workflow({name: "` - a space after the colon, so not code.
        layout = (
            self.MARKER
            + self.BIG
            + self.GAP
            + b' or Workflow({name: "'
            + self.GAP
            + self.DOCTOR
            + b"b" * 300
        )
        _, meta = inv.read_bundle(self._write(layout))
        self.assertEqual(meta["runs_below_floor"], 0)

    def test_read_bundle_rejects_a_region_under_one_megabyte(self) -> None:
        src, meta = inv.read_bundle(self._write(self.MARKER + self.DOCTOR + b"b" * 300))
        self.assertIsNone(src)
        self.assertIn("does not embed", meta["error"])


class TestRegistrarRoutes(unittest.TestCase):
    CANARY = 'eo({name:"doctor",aliases:["checkup"],menuDescription:"Health-check"});'

    def test_cjs_getter_route(self) -> None:
        src = "pt(Q,{registerBundledSkill:()=>xu});" + self.CANARY
        self.assertEqual(
            inv.discover_registrar_route(src, "registerBundledSkill"),
            ("xu", "export-map"),
        )

    def test_esm_export_list_route(self) -> None:
        src = "export{eo as registerBundledSkill,dF as getBundledSkills};" + self.CANARY
        self.assertEqual(
            inv.discover_registrar_route(src, "registerBundledSkill"),
            ("eo", "esm-export"),
        )

    def test_canary_route_when_no_export_names_the_registrar(self) -> None:
        self.assertEqual(
            inv.discover_registrar_route(self.CANARY, "registerBundledSkill"),
            ("eo", "canary"),
        )

    def test_no_route_is_none_and_the_lane_is_broken(self) -> None:
        self.assertEqual(
            inv.discover_registrar_route("var x=1;", "registerBundledSkill"),
            (None, None),
        )
        skills, notes = inv.extract_bundled_skills(
            "var x=1;", inv.build_brace_map("var x=1;")
        )
        self.assertEqual(skills, {})
        self.assertIn("export not found", notes["error"])
        self.assertIsNone(notes["registrar_route"])

    def test_route_is_recorded_in_the_notes(self) -> None:
        src = "function eo(){}export{eo as registerBundledSkill};" + self.CANARY
        _, notes = inv.extract_bundled_skills(src, inv.build_brace_map(src))
        self.assertEqual(notes["registrar_route"], "esm-export")


class TestNameLocality(unittest.TestCase):
    """Computed names resolve by locality, never by a single global value."""

    HEAD = "function eo(){}export{eo as registerBundledSkill};"

    def _skills(self, src: str) -> tuple[dict, dict]:
        return inv.extract_bundled_skills(src, inv.build_brace_map(src))

    def test_nearest_preceding_binding_wins_over_a_farther_one(self) -> None:
        # The phantom this guards: `oO="ehrpd"` in an unrelated module far
        # ahead must not shadow `oO="artifact-design"` bound closer in.
        src = (
            self.HEAD
            + 'var oO="ehrpd";'
            + "z" * 500
            + ';var oO="artifact-design";'
            + 'eo({name:oO,menuDescription:"Design"});'
        )
        skills, notes = self._skills(src)
        self.assertIn("artifact-design", skills)
        self.assertNotIn("ehrpd", skills)
        self.assertNotIn("unresolved_dynamic_names", notes)

    def test_a_lone_far_binding_of_a_short_identifier_is_not_resolved(self) -> None:
        src = (
            self.HEAD
            + 'var e="linux";'
            + "z" * (inv.SHORT_IDENT_LOCALITY_BYTES + 10)
            + ';eo({name:e,menuDescription:"D"});'
        )
        skills, notes = self._skills(src)
        self.assertEqual(skills, {})
        self.assertEqual(notes["unresolved_dynamic_names"], ["e"])

    def test_a_short_identifier_bound_nearby_resolves(self) -> None:
        # The design canvas registration: `var r="design"` a few KB ahead of
        # `eo({name:r,...})` inside the same module.
        src = (
            self.HEAD
            + 'var r="design";'
            + "z" * 4000
            + ';eo({name:r,menuDescription:"Draft"});'
        )
        skills, _ = self._skills(src)
        self.assertIn("design", skills)

    def test_a_long_identifier_bound_far_ahead_resolves(self) -> None:
        src = (
            self.HEAD
            + 'var kYe="simplify";'
            + "z" * (inv.SHORT_IDENT_LOCALITY_BYTES * 2)
            + ';eo({name:kYe,menuDescription:"Clean up"});'
        )
        skills, _ = self._skills(src)
        self.assertIn("simplify", skills)

    def test_a_nearer_non_constant_binding_shadows_a_constant(self) -> None:
        src = (
            self.HEAD
            + 'var kYe="simplify";'
            + "z" * 500
            + ';function f(e){let kYe=e?g(e):"x";eo({name:kYe,menuDescription:"D"})}'
        )
        skills, notes = self._skills(src)
        self.assertEqual(skills, {})
        self.assertEqual(notes["unresolved_dynamic_names"], ["kYe"])

    def test_a_binding_after_the_registration_does_not_resolve_it(self) -> None:
        src = self.HEAD + 'eo({name:zz,menuDescription:"D"});var zz="later";'
        skills, notes = self._skills(src)
        self.assertEqual(skills, {})
        self.assertEqual(notes["unresolved_dynamic_names"], ["zz"])

    def test_a_template_literal_name_is_a_dynamic_roster(self) -> None:
        src = (
            self.HEAD + "eo({name:`artifact-${e}`,menuDescription:t,userInvocable:!0});"
        )
        skills, notes = self._skills(src)
        self.assertEqual(skills, {})
        self.assertEqual(notes["dynamic_roster"], 1)
        self.assertEqual(notes["dynamic_roster_patterns"], ["`artifact-${e}`"])

    def test_a_same_identifier_call_without_a_name_is_not_a_registration(self) -> None:
        # Another module's `eo(...)` taking an options object: no `name:`,
        # so it is neither a registration nor an unresolved one.
        src = (
            self.HEAD
            + 'eo({check:"overwrite",tx:e});eo({name:"run",menuDescription:"Launch"});'
        )
        skills, notes = self._skills(src)
        self.assertEqual(list(skills), ["run"])
        self.assertEqual(notes["registrations_seen"], 1)
        self.assertEqual(notes["same_identifier_calls_skipped"], 1)

    def test_a_descriptor_member_name_resolves(self) -> None:
        # registerSlidesSkill in 2.1.284: the registration reads its fields
        # from a descriptor object whose name is a hoisted constant.
        src = (
            self.HEAD + 'var o="slides";var c={name:o,intent:"slides",'
            'description:"Make a new Slides deck artifact from a brief"};'
            "function Wvn(){let t=c;eo({name:t.name,description:t.description,"
            "isEnabled:()=>l(t),userInvocable:!0,disableModelInvocation:!0})}"
        )
        skills, notes = self._skills(src)
        self.assertEqual(
            skills["slides"]["description"],
            "Make a new Slides deck artifact from a brief",
        )
        self.assertTrue(skills["slides"]["disable_model_invocation"])
        self.assertNotIn("unresolved_dynamic_names", notes)

    def test_a_loop_over_a_literal_table_is_enumerated(self) -> None:
        src = (
            self.HEAD
            + 'var Qi=[{kind:"report",description:"R"},{kind:"explainer",description:"E"}];'
            "function Zt(){for(let{kind:e,description:n}of Qi)"
            "eo({name:`artifact-${e}`,description:n,userInvocable:!0})}"
            'var za=[{kind:"doc",description:"D"}];'
            "function Cn(){for(let{kind:e,description:s}of za)"
            "eo({name:e,description:s,userInvocable:!0})}"
        )
        skills, notes = self._skills(src)
        self.assertEqual(
            sorted(skills), ["artifact-explainer", "artifact-report", "doc"]
        )
        self.assertEqual(skills["artifact-report"]["description"], "R")
        self.assertEqual(skills["doc"]["description"], "D")
        self.assertEqual(notes["rosters_resolved"], {"Qi": 2, "za": 1})
        self.assertNotIn("dynamic_roster", notes)
        self.assertEqual(notes["registrations_seen"], notes["resolved"])

    def test_a_function_whose_name_ends_in_the_registrar_is_not_a_call(self) -> None:
        # `productionRemoteToolsAnnounceDeps({...name:be.name...})` ends in
        # the 2.1.284 registrar `ps`; it is not a registration.
        src = self.HEAD + 'xeo({bridge:()=>({name:be.name})});eo({name:"run"});'
        skills, notes = self._skills(src)
        self.assertEqual(list(skills), ["run"])
        self.assertEqual(notes["registrations_seen"], 1)

    def test_a_loop_registration_is_a_dynamic_roster(self) -> None:
        src = (
            self.HEAD
            + 'var e="linux";'
            + "for(let{kind:e,menuDescription:o}of ls)eo({name:e,menuDescription:o});"
        )
        skills, notes = self._skills(src)
        self.assertEqual(skills, {})
        self.assertEqual(notes["dynamic_roster"], 1)
        self.assertNotIn("unresolved_dynamic_names", notes)
        self.assertEqual(notes["registrations_seen"], 1)


class TestInvocationFieldsAndCollisions(unittest.TestCase):
    HEAD = "function eo(){}export{eo as registerBundledSkill};"
    DOCTOR = (
        'eo({name:"doctor",aliases:["checkup"],isEnabled:()=>!a.X,survivesBundledKillSwitch:!0,'
        'requires:{workspace:!0},terminalOriented:!0,menuDescription:"Health-check",'
        "userInvocable:!0,disableModelInvocation:!0});"
    )
    SIMPLIFY = 'eo({name:"simplify",menuDescription:"Clean up",userInvocable:!0});'
    VERIFY = 'eo({name:"verify",description:As,userInvocable:!0,disableModelInvocation:()=>!P1e()});'

    def _skills(self, src: str) -> tuple[dict, dict]:
        return inv.extract_bundled_skills(src, inv.build_brace_map(src))

    def test_invocation_fields_are_read_when_present(self) -> None:
        skills, _ = self._skills(self.HEAD + self.DOCTOR + self.SIMPLIFY)
        doctor = skills["doctor"]
        self.assertTrue(doctor["user_invocable"])
        self.assertTrue(doctor["disable_model_invocation"])
        self.assertTrue(doctor["terminal_oriented"])
        self.assertTrue(doctor["survives_kill_switch"])
        self.assertTrue(doctor["gated"])
        simplify = skills["simplify"]
        self.assertTrue(simplify["user_invocable"])
        self.assertNotIn("disable_model_invocation", simplify)
        self.assertNotIn("terminal_oriented", simplify)

    def test_a_function_valued_field_reads_as_true_and_flag_driven(self) -> None:
        skills, _ = self._skills(self.HEAD + self.VERIFY)
        self.assertTrue(skills["verify"]["disable_model_invocation"])
        self.assertEqual(skills["verify"]["flag_driven"], ["disable_model_invocation"])

    def test_two_registrations_sharing_a_name_are_both_kept(self) -> None:
        # 2.1.263 registers `design` twice: the canvas skill (model-invocable)
        # and the claude.ai/design hub (model-disabled). Neither may win.
        hub = 'eo({name:"design",menuDescription:"Work with Claude Design",disableModelInvocation:!0,userInvocable:!0});'
        canvas = 'var r="design";eo({name:r,menuDescription:"Draft a design on a canvas",isEnabled:o,userInvocable:!0});'
        skills, notes = self._skills(self.HEAD + hub + canvas)
        design = skills["design"]
        self.assertIsInstance(design, list)
        self.assertEqual(len(design), 2)
        self.assertEqual(
            sorted(r.get("disable_model_invocation", False) for r in design),
            [False, True],
        )
        self.assertTrue(all(r["collision"] for r in design))
        self.assertEqual(notes["collisions"], ["design"])
        self.assertEqual(notes["resolved"], 2)
        self.assertEqual(len(inv.registrations_of(design)), 2)

    def test_a_flag_driven_twin_of_a_constant_field_is_a_collision(self) -> None:
        # Same boolean reading, different basis: one fixed, one decided at
        # runtime. That difference is evidence, so both registrations stay.
        fixed = 'eo({name:"verify",description:As,userInvocable:!0,disableModelInvocation:!0});'
        skills, notes = self._skills(self.HEAD + fixed + self.VERIFY)
        self.assertIsInstance(skills["verify"], list)
        self.assertEqual(len(skills["verify"]), 2)
        self.assertEqual(notes["collisions"], ["verify"])

    def test_the_same_registration_seen_twice_is_not_a_collision(self) -> None:
        skills, notes = self._skills(self.HEAD + self.SIMPLIFY + self.SIMPLIFY)
        self.assertIsInstance(skills["simplify"], dict)
        self.assertNotIn("collisions", notes)


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
        self.assertEqual(
            inv.extract_plugin_backed(src), {"security-review": "security-review"}
        )


class TestBundledSkillFieldBinding(unittest.TestCase):
    """A registration missing a field must not adopt the next one's."""

    BLEED = (
        "pt(Q,{registerBundledSkill:()=>xu});"
        'xu({name:"first"});'
        'xu({name:"second",aliases:["s"],menuDescription:"Second description"});'
    )

    def test_missing_description_does_not_bleed_forward(self) -> None:
        skills, _ = inv.extract_bundled_skills(
            self.BLEED, inv.build_brace_map(self.BLEED)
        )
        self.assertEqual(skills["first"]["description"], "")
        self.assertEqual(skills["first"]["aliases"], [])
        self.assertEqual(skills["second"]["description"], "Second description")


class TestManifestComponentPaths(unittest.TestCase):
    """A declared path replaces the default directory rather than adding to it."""

    def test_dotted_key_resolves(self) -> None:
        m = {"experimental": {"themes": "./custom-themes/"}}
        self.assertEqual(
            inv._manifest_paths(m, "experimental.themes"), ["./custom-themes/"]
        )

    def test_absent_key_is_none(self) -> None:
        self.assertIsNone(inv._manifest_paths({}, "agents"))
        self.assertIsNone(
            inv._manifest_paths({"experimental": {}}, "experimental.themes")
        )

    def test_array_form(self) -> None:
        self.assertEqual(
            inv._manifest_paths({"commands": ["./a/", "./b/"]}, "commands"),
            ["./a/", "./b/"],
        )

    def test_declared_dir_replaces_default(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            root = pathlib.Path(td)
            (root / "agents").mkdir()
            (root / "agents" / "default.md").write_text("x", encoding="utf-8")
            (root / "custom").mkdir()
            (root / "custom" / "declared.md").write_text("x", encoding="utf-8")
            spec = {"dir": "agents", "manifest": "agents", "kind": "dir-of-files"}
            self.assertEqual(
                inv._scan_component(root, spec, {"agents": ["./custom/"]}),
                ["declared.md"],
            )
            self.assertEqual(inv._scan_component(root, spec, {}), ["default.md"])


class TestSelfCheckDiagnostic(unittest.TestCase):
    def test_unknown_version_is_an_advisory(self) -> None:
        src = "pt(Q,{registerBundledSkill:()=>xu});" + "".join(
            f'x{i}={{type:"local",name:"{n}",description:"d"}};'
            for i, n in enumerate(inv.CANARY_COMMANDS)
        )
        got = inv.check_integrity(
            src,
            inv.extract_builtin_commands(src, inv.build_brace_map(src)),
            {"a": {}},
            {"registrations_seen": 1, "resolved": 1},
        )
        self.assertEqual(got["status"], "degraded")
        self.assertTrue(
            any("could not read a CLI version" in a for a in got["advisories"])
        )


def _cmd(src: str, name: str) -> dict:
    return inv.extract_builtin_commands(src, inv.build_brace_map(src))[name]


class TestStaticValues(unittest.TestCase):
    """Descriptions and argument hints held in getters, constants, and calls."""

    def test_ternary_getter_takes_the_fallthrough_branch(self) -> None:
        rec = _cmd(
            'x={type:"local-jsx",name:"exit",get description(){return kt()?"Detach":"Exit the CLI"}};',
            "exit",
        )
        self.assertEqual(rec["description"], "Exit the CLI")
        self.assertEqual(rec["description_source"], "getter")
        self.assertEqual(rec["description_variants"], ["Detach", "Exit the CLI"])

    def test_a_ternary_inside_the_condition_is_not_a_value(self) -> None:
        rec = _cmd(
            'x={type:"local-jsx",name:"diff",get description(){return OMt(rc()?"full":"inline")'
            '==="full"?"Toggle the panel":"View changes"}};',
            "diff",
        )
        self.assertEqual(
            rec["description_variants"], ["Toggle the panel", "View changes"]
        )

    def test_a_getter_returning_a_call_follows_the_function(self) -> None:
        rec = _cmd(
            'function HKt(){return kt()?"Detach":"Exit the CLI"}'
            'x={type:"local",name:"exit",get description(){return HKt()}};',
            "exit",
        )
        self.assertEqual(rec["description"], "Exit the CLI")

    def test_several_returns_end_on_the_last(self) -> None:
        rec = _cmd(
            'x={type:"local-jsx",name:"terminal-setup",get description(){if(a.t==="A")'
            'return"Apple";if(a.t!==null)return`Check ${a.t}`;return"Install binding"}};',
            "terminal-setup",
        )
        self.assertEqual(rec["description"], "Install binding")
        self.assertEqual(
            rec["description_variants"], ["Apple", "Check …", "Install binding"]
        )

    def test_a_constant_and_a_single_quoted_literal_resolve(self) -> None:
        src = (
            'Kix="Build a design together";'
            'x={type:"local",name:"a",description:Kix};'
            'y={type:"local",name:"b",description:\'Use when "rebind" is asked\'};'
        )
        self.assertEqual(_cmd(src, "a")["description"], "Build a design together")
        self.assertEqual(_cmd(src, "a")["description_source"], "constant")
        self.assertEqual(_cmd(src, "b")["description"], 'Use when "rebind" is asked')

    def test_a_function_reference_is_read_as_a_getter(self) -> None:
        src = 'function ta(){return"Review the diff"}x={type:"local",name:"r",description:ta};'
        self.assertEqual(_cmd(src, "r")["description"], "Review the diff")
        self.assertEqual(_cmd(src, "r")["description_source"], "call")

    def test_concatenated_literals_join(self) -> None:
        rec = _cmd('x={type:"local",name:"c",description:"one "+"two"};', "c")
        self.assertEqual(rec["description"], "one two")

    def test_argument_hint_literal_getter_and_absent(self) -> None:
        src = (
            'x={type:"local",name:"a",description:"d",argumentHint:"[on|off]"};'
            'y={type:"local",name:"b",description:"d",get argumentHint(){return Vl()?void 0:"[name]"}};'
            'z={type:"local",name:"c",description:"d"};'
        )
        self.assertEqual(_cmd(src, "a")["argument_hint"], "[on|off]")
        self.assertEqual(_cmd(src, "b")["argument_hint"], "[name]")
        self.assertEqual(_cmd(src, "b")["argument_hint_source"], "getter")
        self.assertIsNone(_cmd(src, "c")["argument_hint"])
        self.assertEqual(_cmd(src, "c")["argument_hint_source"], "absent")

    def test_an_unresolvable_description_is_empty_and_labeled(self) -> None:
        rec = _cmd('x={type:"local",name:"d",description:()=>n().description()};', "d")
        self.assertEqual(rec["description"], "")
        self.assertEqual(rec["description_source"], "unresolved")


class TestInvocability(unittest.TestCase):
    def test_prompt_command_from_builtin_is_model_invocable(self) -> None:
        rec = _cmd(
            'x={type:"prompt",name:"init",description:"d",source:"builtin"};', "init"
        )
        self.assertEqual((rec["model_invocable"], rec["user_invocable"]), (True, True))

    def test_prompt_command_with_model_invocation_disabled(self) -> None:
        rec = _cmd(
            'x={type:"prompt",name:"insights",description:"d",source:"builtin",'
            "disableModelInvocation:!0};",
            "insights",
        )
        self.assertIs(rec["model_invocable"], False)

    def test_local_command_is_never_model_invocable(self) -> None:
        rec = _cmd('x={type:"local-jsx",name:"help",description:"d"};', "help")
        self.assertIs(rec["model_invocable"], False)
        self.assertIs(rec["user_invocable"], True)

    def test_prompt_command_without_a_source_is_undetermined(self) -> None:
        rec = _cmd('x={type:"prompt",name:"p",description:"d"};', "p")
        self.assertIsNone(rec["model_invocable"])

    def _skills(self, body: str) -> dict:
        src = "pt(Q,{registerBundledSkill:()=>xu});" + body
        return inv.extract_bundled_skills(src, inv.build_brace_map(src))[0]

    def test_bundled_skill_defaults_are_user_and_model(self) -> None:
        rec = self._skills('xu({name:"simplify",description:"d"});')["simplify"]
        self.assertEqual((rec["user_invocable"], rec["model_invocable"]), (True, True))

    def test_bundled_skill_disable_model_invocation(self) -> None:
        skills = self._skills(
            'xu({name:"doctor",description:"d",disableModelInvocation:!0,argumentHint:"[x]"});'
            'xu({name:"verify",description:"d",disableModelInvocation:()=>!cft()});'
            'xu({name:"keys",description:"d",userInvocable:!1});'
        )
        self.assertIs(skills["doctor"]["model_invocable"], False)
        self.assertEqual(skills["doctor"]["argument_hint"], "[x]")
        self.assertIsNone(skills["verify"]["model_invocable"])
        self.assertIs(skills["keys"]["user_invocable"], False)
        self.assertIs(skills["keys"]["model_invocable"], True)

    def test_a_roster_description_comes_from_its_row(self) -> None:
        skills = self._skills(
            'Qi=[{kind:"report",description:"A report"}];let n="decoy";'
            "for(let{kind:e,description:n}of Qi)xu({name:`artifact-${e}`,description:n});"
        )
        self.assertEqual(skills["artifact-report"]["description"], "A report")
        self.assertEqual(skills["artifact-report"]["description_source"], "roster")


WORKFLOW_SRC = (
    'function dro(o,e,r){eo().bundledWorkflows.push({source:"built-in",...e,script:o,'
    "disableModelInvocation:r?.disableModelInvocation})}"
    'var i="deep-research",e=i,t="Deep research harness",'
    's=[{title:"Scope",detail:"x"},{title:"Search",detail:"y"}];'
    "function l(){return!0}"
    "function a(){dro(`let e = \"shadow\";\nexport const meta = {name: '${e}'}`,"
    "{name:e,description:t,phases:s},{disableModelInvocation:l})}"
)


class TestBundledWorkflows(unittest.TestCase):
    def _extract(self, src: str) -> tuple[dict, dict]:
        return inv.extract_bundled_workflows(src, inv.build_brace_map(src))

    def test_registration_resolves_from_the_call_site_not_the_script(self) -> None:
        flows, notes = self._extract(WORKFLOW_SRC)
        rec = flows["deep-research"]
        self.assertEqual(rec["description"], "Deep research harness")
        self.assertEqual(rec["phases"], ["Scope", "Search"])
        self.assertEqual(notes["registrar"], ["dro"])
        self.assertEqual((notes["registrations_seen"], notes["resolved"]), (1, 1))

    def test_function_valued_model_flag_is_undetermined(self) -> None:
        rec = self._extract(WORKFLOW_SRC)[0]["deep-research"]
        self.assertIsNone(rec["model_invocable"])
        self.assertIs(rec["user_invocable"], True)
        self.assertEqual(rec["flag_driven"], ["disable_model_invocation"])

    def test_constant_model_flag_is_read(self) -> None:
        rec = self._extract(
            WORKFLOW_SRC.replace(
                "{disableModelInvocation:l}", "{disableModelInvocation:!1}"
            )
        )[0]["deep-research"]
        self.assertIs(rec["model_invocable"], True)

    def test_no_push_site_is_an_error(self) -> None:
        flows, notes = self._extract('var i="deep-research";')
        self.assertEqual(flows, {})
        self.assertIn("error", notes)

    def test_lane_breaks_on_a_missing_canary_and_others_stand(self) -> None:
        src = TestIntegrity()._src()
        got = inv.check_integrity(
            src,
            inv.extract_builtin_commands(src, inv.build_brace_map(src)),
            {"a": {}},
            {"registrations_seen": 1, "resolved": 1},
            {"security-review": "security-review"},
            0,
            {},
            {"registrations_seen": 0, "resolved": 0},
        )
        self.assertEqual(got["lanes"][inv.WORKFLOW_LANE]["status"], "broken")
        self.assertEqual(got["lanes"]["builtin_commands"]["status"], "ok")
        self.assertEqual(got["status"], "degraded")

    def test_lane_ok_with_the_canary(self) -> None:
        src = TestIntegrity()._src()
        flows, notes = self._extract(WORKFLOW_SRC)
        got = inv.check_integrity(
            src,
            inv.extract_builtin_commands(src, inv.build_brace_map(src)),
            {"a": {}},
            {"registrations_seen": 1, "resolved": 1},
            {"security-review": "security-review"},
            0,
            flows,
            notes,
        )
        self.assertEqual(got["lanes"][inv.WORKFLOW_LANE]["status"], "ok")
        self.assertEqual(got["status"], "ok")


# Shapes from 2.1.285: literal and constant agent types, a disallowed list
# with a spread, a getter tool list, a chunk agent pushed through a renamed
# export, an internal agent outside the roster, a user-settings agent, and a
# runtime context object that copies `agentType` and `source`.
AGENT_SRC = (
    'var xt="Edit",yt="Agent";var B6=[xt];var zz="Explore";'
    'var GP={agentType:"general-purpose",whenToUse:"General agent",tools:["*"],'
    'source:"built-in",baseDir:"built-in",getSystemPrompt:()=>""};'
    'var EX={agentType:zz,whenToUse:"Fast search",disallowedTools:[yt,...B6],'
    'source:"built-in",baseDir:"built-in",model:"inherit",omitClaudeMd:!0,'
    'maxTurns:15,getSystemPrompt:()=>""};'
    'var PL={agentType:"Plan",whenToUse:"Plans",source:"built-in",tools:EX.tools,'
    'getSystemPrompt(){return""}};'
    'var SL={agentType:"statusline-setup",whenToUse:"Status line",'
    'tools:["Read","Edit"],source:"built-in",model:"sonnet",getSystemPrompt:()=>""};'
    'var GD={agentType:"claude-code-guide",whenToUse:"Docs questions",'
    'get tools(){return[yt]},source:"built-in",getSystemPrompt:()=>""};'
    'var qHe={agentType:"claude",whenToUse:"Catch-all",tools:["*"],source:"built-in",'
    'getSystemPrompt:()=>""};export{qHe};export{qHe as CLAUDE_AGENT};'
    'var o={agentType:"workflow-subagent",whenToUse:"Internal",tools:["*"],'
    'source:"built-in",getSystemPrompt:()=>""};export{o as WF};'
    'var UC={agentType:"custom",whenToUse:"x",source:"userSettings",'
    'getSystemPrompt:()=>""};'
    "var ctx={agentType:GP.agentType,source:GP.source};"
    "function R(){let n=[GP];if(a())n.push(SL);if(b()){let{CLAUDE_AGENT:s}="
    'req("c");n.push(s)}if(c())n.push(EX,PL);n.push(GD);return n}'
)


class TestBuiltinAgents(unittest.TestCase):
    def _extract(self, src: str = AGENT_SRC) -> tuple[dict, dict]:
        return inv.extract_builtin_agents(src, inv.build_brace_map(src))

    def test_only_built_in_definitions_are_agents(self) -> None:
        agents, notes = self._extract()
        self.assertEqual(
            sorted(agents),
            [
                "Explore",
                "Plan",
                "claude",
                "claude-code-guide",
                "general-purpose",
                "statusline-setup",
                "workflow-subagent",
            ],
        )
        self.assertEqual((notes["definitions_seen"], notes["resolved"]), (7, 7))

    def test_a_constant_type_resolves_and_fields_are_read(self) -> None:
        rec = self._extract()[0]["Explore"]
        self.assertEqual(rec["description"], "Fast search")
        self.assertEqual(rec["model"], "inherit")
        self.assertEqual(rec["max_turns"], 15)
        self.assertIs(rec["omit_claude_md"], True)
        self.assertEqual(rec["disallowed_tools"], ["Agent", "Edit"])
        self.assertEqual(rec["disallowed_tools_source"], "literal")

    def test_tool_list_forms(self) -> None:
        agents = self._extract()[0]
        self.assertEqual(agents["statusline-setup"]["tools"], ["Read", "Edit"])
        self.assertEqual(agents["general-purpose"]["tools"], ["*"])
        self.assertEqual(agents["Plan"]["tools_source"], "reference")
        self.assertIsNone(agents["claude-code-guide"]["tools"])
        self.assertEqual(agents["claude-code-guide"]["tools_source"], "getter")
        self.assertEqual(agents["Explore"]["tools_source"], "absent")

    def test_roster_statuses(self) -> None:
        agents, notes = self._extract()
        self.assertTrue(notes["roster_found"])
        self.assertEqual(agents["general-purpose"]["roster"], "default")
        self.assertIs(agents["general-purpose"]["gated"], False)
        for name in ("statusline-setup", "Explore", "Plan", "claude-code-guide"):
            self.assertEqual(agents[name]["roster"], "conditional", name)
        # Pushed through `{CLAUDE_AGENT:s}`, the name a later export gives it.
        self.assertEqual(agents["claude"]["roster"], "conditional")
        self.assertEqual(agents["workflow-subagent"]["roster"], "absent")
        self.assertIsNone(agents["workflow-subagent"]["model_invocable"])
        self.assertIs(agents["Explore"]["model_invocable"], True)
        self.assertIs(agents["Explore"]["user_invocable"], True)

    def test_an_unresolved_type_is_counted(self) -> None:
        src = AGENT_SRC + (
            'var UU={agentType:qq9,whenToUse:"u",source:"built-in",'
            'getSystemPrompt:()=>""};'
        )
        agents, notes = self._extract(src)
        self.assertEqual(notes["unresolved_names"], ["qq9"])
        self.assertEqual(notes["resolved"], notes["definitions_seen"] - 1)

    def test_a_spread_reads_its_own_scope_not_the_nearest_binding(self) -> None:
        src = AGENT_SRC + (
            'var pY=[xt,"Artifact"];function g(){let pY=p(1);return pY}'
            'var SP={agentType:"spread-probe",whenToUse:"s",source:"built-in",'
            'disallowedTools:[yt,...pY],getSystemPrompt:()=>""};'
        )
        rec = self._extract(src)[0]["spread-probe"]
        self.assertEqual(rec["disallowed_tools"], ["Agent", "Edit", "Artifact"])
        self.assertEqual(rec["disallowed_tools_source"], "literal")

    def test_a_spread_of_a_non_constant_binding_stays_partial(self) -> None:
        src = AGENT_SRC + (
            'var pY=[xt,"Artifact"];var pY=c?[xt]:[yt];'
            'var SP={agentType:"spread-probe",whenToUse:"s",source:"built-in",'
            'disallowedTools:[yt,...pY],getSystemPrompt:()=>""};'
        )
        rec = self._extract(src)[0]["spread-probe"]
        self.assertEqual(rec["disallowed_tools"], ["Agent"])
        self.assertEqual(rec["disallowed_tools_source"], "partial")

    def test_a_spread_another_function_reassigns_stays_partial(self) -> None:
        src = AGENT_SRC + (
            'var pY=[xt,"Artifact"];function init(){pY=["Other"]}init();'
            'var SP={agentType:"spread-probe",whenToUse:"s",source:"built-in",'
            'disallowedTools:[yt,...pY],getSystemPrompt:()=>""};'
        )
        rec = self._extract(src)[0]["spread-probe"]
        self.assertEqual(rec["disallowed_tools"], ["Agent"])
        self.assertEqual(rec["disallowed_tools_source"], "partial")

    def test_a_spread_written_off_the_straight_line_stays_partial(self) -> None:
        for prelude in (
            'var pY=[xt,"Artifact"];if(c){pY=["Other"]}',
            'var pY=[xt,"Artifact"];for(;;){pY=["Other"]}',
            'var pY=[xt,"Artifact"];var f=()=>pY=["Other"];f();',
            'var f=()=>pY=["Other"];var pY=[xt,"Artifact"];f();',
            'var pY=[xt,"Artifact"];if(c)pY=["Other"];',
            'var pY=[xt,"Artifact"];pY=c?["Other"]:pY;',
            'var pY=[xt,"Artifact"];c&&(pY=["Other"]);',
            'var pY=[xt,"Artifact"];for(;;)pY=["Other"];',
            'var pY=[xt,"Artifact"];if(c){var pY=f()}',
        ):
            src = AGENT_SRC + (
                prelude + 'var SP={agentType:"spread-probe",'
                'whenToUse:"s",source:"built-in",disallowedTools:[yt,...pY],'
                'getSystemPrompt:()=>""};'
            )
            rec = self._extract(src)[0]["spread-probe"]
            self.assertEqual(rec["disallowed_tools_source"], "partial", prelude)

    def test_a_spread_declared_after_a_function_declaration_resolves(self) -> None:
        src = AGENT_SRC + (
            'function h(){return 1}var a="x",b=["y","z"],pY=[xt,"Artifact"],q=1;'
            'var SP={agentType:"spread-probe",whenToUse:"s",source:"built-in",'
            'disallowedTools:[yt,...pY],getSystemPrompt:()=>""};'
        )
        rec = self._extract(src)[0]["spread-probe"]
        self.assertEqual(rec["disallowed_tools"], ["Agent", "Edit", "Artifact"])
        self.assertEqual(rec["disallowed_tools_source"], "literal")

    def test_a_spread_whose_writer_shadows_the_name_still_resolves(self) -> None:
        for writer in (
            'function g(){let pY=[];pY=["Other"]}',
            'if(c){let pY=f();pY=["Other"]}',
        ):
            src = AGENT_SRC + (
                'var pY=[xt,"Artifact"];' + writer + 'var SP={agentType:"spread-probe",'
                'whenToUse:"s",source:"built-in",disallowedTools:[yt,...pY],'
                'getSystemPrompt:()=>""};'
            )
            rec = self._extract(src)[0]["spread-probe"]
            self.assertEqual(
                rec["disallowed_tools"], ["Agent", "Edit", "Artifact"], writer
            )

    def test_no_roster_leaves_every_agent_absent(self) -> None:
        agents, notes = self._extract(AGENT_SRC.split("function R()")[0])
        self.assertFalse(notes["roster_found"])
        self.assertEqual({a["roster"] for a in agents.values()}, {"absent"})


TOOL_SRC = (
    'var Qz="Bash",at="Read",xt="Edit",hn="Write",wr="WebFetch";'
    'var k1="SendUserFile";var m1="memory_read";'
    "var Kl={isEnabled:()=>!0,isConcurrencySafe:(e)=>!1};"
    'function Ku(){let k1="system_assigned_identity";return k1}'
    '$t({name:Qz,searchHint:"execute shell commands",'
    "get maxResultSizeChars(){return 1},"
    'async description({description:e}){return e||"Run"},isEnabled(){return!0}});'
    '$t({name:at,maxResultSizeChars:1e5,async description(){return"Read a file"},'
    'aliases:["ReadFile"],shouldDefer:!1});'
    '$t({name:xt,maxResultSizeChars:1,description:async()=>"Edit a file",'
    "get shouldDefer(){return x()}});"
    "var De={name:wr,maxResultSizeChars:1,shouldDefer:!0,"
    'userFacingName(){return"Fetch"}};'
    "$t({name:hn,maxResultSizeChars:1,alwaysLoad:!0});"
    "$t({name:k1,maxResultSizeChars:1});"
    "$t({name:m1,maxResultSizeChars:1});"
    "function ne(e){return $t({name:e.name,maxResultSizeChars:5})}"
    'var M=$t({isMcp:!0,name:"mcp",maxResultSizeChars:1});'
)


class TestBuiltinTools(unittest.TestCase):
    def _extract(self, src: str = TOOL_SRC) -> tuple[dict, dict]:
        return inv.extract_builtin_tools(src, inv.build_brace_map(src))

    def test_every_tool_shape_is_found_without_the_builder_name(self) -> None:
        tools, notes = self._extract()
        self.assertEqual(
            sorted(tools),
            [
                "Bash",
                "Edit",
                "Read",
                "SendUserFile",
                "WebFetch",
                "Write",
                "memory_read",
            ],
        )
        self.assertEqual(notes["factory_definitions"], 1)
        self.assertEqual(notes["templates_skipped"], 1)
        self.assertNotIn("unresolved_names", notes)

    def test_pascal_case_binding_wins_over_a_nearer_snake_case_one(self) -> None:
        # `k1` is rebound to a snake_case string nearer the definition, as
        # unrelated code rebinds minified names; a snake_case value is taken
        # only when no PascalCase binding precedes (`m1`).
        tools = self._extract()[0]
        self.assertIn("SendUserFile", tools)
        self.assertIn("memory_read", tools)
        self.assertNotIn("system_assigned_identity", tools)

    def test_a_snake_case_rebinding_the_definition_reads_is_not_skipped(self) -> None:
        # The definition reads the nearer rebinding, so the PascalCase
        # binding behind it is not its name: unresolved, never guessed.
        src = TOOL_SRC.replace(
            "$t({name:k1,", 'k1="system_assigned_identity";$t({name:k1,'
        )
        tools, notes = self._extract(src)
        self.assertNotIn("SendUserFile", tools)
        self.assertIn("k1", notes["unresolved_names"])

    def test_descriptions_hints_and_names(self) -> None:
        tools = self._extract()[0]
        self.assertEqual(tools["Read"]["description"], "Read a file")
        self.assertEqual(tools["Read"]["description_source"], "call")
        self.assertEqual(tools["Edit"]["description"], "Edit a file")
        self.assertEqual(tools["Bash"]["search_hint"], "execute shell commands")
        self.assertEqual(tools["WebFetch"]["user_facing_name"], "Fetch")
        self.assertEqual(tools["Read"]["aliases"], ["ReadFile"])
        self.assertEqual(tools["Write"]["description_source"], "absent")

    def test_deferral_markers(self) -> None:
        tools = self._extract()[0]
        self.assertIs(tools["WebFetch"]["deferred"], True)
        self.assertIs(tools["Read"]["deferred"], False)
        self.assertIs(tools["Bash"]["deferred"], False)
        self.assertIsNone(tools["Edit"]["deferred"])
        self.assertEqual(tools["Edit"]["flag_driven"], ["deferred"])
        self.assertIs(tools["Write"]["always_load"], True)
        self.assertIs(tools["Bash"]["gated"], True)
        self.assertIs(tools["Read"]["gated"], False)

    def test_tools_are_model_only(self) -> None:
        rec = self._extract()[0]["Bash"]
        self.assertEqual((rec["user_invocable"], rec["model_invocable"]), (False, True))

    def test_an_unbound_name_is_unresolved_not_a_factory(self) -> None:
        tools, notes = self._extract(TOOL_SRC + "$t({name:zzq,maxResultSizeChars:1});")
        self.assertEqual(notes["unresolved_names"], ["zzq"])

    def test_resolve_tool_ident_honors_short_locality(self) -> None:
        src = 'var e="Bash";' + "z" * (inv.SHORT_IDENT_LOCALITY_BYTES + 10)
        braces = inv.build_brace_map(src)
        index = inv.build_const_index(src, None, inv.TOOL_NAME_RE)
        self.assertIsNone(inv.resolve_tool_ident(src, braces, "e", len(src), index))
        self.assertEqual(inv.resolve_tool_ident(src, braces, "e", 20, index), "Bash")


def _tool(src: str, name: str) -> dict:
    return inv.extract_builtin_tools(src, inv.build_brace_map(src))[0][name]


class TestToolDescriptionShapes(unittest.TestCase):
    """Tool descriptions built by a call with arguments, from shapes seen in
    Claude Code 2.1.285: the method passes a runtime value into a function
    whose body selects or interpolates hoisted constants."""

    def test_a_call_with_arguments_follows_the_function(self) -> None:
        src = (
            'var e="WRONG",Hq="ClaudeDesign",dp=`Short`,lp=`Work with Claude Design.`;'
            "function kb(e){return`${e?dp:lp}\n\nMore.`}"
            "$t({name:Hq,maxResultSizeChars:1,async description(){return kb(Rt())}});"
        )
        rec = _tool(src, "ClaudeDesign")
        self.assertEqual(rec["description"], "Work with Claude Design.\n\nMore.")
        self.assertEqual(rec["description_source"], "call")

    def test_a_parameter_never_reads_a_same_named_binding(self) -> None:
        src = (
            'var e="Bound elsewhere",Qz="Bash";'
            '$t({name:Qz,maxResultSizeChars:1,async description({description:e}){return e||"Run shell command"}});'
            'var Pz="Probe";function pd(n){return n}'
            "$t({name:Pz,maxResultSizeChars:1,async description(){return pd(1)}});"
        )
        self.assertEqual(_tool(src, "Bash")["description"], "Run shell command")
        self.assertEqual(_tool(src, "Probe")["description_source"], "unresolved")

    def test_a_resolved_left_operand_wins_over_its_fallback(self) -> None:
        src = (
            'var dd="REAL",Qz="Probe";'
            '$t({name:Qz,maxResultSizeChars:1,description:dd||"FALLBACK"||"OTHER"});'
        )
        rec = _tool(src, "Probe")
        self.assertEqual(rec["description"], "REAL")
        self.assertNotIn("description_variants", rec)

    def test_a_resolvable_argument_binds_its_parameter(self) -> None:
        src = (
            'var Qz="Probe",Rz="Other";function ff(x,y){return`Use ${x} ${y}`}'
            '$t({name:Qz,maxResultSizeChars:1,description:ff("REAL",g())});'
            "$t({name:Rz,maxResultSizeChars:1,description:ff(Qz)});"
        )
        self.assertEqual(_tool(src, "Probe")["description"], "Use REAL …")
        self.assertEqual(_tool(src, "Other")["description"], "Use Probe …")

    def test_a_mixed_left_operand_keeps_its_truthy_variants(self) -> None:
        src = 'var Qz="Probe";$t({name:Qz,maxResultSizeChars:1,description:(f?"REAL":"")||"FALLBACK"});'
        rec = _tool(src, "Probe")
        self.assertEqual(rec["description_variants"], ["REAL", "FALLBACK"])

    def test_a_concatenation_keeps_every_combination(self) -> None:
        src = 'var Qz="Probe";$t({name:Qz,maxResultSizeChars:1,description:"A"+(f?"X":"Y")+"B"});'
        rec = _tool(src, "Probe")
        self.assertEqual(rec["description"], "AYB")
        self.assertEqual(rec["description_variants"], ["AXB", "AYB"])

    def test_a_fallback_starting_with_an_empty_literal_is_still_read(self) -> None:
        src = 'var Qz="Probe";$t({name:Qz,maxResultSizeChars:1,description:u.v||""+"Fallback"});'
        self.assertEqual(_tool(src, "Probe")["description"], "Fallback")

    def test_a_resolved_group_settles_its_fallback(self) -> None:
        src = (
            'var Qz="Probe",Rz="Maybe";'
            '$t({name:Qz,maxResultSizeChars:1,description:(f?"A":"C")||"B"});'
            '$t({name:Rz,maxResultSizeChars:1,description:(f?"A":void 0)||"B"});'
        )
        self.assertEqual(_tool(src, "Probe")["description_variants"], ["A", "C"])
        self.assertEqual(_tool(src, "Maybe")["description_variants"], ["A", "B"])

    def test_substitution_and_join_alternatives_are_kept(self) -> None:
        src = (
            'var Qz="Probe",Rz="Joined";'
            '$t({name:Qz,maxResultSizeChars:1,description:`Use ${f?"X":"Y"}`});'
            '$t({name:Rz,maxResultSizeChars:1,description:["a",f?"X":"Y"].join(" ")});'
        )
        self.assertEqual(
            _tool(src, "Probe")["description_variants"], ["Use X", "Use Y"]
        )
        self.assertEqual(_tool(src, "Joined")["description_variants"], ["a X", "a Y"])

    def test_a_non_string_literal_settles_its_fallback(self) -> None:
        def desc(expr: str) -> str:
            src = f'var Qz="Probe";$t({{name:Qz,maxResultSizeChars:1,description:{expr}}});'
            return _tool(src, "Probe")["description"]

        self.assertEqual(desc('true||"FALLBACK"'), "")
        self.assertEqual(desc('false??"FALLBACK"'), "")
        self.assertEqual(desc('false||"FALLBACK"'), "FALLBACK")
        self.assertEqual(desc('null??"FALLBACK"'), "FALLBACK")
        self.assertEqual(desc('1||"FALLBACK"'), "")
        self.assertEqual(desc('!0||"FALLBACK"'), "")
        self.assertEqual(desc('0??"FALLBACK"'), "")
        self.assertEqual(desc('!1??"FALLBACK"'), "")
        self.assertEqual(desc('0||"FALLBACK"'), "FALLBACK")
        for number in ("-1", ".5", "0x1", "1e-2", "1_000n", "1e1_0"):
            with self.subTest(number=number):
                self.assertEqual(desc(f'{number}||"FALLBACK"'), "")
                self.assertEqual(desc(f'{number}??"FALLBACK"'), "")
        self.assertEqual(desc('0x0||"FALLBACK"'), "FALLBACK")
        self.assertEqual(desc('-0.0??"FALLBACK"'), "")
        self.assertEqual(desc('0e1_0??"FALLBACK"'), "")
        self.assertEqual(desc('!false||"FALLBACK"'), "")
        self.assertEqual(desc('!true??"FALLBACK"'), "")
        self.assertEqual(desc('!true||"FALLBACK"'), "FALLBACK")
        self.assertEqual(desc('!!1||"FALLBACK"'), "")
        self.assertEqual(desc('!!0??"FALLBACK"'), "")
        self.assertEqual(desc('!!0||"FALLBACK"'), "FALLBACK")
        self.assertEqual(desc('(true)||"FALLBACK"'), "")
        self.assertEqual(desc('((1))||"FALLBACK"'), "")
        self.assertEqual(desc('(false)??"FALLBACK"'), "")
        self.assertEqual(desc('(false)||"FALLBACK"'), "FALLBACK")

    def test_a_local_alias_of_a_parameter_keeps_its_bound_value(self) -> None:
        src = (
            'var x="WRONG",Qz="Probe";function ff(x){let yy=x;return yy}'
            '$t({name:Qz,maxResultSizeChars:1,description:ff("REAL")});'
        )
        self.assertEqual(_tool(src, "Probe")["description"], "REAL")

    def test_a_partial_substitution_keeps_a_runtime_alternative(self) -> None:
        src = 'var Qz="Probe";$t({name:Qz,maxResultSizeChars:1,description:`Use ${f?"X":void 0}`});'
        rec = _tool(src, "Probe")
        self.assertEqual(rec["description_variants"], ["Use …", "Use X"])
        self.assertEqual(rec["description_source"], "template")

    def test_a_reassigned_parameter_is_not_its_argument(self) -> None:
        src = (
            'var Qz="Probe";function ff(x){x=g();return`Use ${x}`}'
            '$t({name:Qz,maxResultSizeChars:1,description:ff("REAL")});'
        )
        self.assertEqual(_tool(src, "Probe")["description"], "Use …")
        for write in (
            'x+="LOCAL"',
            "x++",
            "--x",
            'x??="LOCAL"',
            '[x]=["LOCAL"]',
            '({a:x}={a:"LOCAL"})',
            "for(x of y);",
        ):
            with self.subTest(write=write):
                src = (
                    f'var Qz="Probe";function ff(x){{{write};return`Use ${{x}}`}}'
                    '$t({name:Qz,maxResultSizeChars:1,description:ff("REAL")});'
                )
                self.assertEqual(_tool(src, "Probe")["description"], "Use …")

    def test_a_local_object_member_keeps_the_bound_parameter(self) -> None:
        src = (
            'var x="WRONG",Qz="Probe";function ff(x){let obj={p:x};return obj.p}'
            '$t({name:Qz,maxResultSizeChars:1,description:ff("REAL")});'
        )
        self.assertEqual(_tool(src, "Probe")["description"], "REAL")

    def test_a_local_object_is_the_visible_one_and_its_getter_closes_over(
        self,
    ) -> None:
        src = (
            'var x="WRONG",Qz="Probe",Rz="Getter";'
            'function ff(x){let obj={p:x};function g(){let obj={p:"WRONG"}}return obj.p}'
            "function gg(x){let obj={get p(){return x}};return obj.p}"
            '$t({name:Qz,maxResultSizeChars:1,description:ff("REAL")});'
            '$t({name:Rz,maxResultSizeChars:1,description:gg("REAL")});'
        )
        self.assertEqual(_tool(src, "Probe")["description"], "REAL")
        self.assertEqual(_tool(src, "Getter")["description"], "REAL")

    def test_a_forwarded_partial_argument_stays_partial(self) -> None:
        src = (
            'var Qz="Probe";function id(x){return x}'
            '$t({name:Qz,maxResultSizeChars:1,description:`Use ${id(f?"REAL":u.v)}`});'
        )
        self.assertEqual(
            _tool(src, "Probe")["description_variants"], ["Use …", "Use REAL"]
        )

    def test_a_partial_argument_leaves_its_fallback_reachable(self) -> None:
        src = (
            'var Qz="Probe";function ff(x){return x||"FALLBACK"}'
            '$t({name:Qz,maxResultSizeChars:1,description:ff(f?"REAL":u.v)});'
        )
        self.assertEqual(
            _tool(src, "Probe")["description_variants"], ["REAL", "FALLBACK"]
        )

    def test_nested_returns_and_quoted_writes_do_not_leak(self) -> None:
        src = (
            'var Qz="Probe",Rz="Quoted";'
            'function ff(x){return x;function inner(){return"WRONG"}}'
            'function gg(x){let s="x=LOCAL";return x}'
            '$t({name:Qz,maxResultSizeChars:1,description:ff("REAL")});'
            '$t({name:Rz,maxResultSizeChars:1,description:gg("REAL")});'
        )
        self.assertEqual(_tool(src, "Probe")["description"], "REAL")
        self.assertNotIn("description_variants", _tool(src, "Probe"))
        self.assertEqual(_tool(src, "Quoted")["description"], "REAL")
        written = (
            'var Qz="Probe";function hh(x){let s=`${x="LOCAL"}`;return`Use ${x}`}'
            '$t({name:Qz,maxResultSizeChars:1,description:hh("REAL")});'
        )
        self.assertEqual(_tool(written, "Probe")["description"], "Use …")

    def test_a_partial_element_or_argument_keeps_a_runtime_alternative(self) -> None:
        src = (
            'var Qz="Probe",Rz="Bound";function ff(x){return`Use ${x}`}'
            '$t({name:Qz,maxResultSizeChars:1,description:["Use",f?"X":u.v].join(" ")});'
            '$t({name:Rz,maxResultSizeChars:1,description:ff(f?"REAL":u.v)});'
        )
        self.assertEqual(
            _tool(src, "Probe")["description_variants"], ["Use …", "Use X"]
        )
        self.assertEqual(
            _tool(src, "Bound")["description_variants"], ["Use …", "Use REAL"]
        )

    def test_a_nested_helper_sees_its_callers_bound_parameter(self) -> None:
        src = (
            'var x="WRONG",Qz="Probe";'
            "function ff(x){function gg(){return x}return gg()}"
            '$t({name:Qz,maxResultSizeChars:1,description:ff("REAL")});'
        )
        self.assertEqual(_tool(src, "Probe")["description"], "REAL")

    def test_a_template_is_never_nullish_and_array_holes_join_empty(self) -> None:
        src = (
            'var Qz="Probe",Rz="Holes";'
            '$t({name:Qz,maxResultSizeChars:1,description:`${u.v}`??"FALLBACK"});'
            '$t({name:Rz,maxResultSizeChars:1,description:[,"A",,"B"].join("-")});'
        )
        self.assertEqual(_tool(src, "Probe")["description_source"], "unresolved")
        self.assertEqual(_tool(src, "Holes")["description"], "-A--B")

    def test_known_primitives_render_like_javascript(self) -> None:
        src = (
            'var Qz="Probe",Rz="Joined";'
            "$t({name:Qz,maxResultSizeChars:1,description:`Count ${2} ${false} ${null}`});"
            '$t({name:Rz,maxResultSizeChars:1,description:["A",null,false,0,"B"].join("-")});'
        )
        self.assertEqual(_tool(src, "Probe")["description"], "Count 2 false null")
        self.assertEqual(_tool(src, "Joined")["description"], "A--false-0-B")

    def test_a_nullish_fallback_keeps_an_empty_string(self) -> None:
        src = 'var Qz="Probe";$t({name:Qz,maxResultSizeChars:1,description:""??"FALLBACK"});'
        self.assertEqual(_tool(src, "Probe")["description"], "")
        self.assertEqual(_tool(src, "Probe")["description_source"], "literal")

    def test_an_empty_fallback_is_not_a_value(self) -> None:
        src = 'var Qz="Probe";$t({name:Qz,maxResultSizeChars:1,description:ua()??""});'
        self.assertEqual(_tool(src, "Probe")["description_source"], "unresolved")

    def test_a_template_of_only_runtime_parts_is_unresolved(self) -> None:
        src = (
            'var Qz="Probe";function kb(e){return`${e.a}\n\n${e.b}`}'
            "$t({name:Qz,maxResultSizeChars:1,async description(){return kb(x)}});"
        )
        rec = _tool(src, "Probe")
        self.assertEqual(rec["description"], "")
        self.assertEqual(rec["description_source"], "unresolved")

    def test_a_parenthesized_ternary_and_a_joined_array_concatenate(self) -> None:
        src = (
            'var ah="Fetch ",am="schemas",ac="tools",ap=" now.",Qz="ToolSearch",Wz="WaitForMcpServers";'
            "function Hj(){return ah+(xf()?am:ac)+ap}"
            'function Gx(){return["Wait for servers.","",...["Then use them."]].join(`\n`)}'
            "$t({name:Qz,maxResultSizeChars:1,async description(){return Hj()}});"
            "$t({name:Wz,maxResultSizeChars:1,async description(){return Gx()}});"
        )
        self.assertEqual(_tool(src, "ToolSearch")["description"], "Fetch tools now.")
        self.assertEqual(
            _tool(src, "WaitForMcpServers")["description"],
            "Wait for servers.\n\nThen use them.",
        )

    def test_a_template_substitution_resolves_its_constant(self) -> None:
        src = (
            'var Br="Grep",Sh="Bash";'
            "function hL(e){if(n(e))return`Short via ${Sh}.`;return`ALWAYS use ${Br}, never ${Sh}.`}"
            "$t({name:Br,maxResultSizeChars:1,async description(){return hL(void 0)}});"
        )
        rec = _tool(src, "Grep")
        self.assertEqual(rec["description"], "ALWAYS use Grep, never Bash.")
        self.assertEqual(rec["description_variants"][0], "Short via Bash.")


def _modules(*bodies: str) -> str:
    return "".join(f"\n// @bun @bytecode\n{b}" for b in bodies)


class TestModuleScopedResolution(unittest.TestCase):
    """A bundle of concatenated modules repeats minified names; a name
    resolves inside its own module or through its import, never to the
    nearest foreign binding."""

    def test_an_imported_name_resolves_in_its_exporting_module(self) -> None:
        src = _modules(
            'var jd="Workflow";export{jd};',
            'function f(){let jd=a?"remote_control_disabled":"host_exit"}',
            'import{jd}from"/$bunfs/root/chunk-a.js";var Qz="Probe";'
            "$t({name:Qz,maxResultSizeChars:1,description:`Write a ${jd} script`});",
        )
        self.assertEqual(_tool(src, "Probe")["description"], "Write a Workflow script")

    def test_a_local_declaration_shadows_an_imported_name(self) -> None:
        src = _modules(
            'var jd="WRONG";export{jd};',
            'import{jd}from"/$bunfs/root/chunk-a.js";var Qz="Probe";'
            'function ff(){let jd="LOCAL";return jd}'
            "$t({name:Qz,maxResultSizeChars:1,description:ff()});",
        )
        self.assertNotEqual(_tool(src, "Probe")["description"], "WRONG")

    def test_a_name_neither_imported_nor_declared_is_a_runtime_value(self) -> None:
        src = _modules(
            'var jd="host_exit";',
            'var Qz="Probe";$t({name:Qz,maxResultSizeChars:1,description:`Write a ${jd} script`});',
        )
        self.assertEqual(_tool(src, "Probe")["description"], "Write a … script")

    def test_a_single_letter_binding_never_crosses_a_module_boundary(self) -> None:
        src = _modules(
            'var e="Foreign";',
            'var Qz="Probe";$t({name:Qz,maxResultSizeChars:1,description:`Use ${e} here`});',
        )
        self.assertEqual(_tool(src, "Probe")["description"], "Use … here")

    def test_a_tool_name_bound_to_a_conditional_is_not_resolved(self) -> None:
        src = _modules(
            'var Qz="Probe";'
            'function f(e){let Qz=e?"Probe":"Other";'
            '$t({name:Qz,maxResultSizeChars:1,description:"d"})}'
        )
        tools, _ = inv.extract_builtin_tools(src, inv.build_brace_map(src))
        self.assertEqual(tools, {})

    def test_a_later_binding_resolves_only_inside_a_function_body(self) -> None:
        src = _modules(
            'var Qz="Probe",Pz="Lazy";'
            "$t({name:Qz,maxResultSizeChars:1,description:zz});"
            "$t({name:Pz,maxResultSizeChars:1,async description(){return zz}});"
            'var zz="later";'
        )
        self.assertEqual(_tool(src, "Probe")["description_source"], "unresolved")
        self.assertEqual(_tool(src, "Lazy")["description"], "later")

    def test_a_binding_local_to_another_function_is_not_visible(self) -> None:
        src = _modules(
            'var Qz="Probe";function outer(){let zz="WRONG"}'
            "$t({name:Qz,maxResultSizeChars:1,async description(){return zz}});"
            'var zz="REAL";'
        )
        self.assertEqual(_tool(src, "Probe")["description"], "REAL")

    def test_a_single_letter_local_of_another_function_is_not_visible(self) -> None:
        src = _modules(
            'var Qz="Probe";function outer(){let e="WRONG"}'
            "$t({name:Qz,maxResultSizeChars:1,async description(){return`Use ${e}`}});"
        )
        self.assertEqual(_tool(src, "Probe")["description"], "Use …")

    def test_aliases_follow_visible_bindings_and_keep_deferral(self) -> None:
        src = _modules(
            'var Qz="Probe",Rz="Alias";'
            'function ff(x){let t={p:x};function other(){let t={p:"BAD"}}let obj=t;return obj.p}'
            "function outer(){let yy=xx;return yy}"
            '$t({name:Qz,maxResultSizeChars:1,description:ff("REAL")});'
            "$t({name:Rz,maxResultSizeChars:1,description:outer});"
            'var xx="LATER";'
        )
        self.assertEqual(_tool(src, "Probe")["description"], "REAL")
        self.assertEqual(_tool(src, "Alias")["description"], "LATER")

    def test_a_hoisted_local_function_shadows_an_outer_one(self) -> None:
        src = _modules(
            'var Qz="Probe";function helper(){return"WRONG"}'
            'function outer(){return helper();function helper(){return"LOCAL"}}'
            "$t({name:Qz,maxResultSizeChars:1,description:outer});"
        )
        self.assertEqual(_tool(src, "Probe")["description"], "LOCAL")

    def test_a_later_local_declaration_shadows_an_outer_binding(self) -> None:
        src = _modules(
            'var Qz="Probe",xx="WRONG";function outer(){return xx;if(c){var xx="LOCAL"}}'
            "$t({name:Qz,maxResultSizeChars:1,description:outer});"
        )
        self.assertEqual(_tool(src, "Probe")["description_source"], "unresolved")

    def test_var_is_function_scoped_across_nested_blocks(self) -> None:
        later = _modules(
            'var Qz="Probe",xx="WRONG";'
            'function outer(){if(a){return xx}for(;;){var xx="LOCAL"}}'
            "$t({name:Qz,maxResultSizeChars:1,description:outer});"
        )
        self.assertEqual(_tool(later, "Probe")["description_source"], "unresolved")
        earlier = _modules(
            'var Qz="Probe",xx="WRONG";'
            'function ff(){if(c){var xx="REAL"}return xx}'
            "$t({name:Qz,maxResultSizeChars:1,description:ff});"
        )
        self.assertEqual(_tool(earlier, "Probe")["description"], "REAL")

    def test_a_var_after_a_call_initializer_still_shadows(self) -> None:
        src = _modules(
            'var Qz="Probe",xx="WRONG";'
            'function outer(){return xx;if(1){var a=f(1,2),xx="LOCAL"}}'
            "$t({name:Qz,maxResultSizeChars:1,description:outer});"
        )
        self.assertEqual(_tool(src, "Probe")["description_source"], "unresolved")

    def test_a_later_local_declaration_shadows_a_one_letter_binding(self) -> None:
        src = _modules(
            'var Qz="Probe";var e="WRONG";function ff(){return e;var e="LOCAL"}'
            "$t({name:Qz,maxResultSizeChars:1,description:ff()});"
        )
        self.assertEqual(_tool(src, "Probe")["description_source"], "unresolved")

    def test_a_nested_function_with_a_call_default_is_not_a_branch(self) -> None:
        src = _modules(
            'var Qz="Probe";'
            'function ff(x){return x;function inner(a=g()){return"WRONG"}}'
            '$t({name:Qz,maxResultSizeChars:1,description:ff("REAL")});'
        )
        self.assertEqual(_tool(src, "Probe")["description"], "REAL")

    def test_a_nested_function_with_a_quoted_paren_default_is_not_a_branch(
        self,
    ) -> None:
        src = _modules(
            'var Qz="Probe";'
            'function ff(x){return x;function inner(sep=")"){return"WRONG"}}'
            '$t({name:Qz,maxResultSizeChars:1,description:ff("REAL")});'
        )
        self.assertEqual(_tool(src, "Probe")["description"], "REAL")

    def test_a_declaration_without_initializer_shadows(self) -> None:
        before = _modules(
            'var Qz="Probe";var xx="WRONG";function ff(){let xx;return xx}'
            "$t({name:Qz,maxResultSizeChars:1,description:ff()});"
        )
        self.assertEqual(_tool(before, "Probe")["description_source"], "unresolved")
        after = _modules(
            'var Qz="Probe";var xx="WRONG";function ff(){return xx;var xx}'
            "$t({name:Qz,maxResultSizeChars:1,description:ff()});"
        )
        self.assertEqual(_tool(after, "Probe")["description_source"], "unresolved")

    def test_a_catch_parameter_shadows(self) -> None:
        src = _modules(
            'var Qz="Probe";var xx="WRONG";'
            'function ff(){try{throw"REAL"}catch(xx){return xx}}'
            "$t({name:Qz,maxResultSizeChars:1,description:ff()});"
        )
        self.assertNotEqual(_tool(src, "Probe").get("description"), "WRONG")

    def test_a_nested_destructuring_write_unbinds_a_parameter(self) -> None:
        src = _modules(
            'var Qz="Probe";'
            'function ff(x){({a:{b:x}}={a:{b:"LOCAL"}});return x}'
            '$t({name:Qz,maxResultSizeChars:1,description:ff("REAL")});'
        )
        self.assertNotEqual(_tool(src, "Probe").get("description"), "REAL")

    def test_a_function_with_a_call_default_hides_no_outer_one(self) -> None:
        src = _modules(
            'var Qz="Probe";function helper(){return"WRONG"}'
            'function outer(){return helper();function helper(x=g()){return"REAL"}}'
            "$t({name:Qz,maxResultSizeChars:1,description:outer()});"
        )
        self.assertNotEqual(_tool(src, "Probe").get("description"), "WRONG")

    def test_a_for_head_binding_ends_with_its_loop(self) -> None:
        src = _modules(
            'var Qz="Probe";var xx="REAL";'
            'function ff(){for(let xx="LOCAL";;){break}return xx}'
            "$t({name:Qz,maxResultSizeChars:1,description:ff()});"
        )
        self.assertEqual(_tool(src, "Probe")["description"], "REAL")

    def test_a_quoted_paren_default_keeps_a_method_parameter(self) -> None:
        src = _modules(
            'var Qz="Probe";var xx="WRONG";'
            '$t({name:Qz,maxResultSizeChars:1,description(xx,a="("){return xx}});'
        )
        self.assertNotEqual(_tool(src, "Probe").get("description"), "WRONG")

    def test_a_catch_parameter_shadows_a_bound_parameter(self) -> None:
        src = _modules(
            'var Qz="Probe";'
            'function ff(x){try{throw"LOCAL"}catch(x){return x}}'
            '$t({name:Qz,maxResultSizeChars:1,description:ff("REAL")});'
        )
        self.assertNotEqual(_tool(src, "Probe").get("description"), "REAL")

    def test_a_for_head_binding_shadows_a_bound_parameter(self) -> None:
        src = _modules(
            'var Qz="Probe";'
            'function ff(x){for(const x of ["LOCAL"]){return x}}'
            '$t({name:Qz,maxResultSizeChars:1,description:ff("REAL")});'
        )
        self.assertNotEqual(_tool(src, "Probe").get("description"), "REAL")

    def test_a_destructured_for_head_without_a_space_shadows_a_bound_parameter(
        self,
    ) -> None:
        for head in ("const{x}", "let{x}", "const[x]", "let[x]"):
            of = "[{x:'L'}]" if "{" in head else "[['L']]"
            with self.subTest(head=head):
                src = _modules(
                    'var Qz="Probe";'
                    f"function ff(x){{for({head}of{of}){{return x}}}}"
                    '$t({name:Qz,maxResultSizeChars:1,description:ff("REAL")});'
                )
                self.assertNotEqual(_tool(src, "Probe").get("description"), "REAL")

    def test_an_unbraced_for_body_sees_the_head_binding(self) -> None:
        src = _modules(
            'var Qz="Probe";'
            "function ff(x){for(const x of a)return x}"
            '$t({name:Qz,maxResultSizeChars:1,description:ff("REAL")});'
        )
        self.assertNotEqual(_tool(src, "Probe").get("description"), "REAL")

    def test_an_unbraced_for_body_ends_at_its_statement(self) -> None:
        src = _modules(
            'var Qz="Probe";'
            "function ff(x){for(const x of a)g(x);return x}"
            '$t({name:Qz,maxResultSizeChars:1,description:ff("REAL")});'
        )
        self.assertEqual(_tool(src, "Probe")["description"], "REAL")

    def test_a_nested_statement_in_an_unbraced_for_body_keeps_the_head_binding(
        self,
    ) -> None:
        for body in (
            "if(x)return x",
            "for(const y of b)return x",
            "if(t(x,{k:1}))return x",
            "return c?{k:1}:x",
        ):
            with self.subTest(body=body):
                src = _modules(
                    'var Qz="Probe";'
                    f"function ff(x){{for(const x of a){body}}}"
                    '$t({name:Qz,maxResultSizeChars:1,description:ff("REAL")});'
                )
                self.assertNotEqual(_tool(src, "Probe").get("description"), "REAL")

    def test_an_unbraced_for_body_ending_in_a_block_ends_its_head_binding(self) -> None:
        src = _modules(
            'var Qz="Probe";'
            "function ff(x,c){for(const x of a)if(c){g()}return x}"
            '$t({name:Qz,maxResultSizeChars:1,description:ff("REAL")});'
        )
        self.assertEqual(_tool(src, "Probe")["description"], "REAL")

    def test_a_for_head_binding_named_of_shadows_a_bound_parameter(self) -> None:
        for head in ("const of of a", "const{of}of a"):
            with self.subTest(head=head):
                src = _modules(
                    'var Qz="Probe";'
                    f"function ff(of){{for({head}){{return of}}}}"
                    '$t({name:Qz,maxResultSizeChars:1,description:ff("REAL")});'
                )
                self.assertNotEqual(_tool(src, "Probe").get("description"), "REAL")

    def test_a_for_head_binding_shadows_an_outer_binding(self) -> None:
        src = _modules(
            'var Qz="Probe";var xx="WRONG";'
            "function ff(){for(let xx of a){return xx}}"
            "$t({name:Qz,maxResultSizeChars:1,description:ff()});"
        )
        self.assertNotEqual(_tool(src, "Probe").get("description"), "WRONG")

    def test_a_quoted_paren_in_a_control_head_keeps_a_var_function_scoped(
        self,
    ) -> None:
        src = _modules(
            'var Qz="Probe";var xx="WRONG";'
            'function ff(){if(a==="("){var xx="REAL"}return xx}'
            "$t({name:Qz,maxResultSizeChars:1,description:ff()});"
        )
        self.assertNotEqual(_tool(src, "Probe").get("description"), "WRONG")

    def test_an_unsafe_integer_in_a_template_stays_unresolved(self) -> None:
        src = 'var Qz="Probe";$t({name:Qz,maxResultSizeChars:1,description:`n${9007199254740993}`});'
        self.assertNotEqual(_tool(src, "Probe").get("description"), "n9007199254740993")

    def test_a_top_level_if_block_reads_no_later_binding(self) -> None:
        src = _modules(
            'var Qz="Probe";'
            "if(flag){$t({name:Qz,maxResultSizeChars:1,description:zz})}"
            'var zz="later";'
        )
        self.assertNotEqual(_tool(src, "Probe").get("description"), "later")

    def test_a_top_level_alias_reads_no_later_binding(self) -> None:
        src = _modules(
            'var Qz="Probe";let tt=later;'
            "$t({name:Qz,maxResultSizeChars:1,async description(){return tt.p}});"
            'var later={p:"LATER"};'
        )
        self.assertEqual(_tool(src, "Probe")["description_source"], "unresolved")

    def test_a_later_declaration_must_be_visible(self) -> None:
        src = _modules(
            'var Qz="Probe";$t({name:Qz,maxResultSizeChars:1,description:ff()});'
            'function outer(){function ff(){return"WRONG"}}function ff(){return"REAL"}'
        )
        self.assertEqual(_tool(src, "Probe")["description"], "REAL")

    def test_a_huge_bigint_does_not_abort_the_run(self) -> None:
        big = "0x1" + "0" * 400 + "n"
        src = f'var Qz="Probe";$t({{name:Qz,maxResultSizeChars:1,description:{big}||"F"}});'
        self.assertEqual(_tool(src, "Probe")["description"], "")

    def test_a_deferred_call_argument_reads_a_later_binding(self) -> None:
        src = _modules(
            'var Qz="Probe";function ff(a){return a}function outer(){return ff(xx)}'
            "$t({name:Qz,maxResultSizeChars:1,description:outer});"
            'var xx="REAL";'
        )
        self.assertEqual(_tool(src, "Probe")["description"], "REAL")

    def test_an_eager_call_does_not_read_a_later_binding(self) -> None:
        src = _modules(
            'var Qz="Probe";function dd(){return zz}'
            "$t({name:Qz,maxResultSizeChars:1,description:dd()});"
            'var zz="later";'
        )
        self.assertEqual(_tool(src, "Probe")["description_source"], "unresolved")

    def test_import_text_in_a_string_links_nothing(self) -> None:
        src = _modules(
            'var jd="Foreign";export{jd};',
            'var jd="Local",Qz="Probe",s="import{jd}from\\"x\\"";'
            "$t({name:Qz,maxResultSizeChars:1,description:`Write a ${jd} script`});"
            'var t="export{Qz}";',
        )
        self.assertEqual(_tool(src, "Probe")["description"], "Write a Local script")

    def test_a_name_two_modules_export_is_ambiguous(self) -> None:
        src = _modules(
            'var jd="One";export{jd};',
            'var jd="Two";export{jd};',
            'import{jd}from"/$bunfs/root/chunk-a.js";var Qz="Probe";'
            "$t({name:Qz,maxResultSizeChars:1,description:`Write a ${jd} script`});",
        )
        self.assertEqual(_tool(src, "Probe")["description"], "Write a … script")

    def test_a_single_letter_function_resolves_only_at_module_top_level(self) -> None:
        tool = 'var B="Projects";$t({name:B,maxResultSizeChars:1,async description(){return P({memory:1})}});'
        body = "function P({memory:e}){return`Read and write the Project.`}" + tool
        self.assertEqual(
            _tool(_modules(body), "Projects")["description"],
            "Read and write the Project.",
        )
        nested = "function o(){function P(){return`Nested.`}}" + tool
        self.assertEqual(
            _tool(_modules(nested), "Projects")["description_source"], "unresolved"
        )
        self.assertEqual(_tool(body, "Projects")["description_source"], "unresolved")


class TestAgentAndToolIntegrity(unittest.TestCase):
    def _check(self, agents: dict, anotes: dict, tools: dict, tnotes: dict) -> dict:
        src = TestIntegrity()._src()
        return inv.check_integrity(
            src,
            inv.extract_builtin_commands(src, inv.build_brace_map(src)),
            {"a": {}},
            {"registrations_seen": 1, "resolved": 1},
            {"security-review": "security-review"},
            agents=agents,
            agent_notes=anotes,
            tools=tools,
            tool_notes=tnotes,
        )

    def _healthy(self) -> tuple[dict, dict, dict, dict]:
        agents = {n: {} for n in inv.AGENT_CANARY}
        tools = {n: {} for n in inv.TOOL_CANARY}
        return agents, {"roster_found": True}, tools, {}

    def test_both_lanes_ok(self) -> None:
        got = self._check(*self._healthy())
        self.assertEqual(got["lanes"][inv.AGENT_LANE]["status"], "ok")
        self.assertEqual(got["lanes"][inv.TOOL_LANE]["status"], "ok")
        self.assertEqual(got["status"], "ok")

    def test_a_missing_canary_breaks_only_that_lane(self) -> None:
        agents, anotes, tools, tnotes = self._healthy()
        del tools["Bash"]
        got = self._check(agents, anotes, tools, tnotes)
        self.assertEqual(got["lanes"][inv.TOOL_LANE]["status"], "broken")
        self.assertEqual(got["lanes"][inv.AGENT_LANE]["status"], "ok")
        self.assertEqual(got["status"], "degraded")
        self.assertTrue(any("Bash" in a for a in got["advisories"]))

    def test_an_empty_lane_is_broken(self) -> None:
        agents, anotes, tools, tnotes = self._healthy()
        got = self._check({}, anotes, tools, tnotes)
        self.assertEqual(got["lanes"][inv.AGENT_LANE]["status"], "broken")

    def test_unresolved_names_and_a_missing_roster_degrade(self) -> None:
        agents, _, tools, _ = self._healthy()
        got = self._check(
            agents, {"roster_found": False}, tools, {"unresolved_names": ["zz"]}
        )
        self.assertEqual(got["lanes"][inv.AGENT_LANE]["status"], "degraded")
        self.assertEqual(got["lanes"][inv.TOOL_LANE]["status"], "degraded")

    def test_factories_do_not_degrade(self) -> None:
        agents, anotes, tools, _ = self._healthy()
        got = self._check(agents, anotes, tools, {"factory_definitions": 4})
        self.assertEqual(got["lanes"][inv.TOOL_LANE]["status"], "ok")

    def test_lanes_absent_when_not_extracted(self) -> None:
        src = TestIntegrity()._src()
        got = inv.check_integrity(
            src,
            inv.extract_builtin_commands(src, inv.build_brace_map(src)),
            {"a": {}},
            {"registrations_seen": 1, "resolved": 1},
        )
        self.assertNotIn(inv.AGENT_LANE, got["lanes"])
        self.assertNotIn(inv.TOOL_LANE, got["lanes"])


class TestNearestBindingBoundary(unittest.TestCase):
    def test_a_longer_identifier_ending_in_the_name_is_not_a_binding(self) -> None:
        src = 'Rvt="a";xRvt="b";o.Rvt="c";z'
        at = len(src) - 1
        v = inv._nearest_binding(src, "Rvt", at)
        assert v is not None
        self.assertEqual(src[v : v + 3], '"a"')


DOCS = """# Commands

## All commands

| Command | Purpose |
| :- | :- |
| `/add-dir <path>` | Add a working directory |
| `/code-review [low\\|high] [--fix]` | **[Skill](/docs/en/skills#bundled-skills).** Review the current diff |
| `/cost` | Alias for `/usage` |
| `/deep-research <question>` | **[Workflow](/docs/en/workflows#bundled-workflows).** Fan out web searches |
| `/exit` | Exit the CLI. Alias: `/quit` |
| `/feedback [report]` | Send feedback. Alias: `/bug`. Before v2.1.212, `/bug` and `/share` were aliases of `/feedback` |
| `/mobile` | Show a QR code. Aliases: `/ios`, `/android` |
| `/reload-skills` | Re-scan skills. Reports how many were added or removed |
| `/review [pr]` | Alias of [`/code-review`](/docs/en/code-review): reviews the diff |
| `/schedule [description]` | Create routines |
| `/ultraplan <prompt>` | Removed. Use plan mode instead |
| `/ultrareview [PR]` | Run a cloud review. The preferred invocation is `/code-review ultra`, and `/ultrareview` is an alias |
| `/usage` | Show usage. `/cost` and `/stats` are aliases |
| `/vim` | Removed in v2.1.92. Use `/config` |

## How the command menu matches

| `/not-a-row` | outside the table section |
"""


def _report() -> dict:
    cmd = lambda aliases=(): {"aliases": list(aliases)}  # noqa: E731
    return {
        "sources": {"binary": {"available": True}},
        "builtin_commands": {
            "add-dir": cmd(),
            "exit": cmd(["quit"]),
            "feedback": cmd(["bug"]),
            "reload-skills": cmd(),
            "ultraplan": cmd(),
            "ultrareview": cmd(),
            "usage": cmd(["cost", "stats"]),
            "secret": cmd(),
            "stub": {"aliases": [], "internal": True},
        },
        "bundled_skills": {"code-review": cmd(["review"]), "schedule": cmd()},
        "bundled_workflows": {"deep-research": cmd()},
        "plugin_backed": {},
    }


class TestDocsCrosscheck(unittest.TestCase):
    def setUp(self) -> None:
        import docs_crosscheck as dc

        self.dc = dc
        self.rows = dc.parse_commands_table(DOCS)
        self.names = dc.classify(_report(), self.rows)

    def test_rows_come_only_from_the_all_commands_table(self) -> None:
        self.assertIn("vim", self.rows)
        self.assertNotIn("not-a-row", self.rows)
        self.assertEqual(self.rows["code-review"]["args"], "[low|high] [--fix]")

    def test_a_fetcher_that_writes_no_manifest_degrades_instead_of_raising(
        self,
    ) -> None:
        with mock.patch.object(self.dc, "_FETCHER", pathlib.Path("missing-fetcher.sh")):
            body, error, _ = self.dc.fetch_text("anthropic", self.dc.COMMANDS_URL)
        self.assertIsNone(body)
        self.assertTrue((error or "").startswith("fetch-failed"))

    def test_an_oversized_row_is_skipped_not_backtracked(self) -> None:
        import time

        hostile = "## All commands\n\n| `/a` | " + " " * 40_000 + "\n| `/b` | ok |\n"
        began = time.monotonic()
        rows = self.dc.parse_commands_table(hostile)
        self.assertLess(time.monotonic() - began, 1.0)
        self.assertEqual(set(rows), {"b"})

    def test_whitespace_runs_under_the_row_cap_parse_in_linear_time(self) -> None:
        import time

        run = " " * (self.dc._ROW_MAX // 2 - 10)
        lines = [
            "| `/a` |" + run + "|" + run + "| x",
            "| `/a` |" + run + "|" + run,
            "| `/a` |" + " |" * (len(run) - 1) + "x",
        ]
        for line in lines:
            self.assertLessEqual(len(line), self.dc._ROW_MAX)
            began = time.monotonic()
            self.dc.parse_commands_table("## All commands\n\n" + line + "\n")
            self.assertLess(time.monotonic() - began, 1.0)
        valid = "| `/a` |" + run + "|" + run + "|"
        rows = self.dc.parse_commands_table("## All commands\n\n" + valid + "\n")
        self.assertEqual(rows["a"]["summary"], "|")

    def test_removed_anchors_on_the_row_start(self) -> None:
        self.assertFalse(self.rows["reload-skills"]["removed"])
        self.assertTrue(self.rows["ultraplan"]["removed"])
        self.assertEqual(self.rows["vim"]["removed_version"], "2.1.92")
        self.assertEqual(self.names["reload-skills"]["status"], "documented")

    def test_markers_and_alias_phrasings(self) -> None:
        self.assertEqual(self.rows["code-review"]["kind"], "skill")
        self.assertEqual(self.rows["deep-research"]["kind"], "workflow")
        self.assertEqual(self.rows["cost"]["alias_of"], "usage")
        self.assertEqual(self.rows["review"]["alias_of"], "code-review")
        self.assertEqual(self.rows["exit"]["aliases"], ["quit"])
        self.assertEqual(self.rows["mobile"]["aliases"], ["android", "ios"])
        self.assertEqual(self.rows["usage"]["aliases"], ["cost", "stats"])
        self.assertTrue(self.rows["ultrareview"]["is_alias"])

    def test_a_past_tense_alias_mention_is_not_a_declaration(self) -> None:
        self.assertEqual(self.rows["feedback"]["aliases"], ["bug"])

    def test_statuses(self) -> None:
        got = {n: e["status"] for n, e in self.names.items()}
        self.assertEqual(got["add-dir"], "documented")
        self.assertEqual(got["cost"], "alias")
        self.assertEqual(got["review"], "alias")
        self.assertEqual(got["quit"], "alias")
        self.assertEqual(got["ultrareview"], "docs_alias_but_registered")
        self.assertEqual(got["vim"], "removed_in_docs")
        self.assertEqual(got["ultraplan"], "removed_in_docs_but_registered")
        self.assertEqual(got["mobile"], "docs_only")
        self.assertEqual(got["ios"], "docs_only")
        self.assertEqual(got["secret"], "undocumented")
        self.assertEqual(got["deep-research"], "documented")
        self.assertNotIn("stub", got)

    def test_kind_mismatch_and_alias_disagreement(self) -> None:
        self.assertTrue(self.names["schedule"]["kind_mismatch"])
        self.assertFalse(self.names["code-review"]["kind_mismatch"])
        self.assertFalse(self.names["deep-research"]["kind_mismatch"])
        self.assertNotIn("alias_disagreement", self.names["usage"])
        report = _report()
        report["builtin_commands"]["exit"]["aliases"] = ["quit", "q"]
        names = self.dc.classify(report, self.rows)
        self.assertEqual(
            names["exit"]["alias_disagreement"], {"docs_only": [], "binary_only": ["q"]}
        )

    def test_changelog_first_mention_and_events(self) -> None:
        text = (
            "# Changelog\n\n## 2.1.5\n\n- Added `/foo` command\n- Fixed ~/.claude/foo path\n"
            "\n## 2.1.3\n\n- Fixed /foo crash\n- Renamed `/bar` to `/baz`\n"
        )
        got = self.dc.parse_changelog(text, {"foo", "bar", "baz"})
        self.assertEqual(got["foo"]["first_mentioned"], "2.1.3")
        self.assertEqual(got["foo"]["mentions"], 2)
        self.assertEqual([e["kinds"] for e in got["foo"]["events"]], [["added"]])
        self.assertEqual(got["baz"]["events"][0]["kinds"], ["renamed"])

    def _run(self, with_commands: bool) -> dict:
        """build_crosscheck against fixtures with no changelog; with_commands
        False leaves the fixture directory empty."""
        with tempfile.TemporaryDirectory() as d:
            if with_commands:
                self._fixture_dir(d, None)
            with mock.patch.dict(os.environ, {"FETCH_DOCS_FIXTURE_DIR": d}):
                return self.dc.build_crosscheck(_report())

    def test_unreadable_commands_page_degrades_only_the_block(self) -> None:
        block = self._run(False)
        self.assertEqual(block["status"], "unavailable")
        self.assertIn("index-unread", block["problems"][0])
        self.assertNotIn("names", block)

    def test_changelog_failure_is_degraded_not_fabricated(self) -> None:
        block = self._run(True)
        self.assertEqual(block["status"], "degraded")
        self.assertIn("fixture-missing", block["advisories"][0])
        self.assertIsNone(block["names"]["add-dir"]["changelog"])
        self.assertEqual(block["counts"]["removed_in_docs"], 1)

    def _fixture_dir(self, root: str, changelog: str | None) -> str:
        """Fixtures in the shared fetcher's layout: the anthropic index and the
        commands page, and the generic profile's slug path for the changelog."""
        base = pathlib.Path(root)
        (base / "llms.txt").write_text(
            f"- [Commands]({self.dc.COMMANDS_URL})\n", encoding="utf-8"
        )
        (base / "commands.md").write_text(DOCS, encoding="utf-8")
        if changelog is not None:
            page = base / "raw-githubusercontent-com/anthropics/claude-code/main"
            page.mkdir(parents=True)
            (page / "changelog.md").write_text(changelog, encoding="utf-8")
        return str(base)

    def test_pages_come_through_the_shared_fetcher(self) -> None:
        changelog = "## 9.9.9\n\n- Added `/add-dir` for extra directories\n"
        with tempfile.TemporaryDirectory() as d:
            fixtures = self._fixture_dir(d, changelog)
            with mock.patch.dict(os.environ, {"FETCH_DOCS_FIXTURE_DIR": fixtures}):
                block = self.dc.build_crosscheck(_report())
        self.assertEqual(block["status"], "ok", block["problems"])
        self.assertEqual(block["sources"]["commands"]["url"], self.dc.COMMANDS_URL)
        self.assertEqual(block["sources"]["commands"]["rows"], len(self.rows))
        self.assertEqual(block["names"]["add-dir"]["status"], "documented")
        self.assertEqual(
            block["names"]["add-dir"]["changelog"]["first_mentioned"], "9.9.9"
        )

    def test_no_bash_leaves_the_page_unread_with_its_reason(self) -> None:
        with mock.patch.object(self.dc, "_bash", return_value=None):
            block = self.dc.build_crosscheck(_report())
        self.assertEqual(block["status"], "unavailable")
        self.assertIn("no-bash", block["problems"][0])

    def test_docs_file_without_the_table_is_broken(self) -> None:
        with tempfile.TemporaryDirectory() as d:
            path = pathlib.Path(d) / "commands.md"
            path.write_text("# Commands\n\nNo table here.\n", encoding="utf-8")
            block = self.dc.build_crosscheck(
                _report(), docs_file=str(path), changelog_file=str(path)
            )
        self.assertEqual(block["status"], "broken")

    def test_without_the_binary_there_is_nothing_to_check(self) -> None:
        block = self.dc.build_crosscheck({"sources": {}}, docs_file="unused")
        self.assertEqual(block["status"], "unavailable")


class TestOutFailure(unittest.TestCase):
    def test_unwritable_out_is_a_clean_usage_error(self) -> None:
        import contextlib
        import io

        with tempfile.TemporaryDirectory() as d:
            err = io.StringIO()
            with contextlib.redirect_stderr(err):
                rc = inv.main(
                    [
                        "--disk-only",
                        "--config-dir",
                        d,
                        "--project-dir",
                        d,
                        "--out",
                        str(pathlib.Path(d) / "missing" / "inventory.json"),
                    ]
                )
        self.assertEqual(rc, 2)
        self.assertIn("cannot write --out", err.getvalue())


TOOLS_DOCS = """# Tools reference

| Tool | Description | Permission required |
| :- | :- | :- |
| `Bash` | Executes shell commands. See [Bash tool behavior](#bash) | Yes |
| `Read` | Reads the contents of files | No |
| `Task` | Legacy spelling | No |
| `TaskOutput` | Retrieves output from a background task | No |

## Configure tools

| `NotATool` | outside the table | No |
"""


class TestToolsDocsCrosscheck(unittest.TestCase):
    def setUp(self) -> None:
        import docs_crosscheck as dc

        self.dc = dc
        self.report = {
            "sources": {"binary": {"available": True}},
            "builtin_tools": {
                "Bash": {"aliases": []},
                "Read": {"aliases": []},
                "Agent": {"aliases": ["Task"]},
                "Poll": {"aliases": []},
            },
            "integrity": {"lanes": {"builtin_tools": {"status": "ok"}}},
        }

    def _block(self, text: str, report: dict | None = None) -> dict:
        with tempfile.TemporaryDirectory() as d:
            path = pathlib.Path(d) / "tools-reference.md"
            path.write_text(text, encoding="utf-8")
            return self.dc.build_tools_crosscheck(report or self.report, str(path))

    def test_rows_come_only_from_the_tools_table(self) -> None:
        rows = self.dc.parse_tools_table(TOOLS_DOCS)
        self.assertEqual(sorted(rows), ["Bash", "Read", "Task", "TaskOutput"])
        self.assertEqual(
            rows["Bash"]["summary"], "Executes shell commands. See Bash tool behavior"
        )
        self.assertEqual(rows["Read"]["permission_required"], "No")

    def test_a_pipe_in_the_description_stays_in_the_summary(self) -> None:
        header = "| Tool | Description | Permission required |\n|:--|:--|:--|\n"
        rows = self.dc.parse_tools_table(header + "| `X` | a \\| b | c |  Yes  |  \n")
        self.assertEqual(rows["X"]["summary"], "a \\| b | c")
        self.assertEqual(rows["X"]["permission_required"], "Yes")

    def test_whitespace_runs_under_the_row_cap_parse_in_linear_time(self) -> None:
        import time

        header = "| Tool | Description | Permission required |\n|:--|:--|:--|\n"
        run = " " * (self.dc._ROW_MAX // 2 - 10)
        lines = [
            "| `A` |" + run + "|" + run + "| x",
            "| `A` |" + run + "|" + run,
            "| `A` |" + run + "|" + run + "|",
            "| `A` |" + " |" * (len(run) - 1) + "x",
        ]
        for line in lines:
            self.assertLessEqual(len(line), self.dc._ROW_MAX)
            began = time.monotonic()
            rows = self.dc.parse_tools_table(header + line + "\n")
            self.assertLess(time.monotonic() - began, 1.0)
        self.assertEqual(rows, {})
        valid = "| `A` |" + run + "|" + run + "|" + " No |"
        self.assertEqual(
            self.dc.parse_tools_table(header + valid + "\n")["A"],
            {"summary": "|", "permission_required": "No"},
        )

    def test_statuses(self) -> None:
        block = self._block(TOOLS_DOCS)
        self.assertEqual(block["status"], "ok")
        names = block["names"]
        self.assertEqual(names["Bash"]["status"], "documented")
        self.assertEqual(names["Poll"]["status"], "undocumented")
        self.assertEqual(names["Agent"]["status"], "undocumented")
        self.assertEqual(names["Task"]["status"], "alias")
        self.assertEqual(names["Task"]["binary_alias_of"], "Agent")
        self.assertEqual(names["TaskOutput"]["status"], "docs_only")
        self.assertEqual(block["counts"]["documented"], 2)

    def test_a_page_without_the_table_is_broken(self) -> None:
        self.assertEqual(self._block("# Tools\n\nNo table.\n")["status"], "broken")

    def test_unmatched_table_rows_never_reach_a_later_section(self) -> None:
        unwrapped = TOOLS_DOCS.replace("`Bash`", "Bash").replace("`Read`", "Read")
        unwrapped = unwrapped.replace("`Task`", "Task").replace(
            "`TaskOutput`", "TaskOutput"
        )
        self.assertEqual(self.dc.parse_tools_table(unwrapped), {})
        self.assertEqual(self._block(unwrapped)["status"], "broken")

    def test_an_unhealthy_lane_degrades_the_block(self) -> None:
        report = dict(self.report)
        report["integrity"] = {"lanes": {"builtin_tools": {"status": "degraded"}}}
        self.assertEqual(self._block(TOOLS_DOCS, report)["status"], "degraded")

    def test_no_tools_lane_is_unavailable_without_fetching(self) -> None:
        block = self.dc.build_tools_crosscheck({"sources": {}}, "unused")
        self.assertEqual(block["status"], "unavailable")

    def test_the_parent_block_carries_it_without_changing_its_status(self) -> None:
        with tempfile.TemporaryDirectory() as d:
            docs = pathlib.Path(d) / "commands.md"
            docs.write_text(DOCS, encoding="utf-8")
            tools = pathlib.Path(d) / "tools-reference.md"
            tools.write_text("no table", encoding="utf-8")
            block = self.dc.build_crosscheck(
                {**_report(), "builtin_tools": {"Bash": {}}},
                docs_file=str(docs),
                changelog_file=str(docs),
                tools_file=str(tools),
            )
        self.assertEqual(block["tools"]["status"], "broken")
        self.assertEqual(block["status"], "ok")


_PAD = "x" * 5000


def _plugin_modules(**swap: str) -> list[str]:
    """Modules shaped like the 2.1.287 built-in plugin registry: a registrar
    module, the loader, and one module per plugin. `swap` replaces a module."""
    modules = {
        "registrar": 'var _i="builtin";function ro(){return S}'
        "function Z_(e){ro().builtinPlugins.set(e.name,e);let o=e.hooksModule}"
        "function zv(e){return e.endsWith(`@${_i}`)}"
        "function PQ(){for(let[t,n]of ro().builtinPlugins){let s=`${t}@${_i}`,"
        "a=n.defaultEnabled??!0}}"
        'var A=new Map([["mermaid","cc-plugin-mermaid"],["sec-default","cc-plugin-sec-default"]]);'
        "function Uo(n){for(let r of n)Z_({name:r,description:`${r}, seated`})}"
        "export{Z_,zv,Uo};",
        "loader": 'import{Xue}from"/$bunfs/root/chunk-l.js";'
        "function Jve(){let e=ro();if(e.builtinPluginsInitialized)return;"
        'if(e.builtinPluginsInitialized=!0,Xue("cc-plugin-sec-default",()=>import.meta.require("/$bunfs/root/c1.js")),'
        'Xue("cc-plugin-agents-md",()=>import.meta.require("/$bunfs/root/c2.js")),'
        'a.CLAUDE_CODE_ENTRYPOINT!=="local-agent"){'
        'if(Xue("cc-plugin-mermaid",()=>import.meta.require("/$bunfs/root/c3.js")),!c7r())'
        'Xue("cc-plugin-tips",()=>import.meta.require("/$bunfs/root/c4.js"))}'
        'let i=a.CLAUDE_CODE_ENTRYPOINT!=="local-agent"&&!c7r();'
        'if(i)Xue("cc-plugin-claude-test",()=>import.meta.require("/$bunfs/root/c5.js"))}'
        "export{Jve};",
        "sec": 'import{Z_}from"/$bunfs/root/chunk-r.js";var ZYe="cc-plugin-sec-default";'
        'var m=v(function(a,b){b.exports={scan:{hooks:["classic.*","tool.check"],'
        'calls:["ui.log"]},files:{}}});'
        'var ge=()=>Z_({name:ZYe,description:"Security default",'
        "enabledFromTrustedSettingsOnly:!0,enabledFromPolicyOnly:!0,"
        "hooksModule:VU(1,m,()=>m())});export{ge as registerPlugin};",
        # The name constant sits more than 4 KiB ahead of the registration.
        "agents": 'import{Z_}from"/$bunfs/root/chunk-r.js";var W=!0;'
        'var B=()=>lo("tengu_agents_md_mod",W);var K="cc-plugin-agents-md";'
        'var H="AGENTS.md as project instructions";var pad="'
        + _PAD
        + '";var Qe=()=>Z_({name:K,description:H,isAvailable:B,userConfig:ne});'
        "export{Qe as registerPlugin};",
        "mermaid": 'import{Z_}from"/$bunfs/root/chunk-r.js";var f=()=>!1;'
        'var c=()=>dQ()&&lo("tengu_mermaid_mod",f());'
        'var h={name:"cc-plugin-mermaid",description:"Mermaid in the terminal",'
        "isAvailable:c,defaultEnabled:!1};"
        'var m=v(function(a,b){b.exports={scan:{hooks:["ui.render"],calls:[]},files:{}}});'
        "var B=()=>Z_({...h,hooksModule:VU(1,{register:1},()=>m())});"
        "export{B as registerPlugin};",
        "tips": 'import{Z_}from"/$bunfs/root/chunk-r.js";'
        'var Xo={name:"diff",description:"Toggle the diff panel"};'
        "async function Vn(p){await p.registerCommand(Xo)}"
        "var api={registerCommand:(u)=>p.command.register(u)};"
        'var m=v(function(a,b){b.exports={scan:{hooks:["ui.render"],'
        'calls:["command.register"]},files:{}}});'
        'function se(){Z_({name:"cc-plugin-tips",description:"Spinner tips",'
        "hooksModule:VU(1,m,()=>m())})}export{se as registerPlugin};",
        "test": 'import{Z_}from"/$bunfs/root/chunk-r.js";'
        'var w=Object.freeze({run:"claude-test",draft:"claude-test-draft"});'
        'var De=Object.freeze({description:"Check that the web app still works"});'
        'var Pe=Object.freeze({description:"Drafts spec files"});'
        "function X(e,r){return{...r,name:w[e],async getPromptForCommand(){return[]}}}"
        'var Fe=[X("run",{...De,userInvocable:!0}),X("draft",{...Pe,userInvocable:!1})];'
        'var b="cc-plugin-claude-test";var g="0.4.15";'
        'var xe=()=>!Il("hipaa")&&lo("tengu_mellow_hollerith",!1);'
        'var rt=v(function(x,y){y.exports={scan:{hooks:["command.run"],calls:["mcp.connect"]},'
        'files:{"agents/author.md":`---\nname: author\ndescription: Writes spec drafts.\n'
        '---\nbody`,"examples/a.ts":"x"}}});'
        'function _r(){Z_({name:b,description:"Claude Test",version:g,isAvailable:xe,'
        "skills:Fe,get mcpServers(){return 1},hooksModule:VU(1,I,()=>rt())})}"
        "export{_r as registerPlugin};",
        # Another module's own `Z_` is not the registrar.
        "foreign": 'function Z_(e){return e}var q=Z_({seccompConfig:1,name:"bwrap"});',
    }
    modules.update(swap)
    return list(modules.values())


def _plugins(**swap: str) -> tuple[dict, dict]:
    src = _modules(*_plugin_modules(**swap))
    return inv.extract_builtin_plugins(src, inv.build_brace_map(src))


class TestBuiltinPlugins(unittest.TestCase):
    def test_every_registration_is_found_by_the_registrar_body(self) -> None:
        plugins, notes = _plugins()
        self.assertEqual(
            sorted(plugins),
            [
                "cc-plugin-agents-md",
                "cc-plugin-claude-test",
                "cc-plugin-mermaid",
                "cc-plugin-sec-default",
                "cc-plugin-tips",
            ],
        )
        self.assertEqual(notes["registrars"], ["Z_"])
        self.assertEqual(notes["factory_registrations"], 1)
        self.assertEqual(notes["loader_callees"], ["Xue"])
        self.assertEqual(notes["loaded_not_registered"], [])
        self.assertNotIn("unresolved_names", notes)

    def test_id_and_aliases_come_from_the_bundle(self) -> None:
        rec = _plugins()[0]["cc-plugin-mermaid"]
        self.assertEqual(rec["id"], "cc-plugin-mermaid@builtin")
        self.assertEqual(rec["aliases"], ["mermaid"])

    def test_load_conditions_follow_the_loader_statements(self) -> None:
        plugins = _plugins()[0]
        self.assertEqual(plugins["cc-plugin-sec-default"]["load"], "unconditional")
        self.assertEqual(plugins["cc-plugin-sec-default"]["load_guards"], [])
        entry = 'a.CLAUDE_CODE_ENTRYPOINT!=="local-agent"'
        self.assertEqual(plugins["cc-plugin-mermaid"]["load_guards"], [entry])
        self.assertEqual(plugins["cc-plugin-tips"]["load_guards"], [entry, "!c7r()"])
        # `if(i)` reads the declaration `let i=...`.
        self.assertEqual(
            plugins["cc-plugin-claude-test"]["load_guards"], [entry + "&&!c7r()"]
        )

    def test_an_else_branch_leaves_every_load_unresolved(self) -> None:
        loader = _plugin_modules()[1].replace(
            '"/$bunfs/root/c5.js"))}', '"/$bunfs/root/c5.js"));else f()}'
        )
        plugins = _plugins(loader=loader)[0]
        self.assertIsNone(plugins["cc-plugin-sec-default"]["load"])
        self.assertIsNone(plugins["cc-plugin-sec-default"]["load_guards"])

    def test_a_spread_descriptor_supplies_the_fields(self) -> None:
        rec = _plugins()[0]["cc-plugin-mermaid"]
        self.assertEqual(rec["description"], "Mermaid in the terminal")
        self.assertIs(rec["default_enabled"], False)
        self.assertEqual(rec["default_enabled_source"], "literal")
        self.assertEqual(
            rec["gate_flags"], [{"flag": "tengu_mermaid_mod", "default": False}]
        )
        self.assertEqual(rec["hook_events"], ["ui.render"])
        self.assertEqual(rec["partial"], [])

    def test_a_module_constant_far_ahead_resolves_the_name(self) -> None:
        rec = _plugins()[0]["cc-plugin-agents-md"]
        self.assertEqual(rec["name_source"], "constant")
        self.assertEqual(rec["description"], "AGENTS.md as project instructions")
        self.assertIs(rec["default_enabled"], True)
        self.assertEqual(rec["default_enabled_source"], "absent-default")
        self.assertEqual(
            rec["gate_flags"], [{"flag": "tengu_agents_md_mod", "default": True}]
        )
        self.assertTrue(rec["user_config"])
        self.assertEqual(rec["hook_events"], [])

    def test_the_default_is_unresolved_without_the_consumer_rule(self) -> None:
        registrar = _plugin_modules()[0].replace("n.defaultEnabled??!0", "n.x")
        rec = _plugins(registrar=registrar)[0]["cc-plugin-agents-md"]
        self.assertIsNone(rec["default_enabled"])
        self.assertIn("default_enabled", rec["partial"])

    def test_policy_flags_are_read_as_written(self) -> None:
        rec = _plugins()[0]["cc-plugin-sec-default"]
        self.assertIs(rec["enabled_from_policy_only"], True)
        self.assertIs(rec["enabled_from_trusted_settings_only"], True)
        self.assertIs(rec["gated"], False)
        self.assertEqual(rec["hook_events"], ["classic.*", "tool.check"])

    def test_factory_skills_embedded_agents_and_mcp(self) -> None:
        rec = _plugins()[0]["cc-plugin-claude-test"]
        self.assertEqual(rec["version"], "0.4.15")
        self.assertEqual(rec["mcp_servers"], "getter")
        skills = {s["name"]: s for s in rec["skills"]}
        self.assertEqual(sorted(skills), ["claude-test", "claude-test-draft"])
        self.assertEqual(
            skills["claude-test"]["description"], "Check that the web app still works"
        )
        self.assertIs(skills["claude-test"]["user_invocable"], True)
        self.assertIs(skills["claude-test-draft"]["user_invocable"], False)
        self.assertEqual(skills["claude-test"]["source"], "factory")
        self.assertEqual(
            rec["agents"],
            [
                {
                    "name": "author",
                    "name_source": "frontmatter",
                    "description": "Writes spec drafts.",
                    "description_source": "frontmatter",
                    "file": "agents/author.md",
                    "source": "embedded-file",
                }
            ],
        )
        self.assertEqual(rec["partial"], [])

    def test_a_registered_command_resolves_and_a_pass_through_is_skipped(self) -> None:
        rec = _plugins()[0]["cc-plugin-tips"]
        self.assertEqual(
            [(c["name"], c["description"]) for c in rec["commands"]],
            [("diff", "Toggle the diff panel")],
        )
        self.assertEqual(rec["partial"], [])

    def test_an_unresolved_command_argument_leaves_commands_partial(self) -> None:
        tips = _plugin_modules()[5].replace(
            "p.registerCommand(Xo)", "p.registerCommand(zz())"
        )
        rec = _plugins(tips=tips)[0]["cc-plugin-tips"]
        self.assertIn("commands", rec["partial"])

    def test_an_unresolved_spread_marks_absent_fields_unresolved(self) -> None:
        mermaid = _plugin_modules()[4].replace(
            "Z_({...h,", 'Z_({...hh,name:"cc-plugin-mermaid",'
        )
        rec = _plugins(mermaid=mermaid)[0]["cc-plugin-mermaid"]
        self.assertEqual(rec["description_source"], "unresolved")
        self.assertIsNone(rec["default_enabled"])
        self.assertIn("description", rec["partial"])
        self.assertIn("skills", rec["partial"])

    def test_every_field_an_unresolved_spread_hides_is_partial(self) -> None:
        # No isAvailable, hooksModule or manifest of its own: each could sit
        # in the unresolved spread, so each is unknown and named in `partial`.
        agents = _plugin_modules()[3].replace(
            "Z_({name:K,description:H,isAvailable:B,userConfig:ne})",
            "Z_({...zz,name:K,description:H})",
        )
        plugins, notes = _plugins(agents=agents)
        rec = plugins["cc-plugin-agents-md"]
        for key in (
            "gated",
            "hook_events",
            "hooks_module",
            "user_config",
            "classic_hooks",
            "mcp_servers",
            "default_enabled",
        ):
            self.assertIsNone(rec[key], key)
            self.assertIn(key, rec["partial"], key)
        lane = self._integrity(plugins, notes)["lanes"][inv.PLUGIN_LANE]
        self.assertEqual(lane["status"], "degraded")
        self.assertTrue(any("cc-plugin-agents-md" in a for a in lane["advisories"]))

    def test_a_complete_record_reads_absent_keys_as_absent(self) -> None:
        rec = _plugins()[0]["cc-plugin-agents-md"]
        self.assertIs(rec["hooks_module"], False)
        self.assertIs(rec["gated"], True)
        self.assertEqual(rec["hook_events"], [])
        self.assertEqual(rec["partial"], [])

    def test_an_unread_load_position_is_partial(self) -> None:
        loader = _plugin_modules()[1].replace(
            '"/$bunfs/root/c5.js"))}', '"/$bunfs/root/c5.js"));else f()}'
        )
        rec = _plugins(loader=loader)[0]["cc-plugin-sec-default"]
        self.assertIn("load", rec["partial"])

    def _test_module(self, old: str, new: str) -> dict:
        test = _plugin_modules()[6]
        self.assertIn(old, test)
        return _plugins(test=test.replace(old, new))[0]["cc-plugin-claude-test"]

    def test_unresolved_manifest_calls_leave_commands_partial(self) -> None:
        rec = self._test_module('calls:["mcp.connect"]', "calls:QQ")
        self.assertIn("commands", rec["partial"])
        # A manifest that declares no calls at all registers none: absent.
        rec = self._test_module('calls:["mcp.connect"]', 'other:["x"]')
        self.assertNotIn("commands", rec["partial"])

    def test_a_block_scalar_description_is_read(self) -> None:
        rec = self._test_module(
            "description: Writes spec drafts.\n",
            "description: >\n  Writes spec\n  drafts.\n",
        )
        self.assertEqual(rec["agents"][0]["description"], "Writes spec drafts.")
        self.assertNotIn("agents", rec["partial"])

    def test_an_unparsed_embedded_description_leaves_its_kind_partial(self) -> None:
        rec = self._test_module(
            "description: Writes spec drafts.\n", "description: {a: b}\n"
        )
        self.assertEqual(rec["agents"][0]["description_source"], "unresolved")
        self.assertIn("agents", rec["partial"])

    def test_an_embedded_file_without_a_frontmatter_name_is_partial(self) -> None:
        rec = self._test_module("name: author\n", "")
        self.assertEqual(rec["agents"][0]["name_source"], "file-name")
        self.assertIn("agents", rec["partial"])

    def test_a_non_literal_files_entry_leaves_every_file_kind_partial(self) -> None:
        rec = self._test_module('"examples/a.ts":"x"', '[pathOf()]:"x"')
        for kind in ("agents", "commands", "skills"):
            self.assertIn(kind, rec["partial"])

    def test_a_non_literal_files_value_leaves_every_file_kind_partial(self) -> None:
        rec = self._test_module(
            'files:{"agents/author.md":',
            'files:F,x:{"agents/author.md":',
        )
        self.assertEqual(rec["agents"], [])
        for kind in ("agents", "commands", "skills"):
            self.assertIn(kind, rec["partial"])

    def test_an_inline_skill_with_an_unevaluable_description_is_partial(self) -> None:
        authoring = (
            'import{Z_}from"/$bunfs/root/chunk-r.js";'
            'var f=Object.freeze({name:"plugin-authoring",description:helper(),'
            "userInvocable:!0});"
            'Z_({name:"cc-plugin-plugin-authoring",description:"Plugin authoring",'
            "skills:[f]});"
        )
        plugins = _plugins(authoring=authoring)[0]
        rec = plugins["cc-plugin-plugin-authoring"]
        self.assertEqual(rec["skills"][0]["description_source"], "unresolved")
        self.assertIn("skills", rec["partial"])

    def test_a_hooks_module_without_a_readable_manifest_is_partial(self) -> None:
        tips = _plugin_modules()[5].replace(
            'var m=v(function(a,b){b.exports={scan:{hooks:["ui.render"],'
            'calls:["command.register"]},files:{}}});',
            "",
        )
        rec = _plugins(tips=tips)[0]["cc-plugin-tips"]
        for key in ("hook_events", "agents", "commands"):
            self.assertIn(key, rec["partial"])

    def test_an_unread_gate_or_flag_default_is_partial(self) -> None:
        rec = self._test_module("isAvailable:xe,", "isAvailable:yy,")
        self.assertIsNone(rec["gate_flags"])
        self.assertIn("gate_flags", rec["partial"])
        rec = self._test_module(
            'lo("tengu_mellow_hollerith",!1)', 'lo("tengu_mellow_hollerith",q())'
        )
        self.assertEqual(
            rec["gate_flags"], [{"flag": "tengu_mellow_hollerith", "default": None}]
        )
        self.assertIn("gate_flags", rec["partial"])

    def test_a_present_but_unresolved_description_is_partial(self) -> None:
        rec = self._test_module('description:"Claude Test",', "description:qq(),")
        self.assertEqual(rec["description_source"], "unresolved")
        self.assertIn("description", rec["partial"])

    def test_an_unresolved_skill_or_command_description_is_partial(self) -> None:
        rec = self._test_module(
            'Object.freeze({description:"Drafts spec files"})',
            "Object.freeze({description:qq()})",
        )
        self.assertIn("skills", rec["partial"])
        tips = _plugin_modules()[5].replace(
            'description:"Toggle the diff panel"', "description:qq()"
        )
        self.assertIn("commands", _plugins(tips=tips)[0]["cc-plugin-tips"]["partial"])

    def test_an_unresolved_marketplace_leaves_the_id_partial(self) -> None:
        registrar = _plugin_modules()[0].replace('var _i="builtin";', "")
        plugins, notes = _plugins(registrar=registrar)
        rec = plugins["cc-plugin-tips"]
        self.assertIsNone(rec["id"])
        self.assertIn("id", rec["partial"])
        lane = self._integrity(plugins, notes)["lanes"][inv.PLUGIN_LANE]
        self.assertEqual(lane["status"], "degraded")

    def test_a_duplicate_registration_degrades_the_lane(self) -> None:
        tips = _plugin_modules()[5] + 'Z_({name:"cc-plugin-tips",description:"again"});'
        plugins, notes = _plugins(tips=tips)
        self.assertEqual(notes["duplicate_registrations"], ["cc-plugin-tips"])
        self.assertIn("registration", plugins["cc-plugin-tips"]["partial"])
        lane = self._integrity(plugins, notes)["lanes"][inv.PLUGIN_LANE]
        self.assertEqual(lane["status"], "degraded")

    # Final-round verifier repros. Each is the simplest fail-closed reading.

    def _loader(self, before: str) -> dict:
        """The plugins with `before` inserted ahead of the loader's first call."""
        loader = _plugin_modules()[1].replace(
            "if(e.builtinPluginsInitialized=!0,",
            before + "if(e.builtinPluginsInitialized=!0,",
        )
        return _plugins(loader=loader)[0]

    def test_an_early_exit_with_a_value_or_throw_guards_later_calls(self) -> None:
        for exit_ in ("return!1;", "throw Error();", "{f();return}"):
            rec = self._loader(f"if(gate()){exit_}")["cc-plugin-sec-default"]
            self.assertEqual(rec["load"], "conditional", exit_)
            self.assertEqual(rec["load_guards"], ["!(gate())"], exit_)

    def test_an_unrecognized_exit_leaves_later_loads_partial(self) -> None:
        rec = self._loader("if(gate()){if(x())return;f()}")["cc-plugin-sec-default"]
        self.assertIsNone(rec["load"])
        self.assertIn("load", rec["partial"])

    def test_a_compound_latch_test_leaves_later_loads_partial(self) -> None:
        loader = _plugin_modules()[1].replace(
            "if(e.builtinPluginsInitialized)return;",
            "if(off()||e.builtinPluginsInitialized)return;",
        )
        rec = _plugins(loader=loader)[0]["cc-plugin-sec-default"]
        self.assertIsNone(rec["load"])
        self.assertIn("load", rec["partial"])

    def test_a_key_before_an_unresolved_spread_is_not_trusted(self) -> None:
        mermaid = _plugin_modules()[4].replace(
            "Z_({...h,",
            'Z_({...h,defaultEnabled:!1,...unk,name:"cc-plugin-mermaid",',
        )
        rec = _plugins(mermaid=mermaid)[0]["cc-plugin-mermaid"]
        # defaultEnabled sits before `...unk`, which may override it.
        self.assertIsNone(rec["default_enabled"])
        self.assertIn("default_enabled", rec["partial"])
        # hooksModule after the last unresolved spread stays read.
        self.assertIs(rec["hooks_module"], True)

    def test_a_name_before_an_unresolved_spread_leaves_the_registration_unresolved(
        self,
    ) -> None:
        mermaid = _plugin_modules()[4].replace(
            "Z_({...h,", 'Z_({name:"cc-plugin-mermaid",...hh,'
        )
        plugins, notes = _plugins(mermaid=mermaid)
        self.assertNotIn("cc-plugin-mermaid", plugins)
        self.assertTrue(notes["unresolved_names"])

    def test_a_substitution_in_an_embedded_file_leaves_its_kind_partial(self) -> None:
        rec = self._test_module("name: author\n", "name: ${N}\n")
        self.assertIn("agents", rec["partial"])
        self.assertNotIn("…", rec["agents"][0]["name"])

    def test_a_multi_line_plain_scalar_description_is_folded(self) -> None:
        rec = self._test_module(
            "description: Writes spec drafts.\n",
            "description: Writes spec\n  drafts for the app.\n",
        )
        self.assertEqual(
            rec["agents"][0]["description"], "Writes spec drafts for the app."
        )
        self.assertNotIn("agents", rec["partial"])

    def test_a_spread_in_the_manifest_declaration_is_unresolved(self) -> None:
        rec = self._test_module("scan:{hooks:", "scan:{...base,hooks:")
        self.assertIsNone(rec["hook_events"])
        self.assertIn("hook_events", rec["partial"])
        self.assertIn("commands", rec["partial"])

    def test_the_marketplace_comes_from_the_registry_walk_only(self) -> None:
        registrar = _plugin_modules()[0].replace(
            "function ro(){return S}",
            'function ro(){return S}var V="1.0.0";function ver(n){return`${n}@${V}`}',
        )
        rec = _plugins(registrar=registrar)[0]["cc-plugin-tips"]
        self.assertEqual(rec["id"], "cc-plugin-tips@builtin")
        registrar = registrar.replace("`${t}@${_i}`", "t")
        rec = _plugins(registrar=registrar)[0]["cc-plugin-tips"]
        self.assertIsNone(rec["id"])
        self.assertIn("id", rec["partial"])

    def test_a_hooks_module_without_a_manifest_leaves_skills_partial(self) -> None:
        tips = _plugin_modules()[5].replace(
            'var m=v(function(a,b){b.exports={scan:{hooks:["ui.render"],'
            'calls:["command.register"]},files:{}}});',
            "",
        )
        self.assertIn("skills", _plugins(tips=tips)[0]["cc-plugin-tips"]["partial"])

    def test_a_quoted_or_computed_plugin_key_is_an_unresolved_read(self) -> None:
        for key in ('"defaultEnabled":!1', "[K]:!1", "isAvailable"):
            agents = _plugin_modules()[3].replace(
                "Z_({name:K,description:H,isAvailable:B,userConfig:ne})",
                f"Z_({{{key},name:K,description:H,isAvailable:B}})",
            )
            rec = _plugins(agents=agents)[0]["cc-plugin-agents-md"]
            self.assertIsNone(rec["default_enabled"], key)
            self.assertIn("default_enabled", rec["partial"], key)
            self.assertIsNone(rec["user_config"], key)

    def test_a_quoted_or_computed_manifest_key_is_unresolved(self) -> None:
        for decl in ('scan:{"hooks":["command.run"],', 'scan:{[K]:["command.run"],'):
            rec = self._test_module('scan:{hooks:["command.run"],', decl)
            self.assertIsNone(rec["hook_events"], decl)
            self.assertIn("hook_events", rec["partial"], decl)

    def test_the_default_rule_is_read_only_where_the_registry_is_walked(self) -> None:
        # The real rule removed from the walk; a decoy elsewhere in the bundle.
        registrar = _plugin_modules()[0].replace("n.defaultEnabled??!0", "n.x")
        decoy = "function other(o){return o.defaultEnabled??!0}"
        plugins, notes = _plugins(registrar=registrar, decoy=decoy)
        self.assertFalse(notes["default_enabled_rule_found"])
        rec = plugins["cc-plugin-agents-md"]
        self.assertIsNone(rec["default_enabled"])
        self.assertIn("default_enabled", rec["partial"])
        # Two disagreeing defaults in the walk are ambiguous, not true.
        registrar = _plugin_modules()[0].replace(
            "a=n.defaultEnabled??!0", "a=n.defaultEnabled??!0,b=n.defaultEnabled??!1"
        )
        self.assertIsNone(
            _plugins(registrar=registrar)[0]["cc-plugin-agents-md"]["default_enabled"]
        )

    def test_no_registrar_is_an_error(self) -> None:
        registrar = _plugin_modules()[0].replace(".builtinPlugins.set(", ".other.set(")
        plugins, notes = _plugins(registrar=registrar)
        self.assertEqual(plugins, {})
        self.assertIn("error", notes)

    def _integrity(self, plugins: dict, notes: dict) -> dict:
        src = f'"{inv.VALIDATED_AGAINST}";' * 30 + "".join(
            f'x{i}={{type:"local",name:"{n}",description:"d"}};'
            for i, n in enumerate(inv.CANARY_COMMANDS)
        )
        return inv.check_integrity(
            src,
            inv.extract_builtin_commands(src, inv.build_brace_map(src)),
            {"a": {}},
            {"registrations_seen": 1, "resolved": 1},
            {"security-review": "x"},
            plugins=plugins,
            plugin_notes=notes,
        )

    def test_the_lane_is_ok_when_everything_resolves(self) -> None:
        got = self._integrity(*_plugins())
        self.assertEqual(got["lanes"][inv.PLUGIN_LANE]["status"], "ok")
        self.assertEqual(got["status"], "ok")

    def test_a_missing_canary_breaks_the_lane_only(self) -> None:
        plugins, notes = _plugins()
        del plugins["cc-plugin-sec-default"]
        got = self._integrity(plugins, notes)
        self.assertEqual(got["lanes"][inv.PLUGIN_LANE]["status"], "broken")
        self.assertEqual(got["status"], "degraded")

    def test_a_partial_plugin_or_a_missing_loader_degrades_the_lane(self) -> None:
        plugins, notes = _plugins()
        plugins["cc-plugin-tips"]["partial"] = ["commands"]
        got = self._integrity(plugins, {**notes, "loader_found": False})
        lane = got["lanes"][inv.PLUGIN_LANE]
        self.assertEqual(lane["status"], "degraded")
        self.assertEqual(len(lane["advisories"]), 2)

    def test_a_registration_the_loader_never_requires_degrades_the_lane(self) -> None:
        loader = _plugin_modules()[1].replace(
            'if(i)Xue("cc-plugin-claude-test",()=>import.meta.require("/$bunfs/root/c5.js"))',
            "",
        )
        plugins, notes = _plugins(loader=loader)
        # The test-seat registration (`name:r`) is a factory, never listed here.
        self.assertEqual(notes["registered_not_loaded"], ["cc-plugin-claude-test"])
        self.assertEqual(notes["factory_registrations"], 1)
        self.assertIs(plugins["cc-plugin-claude-test"]["in_loader"], False)
        self.assertIs(plugins["cc-plugin-tips"]["in_loader"], True)
        lane = self._integrity(plugins, notes)["lanes"][inv.PLUGIN_LANE]
        self.assertEqual(lane["status"], "degraded")
        self.assertTrue(any("never requires" in a for a in lane["advisories"]))

    def test_without_a_loader_nothing_is_registered_not_loaded(self) -> None:
        loader = _plugin_modules()[1].replace("builtinPluginsInitialized=!0", "x=!0")
        plugins, notes = _plugins(loader=loader)
        self.assertEqual(notes["registered_not_loaded"], [])
        self.assertIsNone(plugins["cc-plugin-tips"]["in_loader"])

    def test_a_loaded_plugin_without_a_registration_degrades_the_lane(self) -> None:
        test = _plugin_modules()[6].replace("Z_({name:b,", "Y_({name:b,")
        plugins, notes = _plugins(test=test)
        self.assertEqual(notes["loaded_not_registered"], ["cc-plugin-claude-test"])
        got = self._integrity(plugins, notes)
        self.assertEqual(got["lanes"][inv.PLUGIN_LANE]["status"], "degraded")


class TestBuiltinPluginState(unittest.TestCase):
    PLUGINS = {
        "cc-plugin-diff": {
            "id": "cc-plugin-diff@builtin",
            "default_enabled": True,
            "gate_flags": [{"flag": "tengu_quiet_dolphin", "default": True}],
        },
        "cc-plugin-mermaid": {
            "id": "cc-plugin-mermaid@builtin",
            "default_enabled": True,
            "gate_flags": [{"flag": "tengu_mermaid_mod", "default": False}],
        },
    }

    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.home = pathlib.Path(tmp.name)
        self.root = self.home / ".claude"
        self.project = self.home / "repo"
        (self.project / ".claude").mkdir(parents=True)
        self.root.mkdir()
        home = mock.patch.object(inv.Path, "home", return_value=self.home)
        home.start()
        self.addCleanup(home.stop)

    def write(self, path: pathlib.Path, data: object) -> None:
        path.write_text(json.dumps(data), encoding="utf-8")

    def state(self, root: pathlib.Path | None = None, custom: bool = False) -> dict:
        return inv.builtin_plugin_state(
            self.PLUGINS, root or self.root, self.project, True, custom
        )

    def test_cached_flag_values_sit_beside_each_default(self) -> None:
        self.write(
            self.home / ".claude.json",
            {
                "cachedGrowthBookFeatures": {
                    "tengu_quiet_dolphin": False,
                    "tengu_plugin_hooks_modules": True,
                }
            },
        )
        got = self.state()
        self.assertEqual(
            got["plugins"]["cc-plugin-diff"]["gate_flags"],
            [
                {
                    "flag": "tengu_quiet_dolphin",
                    "default": True,
                    "cached": False,
                    "cached_present": True,
                }
            ],
        )
        # An absent key means the in-binary default applies, not "false".
        mermaid = got["plugins"]["cc-plugin-mermaid"]["gate_flags"][0]
        self.assertEqual((mermaid["cached"], mermaid["cached_present"]), (None, False))
        self.assertEqual(
            got["mods_flag"],
            {
                "flag": "tengu_plugin_hooks_modules",
                "in_bundle": True,
                "cached": True,
                "cached_present": True,
            },
        )
        self.assertTrue(any("pinnedFeatureValues" in c for c in got["caveats"]))

    def test_a_custom_config_dir_holds_its_own_global_config(self) -> None:
        self.write(self.home / ".claude.json", {"cachedGrowthBookFeatures": {}})
        self.write(
            self.root / ".claude.json",
            {"cachedGrowthBookFeatures": {"tengu_mermaid_mod": True}},
        )
        got = self.state(custom=True)
        self.assertEqual(got["global_config"], str(self.root / ".claude.json"))
        self.assertTrue(got["plugins"]["cc-plugin-mermaid"]["gate_flags"][0]["cached"])

    def test_a_custom_config_dir_never_reads_its_parent(self) -> None:
        # `${CLAUDE_CONFIG_DIR:-$HOME}/.claude.json`: a custom dir with no
        # global config of its own has none, whatever sits beside it.
        custom = self.home / "profiles" / "work"
        custom.mkdir(parents=True)
        self.write(
            custom.parent / ".claude.json",
            {"cachedGrowthBookFeatures": {"tengu_mermaid_mod": True}},
        )
        got = self.state(root=custom, custom=True)
        self.assertFalse(got["flag_cache_read"])
        self.assertIsNone(got["global_config"])

    def test_the_default_config_dir_reads_home(self) -> None:
        self.write(self.root / ".claude.json", {"cachedGrowthBookFeatures": {}})
        self.write(
            self.home / ".claude.json",
            {"cachedGrowthBookFeatures": {"tengu_mermaid_mod": True}},
        )
        got = self.state()
        self.assertEqual(got["global_config"], str(self.home / ".claude.json"))
        self.assertTrue(got["plugins"]["cc-plugin-mermaid"]["gate_flags"][0]["cached"])

    def test_a_non_boolean_value_voids_that_files_enabled_plugins(self) -> None:
        pid = "cc-plugin-mermaid@builtin"
        self.write(self.root / "settings.json", {"enabledPlugins": {pid: True}})
        self.write(
            self.project / ".claude" / "settings.json",
            {"enabledPlugins": {pid: False, "other@m": "yes"}},
        )
        got = self.state()
        self.assertEqual(got["enabled_plugins_rejected"], {"project": ["other@m"]})
        mermaid = got["plugins"]["cc-plugin-mermaid"]
        self.assertEqual(mermaid["enabled_overrides"], {"user": True})
        self.assertIs(mermaid["enabled_setting"], True)

    def test_no_flag_cache_is_unknown_not_absent(self) -> None:
        got = self.state()
        self.assertFalse(got["flag_cache_read"])
        self.assertIsNone(got["global_config"])
        flag = got["plugins"]["cc-plugin-diff"]["gate_flags"][0]
        self.assertIsNone(flag["cached_present"])

    def test_local_settings_win_over_project_and_user(self) -> None:
        pid = "cc-plugin-mermaid@builtin"
        self.write(self.root / "settings.json", {"enabledPlugins": {pid: True}})
        self.write(
            self.project / ".claude" / "settings.json",
            {"enabledPlugins": {pid: False}},
        )
        self.write(
            self.project / ".claude" / "settings.local.json",
            {"enabledPlugins": {pid: True}},
        )
        got = self.state()
        mermaid = got["plugins"]["cc-plugin-mermaid"]
        self.assertEqual(
            mermaid["enabled_overrides"],
            {"user": True, "project": False, "local": True},
        )
        self.assertIs(mermaid["enabled_setting"], True)
        self.assertEqual(got["settings_read"], ["local", "project", "user"])
        diff = got["plugins"]["cc-plugin-diff"]
        self.assertEqual(diff["enabled_overrides"], {})
        self.assertIsNone(diff["enabled_setting"])

    def test_project_beats_user_when_local_is_silent(self) -> None:
        pid = "cc-plugin-diff@builtin"
        self.write(self.root / "settings.json", {"enabledPlugins": {pid: True}})
        self.write(
            self.project / ".claude" / "settings.json",
            {"enabledPlugins": {pid: False}},
        )
        self.assertIs(
            self.state()["plugins"]["cc-plugin-diff"]["enabled_setting"], False
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
