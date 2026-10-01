#!/usr/bin/env python3
"""Every JavaScript fixture test_inventory.py feeds the reader parses as a
module under acorn.

A parser-backed reader (#5640) reads only what parses, so a fixture that is
not valid JavaScript tests a shape no real bundle has. The fixtures are
collected by running test_inventory.py with `inventory.build_brace_map`
wrapped: every extraction builds the brace map from its source first, so
the wrapper sees exactly the text each test hands the reader, including
text a test assembles in a loop.

Fixtures known not to parse are listed in KNOWN_UNPARSEABLE by test id, for
P2 to rewrite; the check fails when a new one appears or a listed one starts
parsing, so the list stays exact.

Needs `node` and an `acorn` package that `require("acorn")` resolves (set
NODE_PATH to its node_modules directory, e.g. after
`npm install --prefix <dir> acorn@8`); otherwise the check skips.

Run: python3 -m unittest test_fixture_parse
"""

from __future__ import annotations

import json
import re
import shutil
import subprocess
import tempfile
import unittest

import inventory as inv
import test_inventory

PARSE_JS = r"""
const acorn = require("acorn");
const fixtures = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
const failed = [];
for (const [i, src] of fixtures.entries()) {
  try {
    acorn.parse(src, { ecmaVersion: "latest", sourceType: "module" });
  } catch (e) {
    failed.push([i, e.message]);
  }
}
process.stdout.write(JSON.stringify({ acorn: acorn.version, failed }));
"""

# Four shapes, all fixture shortcuts no real bundle has: an `export{eo as ...}`
# header with no `eo` declared; `z` padding run straight into the next
# token (`zzz…function f`); the version anchor repeated as adjacent string
# literals (`"2.1.287""2.1.287"`); and a bare object literal as a statement.
KNOWN_UNPARSEABLE: frozenset[str] = frozenset(
    {
        "TestAgentAndToolIntegrity.test_a_missing_canary_breaks_only_that_lane",
        "TestAgentAndToolIntegrity.test_an_empty_lane_is_broken",
        "TestAgentAndToolIntegrity.test_both_lanes_ok",
        "TestAgentAndToolIntegrity.test_factories_do_not_degrade",
        "TestAgentAndToolIntegrity.test_lanes_absent_when_not_extracted",
        "TestAgentAndToolIntegrity.test_unresolved_names_and_a_missing_roster_degrade",
        "TestBundledWorkflows.test_lane_breaks_on_a_missing_canary_and_others_stand",
        "TestBundledWorkflows.test_lane_ok_with_the_canary",
        "TestCommandExtraction.test_a_name_bound_to_a_conditional_is_not_resolved",
        "TestCommandExtraction.test_shell_builtin_is_not_a_command",
        "TestIntegrity.test_canary_missing_breaks_the_builtin_lane_only",
        "TestIntegrity.test_degraded_on_unknown_registrar",
        "TestIntegrity.test_degraded_when_registrations_exceed_resolved",
        "TestIntegrity.test_dynamic_roster_is_an_advisory_not_an_unresolved_name",
        "TestIntegrity.test_esm_export_list_feeds_the_registrar_advisory",
        "TestIntegrity.test_every_lane_broken_is_broken",
        "TestIntegrity.test_low_yield_breaks_the_builtin_lane",
        "TestIntegrity.test_missing_plugin_backed_canary_breaks_that_lane",
        "TestIntegrity.test_no_skills_breaks_the_bundled_lane_only",
        "TestIntegrity.test_ok_when_everything_resolves",
        "TestIntegrity.test_registrations_below_the_floor_degrade_the_bundled_lane",
        "TestInvocationFieldsAndCollisions.test_a_flag_driven_twin_of_a_constant_field_is_a_collision",
        "TestInvocationFieldsAndCollisions.test_a_function_valued_field_reads_as_true_and_flag_driven",
        "TestInvocationFieldsAndCollisions.test_invocation_fields_are_read_when_present",
        "TestInvocationFieldsAndCollisions.test_the_same_registration_seen_twice_is_not_a_collision",
        "TestInvocationFieldsAndCollisions.test_two_registrations_sharing_a_name_are_both_kept",
        "TestNameLocality.test_a_binding_after_the_registration_does_not_resolve_it",
        "TestNameLocality.test_a_descriptor_member_name_resolves",
        "TestNameLocality.test_a_function_whose_name_ends_in_the_registrar_is_not_a_call",
        "TestNameLocality.test_a_lone_far_binding_of_a_short_identifier_is_not_resolved",
        "TestNameLocality.test_a_long_identifier_bound_far_ahead_resolves",
        "TestNameLocality.test_a_loop_over_a_literal_table_is_enumerated",
        "TestNameLocality.test_a_loop_registration_is_a_dynamic_roster",
        "TestNameLocality.test_a_nearer_non_constant_binding_shadows_a_constant",
        "TestNameLocality.test_a_same_identifier_call_without_a_name_is_not_a_registration",
        "TestNameLocality.test_a_short_identifier_bound_nearby_resolves",
        "TestNameLocality.test_a_template_literal_name_is_a_dynamic_roster",
        "TestNameLocality.test_nearest_preceding_binding_wins_over_a_farther_one",
        "TestRegistrarRoutes.test_route_is_recorded_in_the_notes",
    }
)


def collect_fixtures() -> dict[str, set[str]]:
    """Each distinct source test_inventory passes the reader, mapped to the
    ids of the tests that passed it."""
    seen: dict[str, set[str]] = {}
    current = [""]
    original = inv.build_brace_map

    def recording(src: str, *args, **kwargs):
        seen.setdefault(src, set()).add(current[0])
        return original(src, *args, **kwargs)

    class Result(unittest.TestResult):
        def startTest(self, test: unittest.TestCase) -> None:
            current[0] = test.id().removeprefix("test_inventory.")
            super().startTest(test)

    suite = unittest.defaultTestLoader.loadTestsFromModule(test_inventory)
    inv.build_brace_map = recording
    try:
        result = Result()
        suite.run(result)
    finally:
        inv.build_brace_map = original
    if result.errors or result.failures:
        raise AssertionError(
            "test_inventory must pass before its fixtures are checked: "
            + "; ".join(t.id() for t, _ in result.errors + result.failures)
        )
    return seen


def modules(src: str) -> list[str]:
    """`src` split into its modules at each `// @bun` header, the unit a real
    bundle is parsed in: concatenated modules repeat top-level names."""
    starts = [0] + [m.start() for m in re.finditer("\n// @bun", src) if m.start()]
    return [src[a:b] for a, b in zip(starts, starts[1:] + [len(src)])]


def _acorn_skip_reason() -> str | None:
    node = shutil.which("node")
    if node is None:
        return "node is not on PATH"
    probe = subprocess.run(
        [node, "-e", 'require("acorn")'], capture_output=True, text=True, check=False
    )
    if probe.returncode != 0:
        return 'node cannot require("acorn"); set NODE_PATH to a node_modules holding acorn@8'
    return None


def unparseable(fixtures: list[str]) -> tuple[str, list[tuple[int, str]]]:
    """Acorn's version, and (index, error) for each fixture that fails."""
    with tempfile.NamedTemporaryFile("w", suffix=".json", encoding="utf-8") as fh:
        json.dump(fixtures, fh)
        fh.flush()
        run = subprocess.run(
            ["node", "-e", PARSE_JS, fh.name],
            capture_output=True,
            text=True,
            check=True,
        )
    out = json.loads(run.stdout)
    return out["acorn"], [tuple(f) for f in out["failed"]]


class TestFixturesParse(unittest.TestCase):
    def test_every_fixture_parses_as_a_module(self) -> None:
        reason = _acorn_skip_reason()
        if reason:
            self.skipTest(reason)
        seen = collect_fixtures()
        owners: dict[str, set[str]] = {}
        for src, tests in seen.items():
            for module in modules(src):
                owners.setdefault(module, set()).update(tests)
        fixtures = sorted(owners)
        _, failed = unparseable(fixtures)
        bad_tests: dict[str, list[str]] = {}
        for i, error in failed:
            for test in owners[fixtures[i]]:
                bad_tests.setdefault(test, []).append(error)
        lines = [f"{t}: {'; '.join(e)}" for t, e in sorted(bad_tests.items())]
        self.assertEqual(
            sorted(bad_tests), sorted(KNOWN_UNPARSEABLE), "\n" + "\n".join(lines)
        )


if __name__ == "__main__":
    unittest.main()
