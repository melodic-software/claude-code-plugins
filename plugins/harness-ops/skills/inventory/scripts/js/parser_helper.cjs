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
//     `reads` are the other reads, each [kind, offset, top] with kind
//     spread or member-read: they change nothing themselves, but the
//     engine looks up names on the prototypes for them (`@@iterator`, the
//     key read), which a patched prototype can answer with code.
//     `declares` is whether `offset` names a plain `var`/`let`/`const`
//     declarator of the variable. A module with a direct `eval` answers
//     found false, since code inside the eval can write any name; one
//     whose code only reads an identifier (`foldEvals`) is that read.
//     -> {"id":5,"ok":true,"found":true,"declares":true,
//         "writes":[["init",120,true]],"mutations":[["method-call",160,true]],
//         "reads":[["spread",180,true]]}
//   {"id":6,"op":"flow","module":"<key>","source":"...","start":{...}}
//     Whether an array value stays unchanged inside the module, following
//     it through aliases, returns, arguments and callbacks; `flow` below
//     documents `start` and the reply. The hops that leave the module come
//     back as `exits` for the caller to follow.
//   {"id":7,"op":"keys_used","module":"<key>","source":"...","names":["pY"]}
//     -> {"id":7,"ok":true,"used":["pY"]}   names the module reads as a property
//   {"id":8,"op":"exports","module":"<key>","source":"..."}
//     -> {"id":8,"ok":true,"names":["pY","default"]}   every name it exports
//   {"id":9,"op":"loads","module":"<key>","source":"...","loaders":["Fe"]}
//     -> {"id":9,"ok":true,"files":["chunk-a.js"],"aliases":[]}  files it
//        loads whole, and the names it exports an alias of `require` under.
//     `loaders`, optional here and on `namespace` and `sinks`, lists every
//     name a module of the bundle exports such an alias under; an import
//     of one is then a named loader, and so is the alias itself.
//   {"id":10,"op":"namespace","module":"<key>","source":"...","file":"chunk-a.js","name":"pY"}
//     Whether each whole load of the file reads only other exports by
//     name; `namespace` below documents the reply.
//   {"id":11,"op":"imports","module":"<key>","source":"..."}
//     -> {"id":11,"ok":true,"names":[["pY","/a.js"]]}  names it imports or
//        re-exports by name, each with the path it names
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

// The built-ins a folded `.replace` (`evalText`) relies on: the string
// method and what it calls on the regex, the flag getters `flags` reads
// included, since `g` and `u` decide what is replaced.
const REPLACE_TRUSTS = ["replace", "@@replace", "exec", "flags", "global", "unicode", "unicodeSets", "lastIndex"];
// The scanned module supplies both the regex and the subject of a folded
// `.replace`, so the fold runs only one that cannot backtrack for long: no
// quantifier character anywhere in the pattern (`/(a+)+$/` stays a sink),
// and both within these lengths.
const FOLD_PATTERN_MAX = 32;
const FOLD_SUBJECT_MAX = 256;

// What a direct `eval` argument evaluates to when the reader can tell, as
// {text, trusts}: a string literal, a template with no expressions, or
// `.replace` on one with a regex literal and a string literal (protobufjs's
// `eval("quire".replace(/^/,"re"))`), which trusts REPLACE_TRUSTS; else null.
// An argument past the FOLD_ limits, or a regex with a quantifier, is null too.
function evalText(arg) {
  const text = literalString(arg);
  if (text !== null) return { text, trusts: [] };
  if (arg?.type !== "CallExpression" || memberName(arg.callee) !== "replace" || arg.arguments.length !== 2) return null;
  const [pattern, replacement] = arg.arguments;
  const subject = literalString(arg.callee.object);
  const by = literalString(replacement);
  if (subject === null || by === null || !pattern.regex) return null;
  const source = pattern.regex.pattern;
  if (source.length > FOLD_PATTERN_MAX || subject.length > FOLD_SUBJECT_MAX || /[*+?{]/.test(source)) return null;
  try {
    return { text: subject.replace(new RegExp(source, pattern.regex.flags), by), trusts: REPLACE_TRUSTS };
  } catch {
    return null;
  }
}

// The identifier a direct `eval` call only reads, as {name, trusts}: its
// one argument folds (`evalText`) to code that parses as nothing but one
// identifier expression, other than `eval` or `arguments`. Else null.
// `eval?.(...)` is an indirect eval, which reads the global, so it stays.
function evalRead(call) {
  if (call.optional || call.callee.type !== "Identifier" || call.callee.name !== "eval" || call.arguments.length !== 1) return null;
  const folded = evalText(call.arguments[0]);
  if (folded === null) return null;
  let program;
  try {
    program = acorn.parse(folded.text, PARSE_OPTIONS);
  } catch {
    return null;
  }
  const expr = program.body.length === 1 && program.body[0].type === "ExpressionStatement" ? program.body[0].expression : null;
  if (expr?.type !== "Identifier" || expr.name === "eval" || expr.name === "arguments") return null;
  return { name: expr.name, trusts: folded.trusts };
}

// Rewrites, in place, each direct `eval` that only reads an identifier
// (`evalRead`) into that read, so scope analysis sees a plain reference
// and no direct eval around it. Returns the built-ins the folds trust.
function foldEvals(ast) {
  const trusts = new Set();
  const stack = [ast];
  while (stack.length) {
    const node = stack.pop();
    const read = node.type === "CallExpression" ? evalRead(node) : null;
    if (read !== null) {
      for (const name of read.trusts) trusts.add(name);
      const { start, end, range } = node;
      for (const key of Object.keys(node)) delete node[key];
      Object.assign(node, { type: "Identifier", name: read.name, start, end }, range ? { range } : {});
      continue;
    }
    for (const key of Object.keys(node)) {
      const child = node[key];
      for (const c of Array.isArray(child) ? child : [child]) {
        if (c && typeof c.type === "string" && c !== node) stack.push(c);
      }
    }
  }
  return trusts;
}

function analyze(source) {
  let ast;
  let manager;
  let folds;
  try {
    // eslint-scope reads node.range, which acorn adds only on request.
    ast = acorn.parse(source, { ...PARSE_OPTIONS, ranges: true });
    folds = foldEvals(ast);
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
  return { ast, manager, top, refs, decls, globals, evals, folds, parents: null };
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
  const out = { writes: [], mutations: [], reads: [] };
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
    if (!r.isReadOnly()) continue;
    const kind = mutationKind(parents, r.identifier);
    if (kind) out.mutations.push([kind, ...at]);
    else out.reads.push([parents.get(r.identifier).type === "SpreadElement" ? "spread" : "member-read", ...at]);
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
// The array methods whose result comes from ArraySpeciesCreate, which reads
// the array's `constructor` and that constructor's @@species.
const SPECIES = new Set(["slice", "map", "filter", "concat", "flat", "flatMap"]);
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

// The variable that holds the function node `fn` and only it: a function
// declaration's name, or a declarator initialized with it and never
// written again. Null for any other function.
function functionBinding(entry, parents, fn) {
  if (fn.type === "FunctionDeclaration") {
    const v = fn.id && entry.decls.get(fn.id.start);
    return v && v.defs.length === 1 && !v.references.some((r) => r.isWrite()) ? v : null;
  }
  if (fn.id) return null;
  const holder = parents.get(fn);
  if (holder?.type !== "VariableDeclarator" || holder.init !== fn || holder.id.type !== "Identifier") return null;
  const v = entry.decls.get(holder.id.start);
  return v && v.defs.length === 1 && v.references.every((r) => !r.isWrite() || r.identifier === holder.id) ? v : null;
}

// The two values `Flow.values` lists that are no function.
const uncallable = (value) => value === "undefined" || value === "uncallable";
// Whether one of `values` may be undefined: an imported binding may be,
// since the module exporting it is not read here.
const mayBeUndefined = (values) => values.some((v) => v === "undefined" || v.imported !== undefined);

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
    // array, a name it relies on the prototypes not holding, a key it reads
    // as a value, and what the engine looks up on its own for a spread, a
    // method building a new array, or a coercion to a primitive (`@@x` is
    // `Symbol.x`). A module that may write one of them is a sink (`sinks`).
    this.trusted = new Set();
    // How many leading indices the array holds as its own elements: an
    // index read below it reaches no prototype.
    this.own = 0;
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
      // `a+=v` and `a++` read the array before replacing it, coercing it
      // through built-in lookups the walk does not track there.
      if (r.isReadWrite()) throw new Unresolved("a compound assignment or update of the array", r.identifier.start);
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
        if (holder === "ArrayExpression" || holder === "CallExpression" || holder === "NewExpression") {
          // The spread calls the array's @@iterator and that iterator's `next`.
          this.trusted.add("@@iterator");
          this.trusted.add("next");
          return;
        }
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
  // undefined, so calling it throws before anything runs. A read in a
  // value-only position trusts its key, since a getter the prototypes hold
  // for it runs with the array as `this`, unless the array holds the key
  // itself; a computed key the walk cannot name could be any key, so it is
  // not followed.
  member(object, member) {
    const call = this.parents.get(member);
    const name = propertyName(member);
    if (call?.type === "CallExpression" && call.callee === member && name !== null) {
      if (CALLBACK_SLOT.has(name)) {
        this.trusted.add(name);
        // Array.prototype.toString calls this.join.
        if (name === "toString") this.trusted.add("join");
        if (SPECIES.has(name)) {
          this.trusted.add("constructor");
          this.trusted.add("@@species");
        }
        // concat reads @@isConcatSpreadable on the array and each argument.
        if (name === "concat") this.trusted.add("@@isConcatSpreadable");
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
    const key = keyName(member.property, member.computed);
    if (key === null) throw new Unresolved("a read on the array by a key that names nothing", member.start);
    // An array holds its own `length` and elements, so reading them reaches no prototype.
    if (key === "length" || (/^(?:0|[1-9]\d*)$/.test(key) && Number(key) < this.own)) return;
    this.trusted.add(key);
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
    for (const value of this.values(fn, new Map())) {
      if (uncallable(value)) continue;
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

  binding(fn) {
    return functionBinding(this.entry, this.parents, fn);
  }

  // Every value `node` can evaluate to: "undefined", "uncallable" (any
  // other value that is no function, so calling it throws), a function
  // node, or {imported} for a function another module exports. Throws
  // Unresolved when any value is unknown.
  values(node, seen) {
    if (++this.steps > FLOW_STEPS) throw new Unresolved("the flow is too long to follow", null);
    switch (node.type) {
      case "Literal":
      case "TemplateLiteral":
      case "BinaryExpression":
      case "UpdateExpression":
      case "ObjectExpression":
      case "ArrayExpression":
        return ["uncallable"];
      case "UnaryExpression":
        return [node.operator === "void" ? "undefined" : "uncallable"];
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
        if (ref && !ref.resolved && node.name === "undefined") return ["undefined"];
        const v = ref?.resolved ?? this.entry.decls.get(node.start);
        if (!v) throw new Unresolved(`\`${node.name}\` is not declared`, node.start);
        return this.variableValues(v, seen);
      }
    }
    throw new Unresolved(`a value from a ${node.type}`, node.start);
  }

  // `seen` maps each variable met to whether it may be undefined, null
  // while it is still being read. One met again adds no value, but whether
  // it may be undefined still decides a destructured key's default
  // (`parameterValues`), and one still being read may be.
  variableValues(v, seen) {
    if (seen.has(v)) return seen.get(v) === false ? [] : ["undefined"];
    seen.set(v, null);
    const values = this.declaredValues(v, seen);
    seen.set(v, mayBeUndefined(values));
    return values;
  }

  declaredValues(v, seen) {
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
        const values = def.node.init ? this.values(def.node.init, seen) : [];
        // A `var` read before its initializer runs is undefined, like one with none.
        return def.parent.kind === "var" || !def.node.init ? ["undefined", ...values] : values;
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
      key = String(prop.key.name ?? prop.key.value);
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
      // `__proto__:` sets the literal's prototype, where a key it lacks is read.
      if (arg.properties.some((p) => !p.shorthand && keyName(p.key, false) === "__proto__")) {
        throw new Unresolved("an object literal setting its prototype", arg.start);
      }
      const matching = arg.properties.filter((p) => String(p.key.name ?? p.key.value) === key);
      // A getter or setter's value is the accessor function, not what reading the key gives.
      if (matching.some((p) => p.kind !== "init")) throw new Unresolved(`an accessor for \`${key}\``, arg.start);
      const prop = matching.at(-1);
      if (prop) {
        // An undefined value takes the key's default instead.
        const values = this.values(prop.value, seen);
        out.push(...values.filter((value) => value !== "undefined"));
        if (!mayBeUndefined(values)) return;
        if (!keyDefault) return out.push("undefined");
      } else if (!keyDefault) {
        throw new Unresolved(`an argument without \`${key}\``, arg.start);
      } else {
        // A key the literal lacks is read from Object.prototype.
        this.trusted.add(key);
      }
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
        out.push("undefined");
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
      // The elements of an array literal with no hole or spread, when the
      // variable holds only it; the walk fails on anything that changes it.
      const def = v.defs.length === 1 ? v.defs[0] : null;
      const init = def?.type === "Variable" && def.node.id === def.name ? def.node.init : null;
      if (
        init?.type === "ArrayExpression" &&
        init.elements.every((e) => e !== null && e.type !== "SpreadElement") &&
        v.references.every((r) => !r.isWrite() || r.identifier === def.name)
      ) {
        walk.own = init.elements.length;
      }
      walk.variable(v);
    } else if (Number.isInteger(start.param)) {
      const v = entry.top?.set.get(start.name);
      if (!v) throw new Unresolved(`\`${start.name}\` is not declared at module scope`, null);
      for (const value of walk.variableValues(v, new Map())) {
        if (uncallable(value)) continue;
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
  return { ok: true, safe: true, exits: walk.exits, trusted: [...new Set([...walk.trusted, ...entry.folds])].sort() };
}

// The file name a module specifier ends in; loads match files by it.
const fileName = (spec) => spec.split("/").at(-1);
// What `loads` lists for a load whose file the scan cannot name.
const UNKNOWN_FILE = "*";

const literalString = (n) =>
  n?.type === "Literal" && typeof n.value === "string"
    ? n.value
    : n?.type === "TemplateLiteral" && n.expressions.length === 0
      ? n.quasis[0].value.cooked
      : null;

// `require(...)` or `x.require(...)`, which Bun answers with the module
// namespace object for an ES module.
const isRequire = (n) =>
  n?.type === "CallExpression" && (n.callee.type === "Identifier" ? n.callee.name === "require" : memberName(n.callee) === "require");

// The file a node loads whole as a namespace, or null: `import(f)`,
// `require(f)`, `x.require(f)`, `import*as N from f` and `export*from f`,
// with `f` a literal. A load with any other specifier is not seen.
function loadedFile(node) {
  let spec = null;
  if (node.type === "ImportExpression") spec = literalString(node.source);
  else if (isRequire(node)) spec = literalString(node.arguments[0]);
  else if (node.type === "ImportDeclaration" && node.specifiers.some((s) => s.type === "ImportNamespaceSpecifier")) spec = node.source.value;
  else if (node.type === "ExportAllDeclaration") spec = node.source.value;
  return spec === null ? null : fileName(spec);
}

const isImportMeta = (n) => n?.type === "MetaProperty" && n.meta.name === "import";

// What reading a namespace object does inside a module: every place the
// module loads a file whole, followed to each read, accepting only a read
// of another export by name. A namespace object has no prototype and no
// accessors, so such a read runs no code; anything else (a computed read,
// an enumeration, a spread, a method call passing it as `this`, an alias
// escaping) could reach the export unseen and throws Unresolved. A promise
// or a record on the way holds it only through the built-ins the walk
// names in `trusted`; `thenable` is whether a promise resolves with the
// namespace, which reads its `then` export. `loaders` maps each call of a
// named loader with a literal specifier to the file it loads.
class Namespace {
  constructor(entry, name, loaders) {
    this.entry = entry;
    this.name = name;
    this.loaders = loaders;
    this.parents = parentsOf(entry);
    this.trusted = new Set();
    this.thenable = false;
    this.steps = 0;
    this.seen = new Set();
  }

  step(at) {
    if (++this.steps > FLOW_STEPS) throw new Unresolved("the namespace is too long to follow", at);
  }

  site(node) {
    const parent = this.parents.get(node);
    if (node.type === "ImportExpression") {
      this.thenable = true;
      if (parent?.type === "ExpressionStatement") return;
      if (parent?.type === "AwaitExpression") {
        // Await reads the promise's `constructor` before it waits.
        this.trusted.add("constructor");
        return this.value(parent);
      }
      if (parent?.type === "ArrayExpression") return this.promiseAll(parent, node);
      throw new Unresolved("an import() not awaited directly", node.start);
    }
    if (node.type === "CallExpression") {
      const callee = node.callee;
      const bare = callee.type === "Identifier" && !this.entry.refs.get(callee.start)?.resolved;
      const meta = callee.type === "MemberExpression" && isImportMeta(callee.object) && !callee.computed;
      if (!bare && !meta && !this.loaders.has(node)) throw new Unresolved("a require through a binding or object", node.start);
      if (meta) this.importMetaIntact();
      this.trusted.add("require");
      return this.value(node);
    }
    if (node.type === "ImportDeclaration") {
      const spec = node.specifiers.find((s) => s.type === "ImportNamespaceSpecifier");
      return this.binding(this.entry.decls.get(spec.local.start));
    }
    throw new Unresolved("an `export*` re-exports every name", node.start);
  }

  // `import.meta` is this module's own object; only its own code can
  // replace `import.meta.require`, and only by reaching it other than as
  // a named read.
  importMetaIntact() {
    if (this.metaChecked) return;
    const stack = [this.entry.ast];
    while (stack.length) {
      const node = stack.pop();
      if (isImportMeta(node)) {
        const member = this.parents.get(node);
        const holder = this.parents.get(member);
        const named = member?.type === "MemberExpression" && member.object === node && memberName(member) !== null;
        if (!named || isTarget(this.parents, member) || holder?.type === "UpdateExpression" || (holder?.type === "UnaryExpression" && holder.operator === "delete")) {
          throw new Unresolved("`import.meta` used other than for a named read", node.start);
        }
      }
      for (const key of Object.keys(node)) {
        const child = node[key];
        for (const c of Array.isArray(child) ? child : [child]) {
          if (c && typeof c.type === "string" && c !== node) stack.push(c);
        }
      }
    }
    this.metaChecked = true;
  }

  // Where the namespace `node` evaluates to goes next.
  value(node) {
    this.step(node.start);
    const parent = this.parents.get(node);
    switch (parent?.type) {
      case "ChainExpression":
      case "LogicalExpression":
        return this.value(parent);
      case "MemberExpression":
        if (parent.object === node) return this.byName(parent);
        break;
      case "VariableDeclarator":
        if (parent.init !== node) break;
        if (parent.id.type === "ObjectPattern") return this.pattern(parent.id);
        if (parent.id.type === "Identifier") return this.binding(this.entry.decls.get(parent.id.start));
        break;
      case "AssignmentExpression":
        if (parent.operator !== "=" || parent.right !== node) break;
        if (parent.left.type === "ObjectPattern") this.pattern(parent.left);
        else if (parent.left.type === "Identifier") this.assigned(parent.left);
        else break;
        return this.value(parent);
      case "Property":
        if (parent.value !== node) break;
        return this.record(parent);
      case "AwaitExpression":
        // Await reads a promise's `constructor`, and settling a promise
        // with the namespace reads its `then`.
        this.trusted.add("constructor");
        this.thenable = true;
        return this.value(parent);
      case "ExpressionStatement":
        return;
      case "SequenceExpression":
        if (parent.expressions.at(-1) === node) return this.value(parent);
        return;
      case "ConditionalExpression":
        if (parent.test === node) return;
        return this.value(parent);
      case "UnaryExpression":
        if (["typeof", "void", "!"].includes(parent.operator)) return;
        break;
      case "BinaryExpression":
        if (parent.operator === "===" || parent.operator === "!==" || (parent.operator === "in" && parent.right === node)) return;
        break;
      case "IfStatement":
      case "WhileStatement":
      case "DoWhileStatement":
      case "ForStatement":
        if (parent.test === node) return;
        break;
    }
    throw new Unresolved(`the namespace reaches a ${parent?.type ?? "module end"}`, node.start);
  }

  // A read of one export by name, which is safe unless it names the
  // export being followed or calls the export with the namespace as `this`.
  byName(member) {
    const key = memberName(member);
    if (key === null) throw new Unresolved("a computed read of the namespace", member.start);
    if (key === this.name) throw new Unresolved(`a read of \`${key}\``, member.start);
    this.readOnly(member, "the namespace");
  }

  // A member read that neither calls the member with its object as
  // `this` (`o.f()`, and `(o?.f)()` too) nor writes or deletes it.
  readOnly(member, what) {
    let use = member;
    let holder = this.parents.get(member);
    while (holder?.type === "ChainExpression") {
      use = holder;
      holder = this.parents.get(holder);
    }
    if (isCallee(holder, use)) throw new Unresolved(`a method call on ${what}`, member.start);
    if (isTarget(this.parents, member) || holder?.type === "UpdateExpression" || (holder?.type === "UnaryExpression" && holder.operator === "delete")) {
      throw new Unresolved(`a write to ${what}`, member.start);
    }
  }

  pattern(p) {
    for (const prop of p.properties) {
      if (prop.type === "RestElement") throw new Unresolved("a rest element taking the namespace", prop.start);
      const key = keyName(prop.key, prop.computed);
      if (key === null) throw new Unresolved("a computed key destructuring the namespace", prop.start);
      if (key === this.name) throw new Unresolved(`a read of \`${key}\``, prop.start);
    }
  }

  // Every read of the variable `v`, which may hold the namespace.
  binding(v) {
    if (!v) throw new Unresolved("an undeclared name", null);
    if (this.seen.has(v)) return;
    this.seen.add(v);
    const decl = v.defs[0]?.type === "Variable" ? v.defs[0].parent : null;
    if (decl && this.parents.get(decl)?.type === "ExportNamedDeclaration") throw new Unresolved("an exported namespace", decl.start);
    for (const r of v.references) if (!r.isWrite() || r.isReadWrite()) this.value(r.identifier);
  }

  assigned(left) {
    const ref = this.entry.refs.get(left.start);
    if (!ref?.resolved) throw new Unresolved("an assignment to an undeclared name", left.start);
    this.binding(ref.resolved);
  }

  // The namespace as a property of an object literal (`{names:ns}`) bound
  // to a variable only ever holding it: every read of the variable is a
  // named member read or a truth test. A read of the property follows the
  // namespace; a read of a name the literal does not hold looks it up on
  // Object.prototype, which is trusted.
  record(prop) {
    const obj = this.parents.get(prop);
    const key = keyName(prop.key, prop.computed);
    const own = new Set();
    for (const p of obj.properties) {
      const k = p.type === "Property" && p.kind === "init" ? keyName(p.key, p.computed) : null;
      if (k === null || k === "__proto__") throw new Unresolved("a record with a spread, accessor, computed or __proto__ key", p.start);
      own.add(k);
    }
    const holder = this.parents.get(obj);
    const id = holder?.type === "VariableDeclarator" && holder.init === obj ? holder.id : null;
    const v = id?.type === "Identifier" ? this.entry.decls.get(id.start) : null;
    if (!v || v.defs.length !== 1 || v.references.some((r) => r.isWrite() && r.identifier !== id)) {
      throw new Unresolved("a record not bound to a variable only ever holding it", obj.start);
    }
    if (this.parents.get(this.parents.get(holder))?.type === "ExportNamedDeclaration") {
      throw new Unresolved("an exported record", obj.start);
    }
    for (const r of v.references) {
      if (r.isWrite()) continue;
      const use = this.parents.get(r.identifier);
      if (use?.type === "MemberExpression" && use.object === r.identifier) {
        const k = memberName(use);
        if (k === null) throw new Unresolved("a computed read of the record", use.start);
        this.readOnly(use, "the record");
        if (!own.has(k)) this.trusted.add(k);
        if (k === key) this.value(use);
        continue;
      }
      // The variable only holds an object, so `v&&x` is x.
      if (use?.type === "LogicalExpression" && use.operator === "&&" && use.left === r.identifier) continue;
      if (use?.type === "ConditionalExpression" && use.test === r.identifier) continue;
      if ((use?.type === "IfStatement" || use?.type === "WhileStatement") && use.test === r.identifier) continue;
      if (use?.type === "UnaryExpression" && ["typeof", "void", "!"].includes(use.operator)) continue;
      throw new Unresolved(`the record reaches a ${use?.type ?? "module end"}`, r.identifier.start);
    }
  }

  // `[...]=await Promise.all([..., import(f), ...])`: the global
  // Promise.all resolves each element through Promise.resolve and `then`,
  // iterating both arrays, and the pattern binds the namespace where the
  // import stood.
  promiseAll(arr, node) {
    const call = this.parents.get(arr);
    const callee = call?.callee;
    const global =
      callee?.type === "MemberExpression" &&
      memberName(callee) === "all" &&
      callee.object.type === "Identifier" &&
      callee.object.name === "Promise" &&
      !this.entry.refs.get(callee.object.start)?.resolved;
    if (!global || call.type !== "CallExpression" || call.arguments[0] !== arr) throw new Unresolved("an import() in an array other than Promise.all's", node.start);
    if (arr.elements.some((e) => e?.type === "SpreadElement")) throw new Unresolved("a spread in Promise.all's array", arr.start);
    for (const n of ["Promise", "all", "resolve", "then", "constructor", "@@species", "@@iterator", "next", "return"]) this.trusted.add(n);
    const awaited = this.parents.get(call);
    const holder = awaited?.type === "AwaitExpression" ? this.parents.get(awaited) : null;
    let target = null;
    if (holder?.type === "VariableDeclarator" && holder.init === awaited) target = holder.id;
    else if (holder?.type === "AssignmentExpression" && holder.operator === "=" && holder.right === awaited && this.parents.get(holder)?.type === "ExpressionStatement") {
      target = holder.left;
    }
    if (target?.type !== "ArrayPattern") throw new Unresolved("Promise.all's result not destructured by an array pattern", call.start);
    const index = arr.elements.indexOf(node);
    if (target.elements.slice(0, index + 1).some((e) => e?.type === "RestElement")) throw new Unresolved("a rest element taking the namespace", target.start);
    let el = target.elements[index] ?? null;
    if (el?.type === "AssignmentPattern") el = el.left;
    if (el === null) return;
    if (el.type === "ObjectPattern") return this.pattern(el);
    if (el.type === "Identifier") {
      const v = this.entry.decls.get(el.start) ?? this.entry.refs.get(el.start)?.resolved;
      return this.binding(v);
    }
    throw new Unresolved("the namespace bound to a nested pattern", el.start);
  }
}

// {"op":"namespace","module":key,"source"?:...,"file":F,"name":Z,"loaders"?:[...]}
//   Whether every place the module loads the file F whole, a named
//   loader's call included (`loaders` as `loads` takes them), reaches no
//   read of the export Z other than through the walk above.
//   -> {"safe":true,"sites":n,"trusted":[...],"thenable":bool}
//   -> {"safe":false,"reason":"...","at":offset|null}
function namespace(req) {
  if (typeof req.module !== "string" || typeof req.file !== "string" || typeof req.name !== "string") {
    return { ok: false, error: "namespace needs a string `module`, `file` and `name`" };
  }
  const entry = moduleFor(req);
  if (entry === null) return { ok: true, need_source: true };
  if (entry.error) return { ok: true, safe: false, reason: `the module does not parse: ${entry.error}`, at: null };
  if (entry.evals) return { ok: true, safe: false, reason: "the module calls eval directly", at: null };
  const named = new Map();
  for (const [node, spec] of loaderUses(entry, loaderNames(req)).uses) if (spec !== null) named.set(node, fileName(spec));
  const walk = new Namespace(entry, req.name, named);
  const paramSpecs = paramSpecsOf(entry);
  let sites = 0;
  try {
    const stack = [entry.ast];
    while (stack.length) {
      const node = stack.pop();
      // The walk does not follow a load through its specifier's parameter.
      if (isRequire(node) && paramSpecs(node.arguments[0])?.some((s) => fileName(s) === req.file)) {
        return { ok: true, safe: false, reason: "a parameter's caller names the file", at: node.start };
      }
      if ((named.get(node) ?? loadedFile(node)) === req.file) {
        sites++;
        walk.site(node);
      }
      for (const key of Object.keys(node)) {
        const child = node[key];
        for (const c of Array.isArray(child) ? child : [child]) {
          if (c && typeof c.type === "string" && c !== node) stack.push(c);
        }
      }
    }
  } catch (e) {
    if (e instanceof RangeError) return { ok: true, safe: false, reason: "the namespace is too deep to follow", at: null };
    if (!(e instanceof Unresolved)) throw e;
    return { ok: true, safe: false, reason: e.message, at: e.at };
  }
  return { ok: true, safe: true, sites, trusted: [...new Set([...walk.trusted, ...entry.folds])].sort(), thenable: walk.thenable };
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

// Whether an object literal property is an own `__proto__` property: every
// form but `__proto__:v` or `"__proto__":v`, which set the literal's
// prototype instead.
const ownProto = (p) =>
  p.type === "Property" && keyName(p.key, p.computed) === "__proto__" && (p.computed || p.shorthand || p.method || p.kind !== "init");

const SINK_LIMIT = 20;
// A computed key known to be a number, which no trusted name spells.
const NUMBER = Symbol("number");
const ARITHMETIC = new Set(["-", "*", "/", "%", "**", "|", "&", "^", "<<", ">>", ">>>"]);
// node:vm's ways to run a string as code, its specifiers, and the names
// an import of it may hold and still run nothing.
const VM_RUNNERS = new Set([
  "runInThisContext",
  "runInNewContext",
  "runInContext",
  "compileFunction",
  "SourceTextModule",
  "SyntheticModule",
]);
const VM_SPECIFIERS = new Set(["vm", "node:vm"]);
const VM_HARMLESS = new Set(["isContext"]);

// The specifier a node loads from, any kind of load or re-export, or null.
function loadedSpecifier(node) {
  if (node.type === "ImportExpression") return literalString(node.source);
  if (isRequire(node)) return literalString(node.arguments[0]);
  if (node.type === "ImportDeclaration" || node.type === "ExportAllDeclaration" || node.type === "ExportNamedDeclaration") {
    return node.source?.value ?? null;
  }
  return null;
}

const TYPEOF = ["undefined", "object", "boolean", "number", "bigint", "string", "symbol", "function"];

// What a computed key in the module can be: `keyValues(node)` is the
// strings it can evaluate to, NUMBER for any number, or null when unknown.
// A variable counts only when every write to it is known; a cycle through
// one (`s=s+x`) is unknown.
function keyValuesOf(entry) {
  const parents = parentsOf(entry);
  const variable = (id) => entry.refs.get(id.start)?.resolved ?? null;
  const seen = new Set();
  const union = (...sets) => (sets.includes(null) ? null : new Set(sets.flatMap((s) => [...s])));
  const keyValues = (node, depth = 0) => {
    if (depth > 16) return null;
    switch (node.type) {
      case "Literal":
        if (typeof node.value === "string") return new Set([node.value]);
        if (typeof node.value === "number" || node.bigint !== undefined) return new Set([NUMBER]);
        return node.value === null || typeof node.value === "boolean" ? new Set([String(node.value)]) : null;
      case "TemplateLiteral":
        return node.expressions.length === 0 ? new Set([node.quasis[0].value.cooked]) : null;
      case "UpdateExpression":
        return new Set([NUMBER]);
      case "UnaryExpression":
        if (["-", "+", "~"].includes(node.operator)) return new Set([NUMBER]);
        if (node.operator === "!") return new Set(["true", "false"]);
        if (node.operator === "void") return new Set(["undefined"]);
        if (node.operator === "typeof") return new Set(TYPEOF);
        return null;
      case "BinaryExpression":
        if (ARITHMETIC.has(node.operator)) return new Set([NUMBER]);
        if (node.operator !== "+") return new Set(["true", "false"]);
        {
          const sides = union(keyValues(node.left, depth + 1), keyValues(node.right, depth + 1));
          return sides !== null && [...sides].every((v) => v === NUMBER) ? sides : null;
        }
      case "ConditionalExpression":
        return union(keyValues(node.consequent, depth + 1), keyValues(node.alternate, depth + 1));
      case "LogicalExpression":
        return union(keyValues(node.left, depth + 1), keyValues(node.right, depth + 1));
      case "SequenceExpression":
        return keyValues(node.expressions.at(-1), depth + 1);
      case "AssignmentExpression":
        if (node.operator === "=") return keyValues(node.right, depth + 1);
        return ARITHMETIC.has(node.operator.slice(0, -1)) ? new Set([NUMBER]) : null;
      case "Identifier": {
        const v = variable(node);
        if (!v || v.defs.length !== 1 || v.defs[0].type !== "Variable" || seen.has(v)) return null;
        const def = v.defs[0];
        if (def.node.id !== def.name || isLoop(parents.get(def.parent))) return null;
        seen.add(v);
        try {
          // A `var` read before its initializer runs is undefined.
          const sets = [def.parent.kind === "var" || def.node.init === null ? new Set(["undefined"]) : new Set()];
          for (const r of v.references) {
            if (!r.isWrite()) continue;
            if (r.identifier === def.name) {
              if (def.node.init !== null) sets.push(keyValues(def.node.init, depth + 1));
              continue;
            }
            const w = parents.get(r.identifier);
            if (w?.type === "UpdateExpression") sets.push(new Set([NUMBER]));
            else if (w?.type === "AssignmentExpression" && w.left === r.identifier) sets.push(keyValues(w, depth + 1));
            else return null;
          }
          return union(...sets);
        } finally {
          seen.delete(v);
        }
      }
    }
    return null;
  };
  return keyValues;
}

// `Object` or `Reflect`, as a name or a member (`globalThis.Object`); by
// name, so a shadowing binding counts too.
const isDefinerHome = (n) =>
  (n?.type === "Identifier" && (n.name === "Object" || n.name === "Reflect")) ||
  (n?.type === "MemberExpression" && ["Object", "Reflect"].includes(memberName(n)));

// The name a definer home (`isDefinerHome`) goes by.
const homeName = (n) => (n.type === "Identifier" ? n.name : memberName(n));

// A built-in that defines properties on an object it is given, with how
// it takes the key: Object.defineProperty/defineProperties/assign/
// setPrototypeOf, Reflect.defineProperty/set/setPrototypeOf, and
// x.__defineGetter__/__defineSetter__, whose receiver is the target.
function definerOf(n) {
  const name = memberName(n);
  if (name === "__defineGetter__" || name === "__defineSetter__") return { name, receiver: true, keyed: false };
  if (n?.type !== "MemberExpression" || !isDefinerHome(n.object)) return null;
  return definerNamed(homeName(n.object), name);
}

// The definer `home`'s method `name` is, as `definerOf` describes it, or null.
function definerNamed(home, name) {
  if (home === "Object" && ["defineProperty", "defineProperties", "assign", "setPrototypeOf"].includes(name)) {
    return { name, receiver: false, keyed: name === "defineProperty" };
  }
  if (home === "Reflect" && ["defineProperty", "set", "setPrototypeOf"].includes(name)) {
    return { name, receiver: false, keyed: name !== "setPrototypeOf" };
  }
  return null;
}

// The statics of `Object` and `Reflect` that define nothing and hand out
// no code to run, which a declarator may destructure freely; any other
// key (`__defineGetter__`, `constructor`) is a definer escape. `Reflect.get`
// and `getOwnPropertyDescriptor(s)` are not inert: each reads a definer off
// a prototype (`g(Array.prototype,"__defineGetter__")`, `.value`) for a
// call the scan does not follow.
const INERT_STATICS = new Set([
  "getPrototypeOf",
  "getOwnPropertyNames",
  "getOwnPropertySymbols",
  "keys",
  "values",
  "entries",
  "create",
  "hasOwn",
  "is",
  "isExtensible",
  "isFrozen",
  "isSealed",
  "freeze",
  "seal",
  "preventExtensions",
  "fromEntries",
  "has",
  "ownKeys",
]);

// What a target needs to be a fresh object: `needs`, the exported
// parameters every importer must pass a fresh object to (each a JSON
// [name, index]), and `trusts`, the built-in names it relies on. Null in
// place of one is a target that may be a built-in prototype.
const FRESH = { needs: new Set(), trusts: new Set() };
const both = (a, b) => a && b && { needs: new Set([...a.needs, ...b.needs]), trusts: new Set([...a.trusts, ...b.trusts]) };
const trusting = (f, ...names) => both(f, { needs: new Set(), trusts: new Set(names) });
const freshReply = (f) => ({ needs: [...f.needs].sort().map((n) => JSON.parse(n)), trusted: [...f.trusts].sort() });
// The methods of `Object` that return the object they are given.
const RETURNS_TARGET = new Set(["defineProperty", "defineProperties", "assign", "setPrototypeOf"]);
// The global constructors that make their object with
// OrdinaryCreateFromConstructor, so `new` of one, or `super()` in a class
// extending one, gives a fresh object. `Object` is not one: `new Object(o)`
// returns `o`.
const BUILTIN_CONSTRUCTORS = new Set([
  "Error",
  "EvalError",
  "RangeError",
  "ReferenceError",
  "SyntaxError",
  "TypeError",
  "URIError",
  "Map",
  "Set",
  "WeakMap",
  "WeakSet",
]);

// What makes a target in the analyzed module `entry` (`analyze`) a fresh
// object, which no write can make a built-in prototype: a function from a
// node to its freshness (FRESH, `both`) or null. Fresh are a literal, a
// function or class expression, `new` of a class the module declares or
// of a built-in constructor by its global name (trusting that name), a
// call of the global `Object.create` (trusting `Object` and `create`,
// either of which can be replaced first), what an Object definer returns
// given a fresh object (trusting `Object` and its name), `this` in the
// constructor of a class with no superclass or a built-in one (trusting
// its name) or in a function only ever bound to a fresh object (trusting
// `bind`), the own `prototype` of a function or class, a `?:` with both
// branches fresh, and a variable only ever holding one of those. A
// parameter never written holds what each call passes.
function freshnessOf(entry) {
  const parents = parentsOf(entry);
  const variable = (id) => entry.refs.get(id.start)?.resolved ?? null;
  const onlyInit = (v) => v.references.every((r) => !r.isWrite() || r.identifier === v.defs[0].name);
  // The method of the global `Object` that `node` reads, directly or
  // through a variable only ever holding it (`var c=Object.create`,
  // `var{create:c}=Object`), or null.
  const objectMethod = (node) => {
    const isObject = (n) => n?.type === "Identifier" && n.name === "Object" && entry.refs.get(n.start)?.resolved === null;
    if (node.type === "MemberExpression") return isObject(node.object) ? memberName(node) : null;
    const v = node.type === "Identifier" ? variable(node) : null;
    const def = v?.defs.length === 1 ? v.defs[0] : null;
    if (def?.type !== "Variable" || def.node.init === null || !onlyInit(v)) return null;
    if (def.node.id === def.name) return def.node.init.type === "MemberExpression" ? objectMethod(def.node.init) : null;
    const prop = parents.get(def.name);
    const own = prop?.type === "Property" && prop.value === def.name && parents.get(prop) === def.node.id;
    return own && isObject(def.node.init) ? keyName(prop.key, prop.computed) : null;
  };
  // Every name the module exports `v` under, "default" included.
  const exportNames = (v) => {
    const def = v.defs[0];
    const holder = parents.get(def.type === "Variable" ? def.parent : def.node);
    const names = holder?.type === "ExportNamedDeclaration" ? [v.name] : holder?.type === "ExportDefaultDeclaration" ? ["default"] : [];
    for (const r of v.references) {
      const spec = parents.get(r.identifier);
      if (spec?.type === "ExportSpecifier" && spec.local === r.identifier) names.push(spec.exported.name ?? spec.exported.value);
    }
    return names;
  };
  // The built-in constructor `node` names by its unshadowed global name, or null.
  const builtinNamed = (node) =>
    node?.type === "Identifier" && BUILTIN_CONSTRUCTORS.has(node.name) && entry.refs.get(node.start)?.resolved === null ? node.name : null;
  // A reference to a class that hands it to other code only where `fresh`
  // clears nothing: a `new` of it (`new.target`, an instance's
  // `constructor`), a named member read that writes nothing or the right of
  // `instanceof` (`this` in a getter or method), a superclass, or an
  // `export{...}` (an importer's binding). A prototype swap on the class
  // there is a sink.
  const classUse = (id) => {
    const p = parents.get(id);
    switch (p?.type) {
      case "NewExpression":
        return p.callee === id;
      case "BinaryExpression":
        return p.operator === "instanceof" && p.right === id;
      case "ClassDeclaration":
      case "ClassExpression":
        return p.superClass === id;
      case "ExportSpecifier":
        return p.local === id;
      case "MemberExpression": {
        const up = parents.get(p);
        const written = isTarget(parents, p) || up?.type === "UpdateExpression" || (up?.type === "UnaryExpression" && up.operator === "delete");
        return p.object === id && memberName(p) !== null && !written;
      }
      default:
        return false;
    }
  };
  // Whether a swap of the class `cls`'s own prototype is always a sink: it
  // is a declaration or a plain declarator's class, never written again,
  // and every reference to it is a `classUse`. Any other reference (an
  // argument, an alias) could hand it to `Object.setPrototypeOf` or
  // `__proto__=` as a target `fresh` clears.
  const unswapped = (cls) => {
    const holder = parents.get(cls);
    const declarator = holder?.type === "VariableDeclarator" && holder.init === cls && holder.id.type === "Identifier" ? holder : null;
    if (cls.type !== "ClassDeclaration" && declarator === null) return false;
    const vars = [...entry.manager.getDeclaredVariables(cls), ...(declarator ? entry.manager.getDeclaredVariables(declarator) : [])];
    return vars.every((v) => v.defs.length === 1 && v.references.every((r) => (r.isWrite() ? r.identifier === v.defs[0].name : classUse(r.identifier))));
  };
  // A class extending a built-in constructor (`class Q extends Error`):
  // `super()` constructs with the class's own prototype, so it makes a
  // fresh object while that is still the built-in (`unswapped`), trusting
  // the name. Null for any other superclass.
  const extendsBuiltin = (cls) => {
    const name = builtinNamed(cls.superClass);
    return name !== null && unswapped(cls) ? trusting(FRESH, name) : null;
  };
  // A class declared in the module and never replaced, with no superclass
  // or a built-in one (any other derived class's instance is whatever
  // `super()` returns) and no constructor returning a value in place of
  // the instance: what `new` of it makes, or null.
  const ownClass = (callee) => {
    const v = callee.type === "Identifier" ? variable(callee) : null;
    const def = v?.defs.length === 1 && onlyInit(v) ? v.defs[0] : null;
    const cls = def?.type === "ClassName" ? def.node : def?.type === "Variable" && def.node.id === def.name ? def.node.init : null;
    if (cls?.type !== "ClassDeclaration" && cls?.type !== "ClassExpression") return null;
    const made = cls.superClass === null ? FRESH : extendsBuiltin(cls);
    const ctor = cls.body.body.find((m) => m.kind === "constructor");
    const stack = made && ctor ? [ctor.value.body] : [];
    while (stack.length) {
      const node = stack.pop();
      if (node.type === "ReturnStatement" && node.argument !== null) return null;
      if (FUNCTIONS.has(node.type)) continue;
      for (const key of Object.keys(node)) {
        const child = node[key];
        for (const c of Array.isArray(child) ? child : [child]) if (c && typeof c.type === "string") stack.push(c);
      }
    }
    return made;
  };
  // The assignment `v=...` writing `id`, when it runs before every read of
  // `v`: a plain `=` inside nothing but sequences and declarations, in a
  // statement directly in the block of `v`'s scope, every read coming
  // later in that same function.
  const assignedFirst = (v, id) => {
    const set = parents.get(id);
    if (set?.type !== "AssignmentExpression" || set.operator !== "=" || set.left !== id) return null;
    const block = v.scope.block;
    const statements = FUNCTIONS.has(block.type) ? block.body.body : block.body;
    if (!Array.isArray(statements)) return null;
    for (let node = set; !statements.includes(node); node = parents.get(node)) {
      const up = parents.get(node);
      const through = ["SequenceExpression", "ExpressionStatement", "VariableDeclaration"].includes(up?.type) || (up?.type === "VariableDeclarator" && up.init === node);
      if (!through) return null;
    }
    // Any other write, a loop head's (`for(var v of a)`) included, rules it out.
    const later = (r) => r.identifier === id || (!r.isWrite() && r.from.variableScope === v.scope.variableScope && r.identifier.start >= set.end);
    const param = v.defs[0].type === "Parameter";
    return v.references.every(later) && !(param && aliased(block)) ? set : null;
  };
  // Whether sloppy code could change a parameter of the function `fn`
  // unseen, through `arguments` (an arrow's `arguments` is its caller's).
  const aliased = (fn) => {
    if (fn.type === "ArrowFunctionExpression") return false;
    const scope = entry.manager.acquire(fn, true);
    return !scope || scope.set.get("arguments")?.references.length > 0;
  };
  // A function declaration in a block, which sloppy code also binds outside it.
  const inBlock = (fn) => {
    const holder = parents.get(fn);
    return fn.type === "FunctionDeclaration" && !["Program", "ExportNamedDeclaration"].includes(holder?.type) && !FUNCTIONS.has(parents.get(holder)?.type);
  };
  const passed = new Map();
  // Parameter `index` of the function `fn`, never written: what every call
  // passes, when `fn` is bound to a plain name and used only by direct
  // calls and exports. Each name it is exported under needs every
  // importer's call to pass a fresh object too.
  const passedTo = (fn, index, depth) => {
    const key = `${fn.start}:${index}`;
    if (passed.has(key)) return passed.get(key);
    passed.set(key, null);
    const v = inBlock(fn) || aliased(fn) ? null : functionBinding(entry, parents, fn);
    const names = v && exportNames(v);
    let out = names && !names.includes("default") ? { needs: new Set(names.map((n) => JSON.stringify([n, index]))), trusts: new Set() } : null;
    for (const r of out ? v.references : []) {
      const call = parents.get(r.identifier);
      if (r.isWrite() || (call?.type === "ExportSpecifier" && call.local === r.identifier)) continue;
      const direct = call?.type === "CallExpression" && call.callee === r.identifier && !call.arguments.slice(0, index + 1).some((a) => a.type === "SpreadElement");
      const arg = direct ? call.arguments[index] : undefined;
      out = arg === undefined ? null : both(out, fresh(arg, depth + 1));
      if (out === null) break;
    }
    passed.set(key, out);
    return out;
  };
  const bound = new Map();
  // `this` in the function `fn`, when every reference to `fn` binds it to
  // a fresh object (`r.bind(o,...)`): the bound function's `this` stays
  // `o` however it is called.
  const boundThis = (fn, depth) => {
    if (bound.has(fn)) return bound.get(fn);
    bound.set(fn, null);
    const v = inBlock(fn) ? null : functionBinding(entry, parents, fn);
    let out = v && exportNames(v).length === 0 ? trusting(FRESH, "bind") : null;
    for (const r of out ? v.references : []) {
      if (r.isWrite()) continue;
      const member = parents.get(r.identifier);
      const call = parents.get(member);
      const binds = call?.type === "CallExpression" && call.callee === member && member.object === r.identifier && memberName(member) === "bind";
      const to = binds ? call.arguments[0] : undefined;
      out = to === undefined || to.type === "SpreadElement" ? null : both(out, fresh(to, depth + 1));
      if (out === null) break;
    }
    bound.set(fn, out);
    return out;
  };
  const fresh = (node, depth = 0) => {
    if (depth > 8) return null;
    switch (node.type) {
      case "ObjectExpression":
      case "ArrayExpression":
      case "FunctionExpression":
      case "ArrowFunctionExpression":
      case "ClassExpression":
        return FRESH;
      // Replacing a built-in's global name replaces what `new` of it makes.
      case "NewExpression": {
        const name = builtinNamed(node.callee);
        return name !== null ? trusting(FRESH, name) : ownClass(node.callee);
      }
      // Replacing `Object` itself replaces the method too.
      case "CallExpression": {
        const name = objectMethod(node.callee);
        if (name === "create") return trusting(FRESH, "Object", name);
        const target = node.arguments[0];
        const given = RETURNS_TARGET.has(name) && target !== undefined && target.type !== "SpreadElement";
        return given ? trusting(fresh(target, depth + 1), "Object", name) : null;
      }
      case "ConditionalExpression": {
        const consequent = fresh(node.consequent, depth + 1);
        return consequent && both(consequent, fresh(node.alternate, depth + 1));
      }
      case "ThisExpression": {
        let fn = parents.get(node);
        while (fn && (!FUNCTIONS.has(fn.type) || fn.type === "ArrowFunctionExpression")) {
          // A field initializer's `this` is the instance, which a derived class takes from `super()`.
          if (fn.type === "PropertyDefinition" || fn.type === "StaticBlock") return null;
          fn = parents.get(fn);
        }
        const holder = fn && parents.get(fn);
        if (holder?.type !== "MethodDefinition") return fn ? boundThis(fn, depth) : null;
        if (holder.kind !== "constructor") return null;
        // A derived class's `this` is what `super()` returns, which can be
        // any object unless the superclass is a built-in.
        const cls = parents.get(parents.get(holder));
        if (cls === undefined) return null;
        return cls.superClass === null ? FRESH : extendsBuiltin(cls);
      }
      case "Identifier": {
        const v = variable(node);
        if (v?.defs.length !== 1) return null;
        const def = v.defs[0];
        if (def.type === "FunctionName" || def.type === "ClassName") return v.references.some((r) => r.isWrite()) ? null : FRESH;
        const writes = v.references.filter((r) => r.isWrite() && r.identifier !== def.name);
        const plain = def.type === "Parameter" || (def.type === "Variable" && def.node.id === def.name);
        if (!plain || writes.length > 1) return null;
        if (def.type === "Variable" && def.node.init !== null) return writes.length === 0 ? fresh(def.node.init, depth + 1) : null;
        if (writes.length === 1) {
          const set = assignedFirst(v, writes[0].identifier);
          return set && fresh(set.right, depth + 1);
        }
        const index = def.type === "Parameter" ? def.node.params.indexOf(def.name) : -1;
        return index < 0 || def.node.params.slice(0, index).some((p) => p.type === "RestElement") ? null : passedTo(def.node, index, depth);
      }
      case "MemberExpression": {
        if (memberName(node) !== "prototype" || node.object.type !== "Identifier") return null;
        const v = variable(node.object);
        if (v?.defs.length !== 1) return null;
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
        const intact = (r) => {
          if (r.isWrite()) return r.identifier === def.name;
          const m = parents.get(r.identifier);
          const use = m && parents.get(m);
          const key = use?.type === "MemberExpression" && use.object === m ? memberName(use) : null;
          return m?.type === "MemberExpression" && m.object === r.identifier && memberName(m) === "prototype" && key !== null && key !== "constructor";
        };
        return own && v.references.every(intact) ? FRESH : null;
      }
      default:
        return null;
    }
  };
  return fresh;
}

// {"op":"sinks","module":key,"source"?:...,"names":[...]}
//   Where the module may write a property the flow trusts (`names`) on an
//   object that could be a built-in prototype:
//   - a member write, update or `delete` whose key is one of the names;
//   - a member write with a computed key that may name anything, which
//     can write any name. A computed key is known when every value it can
//     evaluate to is: a literal, a number (arithmetic, `++`, a unary
//     minus), a boolean or typeof result, or a variable every write of
//     which is one of those (`for(let i=0;...;i++)o[i]=`, a TypeScript
//     enum's `e[e.X=1]=`); it then counts only for the names it spells;
//   - a call given one of the names as a string or `Symbol.x` argument
//     (`Object.defineProperty(o,"includes",...)`, `o.__defineGetter__("has")`,
//     `Reflect.set(o,"some",f)`, or any other callee that may pass it on);
//   - an object literal holding one of the names given to `assign`,
//     `defineProperties`, `setPrototypeOf` or `defineProperty`;
//   - a prototype swap: a `__proto__` write, `Reflect.set` given the key
//     `__proto__`, an own `__proto__` property given to `Object.assign`, or
//     a `setPrototypeOf` call, which can put any object's properties on the
//     chain;
//   - a write to an undeclared (global) name that is one of the names;
//   - code run from a string through node:vm: any load of the vm module
//     except an import naming only `isContext`, and a vm runner's name
//     (`runInThisContext`, `runInNewContext`, ...) read from any object;
//   - a load the scan cannot name (`unknownLoad`, and a use of a named
//     loader other than a call with a literal specifier, given `loaders`
//     as `loads` takes them), which may load node:vm;
//   - the global `Function` used other than for `typeof`, `instanceof` or
//     a `.prototype` read that stays clear of `constructor` (`prototypeOnly`),
//     except a build whose result is discarded and a
//     direct call whose every argument folds to a constant string and
//     whose code, scanned the same way, hits nothing (`unrunOrClean`);
//   - a definer read other than as a direct callee, including through an
//     alias of `Object` or `Reflect`; a declarator destructuring them is
//     no alias when each definer it takes (`var{defineProperty:f}=Object`)
//     is a variable never written again and only ever called, each call
//     then checked as a definer's;
//   - a read of `constructor`, by name, by a computed key that may spell
//     it or as a destructured key, since a function's `constructor` is
//     the Function constructor (`(()=>1).constructor("code")()`), except
//     a read whose value can never be called (`constructorInert`).
//   A target is cleared only when it is provably a fresh object
//   (`freshnessOf`). `Function` counts as one of the names, since the
//   folded calls trust it: a write of it anywhere is a sink of its own
//   (as an argument, only to a definer, as are `Object` and the built-in
//   constructors).
//   -> {"hits":[[kind, name|null, offset], ...]} (at most SINK_LIMIT); a
//      module that does not parse or calls `eval` directly is one hit,
//      except a direct `eval` that only reads an identifier (`foldEvals`),
//      read as that identifier, whose fold adds its built-ins to "trusted".
//      "pending" holds the hits on a target that is fresh only if every
//      importer passes fresh objects, each [kind, name|null, offset,
//      [[export, index], ...]], for the caller to check (`fresh_args`);
//      "trusted" lists the names the cleared targets relied on, which the
//      caller must check every module for too.
function sinks(req) {
  if (typeof req.module !== "string" || !Array.isArray(req.names)) {
    return { ok: false, error: "sinks needs a string `module` and a `names` list" };
  }
  const entry = moduleFor(req);
  if (entry === null) return { ok: true, need_source: true };
  return { ok: true, ...sinkHits(entry, new Set([...req.names, "Function"]), 0, loaderNames(req)) };
}

// How deep a folded `Function` body that builds another is followed.
const FOLD_DEPTH = 4;

// The `sinks` reply for an analyzed module (`analyze`), or for code a
// `Function` call folded to, `depth` folds down; `loaders` as
// `loaderNames` reads them.
function sinkHits(entry, names, depth, loaders = new Set()) {
  if (entry.error) return { hits: [["unparsed", null, 0]], pending: [], trusted: [] };
  if (entry.evals) return { hits: [["eval", null, 0]], pending: [], trusted: [] };
  const parents = parentsOf(entry);
  const hits = [];
  const hit = (kind, name, node) => hits.length < SINK_LIMIT && hits.push([kind, name, node.start]);
  const held = loaderUses(entry, loaders);
  for (const [node, spec] of held.uses) {
    if (spec === null) hit("unknown-load", null, node);
    else if (VM_SPECIFIERS.has(spec)) hit("vm-string-code", null, node);
  }
  const variable = (id) => entry.refs.get(id.start)?.resolved ?? null;
  const onlyInit = (v) => v.references.every((r) => !r.isWrite() || r.identifier === v.defs[0].name);
  const fresh = freshnessOf(entry);
  const pending = [];
  const trusted = new Set(entry.folds);
  // `loads` never sees a parameter's callers in code a `Function` call folded to.
  const paramSpecs = depth === 0 ? paramSpecsOf(entry) : () => null;
  // Counts each of `found` ([kind, name, node]) unless every one of
  // `targets` is fresh. Cleared, the hits leave their trusted names; on
  // a target fresh only through importers they wait in `pending`.
  const unlessFresh = (found, targets) => {
    if (found.length === 0) return;
    let f = FRESH;
    for (const t of targets) f = f && (t === undefined || t.type === "SpreadElement" ? null : both(f, fresh(t)));
    if (f === null) {
      for (const [kind, name, node] of found) hit(kind, name, node);
      return;
    }
    for (const name of f.trusts) trusted.add(name);
    if (f.needs.size === 0) return;
    const { needs } = freshReply(f);
    for (const [kind, name, node] of found) {
      if (pending.length < SINK_LIMIT) pending.push([kind, name, node.start, needs]);
      else hit(kind, name, node);
    }
  };
  // The definer a callee is, read directly (`definerOf`) or through a key
  // destructured from `Object` or `Reflect`.
  const definerAt = (callee) => {
    if (callee.type !== "Identifier") return definerOf(callee);
    const def = variable(callee)?.defs[0];
    const prop = def?.type === "Variable" ? parents.get(def.name) : null;
    if (prop?.type !== "Property" || prop.value !== def.name || parents.get(prop) !== def.node.id || !isDefinerHome(def.node.init)) return null;
    return definerNamed(homeName(def.node.init), keyName(prop.key, prop.computed));
  };
  // Whether every definer the declarator `d` destructures from `Object` or
  // `Reflect` is a variable never written again and only ever called, and
  // every other key it takes is inert (`INERT_STATICS`); a computed key or
  // a rest element may take anything.
  const onlyCalled = (d) =>
    d.id.properties.every((p) => {
      if (p.type !== "Property" || p.computed) return false;
      const key = keyName(p.key, false);
      if (definerNamed(homeName(d.init), key) === null) return INERT_STATICS.has(key);
      const v = p.value.type === "Identifier" ? entry.decls.get(p.value.start) : null;
      const called = (r) => parents.get(r.identifier)?.type === "CallExpression" && parents.get(r.identifier).callee === r.identifier;
      return v?.defs.length === 1 && onlyInit(v) && v.references.every((r) => r.isWrite() || called(r));
    });
  // `Promise=f` in a module replaces the global binding a trusted
  // `Promise.all` reads.
  for (const ref of entry.manager.globalScope.through) {
    if (ref.isWrite() && names.has(ref.identifier.name)) hit("global-write", ref.identifier.name, ref.identifier);
  }
  const keyValues = keyValuesOf(entry);
  // The trusted names a computed `key` may spell, or null when it may spell any.
  const keyNames = (key) => {
    const values = keyValues(key);
    if (values === null || values.has("__proto__") || (values.has(NUMBER) && numericName)) return null;
    return [...values].filter((v) => v !== NUMBER && names.has(v));
  };
  const numericName = [...names].some((n) => String(Number(n)) === n || n === "-0");
  const literalNames = (obj) =>
    obj.properties.flatMap((p) => {
      if (p.type !== "Property") return [null];
      const k = keyName(p.key, p.computed);
      if (k !== null) return names.has(k) ? [k] : [];
      return keyNames(p.key) ?? [null];
    });
  // Whether the global `Function` read as `node` is `Function.prototype`
  // going on only to members other than `constructor`, which is Function
  // again: each further key, after any call on the way (whose result may
  // be any object), names another member (a computed key must be known
  // not to spell it), and the chain ends discarded, tested, compared or
  // written, never held or handed to code that could take its
  // `constructor` (`instanceof` hands it to `Symbol.hasInstance`).
  const prototypeOnly = (node) => {
    let top = parents.get(node);
    if (memberName(top) !== "prototype" || top.object !== node || isTarget(parents, top)) return false;
    for (;;) {
      const up = parents.get(top);
      if (up?.type === "MemberExpression" && up.object === top) {
        const key = keyName(up.property, up.computed);
        const keys = key === null ? keyValues(up.property) : new Set([key]);
        if (keys === null || keys.has("constructor")) return false;
      } else if (up?.type !== "ChainExpression" && !isCallee(up, top)) {
        break;
      }
      top = up;
    }
    const end = parents.get(top);
    if (end?.type === "BinaryExpression") return end.operator !== "instanceof";
    return (
      isTarget(parents, top) ||
      ["UnaryExpression", "UpdateExpression", "ExpressionStatement"].includes(end?.type) ||
      (["IfStatement", "WhileStatement", "DoWhileStatement", "ForStatement", "ConditionalExpression"].includes(end?.type) && end.test === top)
    );
  };
  // Whether the value of `n` is thrown away: an expression statement, a
  // sequence operand other than the last (`try{return new Function(""),!0}`),
  // or a branch of a conditional or the right operand of a logical
  // expression whose own value is thrown away (`r ? o.constructor : null;`).
  const discarded = (n) => {
    const p = parents.get(n);
    if (p?.type === "ExpressionStatement") return true;
    if (p?.type === "SequenceExpression") return p.expressions.at(-1) !== n || discarded(p);
    if (p?.type === "ConditionalExpression") return p.test !== n && discarded(p);
    if (p?.type === "LogicalExpression") return p.right === n && discarded(p);
    return p?.type === "ChainExpression" && discarded(p);
  };
  // Whether the property key `key` may be `constructor`.
  const maySpellConstructor = (key, computed) => {
    const name = keyName(key, computed);
    const keys = name === null ? keyValues(key) : new Set([name]);
    return keys === null || keys.has("constructor");
  };
  // Whether the `constructor` read as `node` is only discarded, tested,
  // compared by identity, the right of `instanceof`, or followed by a
  // `name` read or a plain `prototype` write: none of these calls it or
  // coerces it, which would call a `valueOf` or `toString` with it as
  // `this`. A Function constructor owns `name` and `prototype`, so no
  // inherited getter or setter runs on it either.
  const constructorInert = (node) => {
    let top = node;
    while (parents.get(top)?.type === "ChainExpression") top = parents.get(top);
    const end = parents.get(top);
    if (end?.type === "MemberExpression" && end.object === top) {
      const by = parents.get(end);
      const plainWrite = by?.type === "AssignmentExpression" && by.operator === "=" && by.left === end;
      return memberName(end) === "name" ? !isTarget(parents, end) : memberName(end) === "prototype" && plainWrite;
    }
    if (end?.type === "BinaryExpression") return end.operator === "===" || end.operator === "!==" || (end.operator === "instanceof" && end.right === top);
    if (end?.type === "UnaryExpression") return ["typeof", "!", "void", "delete"].includes(end.operator);
    return discarded(top) || onlyTested(parents, top);
  };
  // `Function(...)` and `new Function(...)` build a function from strings
  // and run none of its body; only a call runs it. So the global
  // `Function` as the callee of `built` runs no unknown code when the
  // result is discarded, or when `built` is called directly
  // (`Function("return this")()`) with every argument a constant string
  // and the code those spell, parsed as a function, hits nothing here.
  // The wrapper has no name, since the built function binds none in its
  // body. It is parsed as a module, which rejects what only sloppy code
  // allows (`with`) and parses the rest the same, except an HTML-like
  // comment (`<!--`, `-->`), so text holding one is not folded.
  const unrunOrClean = (callee, built) => {
    if ((built?.type !== "CallExpression" && built?.type !== "NewExpression") || built.callee !== callee) return false;
    if (discarded(built)) return true;
    const run = parents.get(built);
    if (run?.type !== "CallExpression" || run.callee !== built || depth >= FOLD_DEPTH) return false;
    const parts = built.arguments.map(literalString);
    if (parts.some((s) => s === null || s.includes("<!--") || s.includes("-->"))) return false;
    const body = parts.pop() ?? "";
    const folded = sinkHits(analyze(`(function(${parts.join(",")}\n) {\n${body}\n})`), names, depth + 1);
    if (folded.hits.length > 0 || folded.pending.length > 0) return false;
    for (const name of folded.trusted) trusted.add(name);
    return true;
  };
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
        const found = [];
        if (key === "__proto__") found.push(["proto-swap", key, node]);
        else if (key !== null) {
          if (names.has(key)) found.push(["write", key, node]);
        } else {
          const spelled = keyNames(node.property);
          if (spelled === null) found.push(["computed-write", null, node]);
          else for (const n of spelled) found.push(["write", n, node]);
        }
        unlessFresh(found, [node.object]);
      }
    } else if (node.type === "CallExpression") {
      const definer = definerAt(node.callee);
      const found = [];
      for (const arg of node.arguments) {
        const key = keyName(arg, true);
        // `Function`, `Object` and the built-in constructors count only
        // given to a definer: any other callee that could write one by its
        // parameter is a computed write of its own, and a type test like
        // underscore's `tagTester("Function")` is no write.
        const builtin = key === "Function" || key === "Object" || BUILTIN_CONSTRUCTORS.has(key);
        if (key !== null && names.has(key) && (!builtin || definer !== null)) found.push(["argument", key, arg]);
      }
      if (definer === null) {
        for (const [kind, name, at] of found) hit(kind, name, at);
      } else {
        if (definer.name === "setPrototypeOf") found.push(["proto-swap", null, node]);
        if (node.arguments.some((a) => a.type === "SpreadElement")) found.push(["computed-define", null, node]);
        const keyArg = definer.receiver ? node.arguments[0] : definer.keyed ? node.arguments[1] : null;
        // A [[Set]] of `__proto__` runs the `Object.prototype` setter, which
        // swaps the prototype: `Reflect.set(o,"__proto__",p)`, and an own
        // `__proto__` property `Object.assign` copies (`{["__proto__"]:p}`).
        if (definer.name === "set" && keyArg && keyName(keyArg, true) === "__proto__") found.push(["proto-swap", null, node]);
        if (keyArg && keyName(keyArg, true) === null) {
          const spelled = keyNames(keyArg);
          if (spelled === null) found.push(["computed-define", null, keyArg]);
          else for (const n of spelled) found.push(["argument", n, keyArg]);
        }
        if (definer.name === "assign" || definer.name === "defineProperties") {
          for (const arg of node.arguments.slice(1)) {
            if (arg.type !== "ObjectExpression") found.push(["computed-define", null, arg]);
            else for (const key of literalNames(arg)) found.push([key === null ? "computed-define" : "object-key", key, arg]);
            if (definer.name === "assign" && arg.type === "ObjectExpression" && arg.properties.some(ownProto)) found.push(["proto-swap", null, arg]);
          }
        }
        const target = definer.receiver ? node.callee.object : node.arguments[0];
        // Reflect.set(target,key,value,receiver) writes onto `receiver` when one is given.
        const receiver = definer.name === "set" && !definer.receiver ? node.arguments[3] : undefined;
        unlessFresh(found, receiver === undefined ? [target] : [target, receiver]);
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
    // `.prototype` read that stays clear of `constructor`
    // (`Function.call(0,"code")` and `Function.prototype.constructor("code")`
    // build code too), or to build code that never runs or folds to code
    // that hits nothing.
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
          prototypeOnly(node);
        if (node.name === "Function" && !inert && !unrunOrClean(node, holder)) hit("function-constructor", null, node);
      }
    }
    // The same built-ins reached as a member of any object
    // (`globalThis.eval`, `window.Function`), read other than as a write
    // target.
    const member = memberName(node);
    if ((member === "eval" || member === "Function") && !isTarget(parents, node)) {
      hit(member === "eval" ? "indirect-eval" : "function-constructor", null, node);
    }
    // A function's `constructor` is the Function constructor, so is any
    // object's `constructor.constructor`, and neither needs the name
    // `Function` (`(()=>1).constructor("code")()`). A compound write
    // (`x.constructor+=s`) reads and coerces it first.
    const overwritten = isTarget(parents, node) && !(holder?.type === "AssignmentExpression" && holder.operator !== "=");
    const constructorRead =
      (node.type === "MemberExpression" && !overwritten && maySpellConstructor(node.property, node.computed) && !constructorInert(node)) ||
      (node.type === "Property" && holder?.type === "ObjectPattern" && maySpellConstructor(node.key, node.computed));
    if (constructorRead) hit("function-constructor", null, node);
    // node:vm runs strings as code, and even a new context reaches this
    // realm (`this.constructor.constructor("...")()` inside
    // `runInNewContext` patches the outer prototypes). Any load of the vm
    // module is a sink, except an import naming only functions that run no
    // code; so is a vm runner's name read or destructured from any object.
    if ((VM_RUNNERS.has(member) && !isTarget(parents, node)) || (node.type === "Property" && parents.get(node)?.type === "ObjectPattern" && VM_RUNNERS.has(keyName(node.key, node.computed)))) {
      hit("vm-string-code", null, node);
    }
    const specs = (isRequire(node) ? paramSpecs(node.arguments[0]) : null) ?? [loadedSpecifier(node)];
    if (specs.some((s) => VM_SPECIFIERS.has(s))) {
      const harmless =
        node.type === "ImportDeclaration" &&
        node.specifiers.every((s) => s.type === "ImportSpecifier" && VM_HARMLESS.has(s.imported.name ?? s.imported.value));
      if (!harmless) hit("vm-string-code", null, node);
    }
    // A load the scan cannot name may load node:vm, and `loads` never sees
    // one in code a `Function` call folded to.
    const unseen = depth > 0 && loadedFile(node) !== null;
    if (unseen || (unknownLoad(node, parents, keyValues, paramSpecs) && !held.cleared.has(node))) hit("unknown-load", null, node);
    if (definerOf(node) !== null && !(holder?.type === "CallExpression" && holder.callee === node)) {
      hit("definer-escape", null, node);
    } else if (isDefinerHome(node) && !(holder?.type === "MemberExpression" && holder.property === node && !holder.computed)) {
      const named = holder?.type === "MemberExpression" && holder.object === node && memberName(holder) !== null;
      const inert =
        ((holder?.type === "CallExpression" || holder?.type === "NewExpression") && holder.callee === node) ||
        holder?.type === "BinaryExpression" ||
        (holder?.type === "UnaryExpression" && holder.operator === "typeof") ||
        (holder?.type === "Property" && holder.key === node && !holder.computed && holder.value !== node) ||
        (holder?.type === "VariableDeclarator" && holder.init === node && holder.id.type === "ObjectPattern" && onlyCalled(holder));
      if (!named && !inert) hit("definer-escape", null, node);
    }
    for (const key of Object.keys(node)) {
      const child = node[key];
      for (const c of Array.isArray(child) ? child : [child]) {
        if (c && typeof c.type === "string" && c !== node) stack.push(c);
      }
    }
  }
  return { hits, pending, trusted: [...trusted].sort() };
}

// {"op":"fresh_args","module":key,"source"?:...,"name":Z,"from":path,"index":i}
//   Whether every use of the export Z the module imports from `from` is a
//   direct call passing a fresh object (`freshnessOf`) as argument i: the
//   check a `sinks` "pending" need leaves to each importer.
//   -> {"fresh":true,"needs":[[export, index], ...],"trusted":[...]}, the
//      needs those arguments carry on the module's own exports
//   -> {"fresh":false} for any other use, a re-export of Z, and a module
//      that does not parse or calls `eval` directly
function freshArgs(req) {
  if (typeof req.module !== "string" || typeof req.name !== "string" || typeof req.from !== "string" || !Number.isInteger(req.index)) {
    return { ok: false, error: "fresh_args needs a string `module`, `name` and `from` and an integer `index`" };
  }
  const entry = moduleFor(req);
  if (entry === null) return { ok: true, need_source: true };
  if (entry.error || entry.evals) return { ok: true, fresh: false };
  const parents = parentsOf(entry);
  const fresh = freshnessOf(entry);
  let found = FRESH;
  for (const node of entry.ast.body) {
    if (node.source?.value !== req.from) continue;
    for (const spec of node.specifiers ?? []) {
      if (node.type === "ExportNamedDeclaration" && (spec.local.name ?? spec.local.value) === req.name) return { ok: true, fresh: false };
      if (spec.type !== "ImportSpecifier" || (spec.imported.name ?? spec.imported.value) !== req.name) continue;
      for (const r of entry.decls.get(spec.local.start)?.references ?? []) {
        const call = parents.get(r.identifier);
        const direct = call?.type === "CallExpression" && call.callee === r.identifier && !call.arguments.slice(0, req.index + 1).some((a) => a.type === "SpreadElement");
        const arg = direct ? call.arguments[req.index] : undefined;
        found = arg === undefined ? null : both(found, fresh(arg));
        if (found === null) return { ok: true, fresh: false };
      }
    }
  }
  return { ok: true, fresh: true, ...freshReply(found) };
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
// `keys_used`, beside the files it loads whole (`loadedFile`) for `loads`
// and the names it imports or re-exports by name for `imports`.
const scans = new Map();
// The name a member reads or writes, as `keyName` spells it; null for a
// computed key that names nothing.
const memberName = (n) => (n?.type === "MemberExpression" ? keyName(n.property, n.computed) : null);

// `scanOf`, or null (every name used, every file loaded) when the
// analysis itself fails.
function scanOrNull(ast) {
  try {
    return scanOf(ast);
  } catch {
    return null;
  }
}

// The module's scan, parsing `req.source` when it is not held; undefined
// when the source is needed.
function scanFor(req) {
  let scan = scans.get(req.module);
  if (scan === undefined) {
    if (typeof req.source !== "string") return undefined;
    try {
      const ast = acorn.parse(req.source, PARSE_OPTIONS);
      foldEvals(ast);
      scan = scanOrNull(ast);
    } catch {
      scan = null;
    }
    scans.set(req.module, scan);
  }
  return scan;
}

// Whether `node` (its parent in `parents`) may load a module the scan
// cannot name: `import(x)` with a specifier that is no literal, and
// `require`, `import.meta.require` or `x.require` used other than as the
// direct callee of a call with a literal specifier (an alias, `.call`,
// `(0,require)`), a `typeof` test, `require.resolve`, or a member read only
// tested for truth (`onlyTested`, lodash's `w&&w.require&&w.require("util")`).
// A binding named `require` is no use.
// A computed member or destructured key counts when `keyValues` (from
// `keyValuesOf`) finds it unknown or able to spell `require`
// (`module[k]`, `x["req"+"uire"]`, `{[k]:r}=globalThis`), except the
// target of a plain `o[k]=v`; even a literal specifier does not name its file.
// A specifier `paramSpecs` (from `paramSpecsOf`) names the literals of is
// named too.
function unknownLoad(node, parents, keyValues, paramSpecs = () => null) {
  const parent = parents.get(node);
  if (node.type === "ImportExpression") return literalString(node.source) === null;
  // `import.meta` other than read by name can hand out its `require`
  // (`var m=import.meta`, `{require:r}=import.meta`), and so can any
  // destructured `require` key.
  if (isImportMeta(node)) return !(parent?.type === "MemberExpression" && parent.object === node && memberName(parent) !== null);
  const mayRequire = (key) => {
    const values = keyValues(key);
    return values === null || values.has("require");
  };
  if (node.type === "Property" && parent?.type === "ObjectPattern") {
    const key = keyName(node.key, node.computed);
    return key === null ? mayRequire(node.key) : key === "require";
  }
  const computed = node.type === "MemberExpression" && memberName(node) === null;
  if (computed) {
    if (parent?.type === "AssignmentExpression" && parent.operator === "=" && parent.left === node) return false;
    if (!mayRequire(node.property)) return false;
  } else if ((node.type === "Identifier" ? node.name : memberName(node)) !== "require") {
    return false;
  }
  if (node.type === "Identifier") {
    const binding =
      (parent?.type === "MemberExpression" && parent.property === node && !parent.computed) ||
      ((parent?.type === "Property" || parent?.type === "MethodDefinition" || parent?.type === "PropertyDefinition") && parent.key === node && !parent.computed && !parent.shorthand) ||
      (parent?.type === "VariableDeclarator" && parent.id === node) ||
      (FUNCTIONS.has(parent?.type) && (parent.id === node || parent.params.includes(node))) ||
      ["ImportSpecifier", "ImportDefaultSpecifier", "ImportNamespaceSpecifier", "ExportSpecifier", "LabeledStatement", "BreakStatement", "ContinueStatement"].includes(parent?.type);
    if (binding) return false;
  }
  if (parent?.type === "CallExpression" && parent.callee === node) {
    return computed || (literalString(parent.arguments[0]) === null && paramSpecs(parent.arguments[0]) === null);
  }
  if (parent?.type === "UnaryExpression" && parent.operator === "typeof") return false;
  if (node.type === "MemberExpression" && !computed && onlyTested(parents, node)) return false;
  return !(parent?.type === "MemberExpression" && parent.object === node && memberName(parent) === "resolve");
}

// What a load's specifier `arg` can be when it is a parameter: for a plain
// parameter of a function declaration, never written, whose function is
// not exported and is only ever called directly with a literal string in
// its place, those strings; else null. protobufjs's `inquire(moduleName)`
// loads `moduleName`, and each caller names a package.
function paramSpecsOf(entry) {
  const parents = parentsOf(entry);
  return (arg) => {
    const v = arg?.type === "Identifier" ? entry.refs.get(arg.start)?.resolved : null;
    const def = v?.defs.length === 1 ? v.defs[0] : null;
    const fn = def?.type === "Parameter" ? def.node : null;
    if (fn?.type !== "FunctionDeclaration" || fn.id === null || v.references.some((r) => r.isWrite())) return null;
    const index = fn.params.indexOf(def.name);
    const callee = entry.decls.get(fn.id.start);
    const exported = ["ExportNamedDeclaration", "ExportDefaultDeclaration"].includes(parents.get(fn)?.type);
    if (index < 0 || callee?.defs.length !== 1 || exported) return null;
    const specs = [];
    for (const r of callee.references) {
      const call = parents.get(r.identifier);
      if (r.isWrite() || call?.type !== "CallExpression" || call.callee !== r.identifier) return null;
      if (call.arguments.slice(0, index + 1).some((a) => a.type === "SpreadElement")) return null;
      const spec = literalString(call.arguments[index]);
      if (spec === null) return null;
      specs.push(spec);
    }
    return specs;
  };
}

// Whether the value of `node` is only tested for truth, so it never
// leaves the expression: a `&&` operand other than the last, the test of
// an `if`, a loop or `?:`, or the operand of `!`. The last operand of a
// `&&` is what the whole `&&` may evaluate to.
function onlyTested(parents, node) {
  let value = node;
  let holder = parents.get(node);
  while (holder?.type === "LogicalExpression" && holder.operator === "&&" && holder.right === value) {
    value = holder;
    holder = parents.get(holder);
  }
  if (holder?.type === "LogicalExpression") return holder.operator === "&&" && holder.left === value;
  if (holder?.type === "UnaryExpression") return holder.operator === "!";
  return ["IfStatement", "WhileStatement", "DoWhileStatement", "ForStatement", "ConditionalExpression"].includes(holder?.type) && holder.test === value;
}

// Whether `node`, with parent `parent`, initializes a plain declarator with
// `import.meta.require` or `require` itself, which `aliasesOf` may find to
// be an exported alias.
const aliasInit = (node, parent) =>
  parent?.type === "VariableDeclarator" &&
  parent.init === node &&
  parent.id.type === "Identifier" &&
  ((node.type === "MemberExpression" && isImportMeta(node.object) && memberName(node) === "require") ||
    (node.type === "Identifier" && node.name === "require"));

// The module's aliases of the loader, as [variable, initializer, [exported
// names]]: each module-scope variable a plain declarator initializes with
// `import.meta.require` or a `require` no binding declares, never written
// again, and exported by name other than `default` (Bun's runtime chunk:
// `var Fe=import.meta.require;export{...,Fe}`). A module with a direct
// `eval` has none: eslint-scope resolves no reference there.
function aliasesOf(entry) {
  if (entry.evals) return [];
  const parents = parentsOf(entry);
  const out = [];
  for (const v of entry.top?.variables ?? []) {
    const def = v.defs.length === 1 ? v.defs[0] : null;
    const init = def?.type === "Variable" && def.node.id === def.name ? def.node.init : null;
    if (init === null || !aliasInit(init, def.node)) continue;
    if (init.type === "Identifier" && entry.refs.get(init.start)?.resolved) continue;
    if (v.references.some((r) => r.isWrite() && r.identifier !== def.name)) continue;
    const names = parents.get(def.parent)?.type === "ExportNamedDeclaration" ? [v.name] : [];
    for (const r of v.references) {
      const spec = parents.get(r.identifier);
      if (spec?.type === "ExportSpecifier" && spec.local === r.identifier) names.push(spec.exported.name ?? spec.exported.value);
    }
    if (names.length > 0 && !names.includes("default")) out.push([v, init, names]);
  }
  return out;
}

// The names a request's `loaders` lists: every name some module exports an
// alias under (`aliasesOf`), which the caller collects across the bundle.
const loaderNames = (req) => new Set(Array.isArray(req.loaders) ? req.loaders.filter((n) => typeof n === "string") : []);

// The named loaders the module holds, given `names` (`loaderNames`): each
// of its aliases exported only under those names, and each import of one
// of them by name. A call of one with a literal specifier loads that file.
//   -> {aliases: every name the module exports an alias under,
//       cleared: the initializers of the aliases that are named loaders,
//       uses: [[call, specifier]] for each call with a literal specifier and
//             [node, null] for any other use (a call with no literal, an
//             alias, an escape, a re-export), which may load any file}
function loaderUses(entry, names) {
  const parents = parentsOf(entry);
  const own = aliasesOf(entry);
  const cleared = new Set();
  const held = [];
  for (const [v, init, exported] of own) {
    if (!exported.every((n) => names.has(n))) continue;
    cleared.add(init);
    held.push(v);
  }
  const uses = [];
  for (const node of entry.ast.body) {
    if (node.type === "ImportDeclaration") {
      for (const spec of node.specifiers) {
        const v = spec.type === "ImportSpecifier" && names.has(spec.imported.name ?? spec.imported.value) ? entry.decls.get(spec.local.start) : null;
        if (v) held.push(v);
      }
    } else if (node.type === "ExportNamedDeclaration" && node.source) {
      for (const spec of node.specifiers) if (names.has(spec.local.name ?? spec.local.value)) uses.push([spec, null]);
    }
  }
  for (const v of held) {
    // Under a direct `eval` the import's references are unresolved, so any use may be unseen.
    if (entry.evals) {
      uses.push([v.defs[0].name, null]);
      continue;
    }
    // An alias's own declarator and its exports are how importers get it.
    const alias = v.defs[0].type === "Variable";
    for (const r of v.references) {
      const id = r.identifier;
      const parent = parents.get(id);
      if (alias && (id === v.defs[0].name || (parent?.type === "ExportSpecifier" && parent.local === id))) continue;
      const spec = parent?.type === "CallExpression" && parent.callee === id ? literalString(parent.arguments[0]) : null;
      uses.push(spec === null ? [id, null] : [parent, spec]);
    }
  }
  return { aliases: own.flatMap(([, , exported]) => exported), cleared, uses };
}

// `computed` is whether a computed key or a variable specifier may load a
// module, which takes the scope analysis to tell (`computedLoads`);
// `aliasInits` are the offsets of the `aliasInit` reads, which `loads`
// counts unless each is a named loader's (`loaderUses`).
function scanOf(ast) {
  const keys = new Set();
  const loads = new Set();
  const imports = [];
  const aliasInits = [];
  for (const node of ast.body) {
    if (node.type !== "ImportDeclaration" && !(node.type === "ExportNamedDeclaration" && node.source)) continue;
    for (const spec of node.specifiers) {
      const name = spec.type === "ImportSpecifier" ? spec.imported : spec.type === "ExportSpecifier" ? spec.local : null;
      if (name) imports.push([name.name ?? name.value, node.source.value]);
    }
  }
  let computed = false;
  const deferred = () => {
    computed = true;
    return new Set();
  };
  // A specifier that is a variable may be a parameter `paramSpecsOf` names.
  const deferredSpecs = (arg) => {
    if (arg?.type !== "Identifier") return null;
    computed = true;
    return [];
  };
  const parents = new Map();
  const stack = [ast];
  while (stack.length) {
    const node = stack.pop();
    const loaded = loadedFile(node);
    if (loaded !== null) loads.add(loaded);
    if (unknownLoad(node, parents, deferred, deferredSpecs)) {
      if (aliasInit(node, parents.get(node))) aliasInits.push(node.start);
      else loads.add(UNKNOWN_FILE);
    }
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
        if (c && typeof c.type === "string" && c !== node) {
          parents.set(c, node);
          stack.push(c);
        }
      }
    }
  }
  return { keys, loads, imports, computed, aliasInits };
}

// The files the loads `scanOf` deferred to the scope analysis load: each
// file a parameter's callers name (`paramSpecsOf`), and UNKNOWN_FILE when a
// computed key or a variable specifier may load a module the scan cannot
// name (`unknownLoad` with the key's provenance).
function computedLoads(entry) {
  const parents = parentsOf(entry);
  const keyValues = keyValuesOf(entry);
  const paramSpecs = paramSpecsOf(entry);
  const files = new Set();
  const stack = [entry.ast];
  while (stack.length) {
    const node = stack.pop();
    if (unknownLoad(node, parents, keyValues, paramSpecs) && !aliasInit(node, parents.get(node))) return new Set([UNKNOWN_FILE]);
    if (isRequire(node)) for (const spec of paramSpecs(node.arguments[0]) ?? []) files.add(fileName(spec));
    for (const key of Object.keys(node)) {
      const child = node[key];
      for (const c of Array.isArray(child) ? child : [child]) {
        if (c && typeof c.type === "string" && c !== node) stack.push(c);
      }
    }
  }
  return files;
}

// {"op":"keys_used","module":key,"source"?:...,"names":[...]}
//   -> {"used":[names the module reads as a property]}; a module that does
//      not parse uses every name.
function keysUsed(req) {
  if (typeof req.module !== "string" || !Array.isArray(req.names)) {
    return { ok: false, error: "keys_used needs a string `module` and a `names` list" };
  }
  const scan = scanFor(req);
  if (scan === undefined) return { ok: true, need_source: true };
  return { ok: true, used: req.names.filter((n) => scan === null || scan.keys.has(n)) };
}

// {"op":"loads","module":key,"source"?:...,"loaders"?:[...]}
//   -> {"files":[file names the module loads whole]} (`loadedFile`, a
//      named loader's call with a literal specifier, `loaderUses`, and each
//      literal the callers pass a parameter specifier, `paramSpecsOf`), with
//      "*" when it may load one the scan cannot name (`unknownLoad`, an
//      alias that is no named loader, any other use of one), and
//      "aliases", the names it exports an alias under (`aliasesOf`); or
//      {"files":null,"aliases":[]} for a module that does not parse.
function loads(req) {
  if (typeof req.module !== "string") return { ok: false, error: "loads needs a string `module`" };
  const scan = scanFor(req);
  if (scan === undefined) return { ok: true, need_source: true };
  if (scan === null) return { ok: true, files: null, aliases: [] };
  if (scan.computed && !scan.loads.has(UNKNOWN_FILE)) {
    const entry = moduleFor(req);
    if (entry === null) return { ok: true, need_source: true };
    for (const file of entry.error ? [UNKNOWN_FILE] : computedLoads(entry)) scan.loads.add(file);
    scan.computed = false;
  }
  const names = loaderNames(req);
  const files = new Set(scan.loads);
  let aliases = [];
  if (scan.aliasInits.length > 0 || scan.imports.some(([n]) => names.has(n))) {
    const entry = moduleFor(req);
    if (entry === null) return { ok: true, need_source: true };
    if (entry.error) return { ok: true, files: null, aliases: [] };
    const held = loaderUses(entry, names);
    aliases = held.aliases;
    const cleared = new Set([...held.cleared].map((n) => n.start));
    if (scan.aliasInits.some((at) => !cleared.has(at))) files.add(UNKNOWN_FILE);
    for (const [, spec] of held.uses) files.add(spec === null ? UNKNOWN_FILE : fileName(spec));
  }
  return { ok: true, files: [...files].sort(), aliases };
}

// {"op":"imports","module":key,"source"?:...}
//   -> {"names":[[name, from], ...]}: each name an import or re-export
//      declaration takes by name (`import{x}from f`, `export{x}from f`),
//      with the path `f`, or {"names":null} for a module that does not parse.
function importsOf(req) {
  if (typeof req.module !== "string") return { ok: false, error: "imports needs a string `module`" };
  const scan = scanFor(req);
  if (scan === undefined) return { ok: true, need_source: true };
  return { ok: true, names: scan === null ? null : scan.imports };
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
        if (typeof req.module === "string") {
          foldEvals(ast);
          scans.set(req.module, scanOrNull(ast));
        }
        return { ok: true, parsed: true };
      } catch (e) {
        if (typeof req.module === "string") scans.set(req.module, null);
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
    case "loads":
      return loads(req);
    case "namespace":
      return namespace(req);
    case "sinks":
      return sinks(req);
    case "fresh_args":
      return freshArgs(req);
    case "exports":
      return exportsOf(req);
    case "imports":
      return importsOf(req);
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
