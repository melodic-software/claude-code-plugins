#!/usr/bin/env python3
"""Every JavaScript fixture test_inventory.py feeds the reader in
inventory.py parses as a module under acorn. Naming inventory.py here is
what makes scripts/affected-tests.sh select this suite when it changes.

A parser-backed reader (#5640) reads only what parses, so a fixture that is
not valid JavaScript tests a shape no real bundle has. The fixtures are
collected by running test_inventory.py with `inventory.build_brace_map`
wrapped: every extraction builds the brace map from its source first, so
the wrapper sees exactly the text each test hands the reader, including
text a test assembles in a loop.

Modules known not to parse are listed in KNOWN_UNPARSABLE as
`<test id>#<first 12 hex of the module's sha256>`, for P2 to rewrite. The
check fails when a new key appears or a listed one is gone, so a module that
breaks or is repaired inside an already-listed test changes the comparison;
the failure message prints every current key.

Needs `node` and an `acorn` package that `require("acorn")` resolves (set
NODE_PATH to its node_modules directory, e.g. after
`npm install --prefix <dir> acorn@8`); otherwise the check skips.

Run: python3 -m unittest test_fixture_parse
"""

from __future__ import annotations

import hashlib
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
KNOWN_UNPARSABLE: frozenset[str] = frozenset(
    {
        "TestAgentAndToolIntegrity.test_a_missing_canary_breaks_only_that_lane#b5868a7055b1",
        "TestAgentAndToolIntegrity.test_an_empty_lane_is_broken#b5868a7055b1",
        "TestAgentAndToolIntegrity.test_both_lanes_ok#b5868a7055b1",
        "TestAgentAndToolIntegrity.test_factories_do_not_degrade#b5868a7055b1",
        "TestAgentAndToolIntegrity.test_lanes_absent_when_not_extracted#b5868a7055b1",
        "TestAgentAndToolIntegrity.test_unresolved_names_and_a_missing_roster_degrade#b5868a7055b1",
        "TestBuiltinPlugins.test_a_duplicate_registration_degrades_the_lane#6379c2d60146",
        "TestBuiltinPlugins.test_a_loaded_plugin_without_a_registration_degrades_the_lane#6379c2d60146",
        "TestBuiltinPlugins.test_a_missing_canary_breaks_the_lane_only#6379c2d60146",
        "TestBuiltinPlugins.test_a_partial_plugin_or_a_missing_loader_degrades_the_lane#6379c2d60146",
        "TestBuiltinPlugins.test_a_registration_the_loader_never_requires_degrades_the_lane#6379c2d60146",
        "TestBuiltinPlugins.test_an_unresolved_marketplace_leaves_the_id_partial#6379c2d60146",
        "TestBuiltinPlugins.test_every_field_an_unresolved_spread_hides_is_partial#6379c2d60146",
        "TestBuiltinPlugins.test_the_lane_is_ok_when_everything_resolves#6379c2d60146",
        "TestBundledWorkflows.test_lane_breaks_on_a_missing_canary_and_others_stand#b5868a7055b1",
        "TestBundledWorkflows.test_lane_ok_with_the_canary#b5868a7055b1",
        "TestCommandExtraction.test_a_name_bound_to_a_conditional_is_not_resolved#85ce46d58655",
        "TestCommandExtraction.test_shell_builtin_is_not_a_command#fec1bb3c5c58",
        "TestIntegrity.test_canary_missing_breaks_the_builtin_lane_only#55213d5c1103",
        "TestIntegrity.test_degraded_on_unknown_registrar#3618f81b8f33",
        "TestIntegrity.test_degraded_when_registrations_exceed_resolved#b5868a7055b1",
        "TestIntegrity.test_dynamic_roster_is_an_advisory_not_an_unresolved_name#b5868a7055b1",
        "TestIntegrity.test_esm_export_list_feeds_the_registrar_advisory#e5c5402a79c1",
        "TestIntegrity.test_every_lane_broken_is_broken#55213d5c1103",
        "TestIntegrity.test_low_yield_breaks_the_builtin_lane#b88b934b8a7b",
        "TestIntegrity.test_missing_plugin_backed_canary_breaks_that_lane#b5868a7055b1",
        "TestIntegrity.test_no_skills_breaks_the_bundled_lane_only#b5868a7055b1",
        "TestIntegrity.test_ok_when_everything_resolves#b5868a7055b1",
        "TestIntegrity.test_registrations_below_the_floor_degrade_the_bundled_lane#b5868a7055b1",
        "TestInvocationFieldsAndCollisions.test_a_flag_driven_twin_of_a_constant_field_is_a_collision#e502c2ef5e4a",
        "TestInvocationFieldsAndCollisions.test_a_function_valued_field_reads_as_true_and_flag_driven#44b9fec2dc50",
        "TestInvocationFieldsAndCollisions.test_invocation_fields_are_read_when_present#ce769dbf090c",
        "TestInvocationFieldsAndCollisions.test_the_same_registration_seen_twice_is_not_a_collision#0d36306e877f",
        "TestInvocationFieldsAndCollisions.test_two_registrations_sharing_a_name_are_both_kept#ce69f83385dc",
        "TestNameLocality.test_a_binding_after_the_registration_does_not_resolve_it#9a6e9362fb32",
        "TestNameLocality.test_a_descriptor_member_name_resolves#55be871fc0c5",
        "TestNameLocality.test_a_function_whose_name_ends_in_the_registrar_is_not_a_call#cafe65dd1b41",
        "TestNameLocality.test_a_lone_far_binding_of_a_short_identifier_is_not_resolved#0c5d756b8eac",
        "TestNameLocality.test_a_long_identifier_bound_far_ahead_resolves#41443f4f85cd",
        "TestNameLocality.test_a_loop_over_a_literal_table_is_enumerated#8fd1aba220f9",
        "TestNameLocality.test_a_loop_registration_is_a_dynamic_roster#f666325cf42d",
        "TestNameLocality.test_a_nearer_non_constant_binding_shadows_a_constant#48defb31bfb4",
        "TestNameLocality.test_a_same_identifier_call_without_a_name_is_not_a_registration#9c35b1ff9865",
        "TestNameLocality.test_a_short_identifier_bound_nearby_resolves#553470597e43",
        "TestNameLocality.test_a_template_literal_name_is_a_dynamic_roster#1dd6d1208661",
        "TestNameLocality.test_nearest_preceding_binding_wins_over_a_farther_one#a68e67dc1cbc",
        "TestRegistrarRoutes.test_route_is_recorded_in_the_notes#700bc7dd62e2",
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


def unparsable(fixtures: list[str]) -> tuple[str, list[tuple[int, str]]]:
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
        _, failed = unparsable(fixtures)
        bad: dict[str, str] = {}
        for i, error in failed:
            digest = hashlib.sha256(fixtures[i].encode()).hexdigest()[:12]
            for test in owners[fixtures[i]]:
                bad[f"{test}#{digest}"] = error
        lines = [f'"{k}",  # {e}' for k, e in sorted(bad.items())]
        self.assertEqual(sorted(bad), sorted(KNOWN_UNPARSABLE), "\n" + "\n".join(lines))


if __name__ == "__main__":
    unittest.main()
