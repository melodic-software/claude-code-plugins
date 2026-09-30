#!/usr/bin/env python3
"""Deterministic tests for the inventory extractor.

Every case runs against a synthetic minified fragment rather than a real
Claude Code build, so the suite is fast, hermetic, and does not change its
verdict when the installed CLI updates. The fragments reproduce the shapes
observed in a real bundle, including the ones that broke earlier drafts.

Run: python3 test_inventory.py
"""

from __future__ import annotations

import pathlib
import tempfile
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
            '{name:"alias",description:"Create or list command aliases",'
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
            + f'"{inv.VALIDATED_AGAINST}"' * 30
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
            + f'"{inv.VALIDATED_AGAINST}"' * 30
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
            + f'"{inv.VALIDATED_AGAINST}"' * 30
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
        src = self._src("export{zz as registerSomethingNewSkill};")
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
        src = self._src() + 'type:"local"' * 200
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
        src = "export{eo as registerBundledSkill};" + self.CANARY
        _, notes = inv.extract_bundled_skills(src, inv.build_brace_map(src))
        self.assertEqual(notes["registrar_route"], "esm-export")


class TestNameLocality(unittest.TestCase):
    """Computed names resolve by locality, never by a single global value."""

    HEAD = "export{eo as registerBundledSkill};"

    def _skills(self, src: str) -> tuple[dict, dict]:
        return inv.extract_bundled_skills(src, inv.build_brace_map(src))

    def test_nearest_preceding_binding_wins_over_a_farther_one(self) -> None:
        # The phantom this guards: `oO="ehrpd"` in an unrelated module far
        # ahead must not shadow `oO="artifact-design"` bound closer in.
        src = (
            self.HEAD
            + 'var oO="ehrpd";'
            + "z" * 500
            + 'var oO="artifact-design";'
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
    HEAD = "export{eo as registerBundledSkill};"
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

    def test_no_roster_leaves_every_agent_absent(self) -> None:
        agents, notes = self._extract(AGENT_SRC.split("function R()")[0])
        self.assertFalse(notes["roster_found"])
        self.assertEqual({a["roster"] for a in agents.values()}, {"absent"})


TOOL_SRC = (
    'var Qz="Bash",at="Read",xt="Edit",hn="Write",wr="WebFetch";'
    'var k1="SendUserFile";var m1="memory_read";'
    "var Kl={isEnabled:()=>!0,isConcurrencySafe:(e)=>!1};"
    'k1="system_assigned_identity";'
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
        # unrelated modules rebind minified names; a snake_case value is taken
        # only when no PascalCase binding precedes (`m1`).
        tools = self._extract()[0]
        self.assertIn("SendUserFile", tools)
        self.assertIn("memory_read", tools)
        self.assertNotIn("system_assigned_identity", tools)

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
        index = {"e": [(0, "Bash")]}
        self.assertIsNone(
            inv.resolve_tool_ident("e", inv.SHORT_IDENT_LOCALITY_BYTES + 10, index)
        )
        self.assertEqual(inv.resolve_tool_ident("e", 10, index), "Bash")


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

    def test_a_later_binding_resolves_only_inside_a_function_body(self) -> None:
        src = _modules(
            'var Qz="Probe",Pz="Lazy";'
            "$t({name:Qz,maxResultSizeChars:1,description:zz});"
            "$t({name:Pz,maxResultSizeChars:1,async description(){return zz}});"
            'var zz="later";'
        )
        self.assertEqual(_tool(src, "Probe")["description_source"], "unresolved")
        self.assertEqual(_tool(src, "Lazy")["description"], "later")

    def test_an_eager_call_does_not_read_a_later_binding(self) -> None:
        src = _modules(
            'var Qz="Probe";function dd(){return zz}'
            "$t({name:Qz,maxResultSizeChars:1,description:dd()});"
            'var zz="later";'
        )
        self.assertEqual(_tool(src, "Probe")["description_source"], "unresolved")

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

    def test_a_truncated_response_degrades_instead_of_raising(self) -> None:
        import http.client
        import urllib.request
        from unittest import mock

        class Truncated:
            def __enter__(self):
                return self

            def __exit__(self, *exc):
                return False

            def read(self, _n):
                raise http.client.IncompleteRead(b"partial")

        with mock.patch.object(urllib.request, "urlopen", return_value=Truncated()):
            body, error = self.dc.fetch_text("https://example.invalid/x")
        self.assertIsNone(body)
        self.assertIn("IncompleteRead", error or "")

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

    def _run(self, fetched: dict, **kw) -> dict:
        original = self.dc.fetch_text
        self.dc.fetch_text = lambda url, timeout=20.0: fetched.get(
            url, (None, "URLError: offline")
        )
        try:
            return self.dc.build_crosscheck(_report(), **kw)
        finally:
            self.dc.fetch_text = original

    def test_network_failure_degrades_only_the_block(self) -> None:
        block = self._run({})
        self.assertEqual(block["status"], "unavailable")
        self.assertIn("URLError", block["problems"][0])
        self.assertNotIn("names", block)

    def test_changelog_failure_is_degraded_not_fabricated(self) -> None:
        block = self._run({self.dc.COMMANDS_URL: (DOCS, None)})
        self.assertEqual(block["status"], "degraded")
        self.assertIsNone(block["names"]["add-dir"]["changelog"])
        self.assertEqual(block["counts"]["removed_in_docs"], 1)

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


if __name__ == "__main__":
    unittest.main(verbosity=2)
