"use strict";
// Long-lived parser helper for inventory.py --reader=parser.
//
// Protocol: one JSON request per line on stdin, one JSON response per line on
// stdout, in order. Every response echoes the request's `id`.
//
//   {"id":1,"op":"ping"}
//     -> {"id":1,"ok":true,"node":"v24.0.0","acorn":"8.18.0","eslint_scope":"9.1.2"}
//   {"id":2,"op":"parse_ok","source":"...","module":"<key>"}
//     `module` is optional; with it the module's property names are kept
//     for `keys_used`.
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
//     spread into an array or call and a member read in a value-only
//     position (`valueOnly`): member-write (`x.y=`, `x[i]++`, `[x.y]=`),
//     member-delete (`delete x.y`), method-call (a member chain rooted at
//     the variable as the callee of a call, `new` or tagged template),
//     member-escape (a member read in any other position), object-assign (`Object.assign(x,...)`), call-argument
//     (passed directly to any call, `new` or tagged template), and escape
//     (anything else: an alias, a literal holding it, a return, an operand,
//     `await`, a loop iterable, a destructuring source, an export).
//     `declares` is whether `offset` names a plain `var`/`let`/`const`
//     declarator of the variable. A module with a direct `eval` answers
//     found false, since code inside the eval can write any name.
//     -> {"id":5,"ok":true,"found":true,"declares":true,
//         "writes":[["init",120,true]],"mutations":[["method-call",160,true]]}
//   {"id":6,"op":"flow","module":"<key>","source":"...","start":{...}}
//     Whether an array value stays unchanged inside the module, following
//     it through aliases, returns, arguments and callbacks; `flow` below
//     documents `start` and the reply. The hops that leave the module come
//     back as `exits` for the caller to follow.
//   {"id":7,"op":"keys_used","module":"<key>","source":"...","names":["pY"]}
//     -> {"id":7,"ok":true,"used":["pY"]}   names the module reads as a property
//   {"id":8,"op":"exports","module":"<key>","source":"..."}
//     -> {"id":8,"ok":true,"names":["pY","default"]}   every name it exports
//   anything else
//     -> {"id":...,"ok":false,"error":"..."}
//
// A binding, writes or flow lookup parses its module once and keeps the
// scope analysis for the next MODULE_CACHE lookups' worth of other modules.
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

function isCallee(holder, node) {
  switch (holder?.type) {
    case "CallExpression":
    case "NewExpression":
      return holder.callee === node;
    case "TaggedTemplateExpression":
      return holder.tag === node;
    default:
      return false;
  }
}

// Whether `holder` only reads the value of its child `node`: the member
// read is then a value, never invoked or written through. Any position not
// listed counts as an escape.
function valueOnly(holder, node) {
  switch (holder?.type) {
    case "BinaryExpression":
    case "TemplateLiteral":
    case "ExpressionStatement":
    case "ReturnStatement":
    case "ArrayExpression":
    case "SpreadElement":
      return true;
    case "UnaryExpression":
      return holder.operator !== "delete";
    case "IfStatement":
    case "WhileStatement":
    case "DoWhileStatement":
    case "ForStatement":
    case "ConditionalExpression":
      return holder.test === node;
    case "SwitchStatement":
      return holder.discriminant === node;
    case "SwitchCase":
      return holder.test === node;
    case "MemberExpression":
      return holder.computed && holder.property === node;
    case "VariableDeclarator":
      return holder.init === node;
    case "AssignmentExpression":
      return holder.operator === "=" && holder.right === node;
    case "Property":
      return holder.value === node && !holder.computed;
    case "CallExpression":
    case "NewExpression":
      return holder.arguments.includes(node);
    case "ArrowFunctionExpression":
      return holder.body === node;
    default:
      return false;
  }
}

// How a member read rooted at `object` may change the object, or null when
// it cannot: the member chain's own position decides.
function memberKind(parents, object) {
  let node = object;
  let parent = parents.get(node);
  while (parent && ((parent.type === "MemberExpression" && parent.object === node) || parent.type === "ChainExpression")) {
    node = parent;
    parent = parents.get(node);
  }
  if (!parent) return "member-escape";
  if (parent.type === "UnaryExpression" && parent.operator === "delete") return "member-delete";
  if (parent.type === "UpdateExpression" || isTarget(parents, node)) return "member-write";
  // A method read can reach its call through an operand (`(0,x.push)()`).
  let value = node;
  let holder = parent;
  while (forwards(holder, value)) {
    value = holder;
    holder = parents.get(holder);
  }
  // Any method may change the array or return it (`x.valueOf().push()`),
  // whether called, tagged or constructed.
  if (isCallee(holder, value)) return "method-call";
  return valueOnly(holder, value) ? null : "member-escape";
}

// How a read of `id` may change the value it reads, or null when it cannot.
// Only two shapes are known safe: a spread into an array or a call, which
// copies the elements, and a member read whose result is used as a value.
// Anything else lets the value escape to code that may change it later
// (an alias, a literal holding it, a return, an operand, `await`, a loop
// iterable, a destructuring source, an export), so it counts.
function mutationKind(parents, id) {
  const parent = parents.get(id);
  if (!parent) return "escape";
  if (parent.type === "MemberExpression" && parent.object === id) return memberKind(parents, id);
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

// Array methods that never change the array they run on, by where each
// passes the array to its callback (null: no callback sees the array).
const CALLBACK_SLOT = new Map([
  ...["some", "every", "forEach", "map", "filter", "find", "findIndex", "findLast", "findLastIndex", "flatMap"].map((m) => [m, 2]),
  ...["reduce", "reduceRight"].map((m) => [m, 3]),
  ...["includes", "indexOf", "lastIndexOf", "join", "slice", "at", "concat", "flat", "keys", "values", "entries", "toString"].map(
    (m) => [m, null],
  ),
]);
const FUNCTIONS = new Set(["FunctionDeclaration", "FunctionExpression", "ArrowFunctionExpression"]);
const FLOW_STEPS = 20000;

class Unresolved extends Error {
  constructor(reason, at) {
    super(reason);
    this.at = at;
  }
}

const propertyName = (member) =>
  !member.computed ? member.property.name : typeof member.property.value === "string" ? member.property.value : null;

// Follows one array value through a module: every place it can reach, until
// each is known not to change it, leaves the module (an export, an
// imported callee), or is a place the walk cannot follow, which throws
// Unresolved. `exits` collects the hops to other modules for the caller.
class Flow {
  constructor(entry) {
    this.entry = entry;
    this.parents = parentsOf(entry);
    this.exits = [];
    this.seen = new Set();
    this.steps = 0;
    // The names the walk takes as built in: a method it calls on the
    // array, a name it relies on the prototypes not holding, and what a
    // coercion to a primitive looks up (`@@x` is `Symbol.x`). A module that
    // may write one of them is a sink (`sinks`).
    this.trusted = new Set();
  }

  coerces() {
    for (const name of ["@@toPrimitive", "toString", "valueOf", "join"]) this.trusted.add(name);
  }

  once(key) {
    if (++this.steps > FLOW_STEPS) throw new Unresolved("the flow is too long to follow", null);
    if (this.seen.has(key)) return false;
    this.seen.add(key);
    return true;
  }

  exit(...hop) {
    this.exits.push(hop);
  }

  // The name `export var` or `export function` exports `v` under, or null.
  exportedName(v) {
    const def = v.defs[0];
    const decl = def?.type === "Variable" ? def.parent : def?.type === "FunctionName" || def?.type === "ClassName" ? def.node : null;
    const holder = decl && this.parents.get(decl);
    if (holder?.type === "ExportDefaultDeclaration") throw new Unresolved("a default export", decl.start);
    return holder?.type === "ExportNamedDeclaration" ? v.name : null;
  }

  // Every read of `v`. A write replaces what `v` holds and changes nothing
  // the old value was.
  variable(v) {
    if (!this.once(v)) return;
    const exported = this.exportedName(v);
    if (exported) this.exit("export", exported);
    for (const r of v.references) {
      if (!r.isWrite()) this.value(r.identifier);
    }
  }

  // Where the value `node` evaluates to goes next.
  value(node) {
    let parent = this.parents.get(node);
    while (forwards(parent, node) || parent?.type === "ChainExpression") {
      node = parent;
      parent = this.parents.get(node);
    }
    const at = node.start;
    switch (parent?.type) {
      case "SpreadElement": {
        const holder = this.parents.get(parent)?.type;
        if (holder === "ArrayExpression" || holder === "CallExpression" || holder === "NewExpression") return;
        break;
      }
      case "MemberExpression":
        if (parent.object === node) return this.member(node, parent);
        break;
      case "VariableDeclarator":
        if (parent.init === node && parent.id.type === "Identifier") return this.variable(this.entry.decls.get(parent.id.start));
        break;
      case "AssignmentExpression":
        if (parent.operator === "=" && parent.right === node && parent.left.type === "Identifier") {
          const ref = this.entry.refs.get(parent.left.start);
          if (!ref?.resolved) throw new Unresolved("an assignment to an undeclared name", at);
          this.variable(ref.resolved);
          return this.value(parent);
        }
        break;
      case "ExpressionStatement":
        return;
      case "BinaryExpression":
        // `x instanceof H` hands x to H[Symbol.hasInstance], which can be any code.
        if (parent.operator === "instanceof") {
          if (parent.left === node) break;
          this.trusted.add("@@hasInstance");
        } else if (parent.operator === "in" ? parent.left === node : parent.operator !== "===" && parent.operator !== "!==") {
          this.coerces();
        }
        return;
      case "SequenceExpression":
        if (parent.expressions.at(-1) !== node) return;
        break;
      case "UnaryExpression":
        if (parent.operator === "delete") break;
        if (["+", "-", "~"].includes(parent.operator)) this.coerces();
        return;
      case "TemplateLiteral":
        if (this.parents.get(parent)?.type === "TaggedTemplateExpression") break;
        this.coerces();
        return;
      case "IfStatement":
      case "WhileStatement":
      case "DoWhileStatement":
      case "ForStatement":
      case "ConditionalExpression":
      case "SwitchCase":
        if (parent.test === node) return;
        break;
      case "SwitchStatement":
        if (parent.discriminant === node) return;
        break;
      case "ReturnStatement":
        return this.returned(node);
      case "ArrowFunctionExpression":
        if (parent.body === node) return this.returned(node);
        break;
      case "CallExpression":
        if (parent.arguments.includes(node)) return this.argument(parent, parent.arguments.indexOf(node));
        break;
      case "ExportSpecifier":
        if (parent.local === node) return this.exit("export", parent.exported.name ?? parent.exported.value);
        break;
    }
    throw new Unresolved(`the array reaches a ${parent?.type ?? "module end"}`, at);
  }

  // A member read on the array: a call of a method that never changes it,
  // or the member positions the mutation check already knows are safe. A
  // name neither Array.prototype nor Object.prototype holds reads
  // undefined, so calling it throws before anything runs.
  member(object, member) {
    const call = this.parents.get(member);
    const name = propertyName(member);
    if (call?.type === "CallExpression" && call.callee === member && name !== null) {
      if (CALLBACK_SLOT.has(name)) {
        this.trusted.add(name);
        // Array.prototype.toString calls this.join.
        if (name === "toString") this.trusted.add("join");
        const slot = CALLBACK_SLOT.get(name);
        if (slot !== null && call.arguments.length) this.callback(call.arguments[0], slot);
        return;
      }
      if (!(name in [])) {
        this.trusted.add(name);
        return;
      }
    }
    const kind = memberKind(this.parents, object);
    if (kind) throw new Unresolved(`a ${kind} on the array`, member.start);
  }

  // The array as argument `index` of `call`: each function the callee can
  // be receives it as that parameter.
  argument(call, index) {
    if (call.arguments.slice(0, index + 1).some((a) => a.type === "SpreadElement")) {
      throw new Unresolved("a spread before the argument", call.start);
    }
    if (call.callee.type !== "Identifier") throw new Unresolved("a call through a member or expression", call.start);
    this.callback(call.callee, index);
  }

  // `fn` is called with the array as parameter `index`.
  callback(fn, index) {
    if (fn.type === "SpreadElement") throw new Unresolved("a spread callback", fn.start);
    for (const value of this.values(fn, new Set())) {
      if (value === "uncallable") continue;
      if (value.imported !== undefined) this.exit("param", value.imported, index, value.source);
      else this.parameter(value, index);
    }
  }

  // The array as parameter `index` of the function node `fn`.
  parameter(fn, index) {
    if (!this.once(`${fn.start}:${index}`)) return;
    const params = fn.params;
    if (params.slice(0, index + 1).some((p) => p.type === "RestElement")) throw new Unresolved("a rest parameter", fn.start);
    if (fn.type !== "ArrowFunctionExpression") {
      const scope = this.entry.manager.acquire(fn, true);
      if (!scope || scope.set.get("arguments")?.references.length) {
        throw new Unresolved("a function that reads `arguments`", fn.start);
      }
    }
    const param = params[index];
    if (param === undefined) return;
    const id = param.type === "AssignmentPattern" ? param.left : param;
    if (id.type !== "Identifier") throw new Unresolved("a destructured parameter", param.start);
    this.variable(this.entry.decls.get(id.start));
  }

  // `node` is returned from its function: every call of it yields the array.
  returned(node) {
    let fn = this.parents.get(node);
    while (fn && !FUNCTIONS.has(fn.type)) fn = this.parents.get(fn);
    if (!fn || fn.async || fn.generator) throw new Unresolved("a return from an async, generator or unknown function", node.start);
    const v = this.binding(fn);
    if (!v) throw new Unresolved("a return from a function bound to no plain name", fn.start);
    this.calls(v);
  }

  // Every call of the function variable `v` yields the array.
  calls(v) {
    if (!this.once(`calls:${v.defs[0]?.name.start}`)) return;
    const exported = this.exportedName(v);
    if (exported) this.exit("export-call", exported);
    for (const r of v.references) {
      if (r.isWrite()) continue;
      const parent = this.parents.get(r.identifier);
      if (parent?.type === "CallExpression" && parent.callee === r.identifier) this.value(parent);
      else if (parent?.type === "ExportSpecifier" && parent.local === r.identifier) {
        this.exit("export-call", parent.exported.name ?? parent.exported.value);
      } else throw new Unresolved("the function is used other than by a call", r.identifier.start);
    }
  }

  // The variable that holds the function node `fn` and only it: a function
  // declaration's name, or a declarator initialized with it and never
  // written again. Null for any other function.
  binding(fn) {
    if (fn.type === "FunctionDeclaration") {
      const v = fn.id && this.entry.decls.get(fn.id.start);
      return v && v.defs.length === 1 && !v.references.some((r) => r.isWrite()) ? v : null;
    }
    if (fn.id) return null;
    const holder = this.parents.get(fn);
    if (holder?.type !== "VariableDeclarator" || holder.init !== fn || holder.id.type !== "Identifier") return null;
    const v = this.entry.decls.get(holder.id.start);
    return v && v.defs.length === 1 && v.references.every((r) => !r.isWrite() || r.identifier === holder.id) ? v : null;
  }

  // Every value `node` can evaluate to: "uncallable" (a value that is no
  // function, so calling it throws), a function node, or {imported} for a
  // function another module exports. Throws Unresolved when any value is
  // unknown.
  values(node, seen) {
    if (++this.steps > FLOW_STEPS) throw new Unresolved("the flow is too long to follow", null);
    switch (node.type) {
      case "Literal":
      case "TemplateLiteral":
      case "UnaryExpression":
      case "BinaryExpression":
      case "UpdateExpression":
      case "ObjectExpression":
      case "ArrayExpression":
        return ["uncallable"];
      case "ArrowFunctionExpression":
      case "FunctionExpression":
        return [node];
      case "ConditionalExpression":
        return [...this.values(node.consequent, seen), ...this.values(node.alternate, seen)];
      case "LogicalExpression":
        return [...this.values(node.left, seen), ...this.values(node.right, seen)];
      case "SequenceExpression":
        return this.values(node.expressions.at(-1), seen);
      case "Identifier": {
        const ref = this.entry.refs.get(node.start);
        if (ref && !ref.resolved && node.name === "undefined") return ["uncallable"];
        const v = ref?.resolved ?? this.entry.decls.get(node.start);
        if (!v) throw new Unresolved(`\`${node.name}\` is not declared`, node.start);
        return this.variableValues(v, seen);
      }
    }
    throw new Unresolved(`a value from a ${node.type}`, node.start);
  }

  variableValues(v, seen) {
    if (seen.has(v)) return [];
    seen.add(v);
    if (v.defs.length !== 1) throw new Unresolved(`\`${v.name}\` has ${v.defs.length} declarations`, null);
    const def = v.defs[0];
    const at = def.name.start;
    const otherWrites = v.references.some((r) => r.isWrite() && r.identifier !== def.name);
    switch (def.type) {
      case "FunctionName":
        if (otherWrites || v.references.some((r) => r.isWrite())) break;
        return [def.node];
      case "Variable": {
        const loop = this.parents.get(def.parent);
        if (otherWrites || def.node.id !== def.name || (isLoop(loop) && loop.left === def.parent)) break;
        return def.node.init ? this.values(def.node.init, seen) : ["uncallable"];
      }
      case "ImportBinding": {
        const spec = def.node;
        if (spec.type !== "ImportSpecifier") break;
        return [{ imported: spec.imported.name ?? spec.imported.value, source: this.parents.get(spec)?.source?.value ?? null }];
      }
      case "Parameter":
        if (otherWrites) break;
        return this.parameterValues(def.node, def.name, seen);
    }
    throw new Unresolved(`the values of \`${v.name}\``, at);
  }

  // What the parameter named by `id` of `fn` holds across every call of
  // `fn`: the argument, a default, or one property of an object literal
  // argument the parameter destructures.
  parameterValues(fn, id, seen) {
    const index = fn.params.findIndex((p) => id.start >= p.start && id.end <= p.end);
    let param = fn.params[index];
    if (index < 0 || fn.params.slice(0, index).some((p) => p.type === "RestElement")) {
      throw new Unresolved("a parameter after a rest parameter", id.start);
    }
    const fallback = param.type === "AssignmentPattern" ? param.right : null;
    if (fallback) param = param.left;
    // `key` is the property the parameter reads when it destructures one.
    let key = null;
    let keyDefault = null;
    if (param !== id) {
      const prop =
        param.type === "ObjectPattern" &&
        param.properties.find((p) => p.type === "Property" && (p.value === id || p.value.left === id));
      if (!prop || prop.computed) throw new Unresolved("a nested destructured parameter", id.start);
      key = prop.key.name ?? prop.key.value;
      keyDefault = prop.value.type === "AssignmentPattern" ? prop.value.right : null;
    }
    const v = this.binding(fn);
    if (!v || this.exportedName(v)) throw new Unresolved("a parameter of an exported function or one bound to no plain name", fn.start);
    const out = [];
    const read = (arg) => {
      if (key === null) return out.push(...this.values(arg, seen));
      if (arg.type !== "ObjectExpression") throw new Unresolved("a destructured argument that is not an object literal", arg.start);
      if (arg.properties.some((p) => p.type !== "Property" || p.computed)) {
        throw new Unresolved("an object literal with a spread or computed key", arg.start);
      }
      const prop = arg.properties.findLast((p) => (p.key.name ?? p.key.value) === key);
      if (prop) return out.push(...this.values(prop.value, seen));
      if (!keyDefault) throw new Unresolved(`an argument without \`${key}\``, arg.start);
      out.push(...this.values(keyDefault, seen));
    };
    for (const r of v.references) {
      if (r.isWrite()) continue;
      const call = this.parents.get(r.identifier);
      if (call?.type !== "CallExpression" || call.callee !== r.identifier) {
        throw new Unresolved("the function is used other than by a call", r.identifier.start);
      }
      if (call.arguments.slice(0, index + 1).some((a) => a.type === "SpreadElement")) {
        throw new Unresolved("a spread before the argument", call.start);
      }
      const arg = call.arguments[index];
      if (arg) read(arg);
      if (fallback) read(fallback);
      else if (!arg) {
        if (key !== null) throw new Unresolved("a destructured parameter without its argument", call.start);
        out.push("uncallable");
      }
    }
    return out;
  }
}

// Whether one array value stays unchanged in this module. `start` names
// where it is:
//   {"var":true, offset|top, name}  every read of that variable
//   {"param":i, name}               parameter i of the module-scope function `name`
//   {"import":Z, "calls":bool}      the module's imports of the exported name Z,
//                                   or the results of calling them
// -> {"safe":true,"exits":[hop...]} each hop leaves the module:
//      ["export", Z]                the value is exported as Z
//      ["export-call", Z]           a function returning it is exported as Z
//      ["param", Z, i, from]        it is argument i of the function imported as Z from `from`
// -> {"safe":false,"reason":"...","at":offset|null}
function flow(req) {
  if (typeof req.module !== "string" || typeof req.start !== "object" || req.start === null) {
    return { ok: false, error: "flow needs a string `module` and an object `start`" };
  }
  const entry = moduleFor(req);
  if (entry === null) return { ok: true, need_source: true };
  if (entry.error) return { ok: true, safe: false, reason: `the module does not parse: ${entry.error}`, at: null };
  if (entry.evals) return { ok: true, safe: false, reason: "the module calls eval directly", at: null };
  const walk = new Flow(entry);
  const start = req.start;
  try {
    if (start.var) {
      const v = lookup(entry, { ...start, top: start.top === true });
      if (!v) throw new Unresolved(`\`${start.name}\` is not declared`, null);
      walk.variable(v);
    } else if (Number.isInteger(start.param)) {
      const v = entry.top?.set.get(start.name);
      if (!v) throw new Unresolved(`\`${start.name}\` is not declared at module scope`, null);
      for (const value of walk.variableValues(v, new Set())) {
        if (value === "uncallable") continue;
        if (value.imported !== undefined) walk.exit("param", value.imported, start.param, value.source);
        else walk.parameter(value, start.param);
      }
    } else if (typeof start.import === "string") {
      for (const node of entry.ast.body) {
        if (node.type === "ImportDeclaration") {
          for (const spec of node.specifiers) {
            if (spec.type === "ImportSpecifier" && (spec.imported.name ?? spec.imported.value) === start.import) {
              const v = entry.decls.get(spec.local.start);
              if (start.calls) walk.calls(v);
              else walk.variable(v);
            }
          }
        } else if (node.type === "ExportNamedDeclaration" && node.source) {
          for (const spec of node.specifiers) {
            if ((spec.local.name ?? spec.local.value) === start.import) {
              walk.exit(start.calls ? "export-call" : "export", spec.exported.name ?? spec.exported.value);
            }
          }
        }
      }
    } else {
      return { ok: false, error: "flow `start` needs var, param or import" };
    }
  } catch (e) {
    // A chain deep enough to exhaust the stack is one the walk cannot follow.
    if (e instanceof RangeError) return { ok: true, safe: false, reason: "the flow is too deep to follow", at: null };
    if (!(e instanceof Unresolved)) throw e;
    return { ok: true, safe: false, reason: e.message, at: e.at };
  }
  return { ok: true, safe: true, exits: walk.exits, trusted: [...walk.trusted].sort() };
}

// The name a member or property key spells: `x.k`, `x["k"]`, and
// `x[Symbol.k]` as "@@k"; null for any other computed key.
function keyName(key, computed) {
  if (!computed) return key.name ?? String(key.value);
  if (key.type === "Literal") return String(key.value);
  if (key.type === "TemplateLiteral" && key.expressions.length === 0) return key.quasis[0].value.cooked;
  if (key.type === "MemberExpression" && !key.computed && key.object.type === "Identifier" && key.object.name === "Symbol") {
    return `@@${key.property.name}`;
  }
  return null;
}

const SINK_LIMIT = 20;

// `Object` or `Reflect`, as a name or a member (`globalThis.Object`); by
// name, so a shadowing binding counts too.
const isDefinerHome = (n) =>
  (n?.type === "Identifier" && (n.name === "Object" || n.name === "Reflect")) ||
  (n?.type === "MemberExpression" && ["Object", "Reflect"].includes(memberName(n)));

// A built-in that defines properties on an object it is given, with how
// it takes the key: Object.defineProperty/defineProperties/assign/
// setPrototypeOf, Reflect.defineProperty/set/setPrototypeOf, and
// x.__defineGetter__/__defineSetter__, whose receiver is the target.
function definerOf(n) {
  const name = memberName(n);
  if (name === "__defineGetter__" || name === "__defineSetter__") return { name, receiver: true, keyed: false };
  if (n?.type !== "MemberExpression" || !isDefinerHome(n.object)) return null;
  const home = n.object.type === "Identifier" ? n.object.name : memberName(n.object);
  if (home === "Object" && ["defineProperty", "defineProperties", "assign", "setPrototypeOf"].includes(name)) {
    return { name, receiver: false, keyed: name === "defineProperty" };
  }
  if (home === "Reflect" && ["defineProperty", "set", "setPrototypeOf"].includes(name)) {
    return { name, receiver: false, keyed: name !== "setPrototypeOf" };
  }
  return null;
}

// {"op":"sinks","module":key,"source"?:...,"names":[...]}
//   Where the module may write a property the flow trusts (`names`) on an
//   object that could be a built-in prototype:
//   - a member write, update or `delete` whose key is one of the names;
//   - a member write with a computed key that names nothing, which can
//     write any name;
//   - a call given one of the names as a string or `Symbol.x` argument
//     (`Object.defineProperty(o,"includes",...)`, `o.__defineGetter__("has")`,
//     `Reflect.set(o,"some",f)`, or any other callee that may pass it on);
//   - an object literal holding one of the names given to `assign`,
//     `defineProperties`, `setPrototypeOf` or `defineProperty`;
//   - a prototype swap: a `__proto__` write or `setPrototypeOf` call,
//     which can put any object's properties on the chain.
//   A target is cleared only when it is provably a fresh object: a
//   literal, a function, `Object.create(...)`, `this` in a class
//   constructor, a variable only ever holding one of those, or the
//   `prototype` of a function or class declared in the module that is
//   never replaced.
//   -> {"hits":[[kind, name|null, offset], ...]} (at most SINK_LIMIT); a
//      module that does not parse or calls `eval` directly is one hit.
function sinks(req) {
  if (typeof req.module !== "string" || !Array.isArray(req.names)) {
    return { ok: false, error: "sinks needs a string `module` and a `names` list" };
  }
  const entry = moduleFor(req);
  if (entry === null) return { ok: true, need_source: true };
  if (entry.error) return { ok: true, hits: [["unparsed", null, 0]] };
  if (entry.evals) return { ok: true, hits: [["eval", null, 0]] };
  const names = new Set(req.names);
  const parents = parentsOf(entry);
  const hits = [];
  const hit = (kind, name, node) => hits.length < SINK_LIMIT && hits.push([kind, name, node.start]);
  const variable = (id) => entry.refs.get(id.start)?.resolved ?? null;
  const onlyInit = (v) => v.references.every((r) => !r.isWrite() || r.identifier === v.defs[0].name);
  const fresh = (node, depth = 0) => {
    if (depth > 8) return false;
    switch (node.type) {
      case "ObjectExpression":
      case "ArrayExpression":
      case "FunctionExpression":
      case "ArrowFunctionExpression":
      case "ClassExpression":
        return true;
      case "CallExpression":
        return memberName(node.callee) === "create" && node.callee.object.type === "Identifier" && node.callee.object.name === "Object";
      case "ThisExpression": {
        let fn = parents.get(node);
        while (fn && (!FUNCTIONS.has(fn.type) || fn.type === "ArrowFunctionExpression")) fn = parents.get(fn);
        const holder = fn && parents.get(fn);
        if (holder?.type !== "MethodDefinition" || holder.kind !== "constructor") return false;
        // A derived class's `this` is what `super()` returns, which can be any object.
        const cls = parents.get(parents.get(holder));
        return cls !== undefined && cls.superClass === null;
      }
      case "Identifier": {
        const v = variable(node);
        if (v?.defs.length !== 1) return false;
        const def = v.defs[0];
        if (def.type === "FunctionName" || def.type === "ClassName") return !v.references.some((r) => r.isWrite());
        return def.type === "Variable" && def.node.id === def.name && def.node.init !== null && onlyInit(v) && fresh(def.node.init, depth + 1);
      }
      case "MemberExpression": {
        if (memberName(node) !== "prototype" || node.object.type !== "Identifier") return false;
        const v = variable(node.object);
        if (v?.defs.length !== 1) return false;
        const def = v.defs[0];
        const own =
          ((def.type === "FunctionName" || def.type === "ClassName") && !v.references.some((r) => r.isWrite())) ||
          (def.type === "Variable" &&
            def.node.id === def.name &&
            ["FunctionExpression", "ClassExpression"].includes(def.node.init?.type) &&
            onlyInit(v));
        // F.prototype stays the object F was made with only when nothing can
        // reach F to replace it. Every reference must be `F.prototype.k` with
        // a named key other than `constructor`: a call or `new` makes an
        // instance whose `.constructor` is F, and `F.prototype.constructor`
        // is F itself, either of which can set `F.prototype`.
        return (
          own &&
          v.references.every((r) => {
            if (r.isWrite()) return r.identifier === def.name;
            const m = parents.get(r.identifier);
            const use = m && parents.get(m);
            const key = use?.type === "MemberExpression" && use.object === m ? memberName(use) : null;
            return (
              m?.type === "MemberExpression" &&
              m.object === r.identifier &&
              memberName(m) === "prototype" &&
              key !== null &&
              key !== "constructor"
            );
          })
        );
      }
      default:
        return false;
    }
  };
  const literalNames = (obj) =>
    obj.properties.map((p) => (p.type === "Property" ? keyName(p.key, p.computed) : null)).filter((k) => k === null || names.has(k));
  const stack = [entry.ast];
  while (stack.length && hits.length < SINK_LIMIT) {
    const node = stack.pop();
    if (node.type === "MemberExpression") {
      const holder = parents.get(node);
      const written =
        isTarget(parents, node) ||
        holder?.type === "UpdateExpression" ||
        (holder?.type === "UnaryExpression" && holder.operator === "delete");
      if (written) {
        const key = keyName(node.property, node.computed);
        if (key === "__proto__") {
          if (!fresh(node.object)) hit("proto-swap", key, node);
        } else if (key === null) {
          if (!fresh(node.object)) hit("computed-write", null, node);
        } else if (names.has(key) && !fresh(node.object)) {
          hit("write", key, node);
        }
      }
    } else if (node.type === "CallExpression") {
      const definer = definerOf(node.callee);
      const target = definer?.receiver ? node.callee.object : node.arguments[0];
      const freshArg = (n) => n !== undefined && n.type !== "SpreadElement" && fresh(n);
      // Reflect.set(target,key,value,receiver) writes onto `receiver` when one is given.
      const receiver = definer?.name === "set" && !definer.receiver ? node.arguments[3] : undefined;
      const freshTarget = definer !== null && freshArg(target) && (receiver === undefined || freshArg(receiver));
      for (const arg of node.arguments) {
        const key = keyName(arg, true);
        if (key !== null && names.has(key) && !freshTarget) hit("argument", key, arg);
      }
      if (definer !== null && !freshTarget) {
        if (definer.name === "setPrototypeOf") hit("proto-swap", null, node);
        if (node.arguments.some((a) => a.type === "SpreadElement")) hit("computed-define", null, node);
        const keyArg = definer.receiver ? node.arguments[0] : definer.keyed ? node.arguments[1] : null;
        if (keyArg && keyName(keyArg, true) === null) hit("computed-define", null, keyArg);
        if (definer.name === "assign" || definer.name === "defineProperties") {
          for (const arg of node.arguments.slice(1)) {
            if (arg.type !== "ObjectExpression") hit("computed-define", null, arg);
            else for (const key of literalNames(arg)) hit(key === null ? "computed-define" : "object-key", key, arg);
          }
        }
      }
    }
    // A built-in that defines properties, read other than as a direct
    // callee (`var dp=Object.defineProperty`), can be called with any key;
    // so can one reached through an alias of Object or Reflect, or a
    // computed read on them.
    const holder = parents.get(node);
    // Code built from a string runs unseen: global `eval` other than a
    // direct call (a direct one already makes the module a sink), and the
    // global `Function` used other than for `typeof`, `instanceof` or a
    // `.prototype` read (`Function.call(0,"code")` builds code too).
    if (node.type === "Identifier" && (node.name === "eval" || node.name === "Function")) {
      const ref = entry.refs.get(node.start);
      if (ref && !ref.resolved && ref.identifier === node) {
        const typeOf = holder?.type === "UnaryExpression" && holder.operator === "typeof";
        if (node.name === "eval" && !typeOf && !(holder?.type === "CallExpression" && holder.callee === node)) {
          hit("indirect-eval", null, node);
        }
        const inert =
          typeOf ||
          (holder?.type === "BinaryExpression" && holder.operator === "instanceof" && holder.right === node) ||
          (holder?.type === "MemberExpression" &&
            holder.object === node &&
            memberName(holder) === "prototype" &&
            !isTarget(parents, holder));
        if (node.name === "Function" && !inert) hit("function-constructor", null, node);
      }
    }
    // The same built-ins reached as a member of any object
    // (`globalThis.eval`, `window.Function`), read other than as a write
    // target.
    const member = memberName(node);
    if ((member === "eval" || member === "Function") && !isTarget(parents, node)) {
      hit(member === "eval" ? "indirect-eval" : "function-constructor", null, node);
    }
    if (definerOf(node) !== null && !(holder?.type === "CallExpression" && holder.callee === node)) {
      hit("definer-escape", null, node);
    } else if (isDefinerHome(node) && !(holder?.type === "MemberExpression" && holder.property === node && !holder.computed)) {
      const named = holder?.type === "MemberExpression" && holder.object === node && memberName(holder) !== null;
      const inert =
        ((holder?.type === "CallExpression" || holder?.type === "NewExpression") && holder.callee === node) ||
        holder?.type === "BinaryExpression" ||
        (holder?.type === "UnaryExpression" && holder.operator === "typeof") ||
        (holder?.type === "Property" && holder.key === node && !holder.computed && holder.value !== node);
      if (!named && !inert) hit("definer-escape", null, node);
    }
    for (const key of Object.keys(node)) {
      const child = node[key];
      for (const c of Array.isArray(child) ? child : [child]) {
        if (c && typeof c.type === "string" && c !== node) stack.push(c);
      }
    }
  }
  return { ok: true, hits };
}

// {"op":"exports","module":key,"source"?:...}
//   -> {"names":[every name the module exports], "bindings":{name:[local, from]},
//       "star":bool}; a module that does not parse answers {"error":...}.
function exportsOf(req) {
  if (typeof req.module !== "string") return { ok: false, error: "exports needs a string `module`" };
  const entry = moduleFor(req);
  if (entry === null) return { ok: true, need_source: true };
  if (entry.error) return { ok: true, error: entry.error };
  const names = [];
  // Each exported name's [local, source]: the module-scope name it exports
  // (null for a default expression or a namespace re-export) and, for a
  // re-export, the `from` path it re-exports from (null for a local one).
  const bindings = {};
  const add = (name, local, source) => {
    names.push(name);
    bindings[name] = [local, source];
  };
  let star = false;
  for (const node of entry.ast.body) {
    if (node.type === "ExportAllDeclaration") star = true;
    if (node.type === "ExportDefaultDeclaration") add("default", node.declaration.id?.name ?? null, null);
    if (node.type !== "ExportNamedDeclaration") continue;
    const source = node.source?.value ?? null;
    for (const spec of node.specifiers) {
      add(spec.exported.name ?? spec.exported.value, spec.local.name ?? spec.local.value, source);
    }
    const decl = node.declaration;
    if (decl?.id) add(decl.id.name, decl.id.name, null);
    for (const d of decl?.declarations ?? []) {
      for (const v of entry.manager.getDeclaredVariables(d)) add(v.name, v.name, null);
    }
  }
  return { ok: true, names, bindings, star };
}

// Every name a module reads by name as a property, whatever object it
// reads it from: a member name (`x.k`, `x["k"]`, `` x[`k`] ``) and a
// destructured key (`{k}=x`, `{k:y}=x`, `{"k":y}=x`). A computed read
// with any other key reads no name here. Kept per module key for
// `keys_used`.
const keySets = new Map();
// The name a member reads or writes, as `keyName` spells it; null for a
// computed key that names nothing.
const memberName = (n) => (n?.type === "MemberExpression" ? keyName(n.property, n.computed) : null);

// `keysOf`, or null (every name used) when the analysis itself fails.
function keysOrNull(ast, source) {
  try {
    return keysOf(ast, source);
  } catch {
    return null;
  }
}

function keysOf(ast, source) {
  const keys = new Set();
  const stack = [ast];
  while (stack.length) {
    const node = stack.pop();
    if (node.type === "MemberExpression") {
      const p = node.property;
      if (!node.computed) keys.add(p.name);
      else if (p.type === "Literal") keys.add(String(p.value));
      else if (p.type === "TemplateLiteral" && p.expressions.length === 0) keys.add(p.quasis[0].value.cooked);
    } else if (node.type === "ObjectPattern") {
      for (const prop of node.properties) {
        if (prop.type !== "Property") continue;
        if (!prop.computed) keys.add(prop.key.name ?? String(prop.key.value));
        else if (keyName(prop.key, true) !== null) keys.add(keyName(prop.key, true));
      }
    }
    for (const key of Object.keys(node)) {
      const child = node[key];
      for (const c of Array.isArray(child) ? child : [child]) {
        if (c && typeof c.type === "string" && c !== node) stack.push(c);
      }
    }
  }
  return keys;
}

// {"op":"keys_used","module":key,"source"?:...,"names":[...]}
//   -> {"used":[names the module reads as a property]}; a module that does
//      not parse uses every name.
function keysUsed(req) {
  if (typeof req.module !== "string" || !Array.isArray(req.names)) {
    return { ok: false, error: "keys_used needs a string `module` and a `names` list" };
  }
  let keys = keySets.get(req.module);
  if (keys === undefined) {
    if (typeof req.source !== "string") return { ok: true, need_source: true };
    try {
      keys = keysOrNull(acorn.parse(req.source, PARSE_OPTIONS), req.source);
    } catch {
      keys = null;
    }
    keySets.set(req.module, keys);
  }
  return { ok: true, used: req.names.filter((n) => keys === null || keys.has(n)) };
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
        const ast = acorn.parse(req.source, PARSE_OPTIONS);
        if (typeof req.module === "string") keySets.set(req.module, keysOrNull(ast, req.source));
        return { ok: true, parsed: true };
      } catch (e) {
        if (typeof req.module === "string") keySets.set(req.module, null);
        return { ok: true, parsed: false, error: e.message, pos: e.pos ?? null };
      }
    case "binding":
      return binding(req);
    case "writes":
      return writes(req);
    case "flow":
      return flow(req);
    case "keys_used":
      return keysUsed(req);
    case "sinks":
      return sinks(req);
    case "exports":
      return exportsOf(req);
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
