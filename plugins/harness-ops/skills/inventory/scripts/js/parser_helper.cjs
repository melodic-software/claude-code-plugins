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
//   {"id":5,"op":"writes","module":"<key>","source":"...","offset":120,"name":"pY"}
//     Every place that may change the variable `binding` would return for
//     the same request. `writes` are the references eslint-scope marks as
//     writes, each [kind, offset, top] with kind one of init, assign,
//     compound, update, destructure, for-in-of, plus a function or class
//     declaration of the same name as kind declaration. `mutations` are
//     the reads that may change the value, which is every read except a
//     spread into an array or call and a member read used as a value:
//     member-write (`x.y=`, `x[i]++`, `[x.y]=`), member-delete
//     (`delete x.y`), method-call (any call along a member chain rooted at
//     the variable), object-assign (`Object.assign(x,...)`), call-argument
//     (passed directly to any call, `new` or tagged template), and escape
//     (anything else: an alias, a literal holding it, a return, an operand,
//     `await`, a loop iterable, a destructuring source, an export).
//     `declares` is whether `offset` names a plain `var`/`let`/`const`
//     declarator of the variable. A module with a direct `eval` answers
//     found false, since code inside the eval can write any name.
//     -> {"id":5,"ok":true,"found":true,"declares":true,
//         "writes":[["init",120,true]],"mutations":[["method-call",160,true]]}
//   anything else
//     -> {"id":...,"ok":false,"error":"..."}
//
// A binding or writes lookup parses its module once and keeps the scope
// analysis for the next MODULE_CACHE lookups' worth of other modules.
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
// `optimistic` stays off: a direct `eval` can rebind any name in the scopes
// around it, so eslint-scope leaves their references unresolved, and an
// unresolved value is preferred to a possibly wrong one.
const SCOPE_OPTIONS = { ecmaVersion: 2025, sourceType: "module" };
const MODULE_CACHE = 16;
const PATTERN_NODES = new Set(["ArrayPattern", "ObjectPattern", "AssignmentPattern", "RestElement", "Property"]);
const modules = new Map();

function analyze(source) {
  let ast;
  let manager;
  try {
    // eslint-scope reads node.range, which acorn adds only on request.
    ast = acorn.parse(source, { ...PARSE_OPTIONS, ranges: true });
    manager = eslintScope.analyze(ast, SCOPE_OPTIONS);
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
  const evals = manager.scopes.some((s) => s.directCallToEvalScope);
  return { ast, manager, top, refs, decls, globals, evals, parents: null };
}

// Each node's parent, built on the module's first `writes` request.
function parentsOf(entry) {
  if (entry.parents) return entry.parents;
  const parents = new Map();
  const stack = [entry.ast];
  while (stack.length) {
    const node = stack.pop();
    for (const key of Object.keys(node)) {
      const child = node[key];
      for (const c of Array.isArray(child) ? child : [child]) {
        if (c && typeof c.type === "string" && c !== node) {
          parents.set(c, node);
          stack.push(c);
        }
      }
    }
  }
  entry.parents = parents;
  return parents;
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

function checkRequest(req) {
  if (typeof req.module !== "string" || typeof req.name !== "string") {
    return { ok: false, error: `${req.op} needs a string \`module\` and \`name\`` };
  }
  if (!req.top && !Number.isInteger(req.offset)) {
    return { ok: false, error: `${req.op} needs an integer \`offset\` or \`top\`` };
  }
  return null;
}

function binding(req) {
  const bad = checkRequest(req);
  if (bad) return bad;
  const entry = moduleFor(req);
  if (entry === null) return { ok: true, need_source: true };
  if (entry.error) return { ok: true, found: false, error: entry.error };
  return { ok: true, ...describe(entry, lookup(entry, req)) };
}

const isLoop = (n) => n?.type === "ForInStatement" || n?.type === "ForOfStatement";

// What a write reference to `id` is, read from the nodes around it.
function writeKind(parents, id) {
  let node = id;
  let parent = parents.get(node);
  let patterned = false;
  while (parent && PATTERN_NODES.has(parent.type)) {
    patterned = true;
    node = parent;
    parent = parents.get(node);
  }
  if (parent?.type === "VariableDeclarator") {
    const declaration = parents.get(parent);
    const loop = parents.get(declaration);
    if (isLoop(loop) && loop.left === declaration) return "for-in-of";
    return patterned ? "destructure" : "init";
  }
  if (isLoop(parent) && parent.left === node) return "for-in-of";
  if (parent?.type === "UpdateExpression") return "update";
  if (patterned) return parent?.type.includes("Function") ? "init" : "destructure";
  if (parent?.type === "AssignmentExpression") return parent.operator === "=" ? "assign" : "compound";
  return "write";
}

// Whether `node` is what an assignment or a loop head writes, directly or
// as a target inside a destructuring pattern.
function isTarget(parents, node) {
  let parent = parents.get(node);
  while (parent && PATTERN_NODES.has(parent.type)) {
    if (parent.type === "Property" && parent.value !== node) return false;
    if (parent.type === "AssignmentPattern" && parent.left !== node) return false;
    node = parent;
    parent = parents.get(node);
  }
  return (parent?.type === "AssignmentExpression" || isLoop(parent)) && parent.left === node;
}

const isObjectAssign = (callee) =>
  callee.type === "MemberExpression" &&
  !callee.computed &&
  callee.object.type === "Identifier" &&
  callee.object.name === "Object" &&
  callee.property.name === "assign";

// Whether `holder` evaluates to `node` itself: the last expression of a
// sequence, either side of a logical, a branch of a conditional.
function forwards(holder, node) {
  switch (holder?.type) {
    case "SequenceExpression":
      return holder.expressions.at(-1) === node;
    case "LogicalExpression":
    case "ChainExpression":
      return true;
    case "ConditionalExpression":
      return holder.test !== node;
    default:
      return false;
  }
}

// How a read of `id` may change the value it reads, or null when it cannot.
// Only two shapes are known safe: a spread into an array or a call, which
// copies the elements, and a member read whose result is used as a value.
// Anything else lets the value escape to code that may change it later
// (an alias, a literal holding it, a return, an operand, `await`, a loop
// iterable, a destructuring source, an export), so it counts.
function mutationKind(parents, id) {
  let node = id;
  let parent = parents.get(node);
  let member = false;
  while (parent && ((parent.type === "MemberExpression" && parent.object === node) || parent.type === "ChainExpression")) {
    member ||= parent.type === "MemberExpression";
    node = parent;
    parent = parents.get(node);
  }
  if (!parent) return "escape";
  if (member) {
    // Any method may return the receiver (`x.valueOf().push()`), and a
    // method read can reach the call through an operand (`(0,x.push)()`).
    let callee = node;
    let holder = parent;
    while (forwards(holder, callee)) {
      callee = holder;
      holder = parents.get(holder);
    }
    if (holder?.type === "CallExpression" && holder.callee === callee) return "method-call";
    if (parent.type === "UnaryExpression" && parent.operator === "delete") return "member-delete";
    if (parent.type === "UpdateExpression" || isTarget(parents, node)) return "member-write";
    return null;
  }
  if (parent.type === "SpreadElement") {
    const holder = parents.get(parent)?.type;
    if (holder === "ArrayExpression" || holder === "CallExpression" || holder === "NewExpression") return null;
  }
  if ((parent.type === "CallExpression" || parent.type === "NewExpression") && parent.arguments.includes(id)) {
    return isObjectAssign(parent.callee) && parent.arguments[0] === id ? "object-assign" : "call-argument";
  }
  if (parent.type === "TemplateLiteral" && parents.get(parent)?.type === "TaggedTemplateExpression") {
    return "call-argument";
  }
  return "escape";
}

function writes(req) {
  const bad = checkRequest(req);
  if (bad) return bad;
  const entry = moduleFor(req);
  if (entry === null) return { ok: true, need_source: true };
  if (entry.error) return { ok: true, found: false, error: entry.error };
  if (entry.evals) return { ok: true, found: false, error: "the module calls eval directly" };
  const v = lookup(entry, req);
  if (!v) return { ok: true, found: false };
  const parents = parentsOf(entry);
  const out = { writes: [], mutations: [] };
  // A function or class declaration rebinds the name with no write
  // reference: `function f(e){function e(){}}` replaces the parameter.
  for (const d of v.defs) {
    if (d.type === "FunctionName" || d.type === "ClassName") {
      out.writes.push(["declaration", d.name.start, v.scope === entry.top]);
    }
  }
  for (const r of v.references) {
    const at = [r.identifier.start, r.from === entry.top];
    if (r.isWrite()) out.writes.push([writeKind(parents, r.identifier), ...at]);
    const kind = r.isReadOnly() ? mutationKind(parents, r.identifier) : null;
    if (kind) out.mutations.push([kind, ...at]);
  }
  const declares =
    !req.top && v.defs.some((d) => d.type === "Variable" && d.name.start === req.offset && d.node.id === d.name);
  return { ok: true, found: true, declares, ...out };
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
    case "writes":
      return writes(req);
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
