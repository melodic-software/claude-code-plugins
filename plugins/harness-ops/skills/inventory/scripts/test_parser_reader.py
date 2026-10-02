#!/usr/bin/env python3
"""Tests for parser_reader.py, the js/parser_helper.cjs process it drives, and
inventory.py's --reader=parser|compare wiring.

The install-resolution and fail-closed cases need neither node nor network.
The live-helper cases run when the pinned packages are already installed
(`python3 parser_reader.py --install`) and skip otherwise; with
INVENTORY_REQUIRE_ACORN set, as CI sets it, a missing install fails instead.

Run: python3 -m unittest test_parser_reader
"""

from __future__ import annotations

import contextlib
import io
import json
import os
import pathlib
import shutil
import stat
import tempfile
import unittest
from unittest import mock

import inventory as inv
import parser_reader as pr
import test_inventory

# The region-rule suite's byte layouts, borrowed by value: binding the TestCase
# itself at module level would make the loader run its tests here too.
MARKER, BIG, GAP, DOCTOR = (
    getattr(test_inventory.TestReadBundleRegionRule, n)
    for n in ("MARKER", "BIG", "GAP", "DOCTOR")
)


def _live_target() -> pathlib.Path | None:
    target = pr.install_dir(pr.deps_base(None)[0])
    return target if pr.installed(target) and shutil.which("node") else None


def _require_live(case: unittest.TestCase) -> pathlib.Path:
    target = _live_target()
    if target is None:
        reason = (
            "parser packages not installed; run: python3 parser_reader.py --install"
        )
        if os.environ.get("INVENTORY_REQUIRE_ACORN"):
            case.fail(reason)
        case.skipTest(reason)
    return target


class TestInstallResolution(unittest.TestCase):
    def test_an_explicit_dir_wins(self) -> None:
        with mock.patch.dict(os.environ, {"CLAUDE_PLUGIN_DATA": "/d/harness-ops-x"}):
            self.assertEqual(pr.deps_base("/x"), (pathlib.Path("/x"), "--deps-dir"))

    def test_a_harness_ops_plugin_data_dir_is_used(self) -> None:
        with mock.patch.dict(os.environ, {"CLAUDE_PLUGIN_DATA": "/d/harness-ops-m"}):
            self.assertEqual(
                pr.deps_base(None),
                (pathlib.Path("/d/harness-ops-m"), "CLAUDE_PLUGIN_DATA"),
            )

    def test_another_plugins_data_dir_is_not_used(self) -> None:
        env = {"CLAUDE_PLUGIN_DATA": "/d/miro-m", "CLAUDE_CONFIG_DIR": "/cfg"}
        with (
            mock.patch.dict(os.environ, env),
            mock.patch.object(pr, "checkout_root", return_value=None),
        ):
            base, how = pr.deps_base(None)
        self.assertEqual(
            base, pathlib.Path("/cfg/plugins/data/harness-ops-melodic-software")
        )
        self.assertEqual(how, "plugin data directory")

    def test_a_checkout_installs_under_its_work_dir(self) -> None:
        root = pathlib.Path("/repo")
        with (
            mock.patch.dict(os.environ, {"CLAUDE_PLUGIN_DATA": ""}),
            mock.patch.object(pr, "checkout_root", return_value=root),
        ):
            self.assertEqual(
                pr.deps_base(None), (root / ".work" / "harness-ops", "checkout .work/")
            )

    def test_the_install_dir_is_keyed_by_the_lockfile(self) -> None:
        target = pr.install_dir(pathlib.Path("/b"))
        self.assertEqual(target.parent, pathlib.Path("/b/inventory-parser"))
        self.assertRegex(target.name, r"^[0-9a-f]{12}$")

    def test_the_repair_command_rebuilds_from_the_committed_lockfile(self) -> None:
        cmd = pr.install_command(pathlib.Path("/a b/t"))
        self.assertTrue(cmd.startswith("rm -rf '/a b/t' && mkdir -p '/a b/t' && cp "))
        self.assertIn("package-lock.json", cmd)
        self.assertTrue(
            cmd.endswith(
                "npm ci --prefix '/a b/t' --ignore-scripts --no-audit --no-fund"
            )
        )


class TestFailClosed(unittest.TestCase):
    def setUp(self) -> None:
        self.dir = pathlib.Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.dir, True)
        self.target = self.dir / "inventory-parser" / "k"

    def test_no_npm_is_broken_with_the_command(self) -> None:
        with mock.patch.object(pr.shutil, "which", return_value=None):
            with self.assertRaises(pr.ReaderBroken) as ctx:
                pr.ensure_installed(self.target)
        self.assertIn("npm is not on PATH", ctx.exception.reason)
        self.assertEqual(ctx.exception.command, pr.install_command(self.target))
        self.assertIn("; run: rm -rf ", str(ctx.exception))

    @unittest.skipIf(os.name == "nt", "the fake npm is a POSIX shell script")
    def test_a_failed_npm_ci_is_broken_and_leaves_nothing_behind(self) -> None:
        npm = self.dir / "npm"
        npm.write_text("#!/bin/sh\necho 'network unreachable' >&2\nexit 7\n")
        npm.chmod(npm.stat().st_mode | stat.S_IEXEC)
        with mock.patch.object(pr.shutil, "which", return_value=str(npm)):
            with self.assertRaises(pr.ReaderBroken) as ctx:
                pr.ensure_installed(self.target)
        self.assertIn(
            "npm ci failed (exit 7): network unreachable", ctx.exception.reason
        )
        self.assertEqual(ctx.exception.command, pr.install_command(self.target))
        self.assertEqual(list(self.target.parent.iterdir()), [])

    def test_an_existing_install_is_reused_without_npm(self) -> None:
        for name in pr.REQUIRED_PACKAGES:
            pkg = self.target / "node_modules" / name
            pkg.mkdir(parents=True)
            (pkg / "package.json").write_text("{}")
        with mock.patch.object(pr.shutil, "which", return_value=None):
            self.assertFalse(pr.ensure_installed(self.target))

    def test_no_node_is_broken_with_the_command(self) -> None:
        with mock.patch.object(pr.shutil, "which", return_value=None):
            with self.assertRaises(pr.ReaderBroken) as ctx:
                pr.ParserReader(self.target)
        self.assertIn("node is not on PATH: install Node.js", ctx.exception.reason)
        self.assertIsNone(ctx.exception.command)

    def test_stale_partial_installs_are_removed_and_fresh_ones_kept(self) -> None:
        self.target.parent.mkdir(parents=True)
        stale = self.target.with_name(f"{self.target.name}.partial-111")
        fresh = self.target.with_name(f"{self.target.name}.partial-222")
        other = self.target.with_name("other.partial-333")
        for d in (stale, fresh, other):
            (d / "node_modules").mkdir(parents=True)
        old = os.stat(stale).st_mtime - pr.STALE_PARTIAL_SECONDS - 60
        os.utime(stale, (old, old))
        os.utime(other, (old, old))
        with mock.patch.object(pr.shutil, "which", return_value=None):
            with self.assertRaises(pr.ReaderBroken):
                pr.ensure_installed(self.target)
        self.assertFalse(stale.exists())
        self.assertTrue(fresh.exists())
        self.assertTrue(other.exists())

    @unittest.skipUnless(shutil.which("node"), "node is not on PATH")
    def test_a_helper_that_cannot_load_its_packages_is_broken(self) -> None:
        self.target.mkdir(parents=True)
        reader = pr.ParserReader(self.target)
        self.addCleanup(reader.close)
        with self.assertRaises(pr.ReaderBroken) as ctx:
            reader.ping()
        self.assertIn("the parser helper exited", ctx.exception.reason)
        self.assertIn("acorn", ctx.exception.reason)
        self.assertEqual(ctx.exception.command, pr.install_command(self.target))


class TestLiveHelper(unittest.TestCase):
    def test_ping_reports_the_locked_versions(self) -> None:
        target = _require_live(self)
        lock = json.loads((pr.JS_DIR / "package-lock.json").read_text(encoding="utf-8"))
        with pr.ParserReader(target) as reader:
            got = reader.ping()
        self.assertEqual(
            got["acorn"], lock["packages"]["node_modules/acorn"]["version"]
        )
        self.assertEqual(
            got["eslint_scope"],
            lock["packages"]["node_modules/eslint-scope"]["version"],
        )
        self.assertTrue(got["node"].startswith("v"))

    def test_parse_ok_answers_each_module_in_turn(self) -> None:
        target = _require_live(self)
        with pr.ParserReader(target) as reader:
            self.assertEqual(
                reader.parse_ok("// @bun\nvar a=1;export{a};"), (True, None)
            )
            ok, error = reader.parse_ok("var =;")
            self.assertFalse(ok)
            self.assertIn("Unexpected token", error or "")
            self.assertEqual(reader.parse_ok("let b=`x${1}`;"), (True, None))

    def test_an_unknown_op_is_broken(self) -> None:
        target = _require_live(self)
        with pr.ParserReader(target) as reader:
            with self.assertRaises(pr.ReaderBroken) as ctx:
                reader.request("no_such_op")
        self.assertIn("unknown op", ctx.exception.reason)


class TestBindingQuery(unittest.TestCase):
    """The helper's `binding` op: eslint-scope's resolution over acorn's AST."""

    SRC = (
        'import{a as b}from"m";var pY=["A"];'
        'function f(){"let pY";/*let pY*/pY=["B"]}'
        "function g(pY){return pY}"
        'function h(){let pY="L";return pY}'
        'gl="G";function k(){gl="H"}'
    )

    @classmethod
    def setUpClass(cls) -> None:
        cls.reader = pr.ParserReader(_require_live(cls("run")))

    @classmethod
    def tearDownClass(cls) -> None:
        cls.reader.close()

    def _at(self, needle: str, k: int = 0) -> dict | None:
        at = self.SRC.index(needle) + k
        return self.reader.binding(self.SRC, 0, len(self.SRC), "pY", at)

    def test_declaration_text_in_a_string_or_comment_declares_nothing(self) -> None:
        outer = self._at("pY=[")
        assert outer is not None
        self.assertEqual(outer["kind"], "Variable")
        self.assertEqual(self._at('pY=["B"]'), outer)
        self.assertEqual(
            [w for w, _ in outer["writes"]],
            [self.SRC.index('pY=["A"]'), self.SRC.index('pY=["B"]')],
        )

    def test_a_parameter_and_a_block_local_are_their_own_bindings(self) -> None:
        param = self._at("return pY}", 7)
        local = self._at('let pY="L"', 4)
        assert param is not None and local is not None
        self.assertEqual(param["kind"], "Parameter")
        self.assertEqual(local["kind"], "Variable")
        self.assertEqual(self._at("return pY}function h", 7), param)
        self.assertNotEqual(local, self._at("pY=["))
        self.assertEqual(local["defs"][0][3], False)
        self.assertEqual(self._at("pY=[")["defs"][0][3], True)

    def test_an_import_names_what_it_imports(self) -> None:
        got = self.reader.binding(self.SRC, 0, len(self.SRC), "b", self.SRC.index("b}"))
        self.assertEqual(got, {"kind": "import", "imported": "a"})

    def test_an_undeclared_name_is_one_implicit_global(self) -> None:
        got = self.reader.binding(
            self.SRC, 0, len(self.SRC), "gl", self.SRC.index('gl="H"')
        )
        assert got is not None
        self.assertEqual(got["kind"], "ImplicitGlobal")
        self.assertEqual(
            got["writes"],
            [(self.SRC.index('gl="G"'), True), (self.SRC.index('gl="H"'), False)],
        )

    def test_offsets_are_positions_in_the_whole_source(self) -> None:
        pad = "var zz=1;\n// @bun\n"
        src = pad + self.SRC
        got = self.reader.binding(src, len(pad) - 8, len(src), "pY", src.index("pY=["))
        assert got is not None
        self.assertEqual(got["writes"][0][0], src.index('pY=["A"]'))

    def test_an_evicted_module_is_sent_again(self) -> None:
        first = self._at("pY=[")
        for n in range(20):
            other = f"var pY={n};"
            self.reader.binding(other, 0, len(other), "pY", 4)
        # One character into the name: not asked before, so not memoized.
        self.assertEqual(self._at("pY=[", 1), first)

    def test_an_unparsable_module_resolves_nothing(self) -> None:
        self.assertIsNone(self.reader.binding("var =;", 0, 6, "x", 0))


class _StubReader:
    """Stands in for the helper: every module parses unless its text says not."""

    lookups = 0

    def __init__(self) -> None:
        self.parsed = 0

    def parse_ok(self, source: str) -> tuple[bool, str | None]:
        self.parsed += 1
        return ("UNPARSABLE" not in source, None if "UNPARSABLE" not in source else "x")

    def __enter__(self) -> _StubReader:
        return self

    def __exit__(self, *_: object) -> None:
        pass


class TestInventoryReaderFlag(unittest.TestCase):
    """inventory.py --reader against a synthetic one-module binary."""

    def setUp(self) -> None:
        layout = MARKER + BIG + GAP + DOCTOR + b"b" * 2000
        fd, name = tempfile.mkstemp(suffix=".bin")
        os.close(fd)
        self.binary = pathlib.Path(name)
        self.addCleanup(self.binary.unlink)
        self.binary.write_bytes(layout)

    def _run(self, *argv: str) -> tuple[int, str]:
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = inv.main(["--binary", str(self.binary), *argv])
        return code, out.getvalue()

    def _stub(self, reader: _StubReader | None = None):
        info = {
            "deps_dir": "/d",
            "deps_dir_selected_by": "test",
            "installed_now": False,
        }
        return mock.patch.object(
            pr, "open_reader", return_value=(reader or _StubReader(), info)
        )

    def test_module_spans_are_the_runs_opening_with_a_marker(self) -> None:
        spans: list[tuple[int, int]] = []
        src, _ = inv.read_bundle(self.binary, spans)
        assert src is not None
        self.assertEqual(spans, [(0, len(MARKER + BIG))])

    def test_regex_is_the_default_and_adds_no_reader_block(self) -> None:
        with mock.patch.object(pr, "open_reader") as opened:
            code, out = self._run("--binary-only")
        self.assertEqual(code, 0)
        self.assertNotIn("reader", json.loads(out))
        opened.assert_not_called()

    def test_a_broken_parser_reader_fails_closed_with_the_command(self) -> None:
        broken = pr.ReaderBroken(
            "npm ci failed (exit 1): offline", "npm ci --prefix /t"
        )
        with mock.patch.object(pr, "open_reader", side_effect=broken):
            code, out = self._run("--binary-only", "--reader", "parser")
            report = json.loads(out)
            self.assertEqual(code, 0)
            self.assertFalse(report["sources"]["binary"]["available"])
            self.assertNotIn("builtin_commands", report)
            self.assertEqual(report["reader"]["status"], "broken")
            self.assertEqual(report["reader"]["remediation"], "npm ci --prefix /t")
            code, out = self._run("--self-check", "--reader", "parser")
        self.assertEqual(code, 1)
        self.assertIn(
            "BROKEN: parser reader broken: npm ci failed (exit 1): offline; "
            "run: npm ci --prefix /t",
            out,
        )

    def test_the_parser_reader_parses_every_module(self) -> None:
        stub = _StubReader()
        with self._stub(stub):
            _, out = self._run("--binary-only", "--reader", "parser")
        report = json.loads(out)
        self.assertEqual(stub.parsed, 1)
        self.assertEqual(report["reader"]["modules"], 1)
        self.assertEqual(report["reader"]["status"], "ok")
        self.assertIn("help", report["builtin_commands"])

    def test_an_unparsable_module_breaks_the_report(self) -> None:
        self.binary.write_bytes(MARKER + b"UNPARSABLE;" + BIG + GAP + DOCTOR)
        with self._stub():
            code, out = self._run("--self-check", "--reader", "parser")
        self.assertEqual(code, 1)
        self.assertIn("1 of 1 bundle modules do not parse", out)
        self.assertIn("reader parser: broken, 0 of 1 modules parse", out)

    def test_compare_runs_both_readers_and_reports_no_difference(self) -> None:
        with self._stub():
            _, out = self._run("--binary-only", "--reader", "compare")
        report = json.loads(out)
        self.assertEqual(report["reader"]["compare"]["changes"], [])
        self.assertFalse(report["reader"]["compare"]["failed"])
        self.assertEqual(report["reader"]["status"], "ok")

    def test_compare_gives_each_reader_its_own_answers(self) -> None:
        """Finding 5 on #5640 reads differently under the two readers, so a
        cache carrying the regex run's answers into the parser run (or back)
        shows up as no change, or the wrong section values."""
        _require_live(self)
        probe = (
            test_inventory.AGENT_SRC
            + 'var pY=[xt,"Artifact"];function f(){"let pY";pY=["B"]}f();'
            'var SP={agentType:"spread-probe",whenToUse:"s",source:"built-in",'
            'disallowedTools:[yt,...pY],getSystemPrompt:()=>""};'
        )
        self.binary.write_bytes(MARKER + probe.encode() + BIG + GAP + DOCTOR)
        _, out = self._run("--binary-only", "--reader", "compare")
        report = json.loads(out)
        agent = report[inv.AGENT_LANE]["spread-probe"]
        self.assertEqual(agent["disallowed_tools_source"], "partial")
        pointer = f"/{inv.AGENT_LANE}/spread-probe/disallowed_tools_source"
        changed = {c["pointer"]: c for c in report["reader"]["compare"]["changes"]}
        self.assertIn(pointer, changed)
        self.assertFalse(report["reader"]["compare"]["failed"])
        _, regex = self._run("--binary-only")
        self.assertEqual(
            json.loads(regex)[inv.AGENT_LANE]["spread-probe"][
                "disallowed_tools_source"
            ],
            "literal",
        )

    def test_a_value_that_differs_between_readers_breaks_the_report(self) -> None:
        real = inv.extract_binary
        calls = []

        def second_differs(src: str, meta: dict) -> dict:
            out = real(src, meta)
            calls.append(1)
            if len(calls) == 2:
                out["builtin_commands"]["help"]["description"] = "changed"
            return out

        with self._stub(), mock.patch.object(inv, "extract_binary", second_differs):
            _, out = self._run("--binary-only", "--reader", "compare")
        report = json.loads(out)
        self.assertEqual(report["reader"]["compare"]["disallowed"], 1)
        self.assertEqual(report["integrity"]["status"], "broken")
        self.assertEqual(report["reader"]["status"], "broken")


if __name__ == "__main__":
    unittest.main()
