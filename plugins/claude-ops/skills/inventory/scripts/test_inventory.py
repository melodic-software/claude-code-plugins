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
        import tempfile

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
            + 'eo({name:e,menuDescription:"D"});'
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
            + 'eo({name:r,menuDescription:"Draft"});'
        )
        skills, _ = self._skills(src)
        self.assertIn("design", skills)

    def test_a_long_identifier_bound_far_ahead_resolves(self) -> None:
        src = (
            self.HEAD
            + 'var kYe="simplify";'
            + "z" * (inv.SHORT_IDENT_LOCALITY_BYTES * 2)
            + 'eo({name:kYe,menuDescription:"Clean up"});'
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
        import tempfile

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


if __name__ == "__main__":
    unittest.main(verbosity=2)
