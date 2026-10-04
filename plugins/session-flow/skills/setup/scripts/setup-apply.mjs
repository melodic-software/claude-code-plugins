#!/usr/bin/env node
// Write or check the repository layer of the session-flow plugin's settings,
// docs/conventions/session-flow.yaml, against schemas/session-flow.schema.json.
//
// Usage:
//   setup-apply.mjs [--root <dir>] [--yes] <key>=<value> ...
//   setup-apply.mjs [--root <dir>] --check
//
//   --root <dir>  repository root; default: git's toplevel for the current
//                 directory. The file is always <root>/docs/conventions/session-flow.yaml.
//   --yes         the operator has seen the diff and confirmed it; needed to
//                 change a file that already exists.
//   --check       validate the existing file and print its keys; write nothing.
//
// Two functions hold the guarantees:
//   validate(text)  the whole document parses, sets every top-level key once,
//                   names no key outside the schema, and gives each schema key
//                   one allowed scalar (not empty, null, a quoted empty string,
//                   a map or a list, in block or one-line flow form). Run on
//                   the existing file by --check and by apply, which refuses it
//                   unless every problem is a value it overwrites (out of the
//                   list, empty or null), and on the result by apply.
//   checkPath()     docs/ and docs/conventions/ are real directories that resolve
//                   inside the root, and the target, when present, is a regular
//                   file with one link. Run before reading, and again before any
//                   directory is created and before the file is written.
//
// The bytes go to a temp file opened with O_EXCL|O_NOFOLLOW in the same
// directory, renamed over the target; the temp file is removed on failure only
// when this run created it. A file that already exists is changed only with
// --yes; without it the diff is printed and nothing is written. The YAML reader
// and parser are the plugin's shared copies under skills/retro/scripts/.
//
// Exit codes: 0 written, already configured, or --check found a valid or
// absent file; 1 refused (invalid value or key, a key given twice, an invalid
// existing file, an unsafe path); 2 usage or environment error; 3 the existing
// file would change and --yes was not given (the diff is on stdout).

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
  writeFileSync,
} from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
const PLUGIN_ROOT = join(SCRIPT_DIR, "..", "..", "..");
const SCHEMA_PATH = join(PLUGIN_ROOT, "schemas", "session-flow.schema.json");
const READER = join(PLUGIN_ROOT, "skills", "retro", "scripts", "parse-concern-value.sh");
const PARSER = join(PLUGIN_ROOT, "skills", "retro", "scripts", "yaml-subset.awk");
const REL = "docs/conventions/session-flow.yaml";

function die(code, message) {
  process.stderr.write(`setup-apply: ${message}\n`);
  process.exit(code);
}

const args = process.argv.slice(2);
let root = "";
let yes = false;
let check = false;
const pairs = [];
for (let i = 0; i < args.length; i++) {
  const a = args[i];
  if (a === "--root") {
    if (i + 1 >= args.length) die(2, "--root needs a directory");
    root = args[++i];
  } else if (a === "--yes") yes = true;
  else if (a === "--check") check = true;
  else if (/^[^=-][^=]*=/.test(a)) pairs.push(a);
  else die(2, `unexpected argument: ${a}; usage: setup-apply.mjs [--root <dir>] [--yes] <key>=<value> ... | --check`);
}
if (check && pairs.length) die(2, "--check takes no <key>=<value> arguments");
if (!check && !pairs.length) die(2, "nothing to write; pass at least one <key>=<value>");

if (!root) {
  const git = spawnSync("git", ["rev-parse", "--show-toplevel"], { encoding: "utf8" });
  if (git.status !== 0) die(2, "not inside a git working tree; pass --root <dir>");
  root = git.stdout.trim();
}
if (!lstatOrNull(root)?.isDirectory()) die(2, `root is not a directory: ${root}`);

const schema = JSON.parse(readFileSync(SCHEMA_PATH, "utf8"));
const keys = Object.fromEntries(
  Object.entries(schema.properties).filter(([k]) => k !== "$schema"),
);
const target = join(root, REL);

// A key either lists its values (enum), takes an unquoted true or false
// (boolean), or takes an unquoted integer within the schema's minimum and
// maximum. A quoted number or boolean is a string, so it is invalid.
function allowedText(spec) {
  if (spec.enum) return `one of ${spec.enum.join(", ")}`;
  if (spec.type === "boolean") return "an unquoted true or false";
  return `an integer from ${spec.minimum} to ${spec.maximum}`;
}
function allows(spec, value, quoted = false) {
  if (spec.enum) return spec.enum.includes(value);
  if (spec.type === "boolean") return !quoted && (value === "true" || value === "false");
  return !quoted && /^(0|[1-9][0-9]*)$/.test(value) && Number(value) >= spec.minimum && Number(value) <= spec.maximum;
}

function lstatOrNull(p) {
  try {
    return lstatSync(p);
  } catch (e) {
    if (e.code === "ENOENT") return null;
    die(1, `${p}: ${e.code ?? e.message}; nothing written`);
  }
}

// Refuse any path shape that could send a write somewhere other than
// <root>/docs/conventions/session-flow.yaml. Returns true when the target exists.
function checkPath() {
  for (const part of ["docs", "docs/conventions"]) {
    const st = lstatOrNull(join(root, part));
    if (!st) return false;
    if (st.isSymbolicLink()) die(1, `${part} is a symlink; refusing to write through it`);
    if (!st.isDirectory()) die(1, `${part} exists and is not a directory; nothing written`);
  }
  const conventions = join(root, "docs", "conventions");
  if (realpathSync(conventions) !== join(realpathSync(root), "docs", "conventions")) {
    die(1, "docs/conventions resolves outside the repository; nothing written");
  }
  const st = lstatOrNull(target);
  if (!st) return false;
  if (st.isSymbolicLink()) die(1, `${REL} is a symlink; refusing to write through it`);
  if (!st.isFile()) die(1, `${REL} exists and is not a regular file; nothing written`);
  if (st.nlink > 1) die(1, `${REL} has ${st.nlink} hard links; refusing to write through it`);
  return true;
}

// expected is the file as read at the start (null when absent); a target that
// no longer matches it is refused rather than overwritten.
function writeTarget(text, expected) {
  const tmp = join(root, "docs", "conventions", `.session-flow.yaml.${process.pid}.tmp`);
  const flags = constants.O_WRONLY | constants.O_CREAT | constants.O_EXCL | (constants.O_NOFOLLOW ?? 0);
  let fd;
  try {
    checkPath();
    for (const part of ["docs", "docs/conventions"]) {
      if (!lstatOrNull(join(root, part))) mkdirSync(join(root, part));
    }
    const now = checkPath() ? readFileSync(target, "utf8") : null;
    if (now !== expected) die(1, `${REL} changed while this ran; nothing written, run again`);
    fd = openSync(tmp, flags, 0o644);
    writeFileSync(fd, text);
    closeSync(fd);
    fd = -1;
    renameSync(tmp, target);
  } catch (e) {
    if (fd !== undefined) {
      if (fd >= 0) closeSync(fd);
      rmSync(tmp, { force: true });
    }
    die(1, `${REL}: ${e.code ?? e.message}; nothing written`);
  }
}

// Top-level keys as written, in order, from lines at the document's base
// indent, each with the rest of its line. The flattened parser output cannot
// show a key with nothing after its colon or an empty flow collection, so
// those, and a key set twice, are read from here.
function topLevelLines(text) {
  const lines = text.split(/\r?\n/).filter((l) => l.trim() && !/^\s*#/.test(l) && !/^(---|\.\.\.|%)/.test(l));
  const base = lines.length ? lines[0].match(/^\s*/)[0].length : 0;
  return lines
    .filter((l) => l.match(/^\s*/)[0].length === base)
    .map((l) => l.trim().match(/^["']?([^"':]+?)["']?\s*:\s*(.*)$/))
    .filter(Boolean)
    .map(([, key, rest]) => ({ key, value: rest.replace(/\s+#.*$/, "") }));
}

// Validate a whole document. Returns problems as { msg, fixable }; [] means
// valid. A fixable problem (a value that is empty, null or out of the list)
// is one apply clears by writing a scalar over it; apply refuses a file with
// any other.
function validate(text) {
  const parsed = spawnSync("awk", ["-f", PARSER], { input: text, encoding: "utf8", env: { ...process.env, LC_ALL: "C" } });
  if (parsed.status !== 0) {
    const err = parsed.stdout.split("\n").find((l) => l.startsWith("error\t")) ?? "error\t?\tunreadable";
    const [, line, msg] = err.split("\t");
    return [{ msg: `${REL}: line ${line}: ${msg}`, fixable: false }];
  }
  const records = parsed.stdout.split("\n").filter(Boolean).map((r) => {
    const tab = r.indexOf("\t");
    return { path: r.slice(0, tab), value: r.slice(tab + 1) };
  });
  const tops = topLevelLines(text);
  const problems = [];
  const bad = (msg, fixable = false) => problems.push({ msg: `${REL}: ${msg}`, fixable });
  const count = new Map();
  for (const { key } of tops) count.set(key, (count.get(key) ?? 0) + 1);
  for (const [k, n] of count) if (n > 1) bad(`key ${k} appears ${n} times`);
  for (const k of new Set([...count.keys(), ...records.map((r) => r.path.split(".")[0])])) {
    if (k !== "$schema" && !Object.hasOwn(keys, k)) bad(`key ${k} is not in the schema`);
  }
  for (const [k, spec] of Object.entries(keys)) {
    const allowed = allowedText(spec);
    const lines = tops.filter((t) => t.key === k);
    const scalar = records.find((r) => r.path === k);
    const quoted = lines.some((t) => /^["']/.test(t.value));
    if (records.some((r) => r.path.startsWith(`${k}.`)) || lines.some((t) => /^[[{]/.test(t.value))) {
      bad(`${k} holds a map or a list; it takes ${allowed}`);
    } else if (scalar?.value === "") {
      bad(`${k} is an empty quoted string; it takes ${allowed}`);
    } else if (!scalar && lines.length) {
      bad(`${k} is empty; it takes ${allowed}`, true);
    } else if (scalar && !allows(spec, scalar.value, quoted)) {
      bad(`${k}=${quoted ? lines[0].value : scalar.value} is not ${allowed}`, true);
    }
  }
  return [...new Map(problems.map((p) => [p.msg, p])).values()];
}

const existing = checkPath() ? readFileSync(target, "utf8") : null;

if (check) {
  if (existing === null) {
    process.stdout.write(`${REL}: absent; every key resolves from userConfig or its default\n`);
    process.exit(0);
  }
  const problems = validate(existing);
  if (problems.length) {
    process.stdout.write(problems.map((p) => `${p.msg}\n`).join(""));
    process.exit(1);
  }
  for (const k of Object.keys(keys)) {
    const v = spawnSync("bash", [READER, "-", k], { input: existing, encoding: "utf8" }).stdout.trim();
    process.stdout.write(`${k}: ${v || "(unset)"}\n`);
  }
  process.exit(0);
}

const wanted = [];
for (const pair of pairs) {
  const eq = pair.indexOf("=");
  const k = pair.slice(0, eq);
  const v = pair.slice(eq + 1);
  if (!Object.hasOwn(keys, k)) die(1, `${k} is not a key of ${REL} (keys: ${Object.keys(keys).join(", ")}); nothing written`);
  if (wanted.some(([w]) => w === k)) die(1, `${k} is given more than once; pass each key once, nothing written`);
  if (!allows(keys[k], v)) die(1, `${k}=${v} is not ${allowedText(keys[k])}; nothing written`);
  wanted.push([k, v]);
}

const unfixable = existing === null ? [] : validate(existing).filter((p) => !p.fixable);
if (unfixable.length) die(1, `${unfixable.map((p) => p.msg).join("; ")}; fix the file by hand, nothing written`);

let proposed;
if (existing === null) {
  proposed = `# yaml-language-server: $schema=${schema.$id}\n${wanted.map(([k, v]) => `${k}: ${v}\n`).join("")}`;
} else {
  const lines = existing.replace(/\n$/, "").split("\n");
  for (const [k, v] of wanted) {
    const at = lines.findIndex((l) => new RegExp(`^["']?${k}["']?\\s*:`).test(l));
    if (at === -1) lines.push(`${k}: ${v}`);
    else lines[at] = `${k}: ${v}`;
  }
  proposed = `${lines.join("\n")}\n`;
}

const problems = validate(proposed);
if (problems.length) die(1, `the result would not validate: ${problems.map((p) => p.msg).join("; ")}; nothing written`);

if (existing !== null && proposed === existing) {
  process.stdout.write(`${REL}: already configured; nothing written\n`);
  process.exit(0);
}

if (existing !== null && !yes) {
  const diff = spawnSync(
    "diff",
    ["-u", "--label", `a/${REL}`, "--label", `b/${REL}`, target, "-"],
    { input: proposed, encoding: "utf8" },
  );
  process.stdout.write(diff.stdout);
  process.stdout.write(`${REL} exists and would change; nothing written. Show this diff, and re-run with --yes once the operator confirms.\n`);
  process.exit(3);
}

writeTarget(proposed, existing);
process.stdout.write(`wrote ${REL}\n${proposed}`);
