#!/usr/bin/env python3
# test-scope: plugins/harness-ops/skills/inventory/scripts/js/package-lock.json
# test-scope: plugins/harness-ops/skills/inventory/scripts/js/package.json
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

import pathlib
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
    return _probe_source(AGENT_SRC + prelude + PROBE)


def _probe_source(src: str) -> tuple[list[str], str]:
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
    # a member write, a mutating method call, and a call the array is passed
    # to unless it follows the callee's parameter and finds it unchanged, so
    # the list reads as partial: fixed there.
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
            # #5828 review: a member chain as a tagged-template tag, a `new`
            # callee or an optional call, and through call/apply/bind.
            ("pY.pop`x`", INITIAL),
            ("new pY.constructor(1)", INITIAL),
            ("pY.pop?.()", INITIAL),
            ("pY.pop.call(xt)", INITIAL),
            ("pY.pop.apply(xt,[])", INITIAL),
            ("var p=pY.pop.bind(xt)", INITIAL),
            ("(await pY.pop)()", INITIAL),
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

    def test_an_export_no_module_imports_stays_partial(self) -> None:
        """#5891 second verifier: the bundle is not a closed world, and with
        no named importer and no module table the exporter's file is
        unknown, so a namespace of it cannot be ruled out. JavaScript keeps
        the initializer here, so partial is honest, not a wrong value."""
        self.assert_pinned(
            'var pY=[xt,"Artifact"];export{pY};', INITIAL, INITIAL[0], parser=PARTIAL
        )

    def test_a_hop_the_parser_follows_keeps_the_literal_unless_it_changes_the_list(
        self,
    ) -> None:
        """P4 of #5640, inside one module: an alias returned from a function
        whose caller hands the array to `.some(t)`, where `t` reaches it
        through two parameters and an object literal argument (the 2.1.286
        shape), and an argument into a local function. JavaScript keeps the
        list unless a callback or parameter changes it."""
        shape = (
            "var Gr=pY;function Xr(e){if(e)return Gr;return[]}"
            "function ko(e,t){let n=(s)=>Xr(s).some(t);return n(e)}"
            'function Eo(e,t){return typeof t==="function"?ko(e,t):e}'
            "function gn(e,{hook:n}){return Eo(e,n)}"
        )
        for use, changed in (
            ("gn(1,{hook:!1})", False),
            ('gn(1,{hook:(x)=>x==="Edit"})', False),
            ('gn(1,{hook:(x,i,a)=>a.push("B")})', True),
            # A getter: reading `hook` runs it and yields the pushing callback.
            ('gn(1,{get hook(){return(x,i,a)=>a.push("B")}})', True),
        ):
            with self.subTest(use=use):
                self.assert_pinned(
                    'var pY=[xt,"Artifact"];' + shape + use + ";",
                    INITIAL,
                    ["Agent", "Edit", "Artifact", "B"] if changed else INITIAL[0],
                    parser=PARTIAL if changed else INITIAL,
                )
        for use, changed in (
            ('function g(a,b){return b.includes(a)}g("x",pY)', False),
            ('function g(a,b){b.push(a)}g("B",pY)', True),
            ("pY.forEach((e,i,a)=>a.pop())", True),
        ):
            with self.subTest(use=use):
                self.assert_pinned(
                    'var pY=[xt,"Artifact"];' + use + ";",
                    INITIAL,
                    ["(changed)"] if changed else INITIAL[0],
                    parser=PARTIAL if changed else INITIAL,
                )

    def test_a_patched_prototype_leaves_a_followed_list_partial(self) -> None:
        """#5891 verifier probes: each patches the method the array calls
        through a prototype reached other than as `Array.prototype.x=`, and
        JavaScript runs the patch, which pushes onto the list."""
        patch = 'function(){this.push("B");return!0}'
        for prelude in (
            "var AP=Array.prototype;AP.includes=" + patch + ';pY.includes("x")',
            "[].__proto__.includes=" + patch + ';pY.includes("x")',
            "Object.getPrototypeOf([]).join=" + patch + ";pY.join()",
            'Array["prototype"].includes=' + patch + ';pY.includes("x")',
            "const{prototype:AP}=Array;AP.includes=" + patch + ';pY.includes("x")',
            "var OP=Object.prototype;OP.zz=" + patch + ";pY.zz()",
            # The second #5891 verifier's probes, which the reachability
            # guard missed; the sink rule sees the write of the name.
            "var A=Array;A.prototype.includes=" + patch + ';pY.includes("x")',
            "(0,Array).prototype.includes=" + patch + ';pY.includes("x")',
            "globalThis.Array.prototype.includes=" + patch + ';pY.includes("x")',
            'Array["proto"+"type"].includes=' + patch + ';pY.includes("x")',
            'Reflect.get(Array,"prototype").includes=' + patch + ';pY.includes("x")',
            "var e={hasOwnProperty(o){o.includes="
            + patch
            + '}};e.hasOwnProperty.call(null,Array.prototype);pY.includes("x")',
            "function G(o,k){o.includes="
            + patch
            + '}G(Array.prototype,"__proto__");pY.includes("x")',
            "(function(Object){Object.prototype.includes="
            + patch
            + '})(Array);pY.includes("x")',
            "class WeakSet{constructor(a){a[0].includes="
            + patch
            + '}}new WeakSet([Array.prototype]);pY.includes("x")',
            'Array.prototype.__defineGetter__("includes",function(){return '
            + patch
            + '});pY.includes("x")',
            "var Q=[].__proto__;Q.includes=" + patch + ';pY.includes("x")',
            "var Q=Object.getPrototypeOf([]);Q.includes=" + patch + ';pY.includes("x")',
            # The third #5891 verifier's probes: F.prototype replaced through
            # a reference to F, so F.prototype is not F's own object.
            'function F(){}Object.defineProperty(F,"prototype",{value:Array.prototype});'
            "F.prototype.includes=" + patch + ';pY.includes("x")',
            'function F(){}F["proto"+"type"]=Array.prototype;F.prototype.includes='
            + patch
            + ';pY.includes("x")',
            "function F(){}var G=F;G.prototype=Array.prototype;F.prototype.includes="
            + patch
            + ';pY.includes("x")',
            "function F(){}function s(o){o.prototype=Array.prototype}s(F);"
            "F.prototype.includes=" + patch + ';pY.includes("x")',
            # `Object.create` itself can be replaced, so its result is no fresh object.
            "Object.create=()=>Array.prototype;var o=Object.create(null);o.includes="
            + patch
            + ';pY.includes("x")',
            # A compound assignment on an alias coerces the array first.
            'var a=pY;Array.prototype.toString=function(){this.push("B");return""};a+=""',
            # A template-literal key names the method as a string does.
            "Object.defineProperty(Array.prototype,`includes`,{value:"
            + patch
            + '});pY.includes("x")',
            # Reflect.set writes onto its receiver, not its target.
            'Reflect.set({},"includes",' + patch + ',Array.prototype);pY.includes("x")',
            # F.prototype.constructor is F, so it can replace F.prototype.
            "function F(){}F.prototype.constructor.prototype=Array.prototype;"
            "F.prototype.includes=" + patch + ';pY.includes("x")',
            # A derived class's `this` is what `super()` returned.
            "class B0{constructor(){return Array.prototype}}"
            "class X extends B0{constructor(){super();this.includes="
            + patch
            + '}}new X;pY.includes("x")',
            "var X=class extends function(){return Array.prototype}{constructor(){"
            "super();this.includes=" + patch + '}};new X;pY.includes("x")',
            # Code built from a string, which no rule sees into.
            "(0,eval)('Array.prototype.includes=function(){this.push(\"B\");return!0}');"
            'pY.includes("x")',
            "Function('Array.prototype.includes=function(){this.push(\"B\");return!0}')();"
            'pY.includes("x")',
            "Function.call(0,'Array.prototype.includes=function(){this.push(\"B\");return!0}')();"
            'pY.includes("x")',
            "globalThis.eval('Array.prototype.includes=function(){this.push(\"B\");return!0}');"
            'pY.includes("x")',
            # A write whose key names nothing can write `includes` too.
            'function s(o,k,v){o[k]=v}s(Array.prototype,"inc"+"ludes",'
            + patch
            + ');pY.includes("x")',
        ):
            with self.subTest(prelude=prelude):
                self.assert_pinned(
                    'var pY=[xt,"Artifact"];' + prelude + ";",
                    INITIAL,
                    ["Agent", "Edit", "Artifact", "B"],
                    parser=PARTIAL,
                )

    def test_instanceof_hands_the_array_to_has_instance(self) -> None:
        """#5891 verifier probe: `Symbol.hasInstance` runs with the array as
        its argument, so `pY instanceof H` may change it."""
        self.assert_pinned(
            'var pY=[xt,"Artifact"];class H{static[Symbol.hasInstance](a){a.push("B")}}'
            "pY instanceof H;",
            INITIAL,
            ["Agent", "Edit", "Artifact", "B"],
            parser=PARTIAL,
        )

    def test_an_alias_chain_too_deep_to_follow_reads_partial(self) -> None:
        """#5891 verifier probe: a 5,000-long alias chain ending in a push
        crashed the helper, breaking the whole binary source."""
        chain = "".join(f"var a{i}=a{i - 1};" for i in range(1, 5000))
        self.assert_pinned(
            'var pY=[xt,"Artifact"];var a0=pY;' + chain + 'a4999.push("B");',
            INITIAL,
            ["Agent", "Edit", "Artifact", "B"],
            parser=PARTIAL,
        )

    def assert_across_modules(
        self, changed: bool, *modules: str, table: bool = True
    ) -> None:
        """The probe's module exports `pY` and `modules` follow it, each
        opening with a `// @bun` header as a bundle's modules do. With
        `table`, Bun's module table names them `/a.js`, `/b.js`, ... in
        order. The regex reader never looks past the binding, so it keeps
        the initializer; the parser follows the export and reads partial
        exactly when JavaScript changes the list."""
        src = (
            AGENT_SRC
            + 'var pY=[xt,"Artifact"];'
            + PROBE
            + "export{pY};"
            + "".join("\n// @bun\n" + m for m in modules)
        )
        self.assertEqual(_probe_source(src), INITIAL)
        if type(self).reader is None:
            type(self).reader = pr.ParserReader(_require_live(self))
        if table:
            type(self).reader.set_module_paths(
                src,
                {
                    lo: f"/{chr(97 + i)}.js"
                    for i, lo in enumerate(inv._chunk_starts(src))
                },
            )
        with inv.use_reader(type(self).reader):
            got = _probe_source(src)
        self.assertEqual(got, PARTIAL if changed else INITIAL, modules)

    def test_an_export_is_followed_to_every_importer(self) -> None:
        """P4 of #5640: the 2.1.284-2.1.287 shape, where the array is
        exported and its importers spread it, call `includes`, alias it and
        return it to a `.some` caller, re-export it, and pass it to an
        imported function."""
        imp = 'import{pY}from"/a.js";'
        self.assert_across_modules(False, imp + 'var c=[...pY];pY.includes("x");')
        self.assert_across_modules(True, imp + 'pY.push("B");')
        self.assert_across_modules(True, 'import{pY as q}from"/a.js";var r=q;r.pop();')
        hop = (
            imp + "var Gr=pY;function Xr(e){return Gr}"
            "function ko(e,t){return Xr(e).some(t)}function gn(e,{hook:n}){return ko(e,n)}"
        )
        self.assert_across_modules(False, hop + "gn(1,{hook:!1});")
        self.assert_across_modules(True, hop + 'gn(1,{hook:(x,i,a)=>a.push("B")});')

    def test_a_reexport_is_followed_again(self) -> None:
        reexport = 'import{pY}from"/a.js";export{pY as W};'
        self.assert_across_modules(False, reexport, 'import{W}from"/b.js";W.join();')
        self.assert_across_modules(True, reexport, 'import{W}from"/b.js";W.push("B");')
        self.assert_across_modules(
            True, 'export{pY as W}from"/a.js";', 'import{W}from"/b.js";W.pop();'
        )

    def test_an_imported_callee_is_followed_to_its_exporter(self) -> None:
        caller = 'import{pY}from"/a.js";import{g}from"/c.js";g("x",pY);'
        self.assert_across_modules(
            False, caller, "function g(a,b){return b.includes(a)}export{g};"
        )
        self.assert_across_modules(
            True, caller, 'function g(a,b){b.push("B")}export{g};'
        )
        self.assert_across_modules(True, caller, "export function g(a,b){b.pop()}")
        # A `g` with no `export` of its own stays partial too.
        self.assert_across_modules(True, caller, "function g(a,b){}")

    def test_an_imported_callee_binds_the_exports_own_local(self) -> None:
        """#5891 review (claude[bot]): the exporter fallback bound the name
        to any same-named local. A re-export (`export{g}from"/d.js"`) is
        followed to its own source, and an aliased export (`export{h as g}`)
        binds its local `h`, never a same-named `g` beside it."""
        caller = 'import{pY}from"/a.js";import{g}from"/c.js";g("x",pY);'
        harmless = "function g(a,b){return b.includes(a)}"
        for chunk_c, chunk_d, changed in (
            (
                harmless + 'export{g as k};export{g}from"/d.js";',
                'function g(a,b){b.push("B")}export{g};',
                True,
            ),
            (
                harmless + 'export{g as k};export{g}from"/d.js";',
                harmless + "export{g};",
                False,
            ),
            (harmless + 'function h(a,b){b.push("B")}export{h as g};', "", True),
            ('function g(a,b){b.push("B")}function h(a,b){}export{h as g};', "", False),
        ):
            with self.subTest(chunk_c=chunk_c, chunk_d=chunk_d):
                self.assert_across_modules(changed, caller, chunk_c, chunk_d)

    def test_an_imported_callee_resolves_by_its_from_path_not_its_name(self) -> None:
        """#5891 review (Codex): the array module imports `g` from chunk
        /c.js, which pushes `B`, while an unrelated chunk /d.js exports a
        harmless `g`; resolving by name alone followed /d.js and read a
        wrong literal. An import from a file outside the bundle, or with no
        module table, cannot be followed either."""
        harmless = "function g(a,b){return b.includes(a)}export{g};"
        self.assert_across_modules(
            True,
            'import{pY}from"/a.js";import{g}from"/c.js";g("x",pY);',
            'function g(a,b){b.push("B")}export{g};',
            harmless,
        )
        self.assert_across_modules(
            True,
            'import{pY}from"/a.js";import{g}from"node:external";g("x",pY);',
            harmless,
        )
        self.assert_across_modules(
            True,
            'import{pY}from"/a.js";import{g}from"/c.js";g("x",pY);',
            harmless,
            table=False,
        )

    def test_a_module_taken_whole_as_a_namespace_stays_partial(self) -> None:
        """#5891 verifier probes: a namespace read with a computed key, an
        enumeration or a spread reaches the export without naming it. The
        exporter's file comes from its importers' `from"..."`, and any
        `import*as`, `export*` or `import(...)` of that file reads partial."""
        named = 'import{pY}from"/a.js";var c=[...pY];'
        for module in (
            'import*as N from"/a.js";N[k].push("B");',
            'import*as N from"/a.js";Object.values(N).forEach((v)=>v.push&&v.push("B"));',
            'import*as N from"/a.js";var o={...N};for(var k in o)o[k].push("B");',
            'import("/a.js").then((N)=>{for(var k in N)N[k].push("B")});',
            'export*from"/a.js";',
        ):
            with self.subTest(module=module):
                self.assert_across_modules(True, named, module)

    def test_a_namespace_read_only_by_name_keeps_the_literal(self) -> None:
        """#5901: each whole load of the exporting file that reads only other
        exports by name, the shapes 2.1.284-2.1.288 load the Explore/Plan
        array's re-exporter with, reaches no `pY`, so the literal stands."""
        named = 'import{pY}from"/a.js";var c=[...pY];'
        for module in (
            'import("/a.js");',
            'var{q:x,"r":y}=await import("/a.js");',
            'var x=import.meta.require("/a.js").q,y=import.meta.url;',
            'var n=null,e={name:import.meta.require("/a.js").q,names:import.meta.require("/a.js")},'
            "M=[...e?[e.name,e.names.q]:[]],T={...e&&{[e.names.r]:e.name}};",
            'var[{q},,{r}]=await Promise.all([import("/a.js"),import("/c.js"),import("/a.js")]);',
            'async function f(){let[{q}]=await Promise.all([import("/a.js")]);return q}',
            'import*as N from"/a.js";var x=N.q,y=typeof N;',
        ):
            with self.subTest(module=module):
                self.assert_across_modules(False, named, module)

    def test_a_namespace_read_other_than_by_name_stays_partial(self) -> None:
        """#5901 adversarial probes, one or more per acceptance rule: each
        shape can reach `pY` without naming it, or runs code the walk cannot
        see with the namespace in hand, so the list reads partial."""
        named = 'import{pY}from"/a.js";var c=[...pY];'
        for module in (
            # A namespace read by name: a method call passes it as `this`.
            'import.meta.require("/a.js").f();',
            '(import.meta.require("/a.js")?.f)();',
            # Destructuring: a rest element takes every export.
            'var{q,...o}=await import("/a.js");o.pY.push("B");',
            'var o={...await import("/a.js")};',
            # import.meta must be read only by name.
            'import.meta.require=(p)=>Q;var x=import.meta.require("/a.js").q;',
            'var m=import.meta;var x=m.require("/a.js").q;',
            # A record: a computed read, an escape, `||`, an accessor, a
            # second write, a method call.
            'var e={names:import.meta.require("/a.js")};e.names[k].push("B");',
            'var e={names:import.meta.require("/a.js")};f(e);',
            'var e={names:import.meta.require("/a.js")},x=e||0;',
            'var e={names:import.meta.require("/a.js"),get g(){return this}};var x=e.g;',
            'var e={names:import.meta.require("/a.js")};e={};',
            'var e={names:import.meta.require("/a.js"),f(){return this.names}};e.f();',
            'var e={names:import.meta.require("/a.js"),f(){return this.names}};(e?.f)();',
            # Promise.all: a rest element, a local `Promise`, no array pattern.
            'var[...r]=await Promise.all([import("/a.js")]);',
            'var Promise={all:(a)=>a};var[{q}]=await Promise.all([import("/a.js")]);',
            'var r=await Promise.all([import("/a.js")]);r[0][k].push("B");',
            # A promise not awaited directly.
            'var p=import("/a.js");',
        ):
            with self.subTest(module=module):
                self.assert_across_modules(True, named, module)

    def test_what_a_namespace_load_trusts_stays_checked(self) -> None:
        """#5901: Promise.all and await take built-ins on trust, so a module
        replacing one is a sink; and a promise settled with the namespace
        calls its `then` export with the namespace as `this`."""
        named = 'import{pY}from"/a.js";var c=[...pY];'
        loader = 'var[{q}]=await Promise.all([import("/a.js")]);'
        self.assert_across_modules(True, named, loader, "Promise=function(){};")
        self.assert_across_modules(
            True, named, loader, "Promise.resolve=function(p){return p};"
        )
        self.assert_across_modules(
            True, named, loader, 'Object.defineProperty(Q,"then",{});'
        )
        # Await reads the promise's `constructor`; a record read of a key
        # the literal lacks reads Object.prototype.
        getter = '{get(){for(var k in this.names)this.names[k].push("B")}}'
        self.assert_across_modules(
            True,
            named,
            'var{q}=await import("/a.js");',
            'Object.defineProperty(Promise.prototype,"constructor",{get(){}});',
        )
        self.assert_across_modules(
            True,
            named,
            'var e={names:import.meta.require("/a.js")},x=e.zz;',
            f'Object.defineProperty(Object.prototype,"zz",{getter});',
        )
        reexport = 'export{pY as W}from"/a.js";export function '
        awaited = 'var{q}=await import("/b.js");'
        self.assert_across_modules(False, reexport + "f(){}", awaited)
        self.assert_across_modules(
            True,
            reexport + 'then(r){for(var k in this)this[k].push&&this[k].push("B")}',
            awaited,
        )
        # An `export*` can bring in a `then` the module does not list.
        self.assert_across_modules(
            True, reexport + 'f(){}export*from"/d.js";', awaited, "export var then;"
        )

    def test_a_computed_key_known_to_name_no_trusted_name_clears(self) -> None:
        """#5901 key provenance: the flow trusts `includes`, so any module
        that may write `includes` on an object that could be a prototype
        is a sink. A computed key whose every value is known and none is
        `includes` cannot: a loop counter, arithmetic, a TypeScript enum's
        `e[e.X=1]`, a constant other name."""
        named = 'import{pY}from"/a.js";pY.includes("x");'
        for module in (
            "for(let i=0;i<n;i++)Q[i]=0;Q[i*2+1]=0;Q[-i]=0;",
            '(function(e){e[e.A=0]="A";e[e.B=1]="B"})(Q);',
            'var k="other",j=c?"a":"b";Q[k]=0;Q[j]=1;delete Q[typeof x];',
        ):
            with self.subTest(module=module):
                self.assert_across_modules(False, named, module)

    def test_a_computed_key_that_may_name_a_trusted_name_stays_a_sink(
        self,
    ) -> None:
        """#5901 adversarial probes for key provenance: each key can spell
        `includes` (directly, after a second write, through a cycle, from a
        loop over values, or not at all knowably), so the list reads
        partial."""
        named = 'import{pY}from"/a.js";pY.includes("x");'
        for module in (
            'var k="includes";Q[k]=f;',
            'var k=0;k="includes";Q[k]=f;',
            'var s="inc";s=s+"ludes";Q[s]=f;',
            'var s="inc";s+="ludes";Q[s]=f;',
            'for(const k of ["includes"])Q[k]=f;',
            'var k=c?0:"includes";Object.defineProperty(Q,k,{value:f});',
            "Q[a+b]=f;",
            'Q[`inc${"ludes"}`]=f;',
            "function g(k){Q[k]=f}g(n);",
        ):
            with self.subTest(module=module):
                self.assert_across_modules(True, named, module)

    def test_a_bundle_calling_vm_run_in_this_context_stays_partial(self) -> None:
        """node:vm runs a string as code in this realm, where it could patch
        the `includes` the flow trusts, so each spelling is a sink like
        `eval`; a named import that runs no code is not."""
        named = 'import{pY}from"/a.js";pY.includes("x");'
        for module in (
            'import vm from"node:vm";vm.runInThisContext(s);',
            'var vm=require("vm");vm.runInThisContext(s);',
            'new(require("vm").Script)(s).runInThisContext();',
            'var{compileFunction:c}=import.meta.require("node:vm");c(s)();',
            'import{runInThisContext as r}from"vm";r(s);',
            'import*as V from"node:vm";var k="runIn"+"ThisContext";V[k](s);',
            'var vm=require("vm");g(vm);',
            # A new context still reaches this realm through
            # `this.constructor.constructor`.
            'import{runInNewContext as r}from"node:vm";r(s);',
            'var vm=require("vm");vm.runInContext(s,vm.createContext({}));',
            'import{Script}from"vm";new Script(s).runInNewContext();',
            'import*as V from"node:vm";new V.SourceTextModule(s);',
        ):
            with self.subTest(module=module):
                self.assert_across_modules(True, named, module)
        self.assert_across_modules(False, named, 'import{isContext}from"node:vm";')

    def test_a_load_the_parser_cannot_name_stays_partial(self) -> None:
        """#5970 verifier probes: a load whose file the AST does not name
        (an aliased or `.call`ed require, a comma callee, a specifier that
        is no literal) could load the exporting file whole, so the hop
        stays partial. A direct literal load and `typeof require` stay
        literal."""
        named = 'import{pY}from"/a.js";var c=[...pY];'
        for module in (
            'var r=import.meta.require,n=r("/a.js");for(var k in n)n[k].push&&n[k].push("B");',
            'var n=require.call(null,"/a.js");for(var k in n)n[k].push&&n[k].push("B");',
            'var n=(0,require)("/a.js");for(var k in n)n[k].push&&n[k].push("B");',
            'var n=import.meta.require.call(0,"/a.js");for(var k in n)n[k].push("B");',
            'var n=await import(s);for(var k in n)n[k].push&&n[k].push("B");',
            "var n=require(s);",
            # #5970 Codex: a destructured or aliased `import.meta`.
            'const{require:r}=import.meta;var n=r("/a.js");for(var k in n)n[k].push("B");',
            'var m=import.meta,n=m["req"+"uire"]("/a.js");for(var k in n)n[k].push("B");',
            'var{require:r}=globalThis;var n=r("/a.js");for(var k in n)n[k].push("B");',
        ):
            with self.subTest(module=module):
                self.assert_across_modules(True, named, module)
        for module in (
            'var x=require("/c.js").q,t=typeof require,p=require.resolve("/c.js");',
            "function f(require){return 1}var o={require:1};",
        ):
            with self.subTest(module=module):
                self.assert_across_modules(False, named, module)

    def test_an_exporter_whose_file_is_unknown_stays_partial(self) -> None:
        """#5891 second verifier: the bundle is not a closed world. With no
        module table and no named importer the exporter's file is unknown,
        so nothing rules out a namespace of it, and here one pushes `B`."""
        self.assert_across_modules(
            True, 'import*as N from"/a.js";N[k].push("B");', table=False
        )

    def test_the_module_table_names_the_exporters_own_file(self) -> None:
        """With Bun's module table, the exporter's own path decides, named
        importer or not: the 2.1.284-2.1.288 re-exporting chunk of the
        Explore/Plan array is loaded whole 13 to 14 times by `import(...)`
        and `import.meta.require(...)`, here a record never read and one
        whose namespace is read by a computed key."""
        if type(self).reader is None:
            type(self).reader = pr.ParserReader(_require_live(self))
        reader = type(self).reader
        exporter = AGENT_SRC + 'var pY=[xt,"Artifact"];' + PROBE + "export{pY};"
        for loader, changed in (
            ('var n={names:import.meta.require("/$bunfs/root/chunk-a.js")};', False),
            (
                'var n={names:import.meta.require("/$bunfs/root/chunk-a.js")};'
                'n.names[k].push("B");',
                True,
            ),
            ('import("/$bunfs/root/chunk-b.js");', False),
        ):
            with self.subTest(loader=loader):
                src = exporter + "\n// @bun\n" + loader
                reader.set_module_paths(src, {0: "/$bunfs/root/chunk-a.js"})
                with inv.use_reader(reader):
                    self.assertEqual(
                        _probe_source(src), PARTIAL if changed else INITIAL
                    )

    def test_a_hop_it_cannot_follow_stays_partial(self) -> None:
        """A namespace read by name, a patched prototype, a callback from
        another module, a direct eval in an importer: each could change the
        list, and the parser cannot follow it, so it reads partial."""
        imp = 'import{pY}from"/a.js";'
        for modules in (
            ('import*as N from"/a.js";N.pY.push("B");',),
            (
                imp
                + 'Array.prototype.includes=function(){this.push("B")};pY.includes("x");',
            ),
            (imp + "function k(t){return pY.some(t)}export{k};",),
            (imp + 'pY.includes("x");function e(){eval("")}',),
            (imp + 'function r(){return pY}r().push("B");',),
        ):
            with self.subTest(modules=modules):
                self.assert_across_modules(True, *modules)

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
        and `optimistic` stays off because `eval` can rebind names. Each of
        2.1.284-2.1.288 has one module with one (protobufjs's `inquire`),
        off every flow path, which the sink rule counts against any name a
        flow trusts."""
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


INSTALLED = pathlib.Path.home() / ".local" / "share" / "claude" / "versions"


class TestInstalledBuilds(unittest.TestCase):
    """P4 of #5640 on the builds that motivated it: the Explore and Plan
    agents' `disallowed_tools` spread an array that is exported, aliased,
    returned to a `.some(t)` caller and passed to an imported function.
    The flow follows every hop, and since #5901 every whole load of the
    re-exporting chunk too (13 to 14 per build, each read by name). It
    trusts `some`, `includes` and `has` as built in, and the namespace
    loads trust Promise.all and await, but every one of these builds has
    modules that may write those names on an object the sink rule cannot
    show is no prototype (a write whose key names nothing,
    `Object.defineProperty(o,k,...)`) or that run code built from a string
    (ajv's `Function(...)`, a direct `eval`); 2.1.288 also has 3 modules
    with a load the parser cannot name. So both lists read partial
    under the parser: never a value the regex reader does not also read.
    Each build is skipped when it is not installed on this machine."""

    def test_explore_and_plan_read_partial_under_the_parser(self) -> None:
        target = _require_live(self)
        for version in ("2.1.284", "2.1.285", "2.1.286", "2.1.287", "2.1.288"):
            with self.subTest(version=version):
                binary = INSTALLED / version
                if not binary.is_file():
                    self.skipTest(f"Claude Code {version} is not installed at {binary}")
                spans: list[tuple[int, int]] = []
                src, _ = inv.read_bundle(binary, spans)
                assert src is not None
                braces = inv.build_brace_map(src)
                regex = inv.extract_builtin_agents(src, braces)[0]
                with pr.ParserReader(target) as reader:
                    for lo, hi in spans:
                        reader.parse_module(src, lo, hi)
                    with inv.use_reader(reader):
                        parsed = inv.extract_builtin_agents(src, braces)[0]
                for agent in ("Explore", "Plan"):
                    self.assertEqual(
                        parsed[agent]["disallowed_tools_source"], "partial"
                    )
                    got = parsed[agent]["disallowed_tools"]
                    self.assertTrue(set(got) < set(regex[agent]["disallowed_tools"]))


if __name__ == "__main__":
    unittest.main()
