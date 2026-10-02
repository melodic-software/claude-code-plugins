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
import re
import shutil
import stat
import subprocess
import sys
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
        cmd = pr.install_command(pathlib.Path("/a b/t"), "linux")
        self.assertTrue(cmd.startswith("rm -rf '/a b/t' && mkdir -p '/a b/t' && cp "))
        self.assertIn("package-lock.json", cmd)
        self.assertTrue(
            cmd.endswith(
                "npm ci --prefix '/a b/t' --ignore-scripts --no-audit --no-fund"
            )
        )


class TestRepairCommandPerPlatform(unittest.TestCase):
    POSIX_TARGET = pathlib.Path("/srv/o'brien data/inventory-parser/abc")
    WIN_TARGET = pathlib.Path("D:\\o'brien data\\inventory-parser\\abc")

    def test_the_posix_form_quotes_a_space_and_a_quote_and_parses(self) -> None:
        cmd = pr.install_command(self.POSIX_TARGET, "linux")
        self.assertTrue(
            cmd.startswith(
                "rm -rf '/srv/o'\"'\"'brien data/inventory-parser/abc' && mkdir -p "
            )
        )
        self.assertTrue(cmd.endswith("--ignore-scripts --no-audit --no-fund"))
        bash = shutil.which("bash")
        if bash is None:
            self.skipTest("bash is not installed")
        subprocess.run([bash, "-n", "-c", cmd], check=True)

    def test_the_windows_form_is_powershell_without_and_and_doubles_the_quote(
        self,
    ) -> None:
        cmd = pr.install_command(self.WIN_TARGET, "win32")
        target = "'D:\\o''brien data\\inventory-parser\\abc'"
        self.assertNotIn("&&", cmd)
        self.assertNotIn("rm -rf", cmd)
        self.assertTrue(cmd.startswith("$ErrorActionPreference = 'Stop'; "))
        self.assertIn(
            f"Remove-Item -LiteralPath {target} -Recurse -Force "
            "-ErrorAction SilentlyContinue; ",
            cmd,
        )
        self.assertIn(
            f"New-Item -ItemType Directory -Force -Path {target} | Out-Null; ", cmd
        )
        self.assertRegex(
            cmd,
            r"Copy-Item -LiteralPath '[^']*package\.json', '[^']*package-lock\.json' "
            rf"-Destination {re.escape(target)}; ",
        )
        self.assertTrue(
            cmd.endswith(
                f"npm.cmd ci --prefix {target} --ignore-scripts --no-audit --no-fund"
            )
        )

    def test_the_default_platform_is_this_one(self) -> None:
        target = pathlib.Path("/a b/t")
        self.assertEqual(
            pr.install_command(target), pr.install_command(target, sys.platform)
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
        self.assertIn(f"; run: {pr.install_command(self.target)}", str(ctx.exception))

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


class TestWritesQuery(unittest.TestCase):
    """The helper's `writes` op: write references and possible mutations
    read from the AST."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.reader = pr.ParserReader(_require_live(cls("run")))

    @classmethod
    def tearDownClass(cls) -> None:
        cls.reader.close()

    def _writes(self, src: str, at: str = "pY=[", name: str = "pY") -> dict | None:
        return self.reader.writes(src, 0, len(src), name, src.index(at))

    def _kinds(self, src: str, field: str) -> list[tuple[str, str]]:
        """Each entry's kind with the source text from its offset on."""
        got = self._writes(src)
        assert got is not None
        return [(kind, src[w : w + 8]) for kind, w, _ in got[field]]

    def test_each_write_reference_has_its_kind(self) -> None:
        src = (
            "var pY=[1];pY=[2];pY+=[3];pY++;[pY]=[4];({a:pY}=o);"
            "for(pY of z);function f(){pY=[5]}"
        )
        self.assertEqual(
            [k for k, _ in self._kinds(src, "writes")],
            [
                "init",
                "assign",
                "compound",
                "update",
                "destructure",
                "destructure",
                "for-in-of",
                "assign",
            ],
        )
        got = self._writes(src)
        assert got is not None
        self.assertEqual([top for _, _, top in got["writes"]][-2:], [True, False])

    def test_each_possible_mutation_has_its_kind(self) -> None:
        src = (
            "var pY=[1];pY.size=0;delete pY.x;pY.a.b++;pY.push(2);pY[0].sort();"
            "Object.assign(pY,{});g(pY);new G(pY);t`${pY}`;pY[k]();"
            "pY.map(f);(0,pY.push)(3);f(...pY);[...pY];x=pY.length;f(pY[0]);"
            "pY();q=pY;"
        )
        self.assertEqual(
            self._kinds(src, "mutations"),
            [
                ("member-write", "pY.size="),
                ("member-delete", "pY.x;pY."),
                ("member-write", "pY.a.b++"),
                ("method-call", "pY.push("),
                ("method-call", "pY[0].so"),
                ("object-assign", "pY,{});g"),
                ("call-argument", "pY);new "),
                ("call-argument", "pY);t`${"),
                ("call-argument", "pY}`;pY["),
                ("method-call", "pY[k]();"),
                ("method-call", "pY.map(f"),
                ("method-call", "pY.push)"),
                ("escape", "pY();q=p"),
                ("escape", "pY;"),
            ],
        )

    def test_a_member_read_is_safe_only_in_a_value_only_position(self) -> None:
        src = (
            "var pY=[1];pY.pop`x`;new pY.c();pY.pop?.();x=await pY.pop;"
            "if(pY.length)f(pY[0],`${pY.a}`);o={k:pY.b};"
        )
        self.assertEqual(
            self._kinds(src, "mutations"),
            [
                ("method-call", "pY.pop`x"),
                ("method-call", "pY.c();p"),
                ("method-call", "pY.pop?."),
                ("member-escape", "pY.pop;i"),
            ],
        )

    def test_a_function_declaration_of_the_name_is_a_write(self) -> None:
        src = "function hL(e){function e(){}return e}"
        got = self.reader.writes(src, 0, len(src), "e", src.index("{"))
        assert got is not None
        self.assertEqual(got["writes"], [("declaration", src.index("e(){"), False)])

    def test_text_in_strings_and_comments_is_no_reference(self) -> None:
        src = 'var pY=[1];var s="let pY;pY=[2];pY.push(3)";/*pY=[4]*/`pY=[5]`;'
        self.assertEqual(
            self._writes(src),
            {"declares": True, "writes": [("init", 4, True)], "mutations": []},
        )

    def test_declares_is_only_a_plain_declarator(self) -> None:
        for src, at, declares in (
            ("var pY=[1];", "pY=[", True),
            ("let a,pY=[1];", "pY=[", True),
            ("var pY;pY=[1];", "pY=[", False),
            ("var{pY}=o;", "pY}", False),
            ("pY=[1];", "pY=[", False),
        ):
            with self.subTest(src=src):
                got = self._writes(src, at)
                self.assertEqual(got is not None and got["declares"], declares)

    def test_a_shadowing_parameter_takes_its_own_writes(self) -> None:
        src = "var pY=[1];function g(pY){pY=[2];pY.push(3)}"
        self.assertEqual(
            self._writes(src),
            {"declares": True, "writes": [("init", 4, True)], "mutations": []},
        )

    def test_offsets_are_positions_in_the_whole_source(self) -> None:
        pad = "var zz=1;\n// @bun\n"
        src = pad + "var pY=[1];pY.push(2);"
        got = self.reader.writes(src, len(pad) - 8, len(src), "pY", src.index("pY=["))
        assert got is not None
        self.assertEqual(
            got["mutations"], [("method-call", src.index("pY.push"), True)]
        )

    def test_a_direct_eval_or_an_unparsable_module_answers_nothing(self) -> None:
        self.assertIsNone(self._writes('var pY=[1];function e(){eval("")}'))
        self.assertIsNone(self.reader.writes("var =;", 0, 6, "x", 0))


class TestFlowQuery(unittest.TestCase):
    """The helper's `flow` op: where an array value can go inside one
    module, and the hops that leave it."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.reader = pr.ParserReader(_require_live(cls("run")))

    @classmethod
    def tearDownClass(cls) -> None:
        cls.reader.close()

    def _flow(self, src: str, start: dict | None = None) -> dict:
        start = start or {"var": True, "offset": src.index("pY=["), "name": "pY"}
        return self.reader.flow(src, 0, len(src), start)

    def assert_safe(self, src: str, exits: list[tuple] | None = None) -> None:
        got = self._flow(src)
        self.assertTrue(got["safe"], got)
        self.assertEqual(got["exits"], exits or [])

    def assert_unsafe(self, src: str, at: str) -> None:
        got = self._flow(src)
        self.assertFalse(got["safe"], got)
        self.assertEqual(src[got["at"] : got["at"] + len(at)], at, got["reason"])

    def test_an_alias_returned_to_a_callback_method_resolves_its_callback(self) -> None:
        """The 2.1.286 shape: the callback reaches `.some` through two
        parameters and a destructured object literal argument."""
        body = (
            "var pY=[1],Gr=pY;function Xr(e){if(e)return Gr;return[]}"
            "function ko(e,t){let n=(s)=>Xr(s).some(t);return n(e)}"
            'function Eo(e,t){return typeof t==="function"?ko(e,t):e}'
            "function gn(e,{hook:n}){return Eo(e,n)}"
        )
        self.assert_safe(body + "gn(1,{hook:!1});")
        self.assert_safe(body + "gn(1,{hook:(x)=>x===1});")
        self.assert_unsafe(body + "gn(1,{hook:(x,i,a)=>a.push(2)});", "a.push")
        self.assert_unsafe(body + "gn(1,{hook:h});", "h}")
        self.assert_unsafe(body + "gn(1,{});", "{})")
        self.assert_unsafe(body + "gn(1,{hook:!1});gn(2,o);", "o)")

    def test_a_callback_method_follows_the_array_into_its_callback(self) -> None:
        self.assert_safe("var pY=[1];pY.some((e)=>e>0);pY.forEach(f);function f(e,i){}")
        self.assert_safe("var pY=[1];pY.reduce((s,e,i)=>s+e,0);")
        self.assert_unsafe("var pY=[1];pY.some((e,i,a)=>a.pop());", "a.pop")
        self.assert_unsafe("var pY=[1];pY.reduce((s,e,i,a)=>a.pop());", "a.pop")
        self.assert_unsafe(
            "var pY=[1];function f(e,i,a){a.length=0}pY.map(f);", "a.length"
        )
        self.assert_unsafe("var pY=[1];pY.map(f);", "f)")

    def test_an_argument_follows_into_the_parameter(self) -> None:
        self.assert_safe("var pY=[1];function g(a,b){return b.includes(a)}g(1,pY);")
        self.assert_safe("var pY=[1];var g=(a)=>a.join();g(pY);")
        self.assert_unsafe("var pY=[1];function g(a,b){b.push(a)}g(1,pY);", "b.push")
        self.assert_unsafe(
            "var pY=[1];function g(){arguments[0].push(2)}g(pY);", "function g"
        )
        self.assert_unsafe(
            "var pY=[1];function g(...a){a[0].push(2)}g(pY);", "function g"
        )
        self.assert_unsafe("var pY=[1];function g([a]){}g(pY);", "[a]")
        self.assert_unsafe("var pY=[1];o.g(pY);", "o.g(pY)")

    def test_a_return_follows_every_call(self) -> None:
        self.assert_safe("var pY=[1];function r(){return pY}r().includes(1);[...r()];")
        self.assert_unsafe("var pY=[1];function r(){return pY}r().push(2);", "r().push")
        self.assert_unsafe("var pY=[1];function r(){return pY}h(r);", "r)")
        self.assert_unsafe("var pY=[1];async function r(){return pY}", "pY}")

    def test_a_method_neither_prototype_holds_throws_before_it_runs(self) -> None:
        self.assert_safe(
            'var pY=[1];function g(n){return"has"in n?n.has(1):n.includes(1)}g(pY);'
        )
        self.assert_unsafe("var pY=[1];pY.constructor(2);", "pY.constructor")

    def test_hops_out_of_the_module_come_back_as_exits(self) -> None:
        self.assert_safe("var pY=[1];export{pY as W};", [("export", "W")])
        self.assert_safe("export var pY=[1];", [("export", "pY")])
        self.assert_safe(
            'import{g}from"/x.js";var pY=[1];g(0,pY);pY.some(g);',
            [("param", "g", 1, "/x.js"), ("param", "g", 2, "/x.js")],
        )
        self.assert_safe(
            "var pY=[1];function r(){return pY}export{r};", [("export-call", "r")]
        )
        self.assert_unsafe("var pY=[1];export default pY;", "pY;")

    def test_an_import_start_follows_the_imported_binding(self) -> None:
        src = 'import{pY as q}from"/a.js";export{q as W};q.includes(1);'
        got = self._flow(src, {"import": "pY", "calls": False})
        self.assertEqual(
            got, {"safe": True, "exits": [("export", "W")], "trusted": ["includes"]}
        )
        src = 'import{pY as q}from"/a.js";q.push(1);'
        self.assertFalse(self._flow(src, {"import": "pY", "calls": False})["safe"])
        src = 'export{pY as W}from"/a.js";'
        got = self._flow(src, {"import": "pY", "calls": True})
        self.assertEqual(
            got, {"safe": True, "exits": [("export-call", "W")], "trusted": []}
        )

    def test_a_param_start_resolves_the_module_scope_function(self) -> None:
        src = "function g(a,b){b.push(1)}var h=(a)=>a.at(0);"
        self.assertFalse(self._flow(src, {"param": 1, "name": "g"})["safe"])
        self.assertTrue(self._flow(src, {"param": 0, "name": "h"})["safe"])

    def test_a_chain_too_deep_for_the_stack_is_unresolved_not_a_crash(self) -> None:
        """#5891 verifier: a 5,000-long alias chain exhausted the helper's
        stack before the step limit, so the helper died and the whole binary
        source read as a broken install."""
        chain = "".join(f"var a{i}=a{i - 1};" for i in range(1, 5000))
        got = self._flow("var pY=[1],a0=pY;" + chain + "a4999.push(2);")
        self.assertEqual(got["reason"], "the flow is too deep to follow")
        self.assertTrue(self.reader.ping()["acorn"])

    def test_a_direct_eval_leaves_the_flow_unresolved(self) -> None:
        got = self._flow('var pY=[1];function e(){eval("")}')
        self.assertEqual(got["reason"], "the module calls eval directly")

    def test_keys_used_reads_member_names_and_destructured_keys(self) -> None:
        for src, used in (
            ("n.pY.push(1);", True),
            ('n["pY"];', True),
            ("var{pY:q}=n;", True),
            ("var{pY}=n;", True),
            ("var o={pY:1};", False),
            ('var s="pY";', False),
            ('import{pY}from"/a.js";', False),
        ):
            with self.subTest(src=src):
                self.assertEqual(self.reader.keys_used(src, "pY"), used)

    def _sinks(self, src: str, names: tuple[str, ...] = ("includes",)) -> list[str]:
        return [kind for kind, _, _ in self.reader.sinks(src, 0, len(src), list(names))]

    def test_sinks_are_writes_of_a_trusted_name_on_a_possible_prototype(self) -> None:
        """#5891 second verifier: the sink rule. Every way to reach a
        prototype ends in a write of the name, a definer given the name, or
        a write whose key names nothing; only a provably fresh target is
        cleared."""
        for src, kinds in (
            ("var A=Array;A.prototype.includes=f;", ["write"]),
            ("(0,Array).prototype.includes=f;", ["write"]),
            ("globalThis.Array.prototype.includes=f;", ["write"]),
            ('Array["proto"+"type"].includes=f;', ["write"]),
            ('Reflect.get(Array,"prototype").includes=f;', ["write"]),
            (
                "var e={hasOwnProperty(o){o.includes=f}};e.hasOwnProperty.call(null,[].__proto__);",
                ["write"],
            ),
            ('function G(o,k){o.includes=f}G(Array.prototype,"__proto__");', ["write"]),
            (
                "(function(Object){Object.prototype.includes=f})(Array);",
                ["write", "definer-escape"],
            ),
            (
                "class WeakSet{constructor(a){a[0].includes=f}}new WeakSet([Array.prototype]);",
                ["write"],
            ),
            ('Array.prototype.__defineGetter__("includes",g);', ["argument"]),
            ("var Q=[].__proto__;Q.includes=f;", ["write"]),
            ("var Q=Object.getPrototypeOf([]);Q.includes=f;", ["write"]),
            ('Object.defineProperty(P,"includes",{});', ["argument"]),
            ("Object.assign(P,{includes:f});", ["object-key"]),
            ("Object.defineProperty(P,k,{});", ["computed-define"]),
            ("o[k]=f;", ["computed-write"]),
            ("Object.setPrototypeOf(P,Q);", ["proto-swap"]),
            ("var dp=Object.defineProperty;", ["definer-escape"]),
            ("var R=Reflect;", ["definer-escape"]),
            ('function e(){eval("")}', ["eval"]),
            ("(0,eval)(s);", ["indirect-eval"]),
            ("var e=eval;", ["indirect-eval"]),
            ("Function(s)();", ["function-constructor"]),
            ("new Function(s);", ["function-constructor"]),
            (
                "typeof eval;x instanceof Function;Function.prototype.toString.call(f);",
                [],
            ),
            # Cleared: a trusted name or computed key on a fresh object, or
            # a name nothing trusted.
            ("var o={};o.includes=f;o[k]=1;", []),
            ("class C{constructor(k){this[k]=1}}", []),
            (
                "class D extends B{constructor(k){super();this[k]=1}}",
                ["computed-write"],
            ),
            ("function F(){}F.prototype.includes=f;F.prototype.x;", []),
            ("function F(){}F.prototype.includes=f;new F;", ["write"]),
            (
                "function F(){}F.prototype.constructor.prototype=P;F.prototype.includes=f;",
                ["write"],
            ),
            ("function F(){}var G=F;F.prototype.includes=f;", ["write"]),
            ("function F(){}h(F);F.prototype.includes=f;", ["write"]),
            ('var o=Object.create(null);Object.defineProperty(o,"includes",{});', []),
            ('Reflect.set({},"includes",f,Array.prototype);', ["argument"]),
            ('Reflect.set({},"includes",f,{});', []),
            ("x.join=f;Array.prototype.join=f;", []),
            (
                'Object.keys(o);e instanceof Object;Object.prototype.hasOwnProperty.call(o,"k");',
                [],
            ),
        ):
            with self.subTest(src=src):
                self.assertEqual(self._sinks(src), kinds)

    def test_a_flow_reports_the_names_it_trusted(self) -> None:
        got = self._flow(
            'var pY=[1];pY.some((e)=>e);pY.has(1);var s=""+pY;'
            'function g(n){return"has"in n}g(pY);'
        )
        self.assertTrue(got["safe"], got)
        self.assertEqual(
            got["trusted"],
            ["@@toPrimitive", "has", "join", "some", "toString", "valueOf"],
        )

    def test_exports_lists_every_exported_name(self) -> None:
        src = "export var a=1,{b}=o;export function c(){}var d;export{d as e};"
        self.assertEqual(
            sorted(self.reader.exports(src, 0, len(src)) or []), ["a", "b", "c", "e"]
        )
        self.assertIsNone(self.reader.exports("var =;", 0, 6))


class TestModuleTable(unittest.TestCase):
    """`inventory._graph_sources`: Bun's standalone module table maps each
    module's source offset to its `/$bunfs/root/...` path."""

    @staticmethod
    def _graph(modules: list[tuple[bytes, bytes]]) -> tuple[bytes, list[int]]:
        import struct

        blob = b"\0" * 8
        records = b""
        starts = []
        for name, body in modules:
            name_at = len(blob)
            blob += name + b"\0"
            body_at = len(blob)
            starts.append(body_at)
            blob += body + b"\0"
            records += (
                struct.pack("<4I", name_at, len(name), body_at, len(body)) + b"\0" * 36
            )
        table = len(blob)
        blob += records
        offsets = struct.pack("<QII", len(blob), table, len(records)) + b"\0" * 16
        return b"MZ-prefix" + blob + offsets + inv._GRAPH_TRAILER, starts

    def test_each_source_offset_maps_to_its_path(self) -> None:
        data, starts = self._graph(
            [
                (b"/$bunfs/root/chunk-a.js", b"// @bun\nvar a=1;"),
                (b"/$bunfs/root/b.js", b"// @bun\n"),
            ]
        )
        prefix = len(b"MZ-prefix")
        self.assertEqual(
            inv._graph_sources(data),
            {
                prefix + starts[0]: "/$bunfs/root/chunk-a.js",
                prefix + starts[1]: "/$bunfs/root/b.js",
            },
        )

    def test_a_build_without_a_table_maps_nothing(self) -> None:
        self.assertEqual(inv._graph_sources(b"no graph here"), {})


class _StubReader:
    """Stands in for the helper: every module parses unless its text says not."""

    lookups = 0
    write_lookups = 0
    flow_lookups = 0

    def __init__(self) -> None:
        self.parsed = 0

    def set_module_paths(self, src: str, paths: dict[int, str]) -> None:
        pass

    def parse_module(self, src: str, lo: int, hi: int) -> tuple[bool, str | None]:
        self.parsed += 1
        source = src[lo:hi]
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
        """The flip to the parser is held (#5901)."""
        with mock.patch.object(pr, "open_reader") as opened:
            code, out = self._run("--binary-only")
        self.assertEqual(code, 0)
        self.assertNotIn("reader", json.loads(out))
        self.assertIn("help", json.loads(out)["builtin_commands"])
        opened.assert_not_called()

    def test_the_parser_stays_selectable(self) -> None:
        stub = _StubReader()
        with self._stub(stub):
            code, out = self._run("--binary-only", "--reader", "parser")
        self.assertEqual(code, 0)
        self.assertEqual(json.loads(out)["reader"]["name"], "parser")
        self.assertEqual(stub.parsed, 1)

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
        _, regex = self._run("--binary-only", "--reader", "regex")
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
