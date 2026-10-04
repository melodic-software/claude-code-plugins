#!/usr/bin/env node
// Check or write docs/conventions/docs-hygiene.yaml, the repository layer of
// the docs-hygiene plugin's settings, against schemas/docs-hygiene.schema.json.
//
// Usage:
//   setup-apply.mjs [--root <dir>] --check
//   setup-apply.mjs [--root <dir>] [--yes] <key>=<value> ...
//
//   --root <dir>  repository root; default: git's toplevel for the current
//                 directory. The file is always <root>/docs/conventions/docs-hygiene.yaml.
//   --check       validate the file as it stands and print one line per schema key:
//                 PASS with its value, or WARN when the file's value is invalid and
//                 the key resolves to its default; write nothing.
//   --yes         the operator saw the diff and agreed to it; required to change
//                 a file that already exists.
//
// apply touches only the keys named on the command line: a new file holds just
// those keys, and an existing file keeps every other line as it was. The whole
// resulting document is validated before anything is written.
//
// The YAML reader and parser are the plugin's bundled copies under lib/.
//
// Exit codes: 0 written, already configured, or --check found a valid or absent
// file; 1 refused (bad key or value, an invalid existing file, an unsafe path),
// or --check found a problem (it still prints every key's line);
// 2 usage or environment error; 3 the existing file would change and --yes was
// not given (the diff is on stdout).

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
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const PLUGIN = join(HERE, "..", "..", "..");
const SCHEMA_FILE = join(PLUGIN, "schemas", "docs-hygiene.schema.json");
const READER = join(PLUGIN, "lib", "parse-concern-value.sh");
const PARSER = join(PLUGIN, "lib", "yaml-subset.awk");
const REL = "docs/conventions/docs-hygiene.yaml";
const TMP_REL = "docs/conventions/.docs-hygiene.yaml.tmp";

function die(code, message) {
  process.stderr.write(`setup-apply: ${String(message).replace(/\n/g, " ")}\n`);
  process.exit(code);
}

// Turn a filesystem error into one line that names the path part involved.
function fsError(e, what) {
  if (e.code === "EISDIR") return `${what} is a directory where a file belongs; nothing written`;
  if (e.code === "ENOTDIR") return `a part of ${what} is a file where a directory belongs; nothing written`;
  if (e.code === "ELOOP") return `${what} is a symlink; refusing to write through it`;
  return `${what}: ${e.code ?? e.message}; nothing written`;
}

const argv = process.argv.slice(2);
let root = "";
let yes = false;
let check = false;
const pairs = [];
for (let i = 0; i < argv.length; i++) {
  const a = argv[i];
  if (a === "--root") {
    if (i + 1 >= argv.length) die(2, "--root needs a directory");
    root = argv[++i];
  } else if (a === "--yes") yes = true;
  else if (a === "--check") check = true;
  else if (/^[^=-][^=]*=/.test(a)) pairs.push(a);
  else die(2, `unexpected argument: ${a}; usage: setup-apply.mjs [--root <dir>] --check | [--yes] <key>=<value> ...`);
}
if (check && pairs.length) die(2, "--check takes no <key>=<value> arguments");
if (!check && !pairs.length) die(2, "nothing to write; pass at least one <key>=<value>");

if (!root) {
  const git = spawnSync("git", ["rev-parse", "--show-toplevel"], { encoding: "utf8" });
  if (git.status !== 0) die(2, "not inside a git working tree; pass --root <dir>");
  root = git.stdout.trim();
}

function lstatOrNull(p, what) {
  try {
    return lstatSync(p);
  } catch (e) {
    if (e.code === "ENOENT") return null;
    die(1, fsError(e, what));
  }
}

if (!lstatOrNull(root, "root")?.isDirectory()) die(2, `root is not a directory: ${root}`);

// compress skips the repository layer at $HOME or an ancestor of it, so a file
// written there would never be read.
if (!check && process.env.HOME) {
  const real = (p) => {
    try {
      return realpathSync(p);
    } catch {
      return resolve(p);
    }
  };
  const realRoot = real(root);
  const realHome = real(process.env.HOME);
  if (realHome === realRoot || realHome.startsWith(realRoot.endsWith("/") ? realRoot : `${realRoot}/`)) {
    die(1, `root is $HOME or an ancestor of it, where compress does not read ${REL}; nothing written`);
  }
}

let schema;
try {
  schema = JSON.parse(readFileSync(SCHEMA_FILE, "utf8"));
} catch (e) {
  die(2, `cannot read the schema: ${e.code ?? e.message}`);
}
const keys = Object.fromEntries(Object.entries(schema.properties).filter(([k]) => k !== "$schema"));
const target = join(root, REL);

// Refuse every path shape that could send the write anywhere other than
// <root>/docs/conventions/docs-hygiene.yaml. Returns true when the file exists.
function checkPath() {
  let realRoot;
  try {
    realRoot = realpathSync(root);
  } catch (e) {
    die(1, fsError(e, "root"));
  }
  for (const part of ["docs", "docs/conventions"]) {
    const st = lstatOrNull(join(root, part), part);
    if (!st) return false;
    if (st.isSymbolicLink()) die(1, `${part} is a symlink; refusing to write through it`);
    if (!st.isDirectory()) die(1, `${part} is a file where a directory belongs; nothing written`);
    let real;
    try {
      real = realpathSync(join(root, part));
    } catch (e) {
      die(1, fsError(e, part));
    }
    if (real !== join(realRoot, part)) die(1, `${part} resolves outside the repository; nothing written`);
  }
  const st = lstatOrNull(target, REL);
  if (!st) return false;
  if (st.isSymbolicLink()) die(1, `${REL} is a symlink; refusing to write through it`);
  if (st.isDirectory()) die(1, `${REL} is a directory where a file belongs; nothing written`);
  if (!st.isFile()) die(1, `${REL} is not a regular file; nothing written`);
  if (st.nlink > 1) die(1, `${REL} has ${st.nlink} hard links; refusing to write through it`);
  return true;
}

function readTarget() {
  if (!checkPath()) return null;
  try {
    return readFileSync(target, "utf8");
  } catch (e) {
    die(1, fsError(e, REL));
  }
}

// Top-level keys in the order written, one entry per occurrence, with the raw
// value after the colon (comment removed).
const TOP_KEY = /^(["']?)([A-Za-z0-9_$-]+)\1[ \t]*:(?:[ \t]+(.*))?$/;
function topLevelKeys(text) {
  return text
    .split(/\r?\n/)
    .map((line) => line.match(TOP_KEY))
    .filter(Boolean)
    .map((m) => {
      const raw = (m[3] ?? "").replace(/(^|\s)#.*$/, "").trim();
      return { key: m[2], raw, empty: raw === "" };
    });
}

// Problems with a whole document as { kind, msg }; [] means valid. The kinds
// "empty" and "value" are a single bad scalar line that apply may replace;
// every other kind ("parse", "duplicate", "unknown", "shape", "quoted-empty")
// makes apply refuse.
function validate(text) {
  const parsed = spawnSync("awk", ["-f", PARSER], {
    input: text,
    encoding: "utf8",
    env: { ...process.env, LC_ALL: "C" },
  });
  if (parsed.error) die(2, `cannot run awk: ${parsed.error.code ?? parsed.error.message}`);
  if (parsed.status !== 0) {
    const err = parsed.stdout.split("\n").find((l) => l.startsWith("error\t")) ?? "error\t?\tunreadable";
    const [, line, msg] = err.split("\t");
    return [{ kind: "parse", key: "", msg:`${REL}: line ${line}: ${msg}` }];
  }
  const records = parsed.stdout
    .split("\n")
    .filter(Boolean)
    .map((r) => {
      const tab = r.indexOf("\t");
      return { path: r.slice(0, tab), value: r.slice(tab + 1) };
    });
  const problems = [];
  const tops = topLevelKeys(text);
  // Keys are counted from the raw top-level lines, which TOP_KEY reads trimmed
  // and unquoted (`key : v` and `"key": v` are the same key) and which still
  // show a key with no value, which the parser drops.
  const counts = new Map();
  for (const { key } of tops) counts.set(key, (counts.get(key) ?? 0) + 1);
  for (const r of records) {
    const top = r.path.split(".")[0];
    if (!counts.has(top)) counts.set(top, 1);
  }
  for (const [k, n] of counts) {
    if (k !== "$schema" && !Object.hasOwn(keys, k)) problems.push({ kind: "unknown", key: k, msg: `${REL}: key ${k} is not in the schema` });
    if (n > 1) problems.push({ kind: "duplicate", key: k, msg: `${REL}: key ${k} is set ${n} times` });
  }
  for (const [k, spec] of Object.entries(keys)) {
    if (!counts.has(k) || counts.get(k) > 1) continue;
    const allowed = spec.enum.join(", ");
    const own = records.filter((r) => r.path === k || r.path.startsWith(`${k}.`));
    // The parser emits nothing for an empty flow collection, so `[]` and `{}`
    // are found from the raw line.
    if (own.some((r) => r.path !== k) || tops.some((t) => t.key === k && /^[[{]/.test(t.raw))) {
      problems.push({ kind: "shape", key: k, msg: `${REL}: ${k} holds a map or a list; it takes one of ${allowed}` });
    } else if (own.length === 1 && own[0].value === "" && tops.some((t) => t.key === k && !t.empty)) {
      problems.push({ kind: "quoted-empty", key: k, msg: `${REL}: ${k} is an empty quoted string; it takes one of ${allowed}` });
    } else if (own.length === 0 || ["", "null", "~"].includes(own[0].value)) {
      problems.push({ kind: "empty", key: k, msg: `${REL}: ${k} is empty or null; it takes one of ${allowed}` });
    } else if (!spec.enum.includes(own[0].value)) {
      problems.push({ kind: "value", key: k, msg: `${REL}: ${k}=${own[0].value} is not one of ${allowed}` });
    }
  }
  return problems;
}

// Command-line pairs are checked before the file is read, so a bad request is
// refused the same way whether the file exists or not.
const wanted = new Map();
if (!check) {
  for (const pair of pairs) {
    const eq = pair.indexOf("=");
    const k = pair.slice(0, eq);
    const v = pair.slice(eq + 1);
    if (!Object.hasOwn(keys, k)) die(1, `${k} is not a key of ${REL} (keys: ${Object.keys(keys).join(", ")}); nothing written`);
    if (wanted.has(k)) die(1, `${k} is given more than once; nothing written`);
    if (!keys[k].enum.includes(v)) die(1, `${k}=${v} is not one of ${keys[k].enum.join(", ")}; nothing written`);
    wanted.set(k, v);
  }
}

const existing = readTarget();

if (check) {
  if (existing === null) {
    process.stdout.write(`INFO ${REL}: absent; every key resolves from userConfig or its default\n`);
    process.exit(0);
  }
  // A key whose own value is invalid, or every key when the file does not
  // parse, drops this layer for that key. The repository is the highest layer,
  // so the key resolves to its default, never to the lower userConfig value. A
  // key the schema does not list is reported and leaves the other keys' values
  // in force, as compress reads them; apply still refuses to write over it.
  const problems = validate(existing);
  const parseError = problems.some((p) => p.kind === "parse");
  const out = problems.map((p) => `WARN ${p.msg}\n`);
  for (const k of Object.keys(keys)) {
    if (parseError || problems.some((p) => p.key === k)) {
      out.push(`WARN ${k}: dropped from ${REL}; resolves to its default, ${keys[k].default}, not to userConfig\n`);
      continue;
    }
    const v = spawnSync("bash", [READER, "-", k], { input: existing, encoding: "utf8" }).stdout.trim();
    out.push(`PASS ${k}: ${v || "(unset)"}\n`);
  }
  process.stdout.write(out.join(""));
  process.exit(problems.length ? 1 : 0);
}

// An existing file whose structure is wrong (a key set twice, a map or list
// in any form, an unknown key, a parse error) is left for a hand edit: replacing
// one line could not be trusted to leave the document the operator meant. A
// bad value on a key this run does not write is left for a hand edit too.
if (existing !== null) {
  const blocking = validate(existing).filter(
    (p) => !((p.kind === "empty" || p.kind === "value") && [...wanted.keys()].some((k) => p.msg.startsWith(`${REL}: ${k}`))),
  );
  if (blocking.length) {
    die(1, `the existing file needs a hand edit first; nothing written: ${blocking.map((p) => p.msg).join("; ")}`);
  }
}

let proposed;
if (existing === null) {
  proposed = `# yaml-language-server: $schema=${schema.$id}\n${[...wanted].map(([k, v]) => `${k}: ${v}\n`).join("")}`;
} else {
  // Keep the file's line endings: CRLF when every line break is CRLF. A file
  // that mixes the two is left for a hand edit.
  const crlf = (existing.match(/\r\n/g) ?? []).length;
  if (crlf && crlf !== (existing.match(/\n/g) ?? []).length) {
    die(1, `${REL} mixes CRLF and LF line endings; make them one kind first; nothing written`);
  }
  const eol = crlf ? "\r\n" : "\n";
  const lines = existing.split(eol);
  if (lines.at(-1) === "") lines.pop();
  for (const [k, v] of wanted) {
    const at = lines.findIndex((l) => l.match(TOP_KEY)?.[2] === k);
    if (at === -1) lines.push(`${k}: ${v}`);
    else lines[at] = `${k}: ${v}`;
  }
  proposed = `${lines.join(eol)}${eol}`;
}

const problems = validate(proposed);
if (problems.length) die(1, `the result would not validate; nothing written: ${problems.map((p) => p.msg).join("; ")}`);

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
  process.stdout.write(`${REL} exists and would change; nothing written. Show this diff, and re-run with --yes once the operator agrees.\n`);
  process.exit(3);
}

// Check the path again before each directory is created and once more before
// the write, and require the file to be what was read. The bytes go to a temp
// file opened with O_EXCL|O_NOFOLLOW beside the target, renamed over it. The
// temp name is fixed, so a leftover or a planted link at it is refused rather
// than followed; only a temp file this run created is removed.
for (const part of ["docs", "docs/conventions"]) {
  checkPath();
  if (!lstatOrNull(join(root, part), part)) {
    try {
      mkdirSync(join(root, part));
    } catch (e) {
      die(1, fsError(e, part));
    }
  }
}
if (readTarget() !== existing) die(1, `${REL} changed while this ran; nothing written, run again`);
const tmp = join(root, TMP_REL);
const flags = constants.O_WRONLY | constants.O_CREAT | constants.O_EXCL | (constants.O_NOFOLLOW ?? 0);
let fd = -1;
let created = false;
try {
  fd = openSync(tmp, flags, 0o644);
  created = true;
  writeSync(fd, proposed);
  // close(2) releases the descriptor even when it reports an error, so the
  // cleanup below never closes it a second time.
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
  if (!created && (e.code === "EEXIST" || e.code === "ELOOP")) {
    die(1, `${TMP_REL} already exists (another run, or one that stopped early); remove it and run again; nothing written`);
  }
  die(1, fsError(e, created ? REL : TMP_REL));
}
process.stdout.write(`wrote ${REL}\n${proposed}`);
