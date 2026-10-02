"use strict";
// Long-lived parser helper for inventory.py --reader=parser.
//
// Protocol: one JSON request per line on stdin, one JSON response per line on
// stdout, in order. Every response echoes the request's `id`.
//
//   {"id":1,"op":"ping"}
//     -> {"id":1,"ok":true,"node":"v24.0.0","acorn":"8.18.0","eslint_scope":"9.1.2"}
//   {"id":2,"op":"parse_ok","source":"..."}
//     -> {"id":2,"ok":true,"parsed":true}
//     -> {"id":2,"ok":true,"parsed":false,"error":"Unexpected token (3:4)","pos":17}
//   {"id":3,"op":"binding","module":"<key>","source":"...","offset":120,"name":"pY"}
//   {"id":4,"op":"binding","module":"<key>","top":true,"name":"pY"}
//     The variable `name` resolves to, read at `offset` in the module, or the
//     module-scope variable of that name with `top`. `source` may be left out
//     once the helper holds the module; the reply is then `need_source` until
//     it is sent again. Offsets are UTF-16 code units from the module start.
//     -> {"id":3,"ok":true,"found":false}                   undeclared, or global
//     -> {"id":3,"ok":true,"found":false,"error":"..."}     the module does not parse
//     -> {"id":3,"ok":true,"found":true,"kind":"import","imported":"x"}
//     -> {"id":3,"ok":true,"found":true,"kind":"Variable",
//         "defs":[[type,name_offset,node_offset,top]],"writes":[[offset,top]]}
//        Two lookups name the same variable exactly when their defs match.
//        `top` is true for a write or declaration in the module scope itself.
//   anything else
//     -> {"id":...,"ok":false,"error":"..."}
//
// A binding lookup parses its module once and keeps the scope analysis for
// the next MODULE_CACHE lookups' worth of other modules.
//
// acorn and eslint-scope are resolved through NODE_PATH, which the Python
// side points at the node_modules `npm ci` installed from this directory's
// lockfile. Both are required at load, so a ping answering at all proves the
// whole dependency set loads.

const readline = require("node:readline");

let acorn;
let eslintScope;
try {
  acorn = require("acorn");
  eslintScope = require("eslint-scope");
} catch (e) {
  process.stderr.write(`cannot load the parser packages: ${e.message.split("\n")[0]}\n`);
  process.exit(1);
}

const PARSE_OPTIONS = { ecmaVersion: "latest", sourceType: "module" };
const SCOPE_OPTIONS = { ecmaVersion: 2025, sourceType: "module" };
const MODULE_CACHE = 16;
const modules = new Map();

function analyze(source) {
  let manager;
  try {
    // eslint-scope reads node.range, which acorn adds only on request.
    manager = eslintScope.analyze(acorn.parse(source, { ...PARSE_OPTIONS, ranges: true }), SCOPE_OPTIONS);
  } catch (e) {
    return { error: e.message };
  }
  const top = manager.globalScope.childScopes.find((s) => s.type === "module");
  const refs = new Map();
  const decls = new Map();
  for (const scope of manager.scopes) {
    for (const ref of scope.references) refs.set(ref.identifier.start, ref);
    for (const v of scope.variables) {
      for (const ident of v.identifiers) decls.set(ident.start, v);
    }
  }
  // A name no scope declares is one implicit global, whichever scope uses it.
  const globals = new Map();
  for (const ref of manager.globalScope.through) {
    const name = ref.identifier.name;
    if (!globals.has(name)) globals.set(name, { name, defs: [], references: [], scope: null });
    globals.get(name).references.push(ref);
  }
  return { manager, top, refs, decls, globals };
}

function moduleFor(req) {
  let entry = modules.get(req.module);
  if (entry) {
    modules.delete(req.module);
  } else if (typeof req.source === "string") {
    entry = analyze(req.source);
  } else {
    return null;
  }
  modules.set(req.module, entry);
  if (modules.size > MODULE_CACHE) modules.delete(modules.keys().next().value);
  return entry;
}

function innermostScope(manager, offset) {
  let best = null;
  for (const scope of manager.scopes) {
    const { start, end } = scope.block;
    if (start <= offset && offset < end && (!best || end - start <= best.block.end - best.block.start)) {
      best = scope;
    }
  }
  return best;
}

function lookup(entry, req) {
  if (req.top) return entry.top?.set.get(req.name) ?? null;
  if (entry.decls.get(req.offset)?.name === req.name) return entry.decls.get(req.offset);
  const ref = entry.refs.get(req.offset);
  if (ref && ref.identifier.name === req.name && ref.resolved) return ref.resolved;
  for (let s = innermostScope(entry.manager, req.offset); s; s = s.upper) {
    const v = s.set.get(req.name);
    if (v) return v;
  }
  return entry.globals.get(req.name) ?? null;
}

function describe(entry, v) {
  if (!v) return { found: false };
  const def = v.defs[0];
  if (def?.type === "ImportBinding") {
    const spec = def.node;
    const imported =
      spec.type === "ImportSpecifier" ? (spec.imported.name ?? spec.imported.value) : spec.type === "ImportDefaultSpecifier" ? "default" : "*";
    return { found: true, kind: "import", imported };
  }
  const atTop = v.scope === entry.top;
  return {
    found: true,
    kind: def?.type ?? "ImplicitGlobal",
    defs: v.defs.map((d) => [d.type, d.name.start, d.node.start, atTop]),
    writes: v.references.filter((r) => r.isWrite()).map((r) => [r.identifier.start, r.from === entry.top]),
  };
}

function binding(req) {
  if (typeof req.module !== "string" || typeof req.name !== "string") {
    return { ok: false, error: "binding needs a string `module` and `name`" };
  }
  if (!req.top && !Number.isInteger(req.offset)) {
    return { ok: false, error: "binding needs an integer `offset` or `top`" };
  }
  const entry = moduleFor(req);
  if (entry === null) return { ok: true, need_source: true };
  if (entry.error) return { ok: true, found: false, error: entry.error };
  return { ok: true, ...describe(entry, lookup(entry, req)) };
}

function handle(req) {
  switch (req.op) {
    case "ping":
      return {
        ok: true,
        node: process.version,
        acorn: acorn.version,
        eslint_scope: eslintScope.version,
      };
    case "parse_ok":
      if (typeof req.source !== "string") {
        return { ok: false, error: "parse_ok needs a string `source`" };
      }
      try {
        acorn.parse(req.source, PARSE_OPTIONS);
        return { ok: true, parsed: true };
      } catch (e) {
        return { ok: true, parsed: false, error: e.message, pos: e.pos ?? null };
      }
    case "binding":
      return binding(req);
    default:
      return { ok: false, error: `unknown op: ${JSON.stringify(req.op)}` };
  }
}

const rl = readline.createInterface({ input: process.stdin, crlfDelay: Infinity });
rl.on("line", (line) => {
  let req;
  try {
    req = JSON.parse(line);
  } catch (e) {
    process.stdout.write(`${JSON.stringify({ id: null, ok: false, error: `bad request: ${e.message}` })}\n`);
    return;
  }
  const res = handle(req);
  process.stdout.write(`${JSON.stringify({ id: req.id ?? null, ...res })}\n`);
});
