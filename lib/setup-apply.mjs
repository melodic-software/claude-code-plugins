// Write or check a plugin's repository settings file,
// <home>/<plugin>.yaml, against the plugin's JSON Schema. <home> is the
// repository's convention home (see "Convention home" below). Each plugin's
// skills/setup/scripts/setup-apply.mjs is a thin entry point that calls run()
// with its own paths.
//
// Usage of an entry point:
//   setup-apply.mjs [--root <dir>] [--yes] [--home <dir>] <key>=<value> ...
//   setup-apply.mjs [--root <dir>] --decline
//   setup-apply.mjs [--root <dir>] --check [--ref <ref>]
//
//   --root <dir>  repository root; default: git's toplevel for the current
//                 directory. A symlinked root is resolved first, and every
//                 check below applies to the resolved directory.
//   --yes         the operator has seen the diff or the offer and confirmed it;
//                 needed to change a file that already exists and to write a
//                 pointer region into a repository that has none.
//   --home <dir>  the convention home to offer when the repository binds none:
//                 a repo-relative directory by the resolver's grammar. The
//                 default is docs/conventions. Finding an equivalent home the
//                 repository already has is the setup skill's interview; the
//                 chosen home arrives here. A bound repository keeps its home,
//                 so a different --home is refused.
//   --decline     record that the repository declines a convention home: a
//                 region holding a `declined` line, so the next run does not
//                 offer again and writes <plugin>.yaml under docs/conventions.
//   --check       validate the existing file and print one INFO, PASS or WARN
//                 line per finding; write nothing. A WARN on one key's value,
//                 or on a key outside the schema, leaves a PASS line for every
//                 other key; a problem with the whole file leaves none. Exit 1
//                 on any WARN.
//   --ref <ref>   only where the plugin enables it, and with --check only:
//                 validate the file as committed at <ref>, a 40-hex commit id
//                 or origin/<name>, checked before any git call. origin/<name>
//                 is read only from refs/remotes/origin/<name>, matched
//                 exactly, and exits 2 when that ref is absent. Elsewhere
//                 --ref is a usage error.
//
// Convention home. The home is read with lib/resolve-convention-home.sh, which
// sits beside this file (a plugin's lib/ carries a generated copy), from the
// pointer region in AGENTS.md or CLAUDE.md; the grammar is in that header.
//   bound         the region names a home: <home>/<plugin>.yaml is written
//                 there. A home other than docs/conventions is one the
//                 repository already had, so <plugin>.yaml stays lowercase-kebab
//                 and is listed in <home>/conventions-index.md.
//   unbound       no region: the offer. Without --yes nothing is written and
//                 the offer is printed (exit 3). With --yes the writer creates
//                 the home, writes <plugin>.yaml, adds `<home>/**/*.local.*` to
//                 .gitignore, and adds the region to the instruction file the
//                 repository already keeps (AGENTS.md, else CLAUDE.md, else a
//                 new AGENTS.md), announcing each write. Nothing becomes
//                 always-loaded: the region is one pointer line.
//   declined      the region holds a `declined` line: docs/conventions, no offer.
//   inapplicable  the root is not a git work tree: docs/conventions, no offer.
// A broken region (two pointers, a missing directory, an invalid path) is a
// refusal that names it.
//
// Allowed values come from the schema: `true` and `false` for a boolean key,
// the listed strings for an enum key (quoted or not in the file), for an
// integer key an unquoted whole number from the schema's minimum (0 when
// absent) up to any maximum, with no sign, decimal point or leading zero, and
// for a string key a quoted string, or a plain one YAML does not read as a
// boolean, null or number, that meets any minLength, maxLength and pattern. An
// object key takes a block map, one key per line, whose keys are checked
// against its properties, else its additionalProperties (false refuses them),
// by the same rules, nested to any depth. A key whose schema has another shape
// is reported as unchecked, never guessed at. A command-line value is the bare
// word, so any quote makes it invalid; a string is written quoted when its
// plain form would not read back as given, and an object key or an unchecked
// one is edited by hand.
//
// validate(text) reports every problem in a document: a parse error; a key
// set more than once (keys compared after trimming); a schema key whose value
// is out of the list or range, empty (`key:`), null or `~` (each fixable: apply
// may write over it), or an empty quoted string a string key's schema does not
// allow, a map or list in any form on a key that is not an object, or any
// problem inside an object (not fixable). A top-level key outside the schema
// is a warning: it is ignored, apply keeps its line byte for byte, and the
// valid keys still count. It is refused when it is set twice or holds a map or
// a list.
//
// Apply validates the existing file first and refuses it, with one line and
// the file untouched, unless every problem is a fixable value on a key being
// written or a key outside the schema. It refuses a key outside the schema or
// a key given twice on the command line. It splits the file on its own line
// ending (a file mixing CRLF and LF is refused), writes each key over its own
// line or appends it, and validates the result.
//
// checkFile() refuses a root that is $HOME or an ancestor of it, a directory on
// the way to a target (the home's segments) that is a symlink, not a
// directory, or resolves outside the root, and a target (the settings file, the
// index, .gitignore, the instruction file) that is a symlink, not a regular
// file, or has more than one link. It runs before reading, before each mkdir,
// before the temp file opens and before the rename. Each write goes to a temp
// file opened with O_EXCL|O_NOFOLLOW beside the target, renamed over it once the
// target still holds what was read.
//
// Every refusal is one line on stderr with no stack trace, and a failure
// removes only a temp file this run created. Printed text escapes control
// characters as \xNN, and a command-line value holding one, or U+2028 or
// U+2029, is refused.
//
// Exit codes: 0 written, already configured, or --check found a valid or
// absent file; 1 refused (an invalid value or key, an invalid existing file,
// an unsafe path, a broken pointer region, a failed read or write), or --check
// found a problem; 2 usage or environment error; 3 a write needs the
// operator's confirmation and --yes was not given (the diff or the offer is on
// stdout).

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
// printable(s) escapes C0 (except a line break), DEL and C1 control
// characters as \xNN, so text from a file never reaches the terminal raw.
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

function parseArgs(argv, withRef) {
  const opts = { root: "", yes: false, check: false, ref: null, home: null, decline: false, pairs: [] };
  const usage = `usage: setup-apply.mjs [--root <dir>] [--yes] [--home <dir>] <key>=<value> ... | --decline | --check${withRef ? " [--ref <ref>]" : ""}`;
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--root") {
      if (i + 1 >= argv.length) refuse("--root needs a directory", 2);
      opts.root = argv[++i];
    } else if (a === "--home") {
      if (i + 1 >= argv.length) refuse("--home needs a repo-relative directory", 2);
      opts.home = argv[++i];
    } else if (a === "--decline") opts.decline = true;
    else if (withRef && a === "--ref") {
      if (i + 1 >= argv.length) refuse("--ref needs a commit id or origin/<name>", 2);
      opts.ref = argv[++i];
    } else if (a === "--yes") opts.yes = true;
    else if (a === "--check") opts.check = true;
    else if (/^[^=-][^=]*=/.test(a)) opts.pairs.push(a);
    else refuse(`unexpected argument: ${a}; ${usage}`, 2);
  }
  if (opts.check && opts.pairs.length) refuse("--check takes no <key>=<value> arguments", 2);
  if (opts.decline && (opts.check || opts.pairs.length || opts.home !== null)) {
    refuse("--decline takes no <key>=<value> arguments, --home or --check", 2);
  }
  if (opts.home !== null && opts.check) refuse("--home is a write option; --check reads the bound home", 2);
  if (opts.ref !== null && !opts.check) refuse("--ref is a --check option; a write always targets the working tree", 2);
  // Only a full commit id or origin/<name>: nothing git could read as an
  // option, a revision range, a path or a reflog expression.
  const r = opts.ref;
  if (r !== null && !(/^[0-9a-f]{40}$/.test(r) || (/^origin\/[A-Za-z0-9._/-]+$/.test(r) && !r.includes("..") && !r.startsWith("origin/-")))) {
    refuse(`invalid --ref ${JSON.stringify(r)}; expected a 40-hex commit id or origin/<name>`, 2);
  }
  if (!opts.check && !opts.pairs.length && !opts.decline) refuse("nothing to write; pass at least one <key>=<value>", 2);
  return opts;
}

// allowedText(spec) words a key's allowed values for a message, or is null for
// a schema shape this checker does not validate; allows(spec, raw, value)
// tests one scalar as written, quotes included, with value its parsed string.
// A quoted boolean or number is a string, so it is not allowed; a quoted
// listed string is; a plain true or 5 is not a string.
const isObject = (spec) => spec.type === "object";
const isNull = (raw) => /^(null|Null|NULL|~)$/.test(raw);
const plainNonString = (raw) =>
  isNull(raw) ||
  /^(true|True|TRUE|false|False|FALSE|[-+]?(\.[0-9]+|[0-9]+(\.[0-9]*)?)([eE][-+]?[0-9]+)?|0x[0-9a-fA-F]+|0o[0-7]+|[-+]?\.(inf|Inf|INF)|\.(nan|NaN|NAN))$/.test(raw);
// patternOf(spec) is spec.pattern compiled once with the u flag, or null when
// it does not compile; such a key is unchecked.
const compiled = new WeakMap();
function patternOf(spec) {
  if (!compiled.has(spec)) {
    let re = null;
    try {
      re = new RegExp(spec.pattern, "u");
    } catch {
      // Left null: the key is reported as unchecked.
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
  return null;
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

// written(spec, value) is a command-line value as it goes in the file: a
// string whose plain form would not read back as given is double-quoted.
function written(spec, value) {
  if (spec.type !== "string" || Array.isArray(spec.enum)) return value;
  return /^[A-Za-z0-9_./-]+$/.test(value) && !plainNonString(value) ? value : JSON.stringify(value);
}

// blockTree(text) is the document's key lines as a tree by indentation:
// { raw, keys, dup, list } per key, raw its value as written (comment and
// surrounding space removed), keys its child keys by trimmed name (the first
// of each), dup the child names set more than once, and list true when a
// sequence item sits under it or at its own indent. Lines under a sequence
// item are not read.
const contentLine = (line) => {
  const t = trimWs(line);
  return t !== "" && t[0] !== "#" && !/^(---|\.\.\.|%)/.test(line);
};
function blockTree(text) {
  const node = (raw) => ({ raw, keys: new Map(), dup: new Set(), list: false });
  const root = node("");
  // Each entry is a key line (at its node), or a skipped line (at null), with
  // seq the node whose sequence it is an item of.
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

// checkValue reports each problem with the value at path against spec through
// report(msg, fixable), recursing into an object's keys. valueAt(path) is the
// parsed string at a dotted path, "" when none.
function checkValue(path, spec, node, valueAt, report) {
  const values = allowedText(spec);
  const { raw } = node;
  if (values === null) {
    const shape = badPattern(spec) ? `pattern ${spec.pattern} does not compile as a JavaScript u-flag regular expression` : `type ${spec.type ?? "unset"}`;
    report(`${path} uses a schema shape setup-apply does not check (${shape}); edit it by hand`);
    return;
  }
  if (isObject(spec)) {
    if (node.list || raw.startsWith("[")) report(`${path} holds a list; it takes ${values}`);
    else if (raw.startsWith("{")) report(`${path} is a flow map; it takes ${values}, one key per line`);
    else if (isNull(raw)) report(`${path} is null; it takes ${values}`);
    else if (raw !== "") report(`${path}=${raw} is not a map; it takes ${values}`);
    else if (!node.keys.size) report(`${path} is empty; it takes ${values}`);
    else {
      for (const k of node.dup) report(`${path}.${k} is set more than once`);
      for (const [k, child] of node.keys) {
        const sub = Object.hasOwn(spec.properties ?? {}, k) ? spec.properties[k] : (spec.additionalProperties ?? true);
        if (sub === false) report(`${path}.${k} is not in the schema`);
        else if (sub !== true) checkValue(`${path}.${k}`, sub, child, valueAt, report);
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

// Top-level keys as written, from lines at the document's base indent, each
// with its line index, the key as written, its trimmed form and its raw value
// (comment and surrounding space removed). The flattened parser output cannot
// show a key set twice, an empty value, a quoted value or an empty flow
// collection, so these checks read the lines. Line indexes count LF breaks, so
// they match a split on the file's own line ending.
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

// Whitespace is a space or a tab, as yaml-subset.awk reads it. The scans below
// run in one pass each, because the regexes they stand for backtrack
// quadratically on a long run of whitespace.
const isWs = (c) => c === " " || c === "\t";
function trimWs(s) {
  let a = 0;
  let b = s.length;
  while (a < b && isWs(s[a])) a++;
  while (b > a && isWs(s[b - 1])) b--;
  return s.slice(a, b);
}
const indentOf = (line) => line.length - line.replace(/^ +/, "").length;

// quotedKey(s) scans the quoted key opening s, the way yaml-subset.awk's qscan
// does: `''` inside single quotes is one quote; inside double quotes `\"`,
// `\\`, `\/` and `\t` are unescaped and any other `\x` is kept as written.
// Returns { value, end } with end the index after the closing quote, or null
// when the quote is unclosed.
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

// splitKeyLine(s) splits one trimmed line into { written, rest }: a quoted key
// (unescaped as above), else a bare key with no quote or colon, then optional
// space, a colon, and either the end or space and the rest of the line. null
// when s is not such a line.
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

// stripComment(rest) is rest.replace(/^#.*$|[ \t]+#.*$/, ""): a rest
// splitKeyLine returned starts after the colon's space, so a leading `#` is a
// comment too; otherwise cut at the first run of space followed by `#`.
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

// flatten(text, parser) is the parser's records, { path, top, nested, value }
// per scalar, or { error } with the parse error's message.
function flatten(text, parser) {
  const parsed = spawnSync("awk", ["-f", parser], {
    input: text,
    encoding: "utf8",
    env: { ...process.env, LC_ALL: "C" },
  });
  if (parsed.error) refuse(`cannot run awk: ${why(parsed.error)}`, 2);
  if (parsed.status !== 0) {
    const err = (parsed.stdout ?? "").split("\n").find((l) => l.startsWith("error\t")) ?? "error\t?\tunreadable";
    const [, line, msg] = err.split("\t");
    return { error: `line ${line}: ${msg}` };
  }
  return {
    records: parsed.stdout
      .split("\n")
      .filter(Boolean)
      .map((r) => {
        const path = r.slice(0, r.indexOf("\t"));
        const dot = path.indexOf(".");
        return { path, top: trimWs(dot === -1 ? path : path.slice(0, dot)), nested: dot !== -1, value: r.slice(r.indexOf("\t") + 1) };
      }),
  };
}

// unread(records, tree) is each record path the line reader did not reach: the
// two readers disagree there, so nothing about that key can be trusted. A walk
// stops at a list or a flow collection, which the line reader reports itself.
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

// Validate a whole document. Returns problems as { kind, key, msg, fixable };
// [] means valid. kind is "parse" (the file does not parse), "file" (another
// problem with the whole file), "unknown" (a key outside the schema, ignored)
// or "value" (a problem on the schema key named by key). fixable marks a value
// apply may overwrite.
function validate(text, { keys, parser, exactKeyNames = false, schemaKey = false }) {
  const parsed = flatten(text, parser);
  if (parsed.error) return [{ kind: "parse", key: null, msg: parsed.error, fixable: false }];
  const { records } = parsed;
  const parsedValues = new Map(records.map((r) => [r.path, r.value]));
  const valueAt = (path) => parsedValues.get(path) ?? "";
  const tree = blockTree(text);
  const tops = topLevelLines(text);
  const problems = [];
  const add = (kind, msg, key = null, fixable = false) => problems.push({ kind, key, msg, fixable });
  const known = (k) => k === "$schema" || Object.hasOwn(keys, k);
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
    // Apply writes only a top-level scalar, so only a problem there is fixable.
    checkValue(k, spec, node, valueAt, (msg, fixable = false) => add("value", msg, k, fixable && !isObject(spec)));
  }
  for (const path of unread(records, tree)) {
    const top = trimWs(path.split(".")[0]);
    const own = Object.hasOwn(keys, top);
    add(own ? "value" : "file", `${path} is read differently by the YAML parser; check its quoting and indentation`, own ? top : null);
  }
  // Apply never writes $schema, so a bad value there is a problem with the file.
  const schemaLine = schemaKey && tops.find((t) => t.key === "$schema");
  if (schemaLine) {
    const scalar = records.find((r) => r.top === "$schema" && !r.nested);
    if (records.some((r) => r.top === "$schema" && r.nested) || /^[[{]/.test(schemaLine.raw)) {
      add("file", "$schema holds a map or a list; it takes one schema URL string");
    } else if (!scalar || scalar.value === "" || /^(~|null|Null|NULL)$/.test(schemaLine.raw)) {
      add("file", "$schema is empty or null; it takes one schema URL string");
    }
  }
  return [...new Map(problems.map((p) => [p.msg, p])).values()];
}

// --check reports. Each prints a WARN per problem and returns the exit code.
// perKeyReport, the default, then prints a PASS per key with no problem of its
// own, unless the whole file has one. wholeFileReport prints PASS lines only
// when the sole problems are keys outside the schema.
export function perKeyReport({ rel, keys, problems, value }) {
  process.stdout.write(printable(problems.map((p) => `WARN ${rel}: ${p.msg}\n`).join("")));
  if (problems.some((p) => p.kind === "parse" || p.kind === "file")) return 1;
  for (const k of Object.keys(keys)) {
    if (problems.some((p) => p.key === k)) continue;
    process.stdout.write(printable(`PASS ${k}: ${value(k) ?? "(unset)"}\n`));
  }
  return problems.length ? 1 : 0;
}
export function wholeFileReport({ rel, keys, problems, value }) {
  process.stdout.write(printable(problems.map((p) => `WARN ${rel}: ${p.msg}\n`).join("")));
  if (problems.some((p) => p.kind !== "unknown")) return 1;
  for (const k of Object.keys(keys)) process.stdout.write(printable(`PASS ${k}: ${value(k) ?? "(unset)"}\n`));
  return problems.length ? 1 : 0;
}

// run(config) is the whole command. config: plugin (the concern name), schema,
// reader and parser (absolute paths), and optionally ref (enable --ref),
// exactKeyNames (refuse a quoted key with spaces around its name), schemaKey
// (require $schema to hold one string), fixedTemp (a temp name without the
// process id) and report (a --check printer over validate()'s result that
// returns the exit code). The process exits with run's code.
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
  // The convention home and the settings file in it. The defaults hold until
  // the pointer region is read, below.
  let home = DEFAULT_HOME;
  let rel = `${home}/${name}`;
  const opts = parseArgs(argv, Boolean(config.ref));

  let root = opts.root;
  if (!root) {
    const git = spawnSync("git", ["rev-parse", "--show-toplevel"], { encoding: "utf8" });
    if (git.status !== 0) refuse("not inside a git working tree; pass --root <dir>", 2);
    root = git.stdout.trim();
  }
  // A symlinked root is the operator's choice of repository, so it is resolved
  // once here and every check below applies to the resolved directory.
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
  const keys = Object.fromEntries(Object.entries(schema.properties).filter(([k]) => k !== "$schema"));
  const check = (text) => validate(text, { keys, parser: config.parser, exactKeyNames: config.exactKeyNames, schemaKey: config.schemaKey });

  const checkRoot = () => {
    const realRoot = real(root, "root");
    const userHome = process.env.HOME || homedir();
    if (userHome) {
      let realHome = userHome;
      try {
        realHome = realpathSync(userHome);
      } catch {
        // An unresolvable home is compared as given.
      }
      if (realHome === realRoot || realHome.startsWith(realRoot.endsWith(sep) ? realRoot : realRoot + sep)) {
        refuse(`the root ${root} is $HOME or an ancestor of it, not a repository; nothing written`);
      }
    }
    return realRoot;
  };

  // The directories on the way to relPath: "a/b/c.yaml" gives "a", "a/b".
  const dirPrefixes = (relPath) => {
    const segments = relPath.split("/").slice(0, -1);
    return segments.map((_, i) => segments.slice(0, i + 1).join("/"));
  };

  // Refuse any path shape that could send a write somewhere other than
  // <root>/<relPath>. Returns true when the target exists.
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

  const readFile = (relPath) => {
    if (!checkFile(relPath)) return null;
    try {
      return readFileSync(join(root, relPath), "utf8");
    } catch (e) {
      refuse(`${relPath}: could not read it (${why(e)}); nothing written`);
    }
  };
  const readTarget = () => readFile(rel);

  // expected is the file as read at the start (null when absent); a target
  // that no longer matches it is refused rather than overwritten.
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
      // close(2) releases the descriptor even when it reports an error, so it
      // is marked closed before the call and never closed a second time.
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

  // The commit --ref names, as a 40-hex id. Every git argument is the
  // validated ref, a resolved object id or a fixed string, passed without a
  // shell.
  const git = (...a) => spawnSync("git", ["-C", root, ...a], { encoding: "utf8" });
  const resolveRef = () => {
    checkRoot();
    const ref = opts.ref;
    // origin/<name> is read only from refs/remotes/origin/<name>, matched
    // exactly by show-ref. rev-parse would apply its short-name lookup, where a
    // local branch, a tag or a refs/... look-alike can win or stand in for it.
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

  // The file as committed at sha: { sha, text }, text null when the commit
  // has no such path.
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

  // The convention home, from the pointer region (lib/resolve-convention-home.sh).
  // The resolver reads the committed files when given a commit, else the
  // working tree. Its stdout is the home; its exit code is the state.
  const resolver = config.resolver ?? join(dirname(fileURLToPath(import.meta.url)), "resolve-convention-home.sh");
  const runResolver = (args, input) => {
    if (!lstatOrNull(resolver, "the convention-home resolver")) {
      refuse(`the convention-home resolver ${resolver} is missing; nothing written`, 2);
    }
    const r = spawnSync("bash", [resolver, ...args], { input, encoding: "utf8" });
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
    // The grammar is the resolver's: the home goes in as a region on stdin.
    const asked = /[`\r\n]/.test(opts.home) ? { status: 1, out: "" } : runResolver(["-"], `${REGION_BEGIN}\n\`${opts.home}\`\n${REGION_END}\n`);
    if (asked.status !== 0) refuse(`--home ${JSON.stringify(opts.home)} is not a repo-relative directory of [A-Za-z0-9._-] segments`, 2);
    if (state === "unbound") home = asked.out;
    else if (asked.out !== home) refuse(`--home ${asked.out} differs from the ${state === "bound" ? "bound" : "default"} home ${home}; nothing written`, 2);
  }
  rel = `${home}/${name}`;
  // A home other than the default, bound by the pointer or chosen with --home,
  // is one the repository already had: our file is listed in an index there.
  const indexRel = (state === "bound" || opts.home !== null) && home !== DEFAULT_HOME ? `${home}/${INDEX_NAME}` : null;

  // The pointer region and the overlay ignore line, planned before anything is
  // written: { file, existing, proposed } per file, proposed null for no change.
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
    // A symlinked instruction file is read through (the resolver counts a link
    // to the other file as one file) and is refused only when it is the file
    // to write.
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
    // The file the repository already keeps instructions in: AGENTS.md first,
    // then CLAUDE.md unless it only imports AGENTS.md; AGENTS.md is created
    // only when neither exists. A link is followed to the real file beside it.
    let chosen = present.find((f) => f.file === "AGENTS.md") ?? present.find((f) => !isShim(f.text)) ?? { file: "AGENTS.md", text: null };
    if (chosen.link) chosen = present.find((f) => !f.link && f.real === chosen.real) ?? chosen;
    // Refused here, before any write, so a refusal never leaves a half-set-up repository.
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

  // Command-line pairs are checked before the file is read, so a bad request
  // is refused the same way whether the file exists or not.
  const wanted = new Map();
  for (const pair of opts.pairs) {
    const eq = pair.indexOf("=");
    const k = pair.slice(0, eq).trim();
    const v = pair.slice(eq + 1);
    if (wanted.has(k)) refuse(`${k} is given more than once; pass each key once; nothing written`);
    if (!Object.hasOwn(keys, k)) refuse(`${k} is not a key of ${rel} (keys: ${Object.keys(keys).join(", ")}); nothing written`);
    const spec = keys[k];
    const values = allowedText(spec);
    if (values === null || isObject(spec)) {
      refuse(`${k} takes ${values ?? "a value setup-apply does not check"} and is not set from the command line; edit ${rel} by hand; nothing written`);
    }
    const control = [...v].some((c) => {
      const n = c.codePointAt(0);
      return n < 0x20 || (n >= 0x7f && n <= 0x9f) || n === 0x2028 || n === 0x2029;
    });
    if (control) refuse(`${k}: the value holds a control character or a line or paragraph separator; nothing written`);
    const w = written(spec, v);
    if (/^["']/.test(v) || !allows(spec, w, v)) refuse(`${k}=${v} is not ${values}; nothing written`);
    wanted.set(k, { written: w, value: v });
  }

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

  if (opts.check) {
    if (existing === null) {
      process.stdout.write(`INFO ${rel}: absent; every key resolves from userConfig or its default\n`);
      return 0;
    }
    // An object key shows its leaves as path=value, from the parser's records.
    const leaves = (k) =>
      (flatten(existing, config.parser).records ?? [])
        .filter((r) => r.top === k && r.nested)
        .map((r) => `${r.path.slice(r.path.indexOf(".") + 1)}=${r.value}`)
        .join(", ");
    // null for an absent key. A set value that is empty or has space at either
    // end, which the reader trims, shows quoted as written.
    const present = new Set(topLevelLines(existing).map((t) => t.key));
    const scalars = new Map((flatten(existing, config.parser).records ?? []).filter((r) => !r.nested).map((r) => [r.top, r.value]));
    const value = (k) => {
      if (!present.has(k)) return null;
      if (isObject(keys[k])) return leaves(k);
      const parsed = scalars.get(k) ?? "";
      if (parsed === "" || parsed.trim() !== parsed) return JSON.stringify(parsed);
      return spawnSync("bash", [config.reader, "-", k], { input: existing, encoding: "utf8" }).stdout.trim();
    };
    return (config.report ?? perKeyReport)({ rel, keys, problems: check(existing), value });
  }

  if (existing !== null) {
    const found = check(existing);
    const blocking = found.filter((p) => p.kind !== "unknown" && !(p.fixable && wanted.has(p.key)));
    if (blocking.length) refuse(`${rel}: ${blocking.map((p) => p.msg).join("; ")}; fix the file by hand, nothing written`);
    for (const p of found.filter((p) => p.kind === "unknown")) {
      process.stderr.write(printable(`setup-apply: WARN ${rel}: ${p.msg}; it is ignored and its line is kept as written\n`));
    }
  }

  let proposed;
  if (existing === null) {
    proposed = `# yaml-language-server: $schema=${schema.$id}\n${[...wanted].map(([k, { written: w }]) => `${k}: ${w}\n`).join("")}`;
  } else {
    // Keep the file's line ending: CRLF when every line break is CRLF.
    const crlf = (existing.match(/\r\n/g) ?? []).length;
    if (crlf && crlf !== (existing.match(/\n/g) ?? []).length) {
      refuse(`${rel} mixes CRLF and LF line endings; make them one kind first; nothing written`);
    }
    const eol = crlf ? "\r\n" : "\n";
    const lines = existing.split(eol);
    if (lines.at(-1) === "") lines.pop();
    const tops = topLevelLines(existing);
    for (const [k, { written: w }] of wanted) {
      const line = tops.find((t) => t.key === k);
      if (line) lines[line.at] = `${lines[line.at].match(/^\s*/)[0]}${k}: ${w}`;
      else lines.push(`${k}: ${w}`);
    }
    proposed = `${lines.join(eol)}${eol}`;
  }

  const problems = check(proposed).filter((p) => p.kind !== "unknown");
  if (problems.length) refuse(`the result would not validate: ${problems.map((p) => p.msg).join("; ")}; nothing written`);
  const readBack = new Map((flatten(proposed, config.parser).records ?? []).filter((r) => !r.nested).map((r) => [r.top, r.value]));
  for (const [k, { value }] of wanted) {
    if ((readBack.get(k) ?? "") !== value) refuse(`${k}=${value} would not read back as given; nothing written`);
  }

  const changes = existing === null || proposed !== existing;

  // The index of a home the repository already had lists our file. Creating it
  // needs no confirmation; changing an index that exists does.
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

  // An unbound repository is offered the pointer region and the overlay ignore
  // line, written in the same step as the file.
  const offer = state === "unbound" ? { region: planRegion(regionLines(true)), ignore: planIgnore() } : null;

  if (!changes && index === null && offer === null) {
    process.stdout.write(`${rel}: already configured; nothing written\n`);
    return 0;
  }

  if (!opts.yes && ((existing !== null && changes) || offer !== null || (index !== null && index.existing !== null))) {
    if (existing !== null && changes) {
      const diff = spawnSync("diff", ["-u", "--label", `a/${rel}`, "--label", `b/${rel}`, join(root, rel), "-"], {
        input: proposed,
        encoding: "utf8",
      });
      process.stdout.write(printable(diff.stdout));
      process.stdout.write(`${rel} exists and would change; nothing written. Show this diff, and re-run with --yes once the operator confirms.\n`);
    }
    if (index !== null && index.existing !== null) {
      process.stdout.write(`${indexRel} exists and would list ${name}; nothing written. Re-run with --yes once the operator confirms.\n`);
    }
    if (offer !== null) {
      const { region, ignore } = offer;
      process.stdout.write(
        printable(
          [
            `No convention home is bound in this repository. With the operator's confirmation, setup will:`,
            `  - write ${rel} (the home is created if missing)`,
            `  - add a convention-home region naming \`${home}\` to ${region.file}${region.existing === null ? " (created: neither AGENTS.md nor CLAUDE.md exists)" : ""}`,
            ignore.proposed === null
              ? `  - leave .gitignore as it is (it already holds ${ignore.line})`
              : `  - add the overlay ignore line ${ignore.line} to .gitignore so personal <concern>.local.* files stay untracked`,
            `Nothing is always-loaded: the region is one pointer line. Nothing was written. Re-run with --yes once the operator confirms,`,
            `with --home <dir> to name a different home, or with --decline to record that this repository declines a home.`,
            "",
          ].join("\n"),
        ),
      );
    }
    return 3;
  }

  if (changes) {
    writeFile(rel, proposed, existing);
    process.stdout.write(printable(`wrote ${rel}\n${proposed}`));
  } else {
    process.stdout.write(`${rel}: already configured\n`);
  }
  if (index !== null) {
    writeFile(indexRel, index.proposed, index.existing);
    process.stdout.write(`wrote ${indexRel}: listed ${name}\n`);
  }
  if (offer !== null) {
    // The ignore line goes in before the pointer, so no repository ever binds a
    // home without ignoring its personal overlay.
    const { region, ignore } = offer;
    if (ignore.proposed !== null) {
      writeFile(".gitignore", ignore.proposed, ignore.existing);
      process.stdout.write(printable(`wrote .gitignore: added ${ignore.line} (personal overlay files stay untracked)\n`));
    }
    writeFile(region.file, region.proposed, region.existing);
    process.stdout.write(printable(`wrote ${region.file}: added a convention-home region naming \`${home}\`\n`));
  }
  return 0;
}
