"use strict";

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
const PATTERN_NODES = new Set(["ArrayPattern", "ObjectPattern", "AssignmentPattern", "RestElement", "Property"]);
const modules = new Map();

const REPLACE_TRUSTS = ["replace", "@@replace", "exec", "flags", "global", "unicode", "unicodeSets", "lastIndex"];
const FOLD_PATTERN_MAX = 32;
const FOLD_SUBJECT_MAX = 256;

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

function forEachChild(node, visit) {
  for (const key of Object.keys(node)) {
    const child = node[key];
    for (const c of Array.isArray(child) ? child : [child]) {
      if (c && typeof c.type === "string" && c !== node) visit(c);
    }
  }
}

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
    forEachChild(node, (c) => stack.push(c));
  }
  return trusts;
}

function analyze(source) {
  let ast;
  let manager;
  let folds;
  try {
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
  const globals = new Map();
  for (const ref of manager.globalScope.through) {
    const name = ref.identifier.name;
    if (!globals.has(name)) globals.set(name, { name, defs: [], references: [], scope: null });
    globals.get(name).references.push(ref);
  }
  const evals = manager.scopes.some((s) => s.directCallToEvalScope);
  return { ast, manager, top, refs, decls, globals, evals, folds, parents: null };
}

function parentsOf(entry) {
  if (entry.parents) return entry.parents;
  const parents = new Map();
  const stack = [entry.ast];
  while (stack.length) {
    const node = stack.pop();
    forEachChild(node, (c) => {
      parents.set(c, node);
      stack.push(c);
    });
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
  const decl = entry.decls.get(req.offset);
  if (decl?.name === req.name) return decl;
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
  let value = node;
  let holder = parent;
  while (forwards(holder, value)) {
    value = holder;
    holder = parents.get(holder);
  }
  if (isCallee(holder, value)) return "method-call";
  return valueOnly(holder, value) ? null : "member-escape";
}

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

const CALLBACK_SLOT = new Map([
  ...["some", "every", "forEach", "map", "filter", "find", "findIndex", "findLast", "findLastIndex", "flatMap"].map((m) => [m, 2]),
  ...["reduce", "reduceRight"].map((m) => [m, 3]),
  ...["includes", "indexOf", "lastIndexOf", "join", "slice", "at", "concat", "flat", "keys", "values", "entries", "toString"].map(
    (m) => [m, null],
  ),
]);
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

function exportNames(parents, v) {
  const def = v.defs[0];
  const holder = parents.get(def.type === "Variable" ? def.parent : def.node);
  const names = holder?.type === "ExportNamedDeclaration" ? [v.name] : holder?.type === "ExportDefaultDeclaration" ? ["default"] : [];
  for (const r of v.references) {
    const spec = parents.get(r.identifier);
    if (spec?.type === "ExportSpecifier" && spec.local === r.identifier) names.push(spec.exported.name ?? spec.exported.value);
  }
  return names;
}

function argumentsAliased(entry, fn) {
  if (fn.type === "ArrowFunctionExpression") return false;
  const scope = entry.manager.acquire(fn, true);
  return !scope || scope.set.get("arguments")?.references.length > 0;
}

function inBlock(parents, fn) {
  const holder = parents.get(fn);
  return fn.type === "FunctionDeclaration" && !["Program", "ExportNamedDeclaration"].includes(holder?.type) && !FUNCTIONS.has(parents.get(holder)?.type);
}

const uncallable = (value) => value === "undefined" || value === "uncallable";
const mayBeUndefined = (values) => values.some((v) => v === "undefined" || v.imported !== undefined);

class Flow {
  constructor(entry) {
    this.entry = entry;
    this.parents = parentsOf(entry);
    this.exits = [];
    this.seen = new Set();
    this.steps = 0;
    this.trusted = new Set();
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

  exportedName(v) {
    const def = v.defs[0];
    const decl = def?.type === "Variable" ? def.parent : def?.type === "FunctionName" || def?.type === "ClassName" ? def.node : null;
    const holder = decl && this.parents.get(decl);
    if (holder?.type === "ExportDefaultDeclaration") throw new Unresolved("a default export", decl.start);
    return holder?.type === "ExportNamedDeclaration" ? v.name : null;
  }

  variable(v) {
    if (!this.once(v)) return;
    const exported = this.exportedName(v);
    if (exported) this.exit("export", exported);
    for (const r of v.references) {
      if (r.isReadWrite()) throw new Unresolved("a compound assignment or update of the array", r.identifier.start);
      if (!r.isWrite()) this.value(r.identifier);
    }
  }

  value(node) {
    let parent = this.parents.get(node);
    while (forwards(parent, node)) {
      node = parent;
      parent = this.parents.get(node);
    }
    const at = node.start;
    switch (parent?.type) {
      case "SpreadElement": {
        const holder = this.parents.get(parent)?.type;
        if (holder === "ArrayExpression" || holder === "CallExpression" || holder === "NewExpression") {
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

  member(object, member) {
    const call = this.parents.get(member);
    const name = propertyName(member);
    if (call?.type === "CallExpression" && call.callee === member && name !== null) {
      if (CALLBACK_SLOT.has(name)) {
        this.trusted.add(name);
        if (name === "toString") this.trusted.add("join");
        if (SPECIES.has(name)) {
          this.trusted.add("constructor");
          this.trusted.add("@@species");
        }
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
    if (key === "length" || (/^(?:0|[1-9]\d*)$/.test(key) && Number(key) < this.own)) return;
    this.trusted.add(key);
  }

  argument(call, index) {
    if (call.arguments.slice(0, index + 1).some((a) => a.type === "SpreadElement")) {
      throw new Unresolved("a spread before the argument", call.start);
    }
    if (call.callee.type !== "Identifier") throw new Unresolved("a call through a member or expression", call.start);
    this.callback(call.callee, index);
  }

  callback(fn, index) {
    if (fn.type === "SpreadElement") throw new Unresolved("a spread callback", fn.start);
    for (const value of this.values(fn, new Map())) {
      if (uncallable(value)) continue;
      if (value.imported !== undefined) this.exit("param", value.imported, index, value.source);
      else this.parameter(value, index);
    }
  }

  parameter(fn, index) {
    if (!this.once(`${fn.start}:${index}`)) return;
    const params = fn.params;
    if (params.slice(0, index + 1).some((p) => p.type === "RestElement")) throw new Unresolved("a rest parameter", fn.start);
    if (argumentsAliased(this.entry, fn)) throw new Unresolved("a function that reads `arguments`", fn.start);
    const param = params[index];
    if (param === undefined) return;
    const id = param.type === "AssignmentPattern" ? param.left : param;
    if (id.type !== "Identifier") throw new Unresolved("a destructured parameter", param.start);
    this.variable(this.entry.decls.get(id.start));
  }

  returned(node) {
    let fn = this.parents.get(node);
    while (fn && !FUNCTIONS.has(fn.type)) fn = this.parents.get(fn);
    if (!fn || fn.async || fn.generator) throw new Unresolved("a return from an async, generator or unknown function", node.start);
    const v = this.binding(fn);
    if (!v) throw new Unresolved("a return from a function bound to no plain name", fn.start);
    this.calls(v);
  }

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

  parameterValues(fn, id, seen) {
    const index = fn.params.findIndex((p) => id.start >= p.start && id.end <= p.end);
    let param = fn.params[index];
    if (index < 0 || fn.params.slice(0, index).some((p) => p.type === "RestElement")) {
      throw new Unresolved("a parameter after a rest parameter", id.start);
    }
    const fallback = param.type === "AssignmentPattern" ? param.right : null;
    if (fallback) param = param.left;
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
      if (arg.properties.some((p) => !p.shorthand && keyName(p.key, false) === "__proto__")) {
        throw new Unresolved("an object literal setting its prototype", arg.start);
      }
      const matching = arg.properties.filter((p) => String(p.key.name ?? p.key.value) === key);
      if (matching.some((p) => p.kind !== "init")) throw new Unresolved(`an accessor for \`${key}\``, arg.start);
      const prop = matching.at(-1);
      if (prop) {
        const values = this.values(prop.value, seen);
        out.push(...values.filter((value) => value !== "undefined"));
        if (!mayBeUndefined(values)) return;
        if (!keyDefault) return out.push("undefined");
      } else if (!keyDefault) {
        throw new Unresolved(`an argument without \`${key}\``, arg.start);
      } else {
        this.trusted.add(key);
      }
      out.push(...this.values(keyDefault, seen));
    };
    for (const r of v.references) {
      if (r.isWrite()) continue;
      const call = this.parents.get(r.identifier);
      if (call?.type !== "CallExpression" || call.callee !== r.identifier) {
        throw new Unresolved("the parameter's function is used other than by a call", r.identifier.start);
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
    if (e instanceof RangeError) return { ok: true, safe: false, reason: "the flow is too deep to follow", at: null };
    if (!(e instanceof Unresolved)) throw e;
    return { ok: true, safe: false, reason: e.message, at: e.at };
  }
  return { ok: true, safe: true, exits: walk.exits, trusted: [...new Set([...walk.trusted, ...entry.folds])].sort() };
}

const fileName = (spec) => spec.split("/").at(-1);
const UNKNOWN_FILE = "*";

const literalString = (n) =>
  n?.type === "Literal" && typeof n.value === "string"
    ? n.value
    : n?.type === "TemplateLiteral" && n.expressions.length === 0
      ? n.quasis[0].value.cooked
      : null;

const isRequire = (n) =>
  n?.type === "CallExpression" && (n.callee.type === "Identifier" ? n.callee.name === "require" : memberName(n.callee) === "require");

function loadedFile(node) {
  let spec = null;
  if (node.type === "ImportExpression") spec = literalString(node.source);
  else if (isRequire(node)) spec = literalString(node.arguments[0]);
  else if (node.type === "ImportDeclaration" && node.specifiers.some((s) => s.type === "ImportNamespaceSpecifier")) spec = node.source.value;
  else if (node.type === "ExportAllDeclaration") spec = node.source.value;
  return spec === null ? null : fileName(spec);
}

const isImportMeta = (n) => n?.type === "MetaProperty" && n.meta.name === "import";

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
      forEachChild(node, (c) => stack.push(c));
    }
    this.metaChecked = true;
  }

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

  byName(member) {
    const key = memberName(member);
    if (key === null) throw new Unresolved("a computed read of the namespace", member.start);
    if (key === this.name) throw new Unresolved(`a read of \`${key}\``, member.start);
    this.readOnly(member, "the namespace");
  }

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
      if (use?.type === "LogicalExpression" && use.operator === "&&" && use.left === r.identifier) continue;
      if (use?.type === "ConditionalExpression" && use.test === r.identifier) continue;
      if ((use?.type === "IfStatement" || use?.type === "WhileStatement") && use.test === r.identifier) continue;
      if (use?.type === "UnaryExpression" && ["typeof", "void", "!"].includes(use.operator)) continue;
      throw new Unresolved(`the record reaches a ${use?.type ?? "module end"}`, r.identifier.start);
    }
  }

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
      if (isRequire(node) && paramSpecs(node.arguments[0])?.some((s) => fileName(s) === req.file)) {
        return { ok: true, safe: false, reason: "a parameter's caller names the file", at: node.start };
      }
      if ((named.get(node) ?? loadedFile(node)) === req.file) {
        sites++;
        walk.site(node);
      }
      forEachChild(node, (c) => stack.push(c));
    }
  } catch (e) {
    if (e instanceof RangeError) return { ok: true, safe: false, reason: "the namespace is too deep to follow", at: null };
    if (!(e instanceof Unresolved)) throw e;
    return { ok: true, safe: false, reason: e.message, at: e.at };
  }
  return { ok: true, safe: true, sites, trusted: [...new Set([...walk.trusted, ...entry.folds])].sort(), thenable: walk.thenable };
}

function keyName(key, computed) {
  if (!computed) return key.name ?? String(key.value);
  if (key.type === "Literal") return String(key.value);
  if (key.type === "TemplateLiteral" && key.expressions.length === 0) return key.quasis[0].value.cooked;
  if (key.type === "MemberExpression" && !key.computed && key.object.type === "Identifier" && key.object.name === "Symbol") {
    return `@@${key.property.name}`;
  }
  return null;
}

const ownProto = (p) =>
  p.type === "Property" && keyName(p.key, p.computed) === "__proto__" && (p.computed || p.shorthand || p.method || p.kind !== "init");

const SINK_LIMIT = 20;
const NUMBER = Symbol("number");
const ARITHMETIC = new Set(["-", "*", "/", "%", "**", "|", "&", "^", "<<", ">>", ">>>"]);
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

function loadedSpecifier(node) {
  if (node.type === "ImportExpression") return literalString(node.source);
  if (isRequire(node)) return literalString(node.arguments[0]);
  if (node.type === "ImportDeclaration" || node.type === "ExportAllDeclaration" || node.type === "ExportNamedDeclaration") {
    return node.source?.value ?? null;
  }
  return null;
}

const TYPEOF = ["undefined", "object", "boolean", "number", "bigint", "string", "symbol", "function"];

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

const NUMERIC_KEY = /^(?:-?(?:\d|Infinity$)|NaN$)/;
const NUMERIC_HEAD = /^(?:[-\d]|Infinity|NaN)/;
const NUMERIC_TAIL = /(?:\d|Infinity|NaN)$/;
const SPELL_STEPS = 512;

const strictCode = (ast) =>
  ast.body[0]?.directive === "use strict" || ast.body.some((s) => s.type === "ImportDeclaration" || s.type.startsWith("Export"));

function keySpellsOf(entry, keyValues) {
  const parents = parentsOf(entry);
  const seen = new Set();
  const known = new Map();
  let steps = 0;
  const valuesOf = (node) => {
    if (!known.has(node)) known.set(node, keyValues(node));
    return known.get(node);
  };
  const exact = (values, name) => values.has(name) || (values.has(NUMBER) && NUMERIC_KEY.test(name));
  const affix = (side, name, head) => {
    const values = valuesOf(side);
    if (values === null) return true;
    const numeric = head ? NUMERIC_HEAD : NUMERIC_TAIL;
    return [...values].some((v) => (v === NUMBER ? numeric.test(name) : head ? name.startsWith(v) : name.endsWith(v)));
  };
  const written = (v, name, next) => {
    const def = v.defs[0];
    if (def.type !== "Variable" || def.node.id !== def.name || isLoop(parents.get(def.parent))) return true;
    if ((def.parent.kind === "var" || def.node.init === null) && name === "undefined") return true;
    return v.references.some((r) => {
      if (!r.isWrite()) return false;
      if (r.identifier === def.name) return def.node.init !== null && next(def.node.init);
      const w = parents.get(r.identifier);
      if (w?.type === "UpdateExpression") return NUMERIC_KEY.test(name);
      return w?.type !== "AssignmentExpression" || w.left !== r.identifier || next(w);
    });
  };
  const passed = (v, name, next) => {
    const def = v.defs[0];
    const fn = def.node;
    const index = fn.params.indexOf(def.name);
    if (index < 0 || v.references.some((r) => r.isWrite()) || inBlock(parents, fn) || argumentsAliased(entry, fn)) return true;
    const callee = functionBinding(entry, parents, fn);
    if (!callee || exportNames(parents, callee).length > 0) return true;
    return callee.references.some((r) => {
      if (r.isWrite()) return false;
      const call = parents.get(r.identifier);
      if (call?.type !== "CallExpression" || call.callee !== r.identifier) return true;
      if (call.arguments.slice(0, index + 1).some((a) => a.type === "SpreadElement")) return true;
      const arg = call.arguments[index];
      return arg === undefined ? name === "undefined" : next(arg);
    });
  };
  const walk = (node, name, depth) => {
    const values = valuesOf(node);
    if (values !== null) return exact(values, name);
    if (++steps > SPELL_STEPS || depth > 16) return true;
    const next = (n) => walk(n, name, depth + 1);
    switch (node.type) {
      case "BinaryExpression":
        return node.operator !== "+" || NUMERIC_KEY.test(name) || (affix(node.left, name, true) && affix(node.right, name, false));
      case "TemplateLiteral": {
        const texts = node.quasis.map((q) => q.value.cooked);
        return texts.some((t) => typeof t !== "string") || (name.startsWith(texts[0]) && name.endsWith(texts.at(-1)));
      }
      case "ConditionalExpression":
        return next(node.consequent) || next(node.alternate);
      case "LogicalExpression":
        return next(node.left) || next(node.right);
      case "SequenceExpression":
        return next(node.expressions.at(-1));
      case "AssignmentExpression":
        if (node.operator === "=") return next(node.right);
        return node.operator !== "+=" || NUMERIC_KEY.test(name) || affix(node.right, name, false);
      case "Identifier": {
        const v = entry.refs.get(node.start)?.resolved;
        if (!v || v.defs.length !== 1) return true;
        if (seen.has(v)) return false;
        seen.add(v);
        try {
          return v.defs[0].type === "Parameter" ? passed(v, name, next) : written(v, name, next);
        } finally {
          seen.delete(v);
        }
      }
    }
    return true;
  };
  const bounded = !entry.evals && strictCode(entry.ast);
  return (node, name) => {
    if (!bounded) {
      const values = valuesOf(node);
      return values === null || exact(values, name);
    }
    steps = 0;
    return walk(node, name, 0);
  };
}

const isDefinerHome = (n) =>
  (n?.type === "Identifier" && (n.name === "Object" || n.name === "Reflect")) ||
  (n?.type === "MemberExpression" && ["Object", "Reflect"].includes(memberName(n)));

const homeName = (n) => (n.type === "Identifier" ? n.name : memberName(n));

function definerOf(n) {
  const name = memberName(n);
  if (name === "__defineGetter__" || name === "__defineSetter__") return { name, receiver: true, keyed: false };
  if (n?.type !== "MemberExpression" || !isDefinerHome(n.object)) return null;
  return definerNamed(homeName(n.object), name);
}

function definerNamed(home, name) {
  if (home === "Object" && ["defineProperty", "defineProperties", "assign", "setPrototypeOf"].includes(name)) {
    return { name, receiver: false, keyed: name === "defineProperty" };
  }
  if (home === "Reflect" && ["defineProperty", "set", "setPrototypeOf"].includes(name)) {
    return { name, receiver: false, keyed: name !== "setPrototypeOf" };
  }
  return null;
}

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

const FRESH = { needs: new Set(), trusts: new Set() };
const both = (a, b) => a && b && { needs: new Set([...a.needs, ...b.needs]), trusts: new Set([...a.trusts, ...b.trusts]) };
const trusting = (f, ...names) => both(f, { needs: new Set(), trusts: new Set(names) });
const freshReply = (f) => ({ needs: [...f.needs].sort().map((n) => JSON.parse(n)), trusted: [...f.trusts].sort() });
const RETURNS_TARGET = new Set(["defineProperty", "defineProperties", "assign", "setPrototypeOf"]);
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

const onlyInit = (v) => v.references.every((r) => !r.isWrite() || r.identifier === v.defs[0].name);

function freshnessOf(entry) {
  const parents = parentsOf(entry);
  const variable = (id) => entry.refs.get(id.start)?.resolved ?? null;
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
  const builtinNamed = (node) =>
    node?.type === "Identifier" && BUILTIN_CONSTRUCTORS.has(node.name) && entry.refs.get(node.start)?.resolved === null ? node.name : null;
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
  const unswapped = (cls) => {
    const holder = parents.get(cls);
    const declarator = holder?.type === "VariableDeclarator" && holder.init === cls && holder.id.type === "Identifier" ? holder : null;
    if (cls.type !== "ClassDeclaration" && declarator === null) return false;
    const vars = [...entry.manager.getDeclaredVariables(cls), ...(declarator ? entry.manager.getDeclaredVariables(declarator) : [])];
    return vars.every((v) => v.defs.length === 1 && v.references.every((r) => (r.isWrite() ? r.identifier === v.defs[0].name : classUse(r.identifier))));
  };
  const extendsBuiltin = (cls) => {
    const name = builtinNamed(cls.superClass);
    return name !== null && unswapped(cls) ? trusting(FRESH, name) : null;
  };
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
      forEachChild(node, (c) => stack.push(c));
    }
    return made;
  };
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
    const later = (r) => r.identifier === id || (!r.isWrite() && r.from.variableScope === v.scope.variableScope && r.identifier.start >= set.end);
    const param = v.defs[0].type === "Parameter";
    return v.references.every(later) && !(param && argumentsAliased(entry, block)) ? set : null;
  };
  const passed = new Map();
  const passedTo = (fn, index, depth) => {
    const key = `${fn.start}:${index}`;
    if (passed.has(key)) return passed.get(key);
    passed.set(key, null);
    const v = inBlock(parents, fn) || argumentsAliased(entry, fn) ? null : functionBinding(entry, parents, fn);
    const names = v && exportNames(parents, v);
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
  const boundThis = (fn, depth) => {
    if (bound.has(fn)) return bound.get(fn);
    bound.set(fn, null);
    const v = inBlock(parents, fn) ? null : functionBinding(entry, parents, fn);
    let out = v && exportNames(parents, v).length === 0 ? trusting(FRESH, "bind") : null;
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
      case "NewExpression": {
        const name = builtinNamed(node.callee);
        return name !== null ? trusting(FRESH, name) : ownClass(node.callee);
      }
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
          if (fn.type === "PropertyDefinition" || fn.type === "StaticBlock") return null;
          fn = parents.get(fn);
        }
        const holder = fn && parents.get(fn);
        if (holder?.type !== "MethodDefinition") return fn ? boundThis(fn, depth) : null;
        if (holder.kind !== "constructor") return null;
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

function sinks(req) {
  if (typeof req.module !== "string" || !Array.isArray(req.names)) {
    return { ok: false, error: "sinks needs a string `module` and a `names` list" };
  }
  const entry = moduleFor(req);
  if (entry === null) return { ok: true, need_source: true };
  return { ok: true, ...sinkHits(entry, new Set([...req.names, "Function"]), 0, loaderNames(req)) };
}

const FOLD_DEPTH = 4;

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
  const fresh = freshnessOf(entry);
  const pending = [];
  const trusted = new Set(entry.folds);
  const paramSpecs = depth === 0 ? paramSpecsOf(entry) : () => null;
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
  const definerAt = (callee) => {
    if (callee.type !== "Identifier") return definerOf(callee);
    const def = variable(callee)?.defs[0];
    const prop = def?.type === "Variable" ? parents.get(def.name) : null;
    if (prop?.type !== "Property" || prop.value !== def.name || parents.get(prop) !== def.node.id || !isDefinerHome(def.node.init)) return null;
    return definerNamed(homeName(def.node.init), keyName(prop.key, prop.computed));
  };
  const onlyCalled = (d) =>
    d.id.properties.every((p) => {
      if (p.type !== "Property" || p.computed) return false;
      const key = keyName(p.key, false);
      if (definerNamed(homeName(d.init), key) === null) return INERT_STATICS.has(key);
      const v = p.value.type === "Identifier" ? entry.decls.get(p.value.start) : null;
      const called = (r) => parents.get(r.identifier)?.type === "CallExpression" && parents.get(r.identifier).callee === r.identifier;
      return v?.defs.length === 1 && onlyInit(v) && v.references.every((r) => r.isWrite() || called(r));
    });
  for (const ref of entry.manager.globalScope.through) {
    if (ref.isWrite() && names.has(ref.identifier.name)) hit("global-write", ref.identifier.name, ref.identifier);
  }
  const keyValues = keyValuesOf(entry);
  const spells = keySpellsOf(entry, keyValues);
  const keyNames = (key) => {
    if (spells(key, "__proto__")) return null;
    const values = keyValues(key);
    if (values === null) return [...names].filter((n) => spells(key, n));
    if (values.has(NUMBER) && numericName) return null;
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
  const prototypeOnly = (node) => {
    let top = parents.get(node);
    if (memberName(top) !== "prototype" || top.object !== node || isTarget(parents, top)) return false;
    for (;;) {
      const up = parents.get(top);
      if (up?.type === "MemberExpression" && up.object === top) {
        const key = keyName(up.property, up.computed);
        if (key === null ? spells(up.property, "constructor") : key === "constructor") return false;
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
  const discarded = (n) => {
    const p = parents.get(n);
    if (p?.type === "ExpressionStatement") return true;
    if (p?.type === "SequenceExpression") return p.expressions.at(-1) !== n || discarded(p);
    if (p?.type === "ConditionalExpression") return p.test !== n && discarded(p);
    if (p?.type === "LogicalExpression") return p.right === n && discarded(p);
    return p?.type === "ChainExpression" && discarded(p);
  };
  const maySpellConstructor = (key, computed) => {
    const name = keyName(key, computed);
    return name === null ? spells(key, "constructor") : name === "constructor";
  };
  const maySpellAnywhereSink = (key, computed) =>
    keyName(key, computed) === null &&
    ["eval", "Function", ...VM_RUNNERS, "__defineGetter__", "__defineSetter__"].some((name) => spells(key, name));
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
        const builtin = key === "Function" || key === "Object" || BUILTIN_CONSTRUCTORS.has(key);
        if (key !== null && names.has(key) && (!builtin || definer !== null)) found.push(["argument", key, arg]);
      }
      if (definer === null) {
        for (const [kind, name, at] of found) hit(kind, name, at);
      } else {
        if (definer.name === "setPrototypeOf") found.push(["proto-swap", null, node]);
        if (node.arguments.some((a) => a.type === "SpreadElement")) found.push(["computed-define", null, node]);
        const keyArg = definer.receiver ? node.arguments[0] : definer.keyed ? node.arguments[1] : null;
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
        const receiver = definer.name === "set" && !definer.receiver ? node.arguments[3] : undefined;
        unlessFresh(found, receiver === undefined ? [target] : [target, receiver]);
      }
    }
    const holder = parents.get(node);
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
    const member = memberName(node);
    if ((member === "eval" || member === "Function") && !isTarget(parents, node)) {
      hit(member === "eval" ? "indirect-eval" : "function-constructor", null, node);
    }
    const overwritten = isTarget(parents, node) && !(holder?.type === "AssignmentExpression" && holder.operator !== "=");
    const constructorRead =
      (node.type === "MemberExpression" &&
        !overwritten &&
        maySpellConstructor(node.property, node.computed) &&
        (!constructorInert(node) || maySpellAnywhereSink(node.property, node.computed))) ||
      (node.type === "Property" && holder?.type === "ObjectPattern" && maySpellConstructor(node.key, node.computed));
    if (constructorRead) hit("function-constructor", null, node);
    if (node.type === "MemberExpression" && node.computed && member === null && !isTarget(parents, node) && !maySpellConstructor(node.property, true)) {
      const may = (name) => spells(node.property, name);
      if (may("eval")) hit("indirect-eval", null, node);
      else if (may("Function")) hit("function-constructor", null, node);
      else if ([...VM_RUNNERS].some(may)) hit("vm-string-code", null, node);
      else if (may("__defineGetter__") || may("__defineSetter__")) hit("definer-escape", null, node);
    }
    if (node.type === "Property" && holder?.type === "ObjectPattern" && !maySpellConstructor(node.key, node.computed)) {
      const name = keyName(node.key, node.computed);
      const may = (n) => (name === null ? spells(node.key, n) : name === n);
      if (may("eval")) hit("indirect-eval", null, node);
      else if (may("Function")) hit("function-constructor", null, node);
      else if (name === null && [...VM_RUNNERS].some(may)) hit("vm-string-code", null, node);
      else if (name === null && (may("__defineGetter__") || may("__defineSetter__"))) hit("definer-escape", null, node);
    }
    if ((VM_RUNNERS.has(member) && !isTarget(parents, node)) || (node.type === "Property" && holder?.type === "ObjectPattern" && VM_RUNNERS.has(keyName(node.key, node.computed)))) {
      hit("vm-string-code", null, node);
    }
    const specs = (isRequire(node) ? paramSpecs(node.arguments[0]) : null) ?? [loadedSpecifier(node)];
    if (specs.some((s) => VM_SPECIFIERS.has(s))) {
      const harmless =
        node.type === "ImportDeclaration" &&
        node.specifiers.every((s) => s.type === "ImportSpecifier" && VM_HARMLESS.has(s.imported.name ?? s.imported.value));
      if (!harmless) hit("vm-string-code", null, node);
    }
    const unseen = depth > 0 && loadedFile(node) !== null;
    if (unseen || (unknownLoad(node, parents, spells, paramSpecs) && !held.cleared.has(node))) hit("unknown-load", null, node);
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
    forEachChild(node, (c) => stack.push(c));
  }
  return { hits, pending, trusted: [...trusted].sort() };
}

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

function exportsOf(req) {
  if (typeof req.module !== "string") return { ok: false, error: "exports needs a string `module`" };
  const entry = moduleFor(req);
  if (entry === null) return { ok: true, need_source: true };
  if (entry.error) return { ok: true, error: entry.error };
  const names = [];
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

const scans = new Map();
const memberName = (n) => (n?.type === "MemberExpression" ? keyName(n.property, n.computed) : null);

function scanOrNull(ast) {
  try {
    return scanOf(ast);
  } catch {
    return null;
  }
}

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

function unknownLoad(node, parents, spells, paramSpecs = () => null) {
  const parent = parents.get(node);
  if (node.type === "ImportExpression") return literalString(node.source) === null;
  if (isImportMeta(node)) return !(parent?.type === "MemberExpression" && parent.object === node && memberName(parent) !== null);
  const mayRequire = (key) => spells(key, "require");
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

const aliasInit = (node, parent) =>
  parent?.type === "VariableDeclarator" &&
  parent.init === node &&
  parent.id.type === "Identifier" &&
  ((node.type === "MemberExpression" && isImportMeta(node.object) && memberName(node) === "require") ||
    (node.type === "Identifier" && node.name === "require"));

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

const loaderNames = (req) => new Set(Array.isArray(req.loaders) ? req.loaders.filter((n) => typeof n === "string") : []);

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
    if (entry.evals) {
      uses.push([v.defs[0].name, null]);
      continue;
    }
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
    return false;
  };
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
        const key = prop.computed ? keyName(prop.key, true) : (prop.key.name ?? String(prop.key.value));
        if (key !== null) keys.add(key);
      }
    }
    forEachChild(node, (c) => {
      parents.set(c, node);
      stack.push(c);
    });
  }
  return { keys, loads, imports, computed, aliasInits };
}

function computedLoads(entry) {
  const parents = parentsOf(entry);
  const spells = keySpellsOf(entry, keyValuesOf(entry));
  const paramSpecs = paramSpecsOf(entry);
  const files = new Set();
  const stack = [entry.ast];
  while (stack.length) {
    const node = stack.pop();
    if (unknownLoad(node, parents, spells, paramSpecs) && !aliasInit(node, parents.get(node))) return new Set([UNKNOWN_FILE]);
    if (isRequire(node)) for (const spec of paramSpecs(node.arguments[0]) ?? []) files.add(fileName(spec));
    forEachChild(node, (c) => stack.push(c));
  }
  return files;
}

function keysUsed(req) {
  if (typeof req.module !== "string" || !Array.isArray(req.names)) {
    return { ok: false, error: "keys_used needs a string `module` and a `names` list" };
  }
  const scan = scanFor(req);
  if (scan === undefined) return { ok: true, need_source: true };
  return { ok: true, used: req.names.filter((n) => scan === null || scan.keys.has(n)) };
}

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
