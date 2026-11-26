// GENERATED from lib/setup-apply.mjs by scripts/sync-shared-copies.sh. Do not edit this copy:
// edit the canonical source, then rerun the script.
import { spawnSync } from "node:child_process";
import {
  closeSync,
  constants,
  lstatSync,
  mkdirSync,
  openSync,
  readFileSync,
  realpathSync,
  renameSync,
  rmSync,
  writeSync,
} from "node:fs";
import { homedir } from "node:os";
import { dirname, join, sep } from "node:path";
import { fileURLToPath } from "node:url";
import { parse, YamlSubsetError } from "./yaml-subset.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const DEFAULT_HOME = "docs/conventions";
const REGION_BEGIN = "<!-- BEGIN GENERATED: convention-home -->";
const REGION_END = "<!-- END GENERATED: convention-home -->";
const INDEX_NAME = "conventions-index.md";
const INSTRUCTION_FILES = ["AGENTS.md", "CLAUDE.md"];

class Refusal extends Error {
  constructor(message, code = 1) {
    super(message);
    this.code = code;
  }
}
const why = (e) => e?.code ?? e?.message ?? String(e);
const printable = (s) =>
  [...String(s)]
    .map((c) => {
      const n = c.codePointAt(0);
      return (n < 0x20 && c !== "\n") || (n >= 0x7f && n <= 0x9f) ? `\\x${n.toString(16).padStart(2, "0")}` : c;
    })
    .join("");
const refuse = (message, code = 1) => {
  throw new Refusal(message, code);
};

function lstatOrNull(p, what = p) {
  try {
    return lstatSync(p);
  } catch (e) {
    if (e.code === "ENOENT") return null;
    refuse(`${what}: ${why(e)}; nothing written`);
  }
}
function real(p, what = p) {
  try {
    return realpathSync(p);
  } catch (e) {
    refuse(`${what}: could not resolve it (${why(e)}); nothing written`);
  }
}

function parseArgs(argv, withRef, withDefault) {
  const opts = { root: "", yes: false, check: false, state: false, ref: null, home: null, decline: false, pairs: [], defaults: [] };
  const usage = `usage: setup-apply.mjs [--root <dir>] [--yes] [--home <dir>]${withDefault ? " [--default <key>] ..." : ""} <key>=<value> ... | --decline | --state | --check${withRef ? " [--ref <ref>]" : ""}`;
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--root") {
      if (i + 1 >= argv.length) refuse("--root needs a directory", 2);
      opts.root = argv[++i];
    } else if (withDefault && a === "--default") {
      if (i + 1 >= argv.length) refuse("--default needs a key", 2);
      opts.defaults.push(argv[++i]);
    } else if (a === "--home") {
      if (i + 1 >= argv.length) refuse("--home needs a repo-relative directory", 2);
      opts.home = argv[++i];
    } else if (a === "--decline") opts.decline = true;
    else if (withRef && a === "--ref") {
      if (i + 1 >= argv.length) refuse("--ref needs a commit id or origin/<name>", 2);
      opts.ref = argv[++i];
    } else if (a === "--yes") opts.yes = true;
    else if (a === "--check") opts.check = true;
    else if (a === "--state") opts.state = true;
    else if (/^[^=-][^=]*=/.test(a)) opts.pairs.push(a);
    else refuse(`unexpected argument: ${a}; ${usage}`, 2);
  }
  if (opts.check && opts.pairs.length) refuse("--check takes no <key>=<value> arguments", 2);
  if (opts.check && opts.defaults.length) refuse("--check takes no --default arguments", 2);
  if (opts.decline && (opts.check || opts.pairs.length || opts.defaults.length || opts.home !== null)) {
    refuse("--decline takes no <key>=<value> arguments, --default, --home or --check", 2);
  }
  if (opts.home !== null && opts.check) refuse("--home is a write option; --check reads the bound home", 2);
  if (opts.ref !== null && !opts.check) refuse("--ref is a --check option; a write always targets the working tree", 2);
  const r = opts.ref;
  if (r !== null && !(/^[0-9a-f]{40}$/.test(r) || (/^origin\/[A-Za-z0-9._/-]+$/.test(r) && !r.includes("..") && !r.startsWith("origin/-")))) {
    refuse(`invalid --ref ${JSON.stringify(r)}; expected a 40-hex commit id or origin/<name>`, 2);
  }
  if (opts.state && (opts.yes || opts.check || opts.decline || opts.ref !== null || opts.home !== null || opts.pairs.length || opts.defaults.length)) {
    refuse("--state takes only --root; it writes nothing", 2);
  }
  return opts;
}

const isObject = (spec) => spec.type === "object";
const isCollection = (spec) => spec.type === "object" || spec.type === "array";
const isNull = (raw) => /^(null|Null|NULL|~)$/.test(raw);
const plainNonString = (raw) =>
  isNull(raw) ||
  /^(true|True|TRUE|false|False|FALSE|[-+]?(\.[0-9]+|[0-9]+(\.[0-9]*)?)([eE][-+]?[0-9]+)?|0x[0-9a-fA-F]+|0o[0-7]+|[-+]?\.(inf|Inf|INF)|\.(nan|NaN|NAN))$/.test(raw);
const compiled = new WeakMap();
function patternOf(spec) {
  if (!compiled.has(spec)) {
    let re = null;
    try {
      re = new RegExp(spec.pattern, "u");
    } catch {
    }
    compiled.set(spec, re);
  }
  return compiled.get(spec);
}
const badPattern = (spec) => spec.type === "string" && !Array.isArray(spec.enum) && spec.pattern !== undefined && !patternOf(spec);
function allowedText(spec) {
  if (badPattern(spec)) return null;
  if (Array.isArray(spec.enum)) return `one of ${spec.enum.join(", ")}`;
  if (spec.type === "boolean") return "one of true, false";
  if (spec.type === "integer") {
    const min = spec.minimum ?? 0;
    return spec.maximum === undefined ? `a whole number of at least ${min}` : `a whole number from ${min} to ${spec.maximum}`;
  }
  if (spec.type === "string") {
    const rules = [];
    if (spec.minLength) rules.push(`at least ${spec.minLength} character${spec.minLength === 1 ? "" : "s"}`);
    if (spec.maxLength !== undefined) rules.push(`at most ${spec.maxLength} characters`);
    if (spec.pattern !== undefined) rules.push(`matching ${spec.pattern}`);
    return rules.length ? `a string of ${rules.join(", ")}` : "a string";
  }
  if (isObject(spec)) return "a block map";
  if (spec.type === "array" && checksData(spec)) {
    const item = spec.items === undefined ? null : spec.items.type === "object" ? "maps" : allowedText(spec.items);
    return item ? `a block list of ${item}` : "a block list";
  }
  return null;
}

const DATA_KEYWORDS = new Set([
  "type", "items", "properties", "additionalProperties", "required", "enum", "pattern",
  "minLength", "maxLength", "minimum", "maximum", "minItems", "maxItems", "minProperties", "propertyNames",
]);
const ANNOTATIONS = new Set(["description", "default", "title", "examples", "$comment", "markdownDescription", "deprecated"]);
const DATA_TYPES = new Set(["string", "integer", "number", "boolean", "object", "array", "null"]);
const plainMap = (v) => v !== null && typeof v === "object" && !Array.isArray(v);
export function checksData(spec) {
  if (typeof spec === "boolean") return true;
  if (!plainMap(spec)) return false;
  if (spec.type !== undefined && !DATA_TYPES.has(spec.type)) return false;
  for (const [k, v] of Object.entries(spec)) {
    if (ANNOTATIONS.has(k)) continue;
    if (!DATA_KEYWORDS.has(k)) return false;
    if ((k === "items" || k === "propertyNames" || k === "additionalProperties") && !checksData(v)) return false;
    if (k === "properties" && !(plainMap(v) && Object.values(v).every(checksData))) return false;
    if (k === "pattern" && (typeof v !== "string" || patternOf(spec) === null)) return false;
  }
  return true;
}
const dataType = (v) =>
  v === null ? "null" : Array.isArray(v) ? "a list" : plainMap(v) ? "a map" : Number.isInteger(v) ? "a whole number" : typeof v === "number" ? "a number" : `a ${typeof v}`;
const fitsType = (type, v) =>
  type === "null" ? v === null
  : type === "array" ? Array.isArray(v)
  : type === "object" ? plainMap(v)
  : type === "integer" ? Number.isInteger(v)
  : typeof v === type;
const TYPE_WORDS = { string: "a string", integer: "a whole number", number: "a number", boolean: "true or false", object: "a map", array: "a list", null: "null" };
export function validateData(spec, value, path) {
  const out = [];
  const walk = (s, v, p) => {
    if (s === true) return;
    if (s === false) return void out.push(`${p} is not in the schema`);
    if (s.type !== undefined && !fitsType(s.type, v)) return void out.push(`${p} is ${dataType(v)}; it takes ${TYPE_WORDS[s.type]}`);
    if (Array.isArray(s.enum) && !s.enum.includes(v)) return void out.push(`${p}=${JSON.stringify(v)} is not one of ${s.enum.join(", ")}`);
    if (typeof v === "string") {
      const length = [...v].length;
      if (length < (s.minLength ?? 0)) out.push(`${p} is shorter than ${s.minLength} character${s.minLength === 1 ? "" : "s"}`);
      if (s.maxLength !== undefined && length > s.maxLength) out.push(`${p} is longer than ${s.maxLength} characters`);
      if (s.pattern !== undefined && patternOf(s)?.test(v) !== true) out.push(`${p}=${JSON.stringify(v)} does not match ${s.pattern}`);
    } else if (typeof v === "number") {
      if (s.minimum !== undefined && v < s.minimum) out.push(`${p}=${v} is below ${s.minimum}`);
      if (s.maximum !== undefined && v > s.maximum) out.push(`${p}=${v} is above ${s.maximum}`);
    } else if (Array.isArray(v)) {
      if (v.length < (s.minItems ?? 0)) out.push(`${p} holds ${v.length} item${v.length === 1 ? "" : "s"}; it takes at least ${s.minItems}`);
      if (s.maxItems !== undefined && v.length > s.maxItems) out.push(`${p} holds ${v.length} items; it takes at most ${s.maxItems}`);
      if (s.items !== undefined) v.forEach((item, i) => walk(s.items, item, `${p}.${i}`));
    } else if (plainMap(v)) {
      const keys = Object.keys(v);
      if (keys.length < (s.minProperties ?? 0)) out.push(`${p} holds ${keys.length} key${keys.length === 1 ? "" : "s"}; it takes at least ${s.minProperties}`);
      for (const k of s.required ?? []) if (!Object.hasOwn(v, k)) out.push(`${p}.${k} is required`);
      for (const k of keys) {
        if (s.propertyNames !== undefined) walk(s.propertyNames, k, `${p} key ${JSON.stringify(k)}`);
        const sub = Object.hasOwn(s.properties ?? {}, k) ? s.properties[k] : (s.additionalProperties ?? true);
        walk(sub, v[k], `${p}.${k}`);
      }
    }
  };
  walk(spec, value, path);
  return out;
}
function allows(spec, raw, value) {
  if (Array.isArray(spec.enum)) return spec.enum.includes(raw.replace(/^(["'])(.*)\1$/, "$2"));
  if (spec.type === "boolean") return raw === "true" || raw === "false";
  if (spec.type === "integer") {
    const n = Number(raw);
    return /^(0|[1-9][0-9]*)$/.test(raw) && n >= (spec.minimum ?? 0) && (spec.maximum === undefined || n <= spec.maximum);
  }
  if (spec.type === "string") {
    if (!/^(["']).*\1$/.test(raw) && plainNonString(raw)) return false;
    const length = [...value].length;
    return (
      length >= (spec.minLength ?? 0) &&
      (spec.maxLength === undefined || length <= spec.maxLength) &&
      (spec.pattern === undefined || patternOf(spec)?.test(value) === true)
    );
  }
  return false;
}

function written(spec, value) {
  if (spec.type !== "string" || Array.isArray(spec.enum)) return value;
  return /^[A-Za-z0-9_./-]+$/.test(value) && !plainNonString(value) ? value : JSON.stringify(value);
}

const AGAINST = "written_against";
const PROVENANCE = "provenance";
const META_KEYS = new Set(["$schema", AGAINST, PROVENANCE]);
const defaultText = (spec) => (["string", "number", "boolean"].includes(typeof spec.default) ? String(spec.default) : null);
function parseSource(value) {
  if (value === "default") return { source: "default", seen: null };
  const m = /^chosen(?: \(default (.*)\))?$/.exec(value);
  return m ? { source: "chosen", seen: m[1] ?? null } : null;
}
function sourceText(source, seen) {
  const text = source === "chosen" && seen !== null ? `chosen (default ${seen})` : source;
  return /^[a-z]+(?: \(default [A-Za-z0-9_./@+-]+\))?$/.test(text) ? text : JSON.stringify(text);
}

function retirementRecords(text) {
  const records = [];
  let current = null;
  for (const l of text.split("\n")) {
    const line = l.replace(/\r$/, "");
    if (line === "---") {
      current = Object.create(null);
      records.push(current);
      continue;
    }
    const m = current === null ? null : /^([a-z_]+):[ \t]*(.*)$/.exec(line);
    if (m) current[m[1]] = trimWs(m[2]).replace(/^(["'])(.*)\1$/, "$2");
  }
  return records;
}
const safeRecordPath = (p) =>
  typeof p === "string" && p !== "" && !/^[/~]|[\\\x00-\x1f\x7f]/.test(p) && p.split("/").every((s) => s !== "" && s !== "." && s !== "..");

const contentLine = (line) => {
  const t = trimWs(line);
  return t !== "" && t[0] !== "#" && !/^(---|\.\.\.|%)/.test(line);
};
function blockTree(text) {
  const node = (raw) => ({ raw, keys: new Map(), dup: new Set(), list: false });
  const root = node("");
  const stack = [{ indent: -1, at: root }];
  for (const l of text.replace(/^﻿/, "").split("\n")) {
    const line = l.replace(/\r$/, "");
    if (!contentLine(line)) continue;
    const indent = indentOf(line);
    const t = trimWs(line);
    const item = t === "-" || t.startsWith("- ");
    while (stack.at(-1).indent > indent) stack.pop();
    const same = stack.at(-1);
    if (same.indent === indent) {
      const owner = same.seq ?? (same.at && same.at.raw === "" && !same.at.keys.size ? same.at : null);
      if (item && owner) {
        owner.list = true;
        stack[stack.length - 1] = { indent, at: null, seq: owner };
        continue;
      }
      stack.pop();
    }
    const parent = stack.at(-1).at;
    if (parent === null) continue;
    const m = item ? null : splitKeyLine(t);
    if (!m) {
      if (item) parent.list = true;
      stack.push({ indent, at: null, seq: item ? parent : undefined });
      continue;
    }
    const key = trimWs(m.written);
    const child = node(trimWs(stripComment(m.rest ?? "")));
    if (parent.keys.has(key)) parent.dup.add(key);
    else parent.keys.set(key, child);
    stack.push({ indent, at: child });
  }
  return root;
}

function checkValue(path, spec, node, valueAt, dataAt, report) {
  if (spec.type === "array" && checksData(spec)) {
    const value = dataAt(path);
    if (value === undefined) report(`${path} could not be read as typed data; check its quoting and indentation`);
    else for (const msg of validateData(spec, value, path)) report(msg);
    return;
  }
  const values = allowedText(spec);
  const { raw } = node;
  if (values === null) {
    const shape = badPattern(spec) ? `pattern ${spec.pattern} does not compile as a JavaScript u-flag regular expression` : `type ${spec.type ?? "unset"}`;
    report(`${path} uses a schema shape setup-apply does not check (${shape}); edit it by hand`);
    return;
  }
  if (isObject(spec)) {
    if (node.list || raw.startsWith("[")) report(`${path} holds a list; it takes ${values}`);
    else if (isNull(raw)) report(`${path} is null; it takes ${values}`);
    else if (raw !== "") report(`${path}=${raw} is not a map; it takes ${values}`);
    else if (!node.keys.size) report(`${path} is empty; it takes ${values}`);
    else {
      for (const k of node.dup) report(`${path}.${k} is set more than once`);
      for (const k of spec.required ?? []) if (!node.keys.has(k)) report(`${path}.${k} is required`);
      for (const [k, child] of node.keys) {
        if (spec.propertyNames !== undefined) for (const msg of validateData(spec.propertyNames, k, `${path} key ${JSON.stringify(k)}`)) report(msg);
        const sub = Object.hasOwn(spec.properties ?? {}, k) ? spec.properties[k] : (spec.additionalProperties ?? true);
        if (sub === false) report(`${path}.${k} is not in the schema`);
        else if (sub !== true) checkValue(`${path}.${k}`, sub, child, valueAt, dataAt, report);
      }
    }
    return;
  }
  if (node.keys.size || node.list || /^[[{]/.test(raw)) {
    report(`${path} holds a map or a list${raw ? ` (${path}=${raw})` : ""}; it takes ${values}`);
  } else if ((raw === '""' || raw === "''") && !allows(spec, raw, "")) {
    report(`${path} is an empty string (${path}=${raw}); it takes ${values}`);
  } else if (raw === "") {
    report(`${path} is empty; it takes ${values}`, true);
  } else if (isNull(raw)) {
    report(`${path} is null; ${path}=${raw} is not ${values}`, true);
  } else if (!allows(spec, raw, valueAt(path))) {
    report(`${path}=${raw} is not ${values}`, true);
  }
}

export function topLevelLines(text) {
  const content = text
    .replace(/^﻿/, "")
    .split("\n")
    .map((line, at) => ({ line: line.replace(/\r$/, ""), at }))
    .filter(({ line }) => contentLine(line));
  const base = content.length ? indentOf(content[0].line) : 0;
  return content
    .filter(({ line }) => indentOf(line) === base)
    .map(({ line, at }) => ({ at, m: splitKeyLine(trimWs(line)) }))
    .filter(({ m }) => m)
    .map(({ at, m: { written, rest } }) => ({
      at,
      written,
      key: trimWs(written),
      raw: trimWs(stripComment(rest ?? "")),
    }));
}

const isWs = (c) => c === " " || c === "\t";
function trimWs(s) {
  let a = 0;
  let b = s.length;
  while (a < b && isWs(s[a])) a++;
  while (b > a && isWs(s[b - 1])) b--;
  return s.slice(a, b);
}
const indentOf = (line) => line.length - line.replace(/^ +/, "").length;

function quotedKey(s) {
  const q = s[0];
  let value = "";
  for (let i = 1; i < s.length; i++) {
    const c = s[i];
    if (c === q) {
      if (q === "'" && s[i + 1] === "'") {
        value += "'";
        i++;
        continue;
      }
      return { value, end: i + 1 };
    }
    if (q === '"' && c === "\\" && i < s.length - 1) {
      const e = s[++i];
      value += e === '"' || e === "\\" || e === "/" ? e : e === "t" ? "\t" : c + e;
      continue;
    }
    value += c;
  }
  return null;
}

function splitKeyLine(s) {
  let written;
  let colon;
  if (s[0] === '"' || s[0] === "'") {
    const q = quotedKey(s);
    if (!q) return null;
    written = q.value;
    colon = q.end;
    while (colon < s.length && isWs(s[colon])) colon++;
    if (s[colon] !== ":") return null;
  } else {
    colon = s.search(/["':]/);
    if (colon < 1 || s[colon] !== ":") return null;
    let end = colon;
    while (end > 1 && isWs(s[end - 1])) end--;
    written = s.slice(0, end);
  }
  let at = colon + 1;
  if (at === s.length) return { written, rest: undefined };
  if (!isWs(s[at])) return null;
  while (at < s.length && isWs(s[at])) at++;
  return { written, rest: s.slice(at) };
}

function stripComment(s) {
  if (s[0] === "#") return "";
  for (let i = 0; i < s.length; ) {
    if (!isWs(s[i])) {
      i++;
      continue;
    }
    let end = i;
    while (end < s.length && isWs(s[end])) end++;
    if (s[end] === "#") return s.slice(0, i);
    i = end;
  }
  return s;
}

export function flatten(text) {
  let doc;
  try {
    doc = parse(text, { source: true });
  } catch (e) {
    if (e instanceof YamlSubsetError) return { error: e.message };
    throw e;
  }
  const records = [];
  const walk = (node, path) => {
    if (node === null) return;
    if (typeof node === "string") {
      const dot = path.indexOf(".");
      records.push({ path, top: trimWs(dot === -1 ? path : path.slice(0, dot)), nested: dot !== -1, value: node });
      return;
    }
    const entries = Array.isArray(node) ? node.entries() : node;
    for (const [k, v] of entries) walk(v, path === null ? String(k) : `${path}.${k}`);
  };
  walk(doc, null);
  return { records };
}
const topScalars = (text) => new Map((flatten(text).records ?? []).filter((r) => !r.nested).map((r) => [r.top, r.value]));

function unread(records, tree) {
  const missed = [];
  for (const { path } of records) {
    let node = tree;
    let rest = path.split(".").map(trimWs).join(".");
    while (rest !== "" && !node.list && !/^[[{]/.test(node.raw)) {
      let hit = null;
      for (const k of node.keys.keys()) {
        if ((rest === k || rest.startsWith(`${k}.`)) && (hit === null || k.length > hit.length)) hit = k;
      }
      if (hit === null) {
        missed.push(path);
        break;
      }
      node = node.keys.get(hit);
      rest = rest.slice(hit.length + 1);
    }
  }
  return missed;
}

function validate(text, { keys, exactKeyNames = false, schemaKey = false, recording = false }) {
  const parsed = flatten(text);
  if (parsed.error) return [{ kind: "parse", key: null, msg: parsed.error, fixable: false }];
  const { records } = parsed;
  const parsedValues = new Map(records.map((r) => [r.path, r.value]));
  const valueAt = (path) => parsedValues.get(path) ?? "";
  let data;
  try {
    data = parse(text);
  } catch {
    data = undefined;
  }
  const dataAt = (path) => {
    let v = data;
    for (const step of path.split(".")) {
      if (!plainMap(v) && !Array.isArray(v)) return undefined;
      v = Object.hasOwn(v, step) ? v[step] : undefined;
    }
    return v;
  };
  const tree = blockTree(text);
  const tops = topLevelLines(text);
  const problems = [];
  const add = (kind, msg, key = null, fixable = false) => problems.push({ kind, key, msg, fixable });
  const known = (k) => META_KEYS.has(k) || Object.hasOwn(keys, k);
  const count = new Map();
  for (const { key, written } of tops) {
    count.set(key, (count.get(key) ?? 0) + 1);
    if (exactKeyNames && written !== key) add("file", `key "${written}" has spaces around its name`);
  }
  const twice = new Set([...count].filter(([, n]) => n > 1).map(([k]) => k));
  for (const key of twice) {
    const own = Object.hasOwn(keys, key);
    add(own ? "value" : "file", `key ${key} is set more than once (it appears ${count.get(key)} times)`, own ? key : null);
  }
  for (const key of new Set([...tops.map((t) => t.key), ...records.map((r) => r.top)])) {
    if (known(key) || twice.has(key)) continue;
    const raw = tops.find((t) => t.key === key)?.raw ?? "";
    if (records.some((r) => r.top === key && r.nested) || /^[[{]/.test(raw)) {
      add("file", `key ${key} is not in the schema and holds a map or a list`);
    } else {
      add("unknown", `key ${key} is not in the schema`);
    }
  }
  for (const [k, spec] of Object.entries(keys)) {
    const node = tree.keys.get(k);
    if (!node) continue;
    checkValue(k, spec, node, valueAt, dataAt, (msg, fixable = false) => add("value", msg, k, fixable && !isCollection(spec)));
  }
  const scalarKind = recording ? "file" : "unknown";
  const against = tops.find((t) => t.key === AGAINST);
  if (against && !twice.has(AGAINST)) {
    if (records.some((r) => r.top === AGAINST && r.nested) || /^[[{]/.test(against.raw)) add("file", `${AGAINST} holds a map or a list; it takes <plugin>@<version>`);
    else if (against.raw === "" || isNull(against.raw)) add(scalarKind, `${AGAINST} is empty or null; it takes <plugin>@<version>`);
  }
  const recorded = tree.keys.get(PROVENANCE);
  if (recorded && !twice.has(PROVENANCE)) {
    const form = "default, chosen or chosen (default <value>)";
    if (recorded.list || /^[[{]/.test(recorded.raw)) add("file", `${PROVENANCE} holds a list; it takes a block map of <key>: ${form}`);
    else if (recorded.raw !== "") add(scalarKind, `${PROVENANCE}=${recorded.raw} is not a map; it takes a block map of <key>: ${form}`);
    for (const [k, entry] of recorded.list ? [] : recorded.keys) {
      const at = `${PROVENANCE}.${k}`;
      if (entry.keys.size || entry.list || /^[[{]/.test(entry.raw)) add("file", `${at} holds a map or a list; it takes ${form}`);
      else if (!parseSource(valueAt(at))) add("file", `${at}=${entry.raw} is not ${form}`);
      else if (!Object.hasOwn(keys, k)) problems.push({ kind: "unknown", key: null, msg: `${at} names a key outside the schema`, fixable: false, entry: true });
    }
  }
  for (const path of unread(records, tree)) {
    const top = trimWs(path.split(".")[0]);
    const own = Object.hasOwn(keys, top);
    add(own ? "value" : "file", `${path} is read differently by the YAML parser; check its quoting and indentation`, own ? top : null);
  }
  const schemaLine = schemaKey && tops.find((t) => t.key === "$schema");
  if (schemaLine) {
    const scalar = records.find((r) => r.top === "$schema" && !r.nested);
    if (records.some((r) => r.top === "$schema" && r.nested) || /^[[{]/.test(schemaLine.raw)) {
      add("file", "$schema holds a map or a list; it takes one schema URL string");
    } else if (!scalar || scalar.value === "" || isNull(schemaLine.raw)) {
      add("file", "$schema is empty or null; it takes one schema URL string");
    }
  }
  return [...new Map(problems.map((p) => [p.msg, p])).values()];
}

const warnLines = (rel, problems) => process.stdout.write(printable(problems.map((p) => `WARN ${rel}: ${p.msg}\n`).join("")));
const passLine = (k, value) => process.stdout.write(printable(`PASS ${k}: ${value(k) ?? "(unset)"}\n`));
export function perKeyReport({ rel, keys, problems, value }) {
  warnLines(rel, problems);
  if (problems.some((p) => p.kind === "parse" || p.kind === "file")) return 1;
  for (const k of Object.keys(keys)) {
    if (!problems.some((p) => p.key === k)) passLine(k, value);
  }
  return problems.length ? 1 : 0;
}
export function wholeFileReport({ rel, keys, problems, value }) {
  warnLines(rel, problems);
  if (problems.some((p) => p.kind !== "unknown")) return 1;
  for (const k of Object.keys(keys)) passLine(k, value);
  return problems.length ? 1 : 0;
}

export function run(config) {
  try {
    process.exitCode = main(config, process.argv.slice(2));
  } catch (e) {
    const message = e instanceof Refusal ? e.message : `${why(e)}; nothing written`;
    process.stderr.write(`setup-apply: ${printable(String(message).replace(/[\r\n]+/g, " "))}\n`);
    process.exitCode = e instanceof Refusal ? e.code : 1;
  }
}

function main(config, argv) {
  const name = `${config.plugin}.yaml`;
  let home = DEFAULT_HOME;
  let rel = `${home}/${name}`;
  const opts = parseArgs(argv, Boolean(config.ref), Boolean(config.provenance));

  let root = opts.root;
  if (!root) {
    const git = spawnSync("git", ["-C", process.cwd(), "rev-parse", "--show-toplevel"], { cwd: HERE, encoding: "utf8" });
    if (git.status !== 0) refuse("not inside a git working tree; pass --root <dir>", 2);
    root = git.stdout.trim();
  }
  try {
    root = realpathSync(root);
  } catch (e) {
    if (e.code === "ENOENT" || e.code === "ENOTDIR") refuse(`root is not a directory: ${root}`, 2);
    refuse(`root ${root}: could not resolve it (${why(e)}); nothing written`);
  }
  if (!lstatOrNull(root, "root")?.isDirectory()) refuse(`root is not a directory: ${root}`, 2);

  let schema;
  try {
    schema = JSON.parse(readFileSync(config.schema, "utf8"));
  } catch (e) {
    refuse(`could not read the schema ${config.schema} (${why(e)})`, 2);
  }
  const keys = Object.fromEntries(Object.entries(schema.properties).filter(([k]) => !META_KEYS.has(k)));
  const check = (text) => validate(text, { keys, exactKeyNames: config.exactKeyNames, schemaKey: config.schemaKey, recording: Boolean(config.provenance) });

  let against = null;
  if (config.provenance) {
    const manifest = config.manifest ?? join(dirname(dirname(config.schema)), ".claude-plugin", "plugin.json");
    let version;
    try {
      ({ version } = JSON.parse(readFileSync(manifest, "utf8")));
    } catch (e) {
      refuse(`could not read the plugin manifest ${manifest} (${why(e)})`, 2);
    }
    if (typeof version !== "string" || !/^[0-9A-Za-z.+-]+$/.test(version)) refuse(`the plugin manifest ${manifest} names no version`, 2);
    if (!Object.hasOwn(schema.properties, AGAINST) || !Object.hasOwn(schema.properties, PROVENANCE)) refuse(`the schema does not declare ${AGAINST} and ${PROVENANCE}, which provenance writes`, 2);
    against = `${config.plugin}@${version}`;
  }

  const recordedIn = (text) => {
    const records = flatten(text).records ?? [];
    const entries = new Map();
    for (const r of records.filter((r) => r.top === PROVENANCE && r.nested)) {
      const source = parseSource(r.value);
      if (source) entries.set(trimWs(r.path.slice(r.path.indexOf(".") + 1)), source);
    }
    return {
      against: records.find((r) => r.top === AGAINST && !r.nested)?.value ?? null,
      entries,
      present: topLevelLines(text).some((t) => t.key === PROVENANCE),
    };
  };
  const drift = (text, rec) => {
    const out = { stale: [], moved: [] };
    if (rec.against === against) return out;
    const scalars = topScalars(text);
    for (const [k, spec] of Object.entries(keys)) {
      const now = defaultText(spec);
      if (now === null || isCollection(spec) || !scalars.has(k)) continue;
      const { source, seen } = rec.entries.get(k) ?? { source: "chosen", seen: null };
      const value = scalars.get(k);
      if (source === "default" && value !== now) out.stale.push({ k, from: value, to: now });
      if (source === "chosen" && seen !== null && seen !== now) out.moved.push({ k, value, from: seen, to: now });
    }
    return out;
  };
  const noRecord = (rec) => (rec.present ? "" : `INFO ${rel}: no provenance recorded; each value is read as chosen\n`);
  const movedLines = (moved) =>
    moved.map(({ k, value, from, to }) => `WARN ${rel}: ${k}=${value} was chosen by the team; its plugin default changed from ${from} to ${to}; the value is kept\n`).join("");

  const checkRoot = () => {
    const realRoot = real(root, "root");
    const userHome = process.env.HOME || homedir();
    if (userHome) {
      let realHome = userHome;
      try {
        realHome = realpathSync(userHome);
      } catch {
      }
      if (realHome === realRoot || realHome.startsWith(realRoot.endsWith(sep) ? realRoot : realRoot + sep)) {
        refuse(`the root ${root} is $HOME or an ancestor of it, not a repository; nothing written`);
      }
    }
    return realRoot;
  };

  const dirPrefixes = (relPath) => {
    const segments = relPath.split("/").slice(0, -1);
    return segments.map((_, i) => segments.slice(0, i + 1).join("/"));
  };

  const checkFile = (relPath) => {
    const realRoot = checkRoot();
    for (const part of dirPrefixes(relPath)) {
      const st = lstatOrNull(join(root, part), part);
      if (!st) return false;
      if (st.isSymbolicLink()) refuse(`${part} is a symlink; refusing to write through it`);
      if (!st.isDirectory()) refuse(`${part} exists and is not a directory; nothing written`);
      if (real(join(root, part), part) !== join(realRoot, part)) refuse(`${part} resolves outside the repository; nothing written`);
    }
    const st = lstatOrNull(join(root, relPath), relPath);
    if (!st) return false;
    if (st.isSymbolicLink()) refuse(`${relPath} is a symlink; refusing to write through it`);
    if (st.isDirectory()) refuse(`${relPath} is a directory where a file belongs; nothing written`);
    if (!st.isFile()) refuse(`${relPath} exists and is not a regular file; nothing written`);
    if (st.nlink > 1) refuse(`${relPath} has ${st.nlink} hard links; refusing to write through it`);
    return true;
  };

  const plainFile = (relPath) => {
    for (const part of dirPrefixes(relPath)) {
      const st = lstatOrNull(join(root, part), part);
      if (!st || st.isSymbolicLink() || !st.isDirectory()) return false;
    }
    const st = lstatOrNull(join(root, relPath), relPath);
    return st !== null && st.isFile() && st.nlink === 1;
  };

  const readFile = (relPath) => {
    if (!checkFile(relPath)) return null;
    try {
      return readFileSync(join(root, relPath), "utf8");
    } catch (e) {
      refuse(`${relPath}: could not read it (${why(e)}); nothing written`);
    }
  };
  const readTarget = () => readFile(rel);

  const readRetired = () => {
    if (!config.retired) return null;
    const manifest = config.retirements ?? join(dirname(dirname(config.schema)), "retirements.yaml");
    let manifestText;
    try {
      manifestText = readFileSync(manifest, "utf8");
    } catch (e) {
      refuse(`could not read the retirements manifest ${manifest} (${why(e)})`, 2);
    }
    const record = retirementRecords(manifestText).find((r) => r.id === config.retired);
    if (!record) refuse(`the retirements manifest ${manifest} has no record ${config.retired}`, 2);
    if (record.kind !== "file" || record.action !== "migrate") refuse(`record ${config.retired} is not a migrate record of kind file`, 2);
    if (!safeRecordPath(record.path) || record.path === rel) refuse(`record ${config.retired} names an invalid path ${JSON.stringify(record.path)}`, 2);
    if ((record.status ?? "active") !== "active") return null;
    if (!plainFile(record.path)) return null;
    const text = readFile(record.path);
    if (text === null) return null;
    if (record.content_match !== undefined) {
      const grep = spawnSync("grep", ["-Eq", "-e", record.content_match], { cwd: HERE, input: text.replace(/\r$/gm, ""), encoding: "utf8" });
      if (grep.error || grep.status > 1) refuse(`record ${config.retired}: grep could not apply its content_match`, 2);
      if (grep.status !== 0) return null;
    }
    return { path: record.path, text };
  };

  const readOld = (old) => {
    const values = new Map();
    const bad = new Set();
    let rec = null;
    if (old.path.endsWith(".json")) {
      let doc;
      try {
        doc = JSON.parse(old.text);
      } catch (e) {
        refuse(`${old.path}: ${why(e)}; carry its values by hand; nothing written`);
      }
      if (doc === null || typeof doc !== "object" || Array.isArray(doc)) refuse(`${old.path} is not a JSON object; carry its values by hand; nothing written`);
      for (const [k, v] of Object.entries(doc)) {
        if (META_KEYS.has(k)) continue;
        if (["string", "number", "boolean"].includes(typeof v)) values.set(k, String(v));
        else bad.add(`${k} holds ${v === null ? "null" : "a map or a list"}`);
      }
    } else {
      const parsed = flatten(old.text);
      if (parsed.error) refuse(`${old.path}: ${parsed.error}; carry its values by hand; nothing written`);
      for (const r of parsed.records) {
        if (META_KEYS.has(r.top)) continue;
        if (r.nested) bad.add(`${r.top} holds a map or a list`);
        else values.set(r.top, r.value);
      }
      for (const { key } of topLevelLines(old.text)) {
        if (!META_KEYS.has(key) && !parsed.records.some((r) => r.top === key)) bad.add(`${key} is empty`);
      }
      rec = recordedIn(old.text);
    }
    return { values, rec, bad: [...bad] };
  };

  const writeFile = (relPath, text, expected) => {
    for (const part of dirPrefixes(relPath)) {
      checkFile(relPath);
      if (lstatOrNull(join(root, part), part)) continue;
      try {
        mkdirSync(join(root, part));
      } catch (e) {
        refuse(`${part}: could not create it (${why(e)}); nothing written`);
      }
    }
    if (readFile(relPath) !== expected) refuse(`${relPath} changed while this ran; nothing written, run again`);
    const slash = relPath.lastIndexOf("/") + 1;
    const tmpRel = `${relPath.slice(0, slash)}.${relPath.slice(slash)}.${config.fixedTemp ? "" : `${process.pid}.`}tmp`;
    const tmp = join(root, tmpRel);
    const target = join(root, relPath);
    const mode = expected === null ? 0o644 : lstatSync(target).mode & 0o777;
    const flags = constants.O_WRONLY | constants.O_CREAT | constants.O_EXCL | (constants.O_NOFOLLOW ?? 0);
    let fd = -1;
    try {
      fd = openSync(tmp, flags, mode);
    } catch (e) {
      if (e.code === "EEXIST" || e.code === "ELOOP") {
        refuse(`${tmpRel} already exists (another run, or one that stopped early); remove it and run again; nothing written`);
      }
      refuse(`${tmpRel}: could not create it (${why(e)}); nothing written`);
    }
    try {
      writeSync(fd, text);
      const open = fd;
      fd = -1;
      closeSync(open);
      checkFile(relPath);
      renameSync(tmp, target);
    } catch (e) {
      try {
        if (fd >= 0) closeSync(fd);
      } catch {}
      try {
        rmSync(tmp, { force: true });
      } catch {}
      if (e instanceof Refusal) throw e;
      refuse(`${relPath}: could not write it (${why(e)}); nothing written`);
    }
  };

  const git = (...a) => spawnSync("git", ["-C", root, ...a], { cwd: HERE, encoding: "utf8" });
  const resolveRef = () => {
    checkRoot();
    const ref = opts.ref;
    let commitish = ref;
    if (ref.startsWith("origin/")) {
      const shown = git("show-ref", "--verify", "--hash", "--end-of-options", `refs/remotes/${ref}`);
      commitish = shown.status === 0 ? shown.stdout.trim() : "";
      if (!/^[0-9a-f]{40}$/.test(commitish)) refuse(`--ref ${ref}: refs/remotes/${ref} does not exist`, 2);
    }
    const rev = git("rev-parse", "--verify", "--quiet", "--end-of-options", `${commitish}^{commit}`);
    const sha = rev.status === 0 ? rev.stdout.trim() : "";
    if (!/^[0-9a-f]{40}$/.test(sha)) refuse(`--ref ${ref} does not resolve to a commit`, 2);
    return sha;
  };

  const readAtRef = (sha) => {
    const ref = opts.ref;
    const tree = git("ls-tree", "-z", "--full-tree", sha, "--", rel);
    if (tree.status !== 0) refuse(`${rel} at ${ref} (${sha}): could not list it`);
    const entry = tree.stdout.split("\0").find(Boolean);
    if (!entry) return { sha, text: null };
    const [mode, type, oid] = entry.split("\t")[0].split(" ");
    if (type !== "blob" || !/^1006[0-7]{2}$/.test(mode)) return { sha, mode };
    const blob = git("cat-file", "blob", oid);
    if (blob.status !== 0) refuse(`${rel} at ${ref} (${sha}): could not read it`);
    return { sha, text: blob.stdout };
  };

  const resolver = config.resolver ?? join(HERE, "resolve-convention-home.sh");
  const runResolver = (args, input) => {
    if (!lstatOrNull(resolver, "the convention-home resolver")) {
      refuse(`the convention-home resolver ${resolver} is missing; nothing written`, 2);
    }
    const r = spawnSync("bash", [resolver, ...args], { cwd: HERE, input, encoding: "utf8" });
    if (r.error) refuse(`cannot run bash: ${why(r.error)}`, 2);
    const lines = (r.stderr ?? "").split("\n").filter(Boolean);
    for (const l of lines.filter((l) => l.startsWith("duplicate:"))) process.stderr.write(printable(`setup-apply: WARN ${l}\n`));
    return { status: r.status, out: (r.stdout ?? "").trim(), message: lines.find((l) => !l.startsWith("duplicate:")) ?? "" };
  };
  const sha = opts.ref === null ? null : resolveRef();
  const bound = runResolver(["--root", root, ...(sha ? ["--ref", sha] : [])]);
  const states = { 0: "bound", 1: "unbound", 4: "declined", 5: "inapplicable" };
  const state = states[bound.status];
  if (state === undefined) {
    refuse(`${bound.message || `the convention-home resolver exited ${bound.status}`}; nothing written`, bound.status === 3 ? 1 : 2);
  }
  if (state === "bound") home = bound.out;
  if (opts.home !== null) {
    const asked = /[`\r\n]/.test(opts.home) ? { status: 1, out: "" } : runResolver(["-"], `${REGION_BEGIN}\n\`${opts.home}\`\n${REGION_END}\n`);
    if (asked.status !== 0) refuse(`--home ${JSON.stringify(opts.home)} is not a repo-relative directory of [A-Za-z0-9._-] segments`, 2);
    if (state === "unbound") home = asked.out;
    else if (asked.out !== home) refuse(`--home ${asked.out} differs from the ${state === "bound" ? "bound" : "default"} home ${home}; nothing written`, 2);
  }
  rel = `${home}/${name}`;
  const indexRel = (state === "bound" || opts.home !== null) && home !== DEFAULT_HOME ? `${home}/${INDEX_NAME}` : null;

  const eolOf = (text) => {
    const crlf = (text.match(/\r\n/g) ?? []).length;
    return crlf && crlf === (text.match(/\n/g) ?? []).length ? "\r\n" : "\n";
  };
  const appendLines = (text, lines) => {
    const eol = eolOf(text);
    const tail = text === "" || text.endsWith("\n") ? "" : eol;
    return `${text}${tail}${lines.join(eol)}${eol}`;
  };
  const isShim = (text) => {
    const lines = text.replace(/^﻿/, "").split("\n").map((l) => l.trim()).filter(Boolean);
    return lines.length > 0 && lines.every((l) => l === "@AGENTS.md");
  };
  const planRegion = (regionLines) => {
    const peek = (file) => {
      const st = lstatOrNull(join(root, file), file);
      if (!st) return null;
      if (!st.isSymbolicLink()) return { file, text: readFile(file), link: false, real: real(join(root, file), file) };
      try {
        return { file, text: readFileSync(join(root, file), "utf8"), link: true, real: realpathSync(join(root, file)) };
      } catch {
        return { file, text: "", link: true, real: null };
      }
    };
    const present = INSTRUCTION_FILES.map(peek).filter(Boolean);
    for (const f of present) {
      if (f.text.split("\n").some((l) => l.trim() === REGION_BEGIN)) {
        refuse(`${f.file} has a convention-home region with no pointer line; name the home inside it by hand; nothing written`);
      }
    }
    let chosen = present.find((f) => f.file === "AGENTS.md") ?? present.find((f) => !isShim(f.text)) ?? { file: "AGENTS.md", text: null };
    if (chosen.link) chosen = present.find((f) => !f.link && f.real === chosen.real) ?? chosen;
    if (chosen.link) refuse(`${chosen.file} is a symlink; refusing to write through it; nothing written`);
    const text = chosen.text ?? "";
    return { file: chosen.file, existing: chosen.text, proposed: appendLines(text, text === "" ? regionLines : ["", ...regionLines]) };
  };
  const planIgnore = () => {
    const line = `${home}/**/*.local.*`;
    const existing = readFile(".gitignore");
    if (existing !== null && existing.split("\n").some((l) => l.replace(/\r$/, "").trim() === line)) return { line, existing, proposed: null };
    return { line, existing, proposed: appendLines(existing ?? "", [line]) };
  };
  const regionLines = (pointer) => [
    REGION_BEGIN,
    ...(pointer
      ? [`Team conventions live in \`${home}\` — read the topic doc there`, "before changing a governed surface."]
      : ["This repository declined a convention home; plugins use their bundled defaults.", "declined"]),
    REGION_END,
  ];

  if (opts.decline) {
    if (state === "declined") {
      process.stdout.write("this repository already declined a convention home; nothing written\n");
      return 0;
    }
    if (state === "bound") refuse(`this repository binds ${home}; there is no offer to decline; nothing written`);
    if (state === "inapplicable") refuse("no convention home applies to this root; there is no offer to decline; nothing written");
    const plan = planRegion(regionLines(false));
    writeFile(plan.file, plan.proposed, plan.existing);
    process.stdout.write(`wrote ${plan.file}: a convention-home region recording that this repository declined a home\n`);
    return 0;
  }

  const vet = (k, v) => {
    if (!Object.hasOwn(keys, k)) return { error: `${k} is not a key of ${rel} (keys: ${Object.keys(keys).join(", ")})` };
    const spec = keys[k];
    const values = allowedText(spec);
    if (values === null || isCollection(spec)) {
      return { error: `${k} takes ${values ?? "a value setup-apply does not check"} and is not set from the command line; edit ${rel} by hand` };
    }
    const control = [...v].some((c) => {
      const n = c.codePointAt(0);
      return n < 0x20 || (n >= 0x7f && n <= 0x9f) || n === 0x2028 || n === 0x2029;
    });
    if (control) return { error: `${k}: the value holds a control character or a line or paragraph separator` };
    const w = written(spec, v);
    if (/^["']/.test(v) || !allows(spec, w, v)) return { error: `${k}=${v} is not ${values}` };
    return { written: w, value: v };
  };
  const wanted = new Map();
  for (const pair of opts.pairs) {
    const eq = pair.indexOf("=");
    const k = pair.slice(0, eq).trim();
    if (wanted.has(k)) refuse(`${k} is given more than once; pass each key once; nothing written`);
    const vetted = vet(k, pair.slice(eq + 1));
    if (vetted.error) refuse(`${vetted.error}; nothing written`);
    wanted.set(k, vetted);
  }
  const defaulted = new Map();
  for (const k of opts.defaults) {
    if (wanted.has(k) || defaulted.has(k)) refuse(`${k} is given more than once; pass each key once; nothing written`);
    if (!Object.hasOwn(keys, k)) refuse(`${k} is not a key of ${rel} (keys: ${Object.keys(keys).join(", ")}); nothing written`);
    const spec = keys[k];
    const value = defaultText(spec);
    const w = value === null ? "" : written(spec, value);
    if (value === null || allowedText(spec) === null || isCollection(spec) || !allows(spec, w, value)) {
      refuse(`${k} has no plugin default --default can write; nothing written`);
    }
    defaulted.set(k, { written: w, value });
  }
  const settings = [...wanted, ...defaulted];

  let existing = null;
  if (opts.ref !== null) {
    const at = readAtRef(sha);
    if (at.mode) {
      process.stdout.write(`WARN ${rel} at ${opts.ref} (${at.sha}): not a regular file (mode ${at.mode})\n`);
      return 1;
    }
    process.stdout.write(`INFO read ${rel} at ${opts.ref}, commit ${at.sha}\n`);
    existing = at.text;
  } else {
    existing = readTarget();
  }

  const old = opts.check ? null : readRetired();
  const setupState = old !== null ? "migrate" : existing === null ? "init" : "configure";
  const bothLine = old !== null && existing !== null ? `WARN both ${old.path} and ${rel} exist; ${rel} wins for each key it sets\n` : "";
  if (opts.state) {
    process.stderr.write(printable(bothLine));
    process.stdout.write(printable(`${setupState} ${old !== null ? old.path : rel}\n`));
    return 0;
  }
  if (!opts.check && !settings.length && setupState !== "migrate") refuse("nothing to write; pass at least one <key>=<value>", 2);

  if (opts.check) {
    if (existing === null) {
      process.stdout.write(`INFO ${rel}: absent; every key resolves from userConfig or its default\n`);
      return 0;
    }
    const records = flatten(existing).records ?? [];
    const leaves = (k) =>
      records
        .filter((r) => r.top === k && r.nested)
        .map((r) => `${r.path.slice(r.path.indexOf(".") + 1)}=${r.value}`)
        .join(", ");
    const present = new Set(topLevelLines(existing).map((t) => t.key));
    const scalars = new Map(records.filter((r) => !r.nested).map((r) => [r.top, r.value]));
    const value = (k) => {
      if (!present.has(k)) return null;
      if (isCollection(keys[k])) return leaves(k);
      const parsed = scalars.get(k) ?? "";
      if (parsed === "" || parsed.trim() !== parsed) return JSON.stringify(parsed);
      return spawnSync("bash", [config.reader, "-", k], { cwd: HERE, input: existing, encoding: "utf8" }).stdout.trim();
    };
    const problems = check(existing);
    const code = (config.report ?? perKeyReport)({ rel, keys, problems, value });
    if (against === null || problems.some((p) => p.kind === "parse" || p.kind === "file")) return code;
    const rec = recordedIn(existing);
    const { stale, moved } = drift(existing, rec);
    const from = rec.against ?? "an unrecorded version";
    process.stdout.write(
      printable(
        noRecord(rec) +
          stale.map(({ k, from: old, to }) => `INFO ${rel}: ${k}=${old} is marked default, written against ${from}; the plugin default is now ${to}, and a write with --yes sets it\n`).join("") +
          movedLines(moved),
      ),
    );
    return moved.length ? 1 : code;
  }

  const carried = new Map();
  const kept = [];
  let carriedNotes = "";
  if (old !== null) {
    const { values, rec: oldRec, bad } = readOld(old);
    const oldDrift = against === null || oldRec === null ? { stale: [], moved: [] } : drift(old.text, oldRec);
    const inNew = existing === null ? new Map() : topScalars(existing);
    const setInNew = new Set(existing === null ? [] : topLevelLines(existing).map((t) => t.key));
    const newStale = against === null || existing === null ? [] : drift(existing, recordedIn(existing)).stale;
    const afterRun = (k) => newStale.find((s) => s.k === k)?.to ?? inNew.get(k);
    kept.push(...bad);
    for (const [k, v] of values) {
      const stale = oldDrift.stale.find((s) => s.k === k);
      const update = stale ? vet(k, stale.to) : null;
      const effective = update && !update.error ? stale.to : v;
      const cli = wanted.get(k) ?? defaulted.get(k);
      if (cli) {
        if (cli.value !== effective) kept.push(`${k}=${effective}: the command line sets ${k}=${cli.value}`);
        continue;
      }
      if (setInNew.has(k)) {
        if (afterRun(k) !== effective) kept.push(`${k}=${effective}: ${rel} sets ${k}=${afterRun(k) ?? ""}`);
        continue;
      }
      const vetted = update && !update.error ? update : vet(k, v);
      if (vetted.error) {
        kept.push(vetted.error);
        continue;
      }
      if (vetted === update) {
        carriedNotes += `INFO ${old.path}: ${k}=${v} is marked default, written against ${oldRec.against ?? "an unrecorded version"}; it is carried at the plugin default now, ${stale.to}\n`;
      }
      carried.set(k, { ...vetted, source: oldRec?.entries.get(k)?.source ?? "chosen" });
    }
    carriedNotes += movedLines(oldDrift.moved.filter(({ k }) => carried.has(k)));
  }
  const removeOld = old !== null && kept.length === 0;
  const migrateNotes =
    old === null
      ? ""
      : printable(
          bothLine +
            carriedNotes +
            kept.map((l) => `WARN ${old.path}: ${l}; not carried\n`).join("") +
            (kept.length ? `${old.path} is left in place: carry each value above by hand, then clean it\n` : ""),
        );
  const writes = [...settings, ...carried];

  const rec = existing === null ? { against: null, entries: new Map(), present: true } : recordedIn(existing);
  const given = (k) => wanted.has(k) || defaulted.has(k) || carried.has(k);
  const { stale, moved } = against === null || existing === null ? { stale: [], moved: [] } : drift(existing, rec);
  const updates = stale.filter(({ k }) => !given(k));
  const rewritten = (k) => given(k) || updates.some((u) => u.k === k);

  if (existing !== null) {
    const found = check(existing);
    const blocking = found.filter((p) => p.kind !== "unknown" && !(p.fixable && rewritten(p.key)));
    if (blocking.length) refuse(`${rel}: ${blocking.map((p) => p.msg).join("; ")}; fix the file by hand, nothing written`);
    for (const p of found.filter((p) => p.kind === "unknown")) {
      const fate = p.entry && against !== null ? "the entry is dropped" : "it is ignored and its line is kept as written";
      process.stderr.write(printable(`setup-apply: WARN ${rel}: ${p.msg}; ${fate}\n`));
    }
  }

  const held = new Set([...(existing === null ? [] : topLevelLines(existing).map((t) => t.key)), ...writes.map(([k]) => k)]);
  const sourceOf = (k) =>
    defaulted.has(k) ? "default" : wanted.has(k) ? "chosen" : carried.has(k) ? carried.get(k).source : (rec.entries.get(k)?.source ?? "chosen");
  const entries = Object.keys(keys)
    .filter((k) => held.has(k) && !isCollection(keys[k]) && allowedText(keys[k]) !== null)
    .map((k) => `  ${k}: ${sourceText(sourceOf(k), defaultText(keys[k]))}`);
  const block = against === null ? [] : [`${PROVENANCE}:`, ...entries];

  let proposed;
  if (existing === null) {
    const head = against === null ? [] : [`${AGAINST}: ${against}`];
    proposed = [`# yaml-language-server: $schema=${schema.$id}`, ...head, ...writes.map(([k, { written: w }]) => `${k}: ${w}`), ...block, ""].join("\n");
  } else {
    const eol = eolOf(existing);
    if (eol === "\n" && existing.includes("\r\n")) refuse(`${rel} mixes CRLF and LF line endings; make them one kind first; nothing written`);
    const lines = existing.split(eol);
    if (lines.at(-1) === "") lines.pop();
    const tops = topLevelLines(existing);
    const pad = against === null || !tops.length ? "" : " ".repeat(indentOf(lines[tops[0].at].replace(/^﻿/, "")));
    const appended = [];
    const set = (k, w) => {
      const line = tops.find((t) => t.key === k);
      if (line) lines[line.at] = `${lines[line.at].match(/^\s*/)[0]}${k}: ${w}`;
      else appended.push(`${pad}${k}: ${w}`);
    };
    for (const [k, { written: w }] of writes) set(k, w);
    if (against !== null) {
      for (const { k, to } of updates) set(k, written(keys[k], to));
      set(AGAINST, against);
      const at = tops.find((t) => t.key === PROVENANCE)?.at;
      const [head, ...rest] = block;
      const body = rest.map((l) => pad + l);
      if (at === undefined) appended.push(pad + head, ...body);
      else {
        let end = at;
        for (let i = at + 1; i < lines.length && (!contentLine(lines[i]) || indentOf(lines[i]) > indentOf(lines[at])); i++) {
          if (contentLine(lines[i])) end = i;
        }
        lines.splice(at, end - at + 1, lines[at].match(/^\s*/)[0] + head, ...body);
      }
    }
    lines.push(...appended);
    proposed = `${lines.join(eol)}${eol}`;
  }

  const problems = check(proposed).filter((p) => p.kind !== "unknown");
  if (problems.length) refuse(`the result would not validate: ${problems.map((p) => p.msg).join("; ")}; nothing written`);
  const readBack = topScalars(proposed);
  for (const [k, { value }] of writes) {
    if ((readBack.get(k) ?? "") !== value) refuse(`${k}=${value} would not read back as given; nothing written`);
  }

  const changes = existing === null ? writes.length > 0 : proposed !== existing;
  const unchanged = existing === null ? `nothing in ${old?.path} can be carried into ${rel}; nothing written\n` : `${rel}: already configured; nothing written\n`;

  let index = null;
  if (indexRel !== null) {
    const indexExisting = readFile(indexRel);
    const listed = indexExisting !== null && indexExisting.includes(`](${name})`);
    if (!listed) {
      const entry = `- [${name}](${name}) — settings written by the ${config.plugin} plugin's setup`;
      index = {
        existing: indexExisting,
        proposed:
          indexExisting === null
            ? `# Convention index\n\nFiles the Claude Code plugins wrote in this home. Their names stay lowercase-kebab so the repository can rename them and update the pointer later.\n\n${entry}\n`
            : appendLines(indexExisting, [entry]),
      };
    }
  }

  let offer = null;
  let offerRefused = null;
  if (state === "unbound") {
    try {
      offer = { region: planRegion(regionLines(true)), ignore: planIgnore() };
    } catch (e) {
      if (!(e instanceof Refusal) || opts.yes) throw e;
      offerRefused = e.message.replace(/;? ?nothing written$/, "");
    }
  }
  const printOffer = (pending) => {
    if (offer === null) {
      process.stdout.write(
        printable(`No convention home is bound in this repository, and setup cannot add the pointer region: ${offerRefused}. Add the region by hand, or re-run with --home <dir>.\n`),
      );
      return;
    }
    const { region, ignore } = offer;
    process.stdout.write(
      printable(
        [
          `No convention home is bound in this repository. With the operator's confirmation, setup will:`,
          ...(pending && changes ? [`  - write ${rel} (the home is created if missing)`] : []),
          `  - add a convention-home region naming \`${home}\` to ${region.file}${region.existing === null ? " (created: neither AGENTS.md nor CLAUDE.md exists)" : ""}`,
          ignore.proposed === null
            ? `  - leave .gitignore as it is (it already holds ${ignore.line})`
            : `  - add the personal override ignore line ${ignore.line} to .gitignore so personal <concern>.local.* files stay untracked`,
          `Nothing is always-loaded: the region is one pointer line. ${pending ? "Nothing was written" : "Neither was written"}. Re-run with --yes once the operator confirms,`,
          `with --home <dir> to name a different home, or with --decline to record that this repository declines a home.`,
          "",
        ].join("\n"),
      ),
    );
  };

  const provenanceNotes = against !== null && existing !== null ? printable(noRecord(rec) + movedLines(moved.filter(({ k }) => !given(k)))) : "";
  const unbound = offer !== null || offerRefused !== null;
  if (!changes && index === null && !unbound && !removeOld) {
    process.stdout.write(migrateNotes + unchanged);
    return 0;
  }

  const strandedHome = unbound && home !== DEFAULT_HOME;
  const migrating = old !== null && (changes || removeOld);
  if (!opts.yes && ((existing !== null && changes) || migrating || (index !== null && index.existing !== null) || strandedHome)) {
    if (old !== null) {
      process.stdout.write(migrateNotes);
      process.stdout.write(printable([...carried].map(([k, { value }]) => `would carry ${k}=${value} from ${old.path} into ${rel}\n`).join("")));
      if (removeOld) process.stdout.write(printable(`would remove ${old.path}: every value in it would be in ${rel}\n`));
      if (existing === null && changes) process.stdout.write(printable(`would create ${rel}:\n${proposed}`));
      if (migrating) process.stdout.write(printable(`${old.path} would be migrated into ${rel}; nothing written. Re-run with --yes once the operator confirms.\n`));
    }
    if (existing !== null && changes) {
      process.stdout.write(provenanceNotes);
      const diff = spawnSync("diff", ["-u", "--label", `a/${rel}`, "--label", `b/${rel}`, join(root, rel), "-"], {
        cwd: HERE,
        input: proposed,
        encoding: "utf8",
      });
      process.stdout.write(printable(diff.stdout));
      process.stdout.write(`${rel} exists and would change; nothing written. Show this diff, and re-run with --yes once the operator confirms.\n`);
    }
    if (index !== null && index.existing !== null) {
      process.stdout.write(`${indexRel} exists and would list ${name}; nothing written. Re-run with --yes once the operator confirms.\n`);
    }
    if (unbound) printOffer(true);
    return 3;
  }

  if (changes) {
    writeFile(rel, proposed, existing);
    process.stdout.write(provenanceNotes);
    process.stdout.write(printable(`wrote ${rel}\n${proposed}`));
    for (const { k, from, to } of updates) {
      process.stdout.write(printable(`updated ${k}: ${from} -> ${to}, its plugin default (it was marked default, written against ${rec.against ?? "an unrecorded version"})\n`));
    }
  } else {
    process.stdout.write(unchanged.replace(/; nothing written\n$/, "\n"));
  }
  if (old !== null) {
    process.stdout.write(migrateNotes);
    process.stdout.write(printable([...carried].map(([k, { value }]) => `carried ${k}=${value} from ${old.path}\n`).join("")));
  }
  if (removeOld) {
    if (readFile(old.path) !== old.text) refuse(`${old.path} changed while this ran; ${rel} is written and ${old.path} is left in place; run again`);
    try {
      rmSync(join(root, old.path));
    } catch (e) {
      refuse(`${old.path}: could not remove it (${why(e)}); ${rel} is written`);
    }
    process.stdout.write(printable(`removed ${old.path}: every value in it is in ${rel}\n`));
  }
  if (index !== null) {
    writeFile(indexRel, index.proposed, index.existing);
    process.stdout.write(`wrote ${indexRel}: listed ${name}\n`);
  }
  if (unbound && !opts.yes) {
    printOffer(false);
    return 0;
  }
  if (offer !== null) {
    const { region, ignore } = offer;
    if (ignore.proposed !== null) {
      writeFile(".gitignore", ignore.proposed, ignore.existing);
      process.stdout.write(printable(`wrote .gitignore: added ${ignore.line} (personal override files stay untracked)\n`));
    }
    writeFile(region.file, region.proposed, region.existing);
    process.stdout.write(printable(`wrote ${region.file}: added a convention-home region naming \`${home}\`\n`));
  }
  return 0;
}
