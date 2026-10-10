#!/usr/bin/env node
// Write or check the repository layer of the verification plugin's settings,
// docs/conventions/verification.yaml, against schemas/verification.schema.json.
//
// Usage:
//   setup-apply.mjs [--root <dir>] [--yes] <key>=<value> ...
//   setup-apply.mjs [--root <dir>] --check [--ref <ref>]
//
//   --root <dir>  repository root; default: git's toplevel for the current
//                 directory. The file is always <root>/docs/conventions/verification.yaml.
//   --yes         the operator has seen the diff and confirmed it; needed to
//                 change a file that already exists.
//   --check       validate the existing file and print one INFO, PASS or WARN
//                 line per finding; write nothing. A WARN on one key's value
//                 leaves a PASS line for every other key; a parse error or
//                 an unknown key leaves none. Exit 1 on any WARN.
//   --ref <ref>   with --check only: validate the file as committed at <ref>
//                 instead of the working tree's copy, and print the commit
//                 read. <ref> is a 40-hex commit id or origin/<name>, checked
//                 before any git call; origin/<name> is read only from
//                 refs/remotes/origin/<name>, matched exactly, and exits 2
//                 when that ref is absent. proof_level is read this way
//                 from the default branch, so a branch cannot lower it.
//
// The allowed values of a key come from the schema: `true` and `false` for a
// boolean key, the listed strings for an enum key, and for an integer key an
// unquoted whole number from the schema's minimum up to any maximum (no sign,
// no decimal point, no leading zero). Each key may be given once.
//
// Two functions hold the guarantees:
//   validate(text)  the document parses, sets every top-level key once (keys
//                   compared after trimming), names no key outside the schema,
//                   and gives each key one allowed scalar. Each problem is
//                   marked fixable when it is a value apply may overwrite: an
//                   out-of-list or out-of-range scalar, an empty value or null. A map or a list
//                   in block or flow form, or an empty quoted string, is not.
//                   --check reports every problem; apply refuses an existing
//                   file with any problem it would not overwrite, then
//                   validates its own result.
//   checkPath()     the root is neither $HOME nor an ancestor of it; docs/ and
//                   docs/conventions/ are real directories that resolve inside
//                   the root; the target, when present, is a regular file with
//                   one link. Run before reading, before each mkdir and right
//                   before writing; writeTarget() then writes a temp file
//                   opened with O_EXCL|O_NOFOLLOW in the same directory and
//                   renames it over the target.
//
// Every refusal is one line on stderr. A failed open, read, realpath, write,
// close or rename removes only the temp file this run created.
//
// Exit codes: 0 written, already configured, or --check found a valid or
// absent file; 1 refused (invalid value or key, an invalid existing file, an
// unsafe path, a failed read or write); 2 usage or environment error; 3 the
// existing file would change and --yes was not given (the diff is on stdout).

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
import { homedir } from "node:os";
import { dirname, join, sep } from "node:path";
import { fileURLToPath } from "node:url";

const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
const PLUGIN_ROOT = join(SCRIPT_DIR, "..", "..", "..");
const SCHEMA_PATH = join(PLUGIN_ROOT, "schemas", "verification.schema.json");
const READER = join(PLUGIN_ROOT, "lib", "parse-concern-value.sh");
const PARSER = join(PLUGIN_ROOT, "lib", "yaml-subset.awk");
const REL = "docs/conventions/verification.yaml";

function die(code, message) {
  process.stderr.write(`setup-apply: ${String(message).replace(/[\r\n]+/g, " ")}\n`);
  process.exit(code);
}
const why = (e) => e?.code ?? e?.message ?? String(e);

const args = process.argv.slice(2);
let root = "";
let yes = false;
let check = false;
let ref = null;
const pairs = [];
for (let i = 0; i < args.length; i++) {
  const a = args[i];
  if (a === "--root") {
    if (i + 1 >= args.length) die(2, "--root needs a directory");
    root = args[++i];
  } else if (a === "--ref") {
    if (i + 1 >= args.length) die(2, "--ref needs a commit id or origin/<name>");
    ref = args[++i];
  } else if (a === "--yes") yes = true;
  else if (a === "--check") check = true;
  else if (/^[^=-][^=]*=/.test(a)) pairs.push(a);
  else die(2, `unexpected argument: ${a}; usage: setup-apply.mjs [--root <dir>] [--yes] <key>=<value> ... | --check [--ref <ref>]`);
}
if (check && pairs.length) die(2, "--check takes no <key>=<value> arguments");
if (ref !== null && !check) die(2, "--ref is a --check option; a write always targets the working tree");
// Only a full commit id or origin/<name>: nothing git could read as an option,
// a revision range, a path or a reflog expression.
if (ref !== null && !(/^[0-9a-f]{40}$/.test(ref) || (/^origin\/[A-Za-z0-9._/-]+$/.test(ref) && !ref.includes("..") && !ref.startsWith("origin/-")))) {
  die(2, `invalid --ref ${JSON.stringify(ref)}; expected a 40-hex commit id or origin/<name>`);
}
if (!check && !pairs.length) die(2, "nothing to write; pass at least one <key>=<value>");

if (!root) {
  const git = spawnSync("git", ["rev-parse", "--show-toplevel"], { encoding: "utf8" });
  if (git.status !== 0) die(2, "not inside a git working tree; pass --root <dir>");
  root = git.stdout.trim();
}

function lstatOrNull(p) {
  try {
    return lstatSync(p);
  } catch (e) {
    if (e.code === "ENOENT") return null;
    die(1, `${p}: ${why(e)}; nothing written`);
  }
}
function real(p) {
  try {
    return realpathSync(p);
  } catch (e) {
    die(1, `${p}: could not resolve it (${why(e)}); nothing written`);
  }
}

if (!lstatOrNull(root)?.isDirectory()) die(2, `root is not a directory: ${root}`);

let schema;
try {
  schema = JSON.parse(readFileSync(SCHEMA_PATH, "utf8"));
} catch (e) {
  die(2, `could not read the schema ${SCHEMA_PATH} (${why(e)})`);
}
const keys = Object.fromEntries(
  Object.entries(schema.properties).filter(([k]) => k !== "$schema"),
);
// allowedText(spec) words a key's allowed values for a message; allows(spec,
// raw) tests one value as written, quotes included. A quoted boolean or number
// is a string, so it is not allowed; a quoted listed string is.
function allowedText(spec) {
  if (spec.type === "boolean") return "one of true, false";
  if (spec.type === "integer") {
    const min = spec.minimum ?? 0;
    return spec.maximum === undefined ? `a whole number of at least ${min}` : `a whole number from ${min} to ${spec.maximum}`;
  }
  return `one of ${spec.enum.join(", ")}`;
}
function allows(spec, raw) {
  if (spec.type === "boolean") return raw === "true" || raw === "false";
  if (spec.type === "integer") {
    const n = Number(raw);
    return /^(0|[1-9][0-9]*)$/.test(raw) && n >= (spec.minimum ?? 0) && (spec.maximum === undefined || n <= spec.maximum);
  }
  return spec.enum.includes(raw.replace(/^(["'])(.*)\1$/, "$2"));
}
const target = join(root, REL);

// Refuse any path shape that could send a write somewhere other than
// <root>/docs/conventions/verification.yaml. Returns true when the target exists.
function checkRoot() {
  const realRoot = real(root);
  const home = homedir();
  if (home) {
    let realHome = home;
    try {
      realHome = realpathSync(home);
    } catch {
      // An unresolvable home is compared as given.
    }
    if (realHome === realRoot || realHome.startsWith(realRoot.endsWith(sep) ? realRoot : realRoot + sep)) {
      die(1, `the root ${root} is $HOME or an ancestor of it, not a repository; nothing written`);
    }
  }
  return realRoot;
}

function checkPath() {
  const realRoot = checkRoot();
  for (const part of ["docs", "docs/conventions"]) {
    const st = lstatOrNull(join(root, part));
    if (!st) return false;
    if (st.isSymbolicLink()) die(1, `${part} is a symlink; refusing to write through it`);
    if (!st.isDirectory()) die(1, `${part} exists and is not a directory; nothing written`);
    if (real(join(root, part)) !== join(realRoot, part)) die(1, `${part} resolves outside the repository; nothing written`);
  }
  const st = lstatOrNull(target);
  if (!st) return false;
  if (st.isSymbolicLink()) die(1, `${REL} is a symlink; refusing to write through it`);
  if (!st.isFile()) die(1, `${REL} exists and is not a regular file; nothing written`);
  if (st.nlink > 1) die(1, `${REL} has ${st.nlink} hard links; refusing to write through it`);
  return true;
}

function writeTarget(text) {
  for (const part of ["docs", "docs/conventions"]) {
    checkPath();
    if (lstatOrNull(join(root, part))) continue;
    try {
      mkdirSync(join(root, part));
    } catch (e) {
      die(1, `${part}: could not create it (${why(e)}); nothing written`);
    }
  }
  checkPath();
  const tmp = join(root, "docs", "conventions", `.verification.yaml.${process.pid}.tmp`);
  const flags = constants.O_WRONLY | constants.O_CREAT | constants.O_EXCL | (constants.O_NOFOLLOW ?? 0);
  let fd = -1;
  let created = false;
  try {
    fd = openSync(tmp, flags, 0o644);
    created = true;
    writeFileSync(fd, text);
    // close(2) releases the descriptor even when it reports an error, so it
    // is marked closed before the call and never closed a second time.
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
    die(1, `${REL}: could not write it (${why(e)}); nothing written`);
  }
}

// Top-level keys as written, from lines at the document's base indent, each
// with its line index, its trimmed key and its raw value (comment and
// surrounding space removed). The flattened parser output cannot show a key
// set twice, an empty value, a quoted value or an empty flow collection, so
// these checks read the lines.
function topLevelLines(text) {
  const all = text.replace(/^﻿/, "").split("\n");
  const content = all
    .map((line, at) => ({ line: line.replace(/\r$/, ""), at }))
    .filter(({ line }) => line.trim() && !/^\s*#/.test(line) && !/^(---|\.\.\.|%)/.test(line));
  const base = content.length ? content[0].line.match(/^\s*/)[0].length : 0;
  return content
    .filter(({ line }) => line.match(/^\s*/)[0].length === base)
    .map(({ line, at }) => ({ at, m: line.trim().match(/^(?:"([^"]*)"|'([^']*)'|([^"':]+?))\s*:(?:\s+(.*))?$/) }))
    .filter(({ m }) => m)
    .map(({ at, m: [, dq, sq, bare, rest] }) => ({
      at,
      key: (dq ?? sq ?? bare).trim(),
      raw: (rest ?? "").replace(/\s+#.*$/, "").trim(),
    }));
}

// Validate a whole document. Returns { key, msg, fixable } problems; [] means
// valid. key is the schema key a value problem sits on, null for a problem
// with the whole file (a parse error, an unknown key); fixable marks a value
// apply may overwrite.
function validate(text) {
  const parsed = spawnSync("awk", ["-f", PARSER], {
    input: text,
    encoding: "utf8",
    env: { ...process.env, LC_ALL: "C" },
  });
  if (parsed.status !== 0) {
    const err = (parsed.stdout ?? "").split("\n").find((l) => l.startsWith("error\t")) ?? "error\t?\tunreadable";
    const [, line, msg] = err.split("\t");
    return [{ key: null, msg: `line ${line}: ${msg}`, fixable: false }];
  }
  const records = parsed.stdout
    .split("\n")
    .filter(Boolean)
    .map((r) => {
      const tab = r.indexOf("\t");
      const path = r.slice(0, tab);
      const dot = path.indexOf(".");
      return { top: (dot === -1 ? path : path.slice(0, dot)).trim(), nested: dot !== -1 };
    });
  const tops = topLevelLines(text);
  const problems = [];
  const bad = (msg, key = null, fixable = key !== null) => problems.push({ key, msg, fixable });
  const seen = new Set();
  for (const { key } of tops) {
    if (seen.has(key)) bad(`key ${key} is set more than once`, Object.hasOwn(keys, key) ? key : null, false);
    seen.add(key);
  }
  for (const key of new Set([...tops.map((t) => t.key), ...records.map((r) => r.top)])) {
    if (key !== "$schema" && !Object.hasOwn(keys, key)) bad(`key ${key} is not in the schema`);
  }
  for (const [k, spec] of Object.entries(keys)) {
    const line = tops.find((t) => t.key === k);
    if (!line) continue;
    const values = allowedText(spec);
    const { raw } = line;
    const shown = raw ? `${k}=${raw}` : k;
    if (records.some((r) => r.top === k && r.nested) || /^[[{]/.test(raw)) {
      bad(`${shown} holds a map or a list; it takes ${values}`, k, false);
    } else if (raw === '""' || raw === "''") {
      bad(`${shown} is an empty quoted string; it takes ${values}`, k, false);
    } else if (raw === "") {
      bad(`${k} is empty; it takes ${values}`, k);
    } else if (/^(null|Null|NULL|~)$/.test(raw)) {
      bad(`${k} is null; it takes ${values}`, k);
    } else if (!allows(spec, raw)) {
      bad(`${k}=${raw} is not ${values}`, k);
    }
  }
  return [...new Map(problems.map((p) => [p.msg, p])).values()];
}

// The file as committed at --ref: { sha, text }, text null when the commit has
// no such path. Every git argument is the validated ref, a resolved object id
// or a fixed string, passed without a shell.
function readAtRef() {
  checkRoot();
  const git = (...a) => spawnSync("git", ["-C", root, ...a], { encoding: "utf8" });
  // origin/<name> is read only from refs/remotes/origin/<name>, matched exactly
  // by show-ref. rev-parse would apply its short-name lookup, where a local
  // branch, a tag or a refs/... look-alike can win or stand in for it.
  let commitish = ref;
  if (ref.startsWith("origin/")) {
    const shown = git("show-ref", "--verify", "--hash", "--end-of-options", `refs/remotes/${ref}`);
    commitish = shown.status === 0 ? shown.stdout.trim() : "";
    if (!/^[0-9a-f]{40}$/.test(commitish)) die(2, `--ref ${ref}: refs/remotes/${ref} does not exist`);
  }
  const rev = git("rev-parse", "--verify", "--quiet", "--end-of-options", `${commitish}^{commit}`);
  const sha = rev.status === 0 ? rev.stdout.trim() : "";
  if (!/^[0-9a-f]{40}$/.test(sha)) die(2, `--ref ${ref} does not resolve to a commit`);
  const tree = git("ls-tree", "-z", "--full-tree", sha, "--", REL);
  if (tree.status !== 0) die(1, `${REL} at ${ref} (${sha}): could not list it`);
  const entry = tree.stdout.split("\0").find(Boolean);
  if (!entry) return { sha, text: null };
  const [mode, type, oid] = entry.split("\t")[0].split(" ");
  if (type !== "blob" || !/^1006[0-7]{2}$/.test(mode)) {
    process.stdout.write(`WARN ${REL} at ${ref} (${sha}): not a regular file (mode ${mode})\n`);
    process.exit(1);
  }
  const blob = git("cat-file", "blob", oid);
  if (blob.status !== 0) die(1, `${REL} at ${ref} (${sha}): could not read it`);
  return { sha, text: blob.stdout };
}

let existing = null;
if (ref !== null) {
  const at = readAtRef();
  process.stdout.write(`INFO read ${REL} at ${ref}, commit ${at.sha}\n`);
  existing = at.text;
} else if (checkPath()) {
  try {
    existing = readFileSync(target, "utf8");
  } catch (e) {
    die(1, `${REL}: could not read it (${why(e)}); nothing written`);
  }
}

if (check) {
  if (existing === null) {
    process.stdout.write(`INFO ${REL}: absent; every key resolves from userConfig or its default\n`);
    process.exit(0);
  }
  // A bad value drops only its own key (ADR 0060 Decision 7): every other key
  // still gets its PASS line. A problem with the whole file leaves no PASS.
  const problems = validate(existing);
  process.stdout.write(problems.map((p) => `WARN ${REL}: ${p.msg}\n`).join(""));
  if (problems.some((p) => p.key === null)) process.exit(1);
  for (const k of Object.keys(keys)) {
    if (problems.some((p) => p.key === k)) continue;
    const v = spawnSync("bash", [READER, "-", k], { input: existing, encoding: "utf8" }).stdout.trim();
    process.stdout.write(`PASS ${k}: ${v || "(unset)"}\n`);
  }
  process.exit(problems.length ? 1 : 0);
}

const wanted = new Map();
for (const pair of pairs) {
  const eq = pair.indexOf("=");
  const k = pair.slice(0, eq).trim();
  const v = pair.slice(eq + 1);
  if (wanted.has(k)) die(1, `${k} is given more than once; pass each key once; nothing written`);
  if (!Object.hasOwn(keys, k)) die(1, `${k} is not a key of ${REL} (keys: ${Object.keys(keys).join(", ")}); nothing written`);
  // A command-line value is the bare word itself, so any quote makes it invalid.
  if (/^["']/.test(v) || !allows(keys[k], v)) die(1, `${k}=${v} is not ${allowedText(keys[k])}; nothing written`);
  wanted.set(k, v);
}

if (existing !== null) {
  const blocking = validate(existing).filter((p) => !p.fixable || !wanted.has(p.key));
  if (blocking.length) {
    die(1, `${REL}: ${blocking.map((p) => p.msg).join("; ")}; fix the file by hand, nothing written`);
  }
}

let proposed;
if (existing === null) {
  proposed = `# yaml-language-server: $schema=${schema.$id}\n${[...wanted].map(([k, v]) => `${k}: ${v}\n`).join("")}`;
} else {
  const lines = existing.replace(/\n$/, "").split("\n");
  const tops = topLevelLines(existing);
  for (const [k, v] of wanted) {
    const line = tops.find((t) => t.key === k);
    if (!line) {
      lines.push(`${k}: ${v}`);
      continue;
    }
    const old = lines[line.at];
    lines[line.at] = `${old.match(/^\s*/)[0]}${k}: ${v}${old.endsWith("\r") ? "\r" : ""}`;
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
  const diff = spawnSync("diff", ["-u", "--label", `a/${REL}`, "--label", `b/${REL}`, target, "-"], {
    input: proposed,
    encoding: "utf8",
  });
  process.stdout.write(diff.stdout);
  process.stdout.write(
    `${REL} exists and would change; nothing written. Show this diff, and re-run with --yes once the operator confirms.\n`,
  );
  process.exit(3);
}

writeTarget(proposed);
process.stdout.write(`wrote ${REL}\n${proposed}`);
