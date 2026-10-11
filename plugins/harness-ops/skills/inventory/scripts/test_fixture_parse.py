#!/usr/bin/env python3
# test-scope: plugins/harness-ops/skills/inventory/scripts/js/package-lock.json
# test-scope: plugins/harness-ops/scripts/docs-cache.sh plugins/harness-ops/scripts/fetch-docs.sh
"""Every JavaScript fixture test_inventory.py feeds the reader in
inventory.py parses as a module under acorn. Naming inventory.py here is
what makes scripts/affected-tests.sh select this suite when it changes.

A parser-backed reader (#5640) reads only what parses, so a fixture that is
not valid JavaScript tests a shape no real bundle has. The fixtures are
collected by running test_inventory.py with `inventory.build_brace_map`
wrapped: every extraction builds the brace map from its source first, so
the wrapper sees exactly the text each test hands the reader, including
text a test assembles in a loop.

Every module must parse. A failure lists each one as
`<test id>#<first 12 hex of the module's sha256>` with acorn's error.

Needs `node` and an `acorn` package that `require("acorn")` resolves: the
pinned set `python3 parser_reader.py --install` puts in place, or any
node_modules NODE_PATH names. Otherwise the check skips, unless
INVENTORY_REQUIRE_ACORN is set (CI sets it), which makes it fail.

Run: python3 -m unittest test_fixture_parse
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import shutil
import subprocess
import tempfile
import unittest

import inventory as inv
import parser_reader
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


def _node_env() -> dict[str, str]:
    """The environment node runs in: the installed parser packages on
    NODE_PATH when they exist, else the caller's NODE_PATH."""
    target = parser_reader.install_dir(parser_reader.deps_base(None)[0])
    if parser_reader.installed(target):
        return dict(os.environ, NODE_PATH=str(target / "node_modules"))
    return dict(os.environ)


def _acorn_skip_reason() -> str | None:
    node = shutil.which("node")
    if node is None:
        return "node is not on PATH"
    probe = subprocess.run(
        [node, "-e", 'require("acorn")'],
        capture_output=True,
        text=True,
        check=False,
        env=_node_env(),
    )
    if probe.returncode != 0:
        return (
            'node cannot require("acorn"); run `python3 parser_reader.py --install` '
            "or set NODE_PATH to a node_modules holding acorn@8"
        )
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
            env=_node_env(),
        )
    out = json.loads(run.stdout)
    return out["acorn"], [tuple(f) for f in out["failed"]]


class TestFixturesParse(unittest.TestCase):
    def test_every_fixture_parses_as_a_module(self) -> None:
        reason = _acorn_skip_reason()
        if reason and os.environ.get("INVENTORY_REQUIRE_ACORN"):
            self.fail(reason)
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
        lines = [f"{k}: {e}" for k, e in sorted(bad.items())]
        self.assertEqual(bad, {}, "\n" + "\n".join(lines))


if __name__ == "__main__":
    unittest.main()
