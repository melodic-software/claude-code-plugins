#!/usr/bin/env node
// Write or check the repository layer of the discovery plugin's settings,
// docs/conventions/discovery.yaml, against schemas/discovery.schema.json.
//
// Usage:
//   setup-apply.mjs [--root <dir>] [--yes] <key>=<value> ...
//   setup-apply.mjs [--root <dir>] --check
//
//   --root <dir>  repository root, a symlink resolved; default: git's toplevel
//                 for the current directory. The file is always
//                 <root>/docs/conventions/discovery.yaml.
//   --yes         the operator has seen the diff and confirmed it; needed to
//                 change a file that already exists.
//   --check       validate the existing file and print one INFO, PASS or WARN
//                 line per finding; write nothing.
//
// Two functions hold the guarantees:
//   validate(text)  the whole document parses, sets every top-level key once,
//                   names no key outside the schema, and gives each schema key
//                   one allowed string (not empty, null, a map or a list).
//                   Run on the existing file by --check and by apply, which
//                   refuses it unless every problem is a value it overwrites,
//                   and on the result by apply.
//   checkPath()     docs/ and docs/conventions/ are real directories that resolve
//                   inside the root, and the target, when present, is a regular
//                   file with one link. Run before reading and again right before
//                   writing; writeTarget() then writes a temp file opened with
//                   O_EXCL|O_NOFOLLOW in the same directory and renames it over
//                   the target, removing the temp file on any failure.
//
// Exit codes: 0 written, already configured, or --check found a valid or
// absent file; 1 refused (invalid value or key, an invalid existing file, an
// unsafe path); 2 usage or environment error; 3 the existing file would change
// and --yes was not given (the diff is on stdout).

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
const SCHEMA_PATH = join(SCRIPT_DIR, "..", "..", "..", "schemas", "discovery.schema.json");
const READER = join(SCRIPT_DIR, "parse-concern-value.sh");
const PARSER = join(SCRIPT_DIR, "yaml-subset.awk");
const REL = "docs/conventions/discovery.yaml";

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
// A symlinked root is the operator's own choice of repository, so it is
// resolved once here; checkPath() still refuses links below it.
try {
  root = realpathSync(root);
} catch (e) {
  die(2, `root ${root}: ${e.code ?? e.message}`);
}
if (!lstatOrNull(root)?.isDirectory()) die(2, `root is not a directory: ${root}`);

const schema = JSON.parse(readFileSync(SCHEMA_PATH, "utf8"));
const keys = Object.fromEntries(
  Object.entries(schema.properties).filter(([k]) => k !== "$schema"),
);
const target = join(root, REL);

function lstatOrNull(p) {
  try {
    return lstatSync(p);
  } catch (e) {
    if (e.code === "ENOENT") return null;
    die(1, `${p}: ${e.code ?? e.message}; nothing written`);
  }
}

// Refuse any path shape that could send a write somewhere other than
// <root>/docs/conventions/discovery.yaml. Returns true when the target exists.
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

function writeTarget(text) {
  const tmp = join(root, "docs", "conventions", `.discovery.yaml.${process.pid}.tmp`);
  const flags = constants.O_WRONLY | constants.O_CREAT | constants.O_EXCL | (constants.O_NOFOLLOW ?? 0);
  let fd = -1;
  let created = false;
  try {
    checkPath();
    for (const part of ["docs", "docs/conventions"]) {
      if (!lstatOrNull(join(root, part))) mkdirSync(join(root, part));
    }
    checkPath();
    fd = openSync(tmp, flags, 0o644);
    created = true;
    writeFileSync(fd, text);
    // close(2) releases the descriptor even when it reports an error, so the
    // cleanup below must never close it a second time.
    const open = fd;
    fd = -1;
    closeSync(open);
    renameSync(tmp, target);
  } catch (e) {
    try {
      if (fd >= 0) closeSync(fd);
    } catch {}
    try {
      if (created) rmSync(tmp, { force: true });
    } catch {}
    die(1, `${REL}: ${e.code ?? e.message}; nothing written`);
  }
}

// Top-level keys as written, in order, from lines at the document's base
// indent. Used for the checks the flattened parser output cannot show: a key
// set twice with nothing after the colon, and a key whose value is empty or an
// empty flow collection.
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
// valid. A fixable problem (an empty, null or unknown value) is one apply
// clears by writing a scalar over it; apply refuses a file with any other.
function validate(text) {
  const parsed = spawnSync("awk", ["-f", PARSER], { input: text, encoding: "utf8", env: { ...process.env, LC_ALL: "C" } });
  if (parsed.status !== 0) {
    const err = parsed.stdout.split("\n").find((l) => l.startsWith("error\t")) ?? "error\t?\tunreadable";
    const [, line, msg] = err.split("\t");
    return [{ msg: `line ${line}: ${msg}`, fixable: false }];
  }
  const records = parsed.stdout.split("\n").filter(Boolean).map((r) => {
    const tab = r.indexOf("\t");
    return { path: r.slice(0, tab), value: r.slice(tab + 1) };
  });
  const tops = topLevelLines(text);
  const problems = [];
  const bad = (msg, fixable = false) => problems.push({ msg, fixable });
  const seen = new Set();
  for (const key of [...records.map((r) => r.path), ...tops.filter((t) => t.value === "").map((t) => t.key)]) {
    if (seen.has(key)) bad(`key ${key} is set more than once`);
    seen.add(key);
  }
  for (const top of new Set([...tops.map((t) => t.key), ...records.map((r) => r.path.split(".")[0])])) {
    if (top !== "$schema" && !Object.hasOwn(keys, top)) bad(`key ${top} is not in the schema`);
  }
  for (const [k, spec] of Object.entries(keys)) {
    const allowed = spec.enum.join(", ");
    const lines = tops.filter((t) => t.key === k);
    const scalar = records.find((r) => r.path === k);
    if (records.some((r) => r.path.startsWith(`${k}.`)) || lines.some((t) => /^[[{]/.test(t.value))) {
      bad(`${k} holds a map or a list; it takes one of ${allowed}`);
    } else if (scalar?.value === "") {
      bad(`${k} is an empty string; it takes one of ${allowed}`);
    } else if (!scalar && lines.length) {
      bad(`${k} is empty; it takes one of ${allowed}`, true);
    } else if (scalar && !spec.enum.includes(scalar.value)) {
      bad(`${k}=${scalar.value} is not one of ${allowed}`, true);
    }
  }
  return [...new Map(problems.map((p) => [p.msg, p])).values()];
}

const existing = checkPath() ? readFileSync(target, "utf8") : null;

if (check) {
  if (existing === null) {
    process.stdout.write(`INFO ${REL}: absent; every key resolves from userConfig or its default\n`);
    process.exit(0);
  }
  const problems = validate(existing);
  if (problems.length) {
    process.stdout.write(problems.map((p) => `WARN ${REL}: ${p.msg}\n`).join(""));
    process.exit(1);
  }
  for (const k of Object.keys(keys)) {
    const v = spawnSync("bash", [READER, "-", k], { input: existing, encoding: "utf8" }).stdout.trim();
    process.stdout.write(`PASS ${k}: ${v || "(unset)"}\n`);
  }
  process.exit(0);
}

const wanted = [];
for (const pair of pairs) {
  const eq = pair.indexOf("=");
  const k = pair.slice(0, eq);
  const v = pair.slice(eq + 1);
  if (!Object.hasOwn(keys, k)) die(1, `${k} is not a key of ${REL} (keys: ${Object.keys(keys).join(", ")}); nothing written`);
  if (wanted.some(([seen]) => seen === k)) die(1, `${k} is given more than once; nothing written`);
  if (!keys[k].enum.includes(v)) {
    die(1, `${k}=${v} is not one of ${keys[k].enum.join(", ")}; nothing written`);
  }
  wanted.push([k, v]);
}

const unfixable = existing === null ? [] : validate(existing).filter((p) => !p.fixable);
if (unfixable.length) die(1, `${REL}: ${unfixable.map((p) => p.msg).join("; ")}; fix the file by hand, nothing written`);

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

writeTarget(proposed);
process.stdout.write(`wrote ${REL}\n${proposed}`);
