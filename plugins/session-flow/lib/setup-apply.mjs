// GENERATED from lib/setup-apply.mjs by scripts/sync-shared-copies.sh. Do not edit this copy:
// edit the canonical source, then rerun the script.
// Write or check a plugin's repository settings file,
// <home>/<plugin>.yaml, against the plugin's JSON Schema. <home> is the
// repository's convention home (see "Convention home" below). Each plugin's
// skills/setup/scripts/setup-apply.mjs is a thin entry point that calls run()
// with its own paths.
//
// Usage of an entry point:
//   setup-apply.mjs [--root <dir>] [--yes] [--home <dir>] [--default <key>] ... <key>=<value> ...
//   setup-apply.mjs [--root <dir>] --decline
//   setup-apply.mjs [--root <dir>] --state
//   setup-apply.mjs [--root <dir>] --check [--ref <ref>]
//
//   --root <dir>  repository root; default: git's toplevel for the current
//                 directory. A symlinked root is resolved first, and every
//                 check below applies to the resolved directory.
//   --yes         the operator has seen the diff or the offer and confirmed it;
//                 needed to change a file that already exists, to write a
//                 pointer region and the overlay ignore line into a repository
//                 that has none, and to write into a --home no pointer names.
//                 A missing settings file is created without it.
//   --home <dir>  the convention home to offer when the repository binds none:
//                 a repo-relative directory by the resolver's grammar. The
//                 default is docs/conventions. Finding an equivalent home the
//                 repository already has is the setup skill's interview; the
//                 chosen home arrives here. A bound repository keeps its home,
//                 so a different --home is refused.
//   --default <key>  only where the plugin records provenance: write <key> at
//                 the plugin's current schema default and mark it default.
//                 Repeatable; a key given here may not also be a <key>=<value>.
//   --decline     record that the repository declines a convention home: a
//                 region holding a `declined` line, so the next run does not
//                 offer again and writes <plugin>.yaml under docs/conventions.
//   --state       print the repository's state (see "States" below) as one
//                 line, `<state> <path>`, the path its evidence; write nothing.
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
//   unbound       no region: the offer. Without --yes the offer is printed and
//                 only a missing docs/conventions/<plugin>.yaml is written
//                 (exit 0); with a different --home nothing is written (exit
//                 3), since the file would sit where no pointer names it. With
//                 --yes the writer creates
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
// Provenance (docs/contracts/setup-lifecycle/README.md "Provenance"). An entry
// point that passes provenance: true records two top-level keys beside the
// settings, whose values stay flat where they are. Its schema must declare both,
// beside $schema, and neither is a setting: no PASS line, no <key>=<value>:
//   written_against: <plugin>@<version>   the version from the plugin's
//                 manifest (config.manifest, default
//                 <schema dir>/../.claude-plugin/plugin.json), set at each write
//   provenance:   a block map, one entry per scalar schema key in the file:
//                 `<key>: default` for a value filled at the plugin default,
//                 `<key>: chosen (default <d>)` for one the operator set or
//                 confirmed, <d> the plugin default at written_against, or
//                 `<key>: chosen` when the key has no default.
// A key given as <key>=<value> is chosen; a --default key is default; any
// other key keeps its entry, and a key without one is chosen. When
// written_against names another version, --check prints an INFO line for each
// default value that differs from the plugin default now (a hand edit of it
// looks the same) and a WARN line, with the old and new default, for each
// chosen value whose recorded default differs; a write sets each such default
// value to the plugin default, prints the change, keeps each chosen value and
// prints the same WARN. A file with no provenance key is read with every value
// chosen and one INFO line. The writer rewrites the provenance block whole,
// and appends either key, at the document's base indent, where it is absent.
// validate() accepts both keys for every entry point: written_against must be a
// scalar, each provenance entry one of the forms above (an entry for a key
// outside the schema is a warning, and a write that records provenance drops
// it).
//
// States (docs/contracts/setup-lifecycle/README.md "Converge-by-state apply").
// A write acts on the state it finds:
//   init          no <home>/<plugin>.yaml and no retired file: the file is
//                 created from the <key>=<value> and --default arguments.
//   migrate       the retired file is present: the active migrate record of
//                 kind file that the entry point names (config.retired, a
//                 record id in config.retirements, default <schema
//                 dir>/../retirements.yaml) finds a regular file at its path
//                 whose content matches any content_match. Its top-level
//                 scalars (a JSON object for a .json path, else the YAML
//                 subset) are carried into <plugin>.yaml with each one's
//                 provenance entry, a value without one as chosen, under the
//                 provenance rules against the retired file's written_against
//                 (a stale default value is carried at the new default). A key the
//                 command line or <plugin>.yaml already sets keeps that value:
//                 the new location wins, and a run that finds both files warns,
//                 naming both. Each value not carried (a key outside the schema,
//                 a value it does not allow, an empty key, a map or a list, or
//                 one the new location sets differently) is printed, and the
//                 retired file is left in place; with none, the retired file is
//                 removed after the write. Carrying a value or removing the
//                 file needs --yes; without it the plan is printed (exit 3). An
//                 entry point without config.retired never migrates.
//   configure     <plugin>.yaml exists: each key given is written over its
//                 line or appended.
// Only migrate runs with no <key>=<value> or --default (exit 2 elsewhere). A
// second run with the same inputs writes nothing.
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
import { parse, YamlSubsetError } from "./yaml-subset.mjs";

// This file's directory: the working directory of every child process, so a
// same-named executable in the caller's directory is never the one run.
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
  // Only a full commit id or origin/<name>: nothing git could read as an
  // option, a revision range, a path or a reflog expression.
  const r = opts.ref;
  if (r !== null && !(/^[0-9a-f]{40}$/.test(r) || (/^origin\/[A-Za-z0-9._/-]+$/.test(r) && !r.includes("..") && !r.startsWith("origin/-")))) {
    refuse(`invalid --ref ${JSON.stringify(r)}; expected a 40-hex commit id or origin/<name>`, 2);
  }
  if (opts.state && (opts.yes || opts.check || opts.decline || opts.ref !== null || opts.home !== null || opts.pairs.length || opts.defaults.length)) {
    refuse("--state takes only --root; it writes nothing", 2);
  }
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

// The two top-level keys an entry point that records provenance writes beside
// the settings (see "Provenance" above).
const AGAINST = "written_against";
const PROVENANCE = "provenance";
// defaultText(spec) is a scalar key's schema default as the file reads it, or
// null when the key has none.
const defaultText = (spec) => (["string", "number", "boolean"].includes(typeof spec.default) ? String(spec.default) : null);
// parseSource(value) reads one provenance entry: { source, seen }, seen the
// default a chosen value was written against (null when not recorded), or
// null when the entry is none of the three forms.
function parseSource(value) {
  if (value === "default") return { source: "default", seen: null };
  const m = /^chosen(?: \(default (.*)\))?$/.exec(value);
  return m ? { source: "chosen", seen: m[1] ?? null } : null;
}
// sourceText(source, seen) is a provenance entry as it goes in the file,
// double-quoted when its plain form would not read back as given.
function sourceText(source, seen) {
  const text = source === "chosen" && seen !== null ? `chosen (default ${seen})` : source;
  return /^[a-z]+(?: \(default [A-Za-z0-9_./@+-]+\))?$/.test(text) ? text : JSON.stringify(text);
}

// retirementRecords(text) reads a retirements.yaml manifest by its flat
// grammar (docs/contracts/retired-conventions/README.md "Grammar"): records
// split on a line that is exactly ---, each line `key: value` with one layer
// of quotes stripped.
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
// safeRecordPath(p): a record path the manifest grammar allows, relative with
// no `.`, `..` or empty segment, no leading ~, backslash or control character.
const safeRecordPath = (p) =>
  typeof p === "string" && p !== "" && !/^[/~]|[\\\x00-\x1f\x7f]/.test(p) && p.split("/").every((s) => s !== "" && s !== "." && s !== "..");

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
// `\\`, `\/` and `\t` are unescaped and any other `\x` is kept as written (in
// a file the parser accepted, that is only `\n`).
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

// flatten(text) is yaml-subset.mjs's records, { path, top, nested, value } per
// scalar in document order, as yaml-subset.awk prints them: the path dotted
// with sequence indexes, the value its source text, and nothing for an empty
// value, an empty list or a key with nothing under it. A parse error gives
// { error } with its message.
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
function validate(text, { keys, exactKeyNames = false, schemaKey = false, recording = false }) {
  const parsed = flatten(text);
  if (parsed.error) return [{ kind: "parse", key: null, msg: parsed.error, fixable: false }];
  const { records } = parsed;
  const parsedValues = new Map(records.map((r) => [r.path, r.value]));
  const valueAt = (path) => parsedValues.get(path) ?? "";
  const tree = blockTree(text);
  const tops = topLevelLines(text);
  const problems = [];
  const add = (kind, msg, key = null, fixable = false) => problems.push({ kind, key, msg, fixable });
  const known = (k) => k === "$schema" || k === AGAINST || k === PROVENANCE || Object.hasOwn(keys, k);
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
  // The provenance keys: one version string, and a block map of one entry per
  // schema key. An entry for a key the schema no longer has is a warning. A
  // scalar shape is a warning too where the entry point does not record
  // provenance, as for any key outside the schema.
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

// run(config) is the whole command. config: plugin (the concern name), schema
// and reader (absolute paths), and optionally ref (enable --ref),
// exactKeyNames (refuse a quoted key with spaces around its name), schemaKey
// (require $schema to hold one string), fixedTemp (a temp name without the
// process id), report (a --check printer over validate()'s result that
// returns the exit code), provenance (record written_against and provenance),
// manifest (the plugin.json provenance reads the version from), retired (the
// id of the retirements.yaml record whose file migrate carries from) and
// retirements (that manifest's path). The process exits with run's code.
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
  const opts = parseArgs(argv, Boolean(config.ref), Boolean(config.provenance));

  let root = opts.root;
  if (!root) {
    const git = spawnSync("git", ["-C", process.cwd(), "rev-parse", "--show-toplevel"], { cwd: HERE, encoding: "utf8" });
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
  const keys = Object.fromEntries(Object.entries(schema.properties).filter(([k]) => !["$schema", AGAINST, PROVENANCE].includes(k)));
  const check = (text) => validate(text, { keys, exactKeyNames: config.exactKeyNames, schemaKey: config.schemaKey, recording: Boolean(config.provenance) });

  // <plugin>@<version> when the entry point records provenance, else null.
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

  // What a file records: the version it was written against (null when
  // absent), its provenance entries by key, and whether it has a provenance
  // key at all.
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
  // Once the file names another version: stale, each default value that
  // differs from the plugin default now, which the writer sets to it (a hand
  // edit of such a value looks the same); moved, each chosen value whose
  // recorded default differs from it, which the writer keeps. Nothing is
  // stale or moved while the file names this version.
  const drift = (text, rec) => {
    const out = { stale: [], moved: [] };
    if (rec.against === against) return out;
    const scalars = new Map((flatten(text).records ?? []).filter((r) => !r.nested).map((r) => [r.top, r.value]));
    for (const [k, spec] of Object.entries(keys)) {
      const now = defaultText(spec);
      if (now === null || isObject(spec) || !scalars.has(k)) continue;
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

  // Whether relPath is the shape checkFile accepts, tested without refusing:
  // each parent a real directory, the path a regular file with one link.
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

  // The retired settings file the entry point's record names, as
  // { path, text } when it is present and the record is active, else null.
  // Its detection is check-retirements.sh's for kind file: a regular file at
  // the path whose content matches any content_match.
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
    // Detection is read-only: anything but a plain regular file reached
    // through real directories reads as absent, never as checkFile's refusal,
    // so a symlinked .claude stops neither --state nor a settings write.
    if (!plainFile(record.path)) return null;
    const text = readFile(record.path);
    if (text === null) return null;
    if (record.content_match !== undefined) {
      // As check-retirements.sh reads it: each line's trailing CR stripped.
      const grep = spawnSync("grep", ["-Eq", "-e", record.content_match], { cwd: HERE, input: text.replace(/\r$/gm, ""), encoding: "utf8" });
      if (grep.error || grep.status > 1) refuse(`record ${config.retired}: grep could not apply its content_match`, 2);
      if (grep.status !== 0) return null;
    }
    return { path: record.path, text };
  };

  // The values in the retired file: top-level scalars of a .json object, else
  // of the YAML subset, with the provenance a YAML file records (rec, null for
  // JSON). bad names each key that holds something other than a scalar, or
  // nothing.
  const meta = new Set([AGAINST, PROVENANCE, "$schema"]);
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
        if (meta.has(k)) continue;
        if (["string", "number", "boolean"].includes(typeof v)) values.set(k, String(v));
        else bad.add(`${k} holds ${v === null ? "null" : "a map or a list"}`);
      }
    } else {
      const parsed = flatten(old.text);
      if (parsed.error) refuse(`${old.path}: ${parsed.error}; carry its values by hand; nothing written`);
      for (const r of parsed.records) {
        if (meta.has(r.top)) continue;
        if (r.nested) bad.add(`${r.top} holds a map or a list`);
        else values.set(r.top, r.value);
      }
      // A key the parser gives no record for holds nothing it could carry.
      for (const { key } of topLevelLines(old.text)) {
        if (!meta.has(key) && !parsed.records.some((r) => r.top === key)) bad.add(`${key} is empty`);
      }
      rec = recordedIn(old.text);
    }
    return { values, rec, bad: [...bad] };
  };

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
  const git = (...a) => spawnSync("git", ["-C", root, ...a], { cwd: HERE, encoding: "utf8" });
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
  // vet(k, v) checks one value given as a bare word, from the command line or
  // carried from a retired file: { written, value }, or { error } saying why it
  // cannot be written.
  const vet = (k, v) => {
    if (!Object.hasOwn(keys, k)) return { error: `${k} is not a key of ${rel} (keys: ${Object.keys(keys).join(", ")})` };
    const spec = keys[k];
    const values = allowedText(spec);
    if (values === null || isObject(spec)) {
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
  // --default keys: written at the plugin's current default, marked default.
  const defaulted = new Map();
  for (const k of opts.defaults) {
    if (wanted.has(k) || defaulted.has(k)) refuse(`${k} is given more than once; pass each key once; nothing written`);
    if (!Object.hasOwn(keys, k)) refuse(`${k} is not a key of ${rel} (keys: ${Object.keys(keys).join(", ")}); nothing written`);
    const spec = keys[k];
    const value = defaultText(spec);
    const w = value === null ? "" : written(spec, value);
    if (value === null || allowedText(spec) === null || isObject(spec) || !allows(spec, w, value)) {
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

  // The state the repository is in: migrate while the retired file is present,
  // else configure when the settings file exists, else init.
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
    // An object key shows its leaves as path=value, from the parser's records.
    const leaves = (k) =>
      (flatten(existing).records ?? [])
        .filter((r) => r.top === k && r.nested)
        .map((r) => `${r.path.slice(r.path.indexOf(".") + 1)}=${r.value}`)
        .join(", ");
    // null for an absent key. A set value that is empty or has space at either
    // end, which the reader trims, shows quoted as written.
    const present = new Set(topLevelLines(existing).map((t) => t.key));
    const scalars = new Map((flatten(existing).records ?? []).filter((r) => !r.nested).map((r) => [r.top, r.value]));
    const value = (k) => {
      if (!present.has(k)) return null;
      if (isObject(keys[k])) return leaves(k);
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

  // Migrate: each value in the retired file is carried into the settings file
  // with its provenance entry, unless the command line or the settings file
  // sets that key, which wins. A value not carried is named in kept, and the
  // retired file is removed only when kept is empty: every value in it is then
  // in the settings file as written.
  const carried = new Map();
  const kept = [];
  let carriedNotes = "";
  if (old !== null) {
    const { values, rec: oldRec, bad } = readOld(old);
    // A carried value follows the provenance rules against the version the
    // retired file was written against: a default value whose plugin default
    // changed is carried at the new default, and a chosen one is kept with the
    // WARN a write prints.
    const oldDrift = against === null || oldRec === null ? { stale: [], moved: [] } : drift(old.text, oldRec);
    const inNew = new Map((existing === null ? [] : (flatten(existing).records ?? [])).filter((r) => !r.nested).map((r) => [r.top, r.value]));
    const setInNew = new Set(existing === null ? [] : topLevelLines(existing).map((t) => t.key));
    // A key the settings file sets is never carried, so a stale default in it
    // is updated by this same run: compare against the value it will hold.
    const newStale = against === null || existing === null ? [] : drift(existing, recordedIn(existing)).stale;
    const afterRun = (k) => newStale.find((s) => s.k === k)?.to ?? inNew.get(k);
    kept.push(...bad);
    for (const [k, v] of values) {
      // A stale default is vetted at the value written, the new default, so
      // an old value the schema no longer allows does not block the carry.
      // The command line and the settings file are compared against that
      // value, the one the carry would write, so a rerun after the carry, or
      // a settings file already at the new default or moved to it by this
      // run, does not keep the key.
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

  // With provenance, a default value whose plugin default changed is updated
  // and a chosen one is kept; neither happens for a key given on the command
  // line or carried from the retired file, which is written as given.
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

  // The provenance block: one entry per scalar schema key the file will hold,
  // in schema order. A key given on the command line is chosen, a --default
  // key is default, a carried key keeps the entry the retired file recorded,
  // and any other key keeps its entry; a key without one is chosen. A chosen
  // entry records the default it is now written against.
  const held = new Set([...(existing === null ? [] : topLevelLines(existing).map((t) => t.key)), ...writes.map(([k]) => k)]);
  const sourceOf = (k) =>
    defaulted.has(k) ? "default" : wanted.has(k) ? "chosen" : carried.has(k) ? carried.get(k).source : (rec.entries.get(k)?.source ?? "chosen");
  const entries = Object.keys(keys)
    .filter((k) => held.has(k) && !isObject(keys[k]) && allowedText(keys[k]) !== null)
    .map((k) => `  ${k}: ${sourceText(sourceOf(k), defaultText(keys[k]))}`);
  const block = against === null ? [] : [`${PROVENANCE}:`, ...entries];

  let proposed;
  if (existing === null) {
    const head = against === null ? [] : [`${AGAINST}: ${against}`];
    proposed = [`# yaml-language-server: $schema=${schema.$id}`, ...head, ...writes.map(([k, { written: w }]) => `${k}: ${w}`), ...block, ""].join("\n");
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
    // Each key is written over its own line or appended; line indexes hold
    // until the provenance block is replaced, last. With provenance, an
    // appended line takes the document's base indent.
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
        // The writer owns the block: it runs to its last line indented past
        // its key, comments inside included, and is replaced whole.
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
  const readBack = new Map((flatten(proposed).records ?? []).filter((r) => !r.nested).map((r) => [r.top, r.value]));
  for (const [k, { value }] of writes) {
    if ((readBack.get(k) ?? "") !== value) refuse(`${k}=${value} would not read back as given; nothing written`);
  }

  // A migration that carries nothing creates no settings file.
  const changes = existing === null ? writes.length > 0 : proposed !== existing;
  const unchanged = existing === null ? `nothing in ${old?.path} can be carried into ${rel}; nothing written\n` : `${rel}: already configured; nothing written\n`;

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
  // Without --yes nothing in the offer is written, so a plan the writer would
  // refuse (a symlinked AGENTS.md or .gitignore) does not stop the settings
  // file; the refusal is printed in place of the offer.
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
  // pending: the settings file waits for --yes too, so the offer lists it.
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
            : `  - add the overlay ignore line ${ignore.line} to .gitignore so personal <concern>.local.* files stay untracked`,
          `Nothing is always-loaded: the region is one pointer line. ${pending ? "Nothing was written" : "Neither was written"}. Re-run with --yes once the operator confirms,`,
          `with --home <dir> to name a different home, or with --decline to record that this repository declines a home.`,
          "",
        ].join("\n"),
      ),
    );
  };

  // Printed once the settings file is written, or beside the diff that waits
  // for --yes, so a refusal before either stays one line.
  const provenanceNotes = against !== null && existing !== null ? printable(noRecord(rec) + movedLines(moved.filter(({ k }) => !given(k)))) : "";
  const unbound = offer !== null || offerRefused !== null;
  if (!changes && index === null && !unbound && !removeOld) {
    process.stdout.write(migrateNotes + unchanged);
    return 0;
  }

  // Without --yes a missing settings file is still created; changing an
  // existing file or index waits, and so does a file in a --home the pointer
  // does not name yet, since an unbound repository reads docs/conventions,
  // and so does a migration, which moves values out of the retired file.
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
    // Removed only while it still holds what was read, after the settings
    // file is written, so a failure here loses no value.
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
    // Printed after the settings write, so a refusal there stays one line.
    printOffer(false);
    return 0;
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
