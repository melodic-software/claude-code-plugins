// Write or check a plugin's repository settings file,
// docs/conventions/<plugin>.yaml, against the plugin's JSON Schema. Each
// plugin's skills/setup/scripts/setup-apply.mjs is a thin entry point that
// calls run() with its own paths.
//
// Usage of an entry point:
//   setup-apply.mjs [--root <dir>] [--yes] <key>=<value> ...
//   setup-apply.mjs [--root <dir>] --check [--ref <ref>]
//
//   --root <dir>  repository root; default: git's toplevel for the current
//                 directory. A symlinked root is resolved first, and every
//                 check below applies to the resolved directory.
//   --yes         the operator has seen the diff and confirmed it; needed to
//                 change a file that already exists.
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
// Allowed values come from the schema: `true` and `false` for a boolean key,
// the listed strings for an enum key (quoted or not in the file), and for an
// integer key an unquoted whole number from the schema's minimum (0 when
// absent) up to any maximum, with no sign, decimal point or leading zero. A
// command-line value is the bare word, so any quote makes it invalid.
//
// validate(text) reports every problem in a document: a parse error; a key
// set more than once (keys compared after trimming); a schema key whose value
// is out of the list or range, empty (`key:`), null or `~` (each fixable: apply
// may write over it), or an empty quoted string or a map or list in any form
// (not fixable). A top-level key outside the schema is a warning: it is
// ignored, apply keeps its line byte for byte, and the valid keys still count.
// It is refused when it is set twice or holds a map or a list.
//
// Apply validates the existing file first and refuses it, with one line and
// the file untouched, unless every problem is a fixable value on a key being
// written or a key outside the schema. It refuses a key outside the schema or
// a key given twice on the command line. It splits the file on its own line
// ending (a file mixing CRLF and LF is refused), writes each key over its own
// line or appends it, and validates the result.
//
// checkPath() refuses a root that is $HOME or an ancestor of it, a docs/ or
// docs/conventions/ that is a symlink, not a directory, or resolves outside
// the root, and a target that is a symlink, not a regular file, or has more
// than one link. It runs before reading, before each mkdir, before the temp
// file opens and before the rename. The write goes to a temp file opened with
// O_EXCL|O_NOFOLLOW beside the target, renamed over it once the target still
// holds what was read.
//
// Every refusal is one line on stderr with no stack trace, and a failure
// removes only a temp file this run created.
//
// Exit codes: 0 written, already configured, or --check found a valid or
// absent file; 1 refused (an invalid value or key, an invalid existing file,
// an unsafe path, a failed read or write), or --check found a problem; 2
// usage or environment error; 3 the existing file would change and --yes was
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
import { homedir } from "node:os";
import { join, sep } from "node:path";

class Refusal extends Error {
  constructor(message, code = 1) {
    super(message);
    this.code = code;
  }
}
const why = (e) => e?.code ?? e?.message ?? String(e);
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
  const opts = { root: "", yes: false, check: false, ref: null, pairs: [] };
  const usage = `usage: setup-apply.mjs [--root <dir>] [--yes] <key>=<value> ... | --check${withRef ? " [--ref <ref>]" : ""}`;
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--root") {
      if (i + 1 >= argv.length) refuse("--root needs a directory", 2);
      opts.root = argv[++i];
    } else if (withRef && a === "--ref") {
      if (i + 1 >= argv.length) refuse("--ref needs a commit id or origin/<name>", 2);
      opts.ref = argv[++i];
    } else if (a === "--yes") opts.yes = true;
    else if (a === "--check") opts.check = true;
    else if (/^[^=-][^=]*=/.test(a)) opts.pairs.push(a);
    else refuse(`unexpected argument: ${a}; ${usage}`, 2);
  }
  if (opts.check && opts.pairs.length) refuse("--check takes no <key>=<value> arguments", 2);
  if (opts.ref !== null && !opts.check) refuse("--ref is a --check option; a write always targets the working tree", 2);
  // Only a full commit id or origin/<name>: nothing git could read as an
  // option, a revision range, a path or a reflog expression.
  const r = opts.ref;
  if (r !== null && !(/^[0-9a-f]{40}$/.test(r) || (/^origin\/[A-Za-z0-9._/-]+$/.test(r) && !r.includes("..") && !r.startsWith("origin/-")))) {
    refuse(`invalid --ref ${JSON.stringify(r)}; expected a 40-hex commit id or origin/<name>`, 2);
  }
  if (!opts.check && !opts.pairs.length) refuse("nothing to write; pass at least one <key>=<value>", 2);
  return opts;
}

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

// Top-level keys as written, from lines at the document's base indent, each
// with its line index, the key as written, its trimmed form and its raw value
// (comment and surrounding space removed). The flattened parser output cannot
// show a key set twice, an empty value, a quoted value or an empty flow
// collection, so these checks read the lines. Line indexes count LF breaks, so
// they match a split on the file's own line ending.
function topLevelLines(text) {
  const content = text
    .replace(/^﻿/, "")
    .split("\n")
    .map((line, at) => ({ line: line.replace(/\r$/, ""), at }))
    .filter(({ line }) => line.trim() && !/^\s*#/.test(line) && !/^(---|\.\.\.|%)/.test(line));
  const base = content.length ? content[0].line.match(/^\s*/)[0].length : 0;
  return content
    .filter(({ line }) => line.match(/^\s*/)[0].length === base)
    .map(({ line, at }) => ({ at, m: line.trim().match(/^(?:"([^"]*)"|'([^']*)'|([^"':]+?))\s*:(?:\s+(.*))?$/) }))
    .filter(({ m }) => m)
    .map(({ at, m: [, dq, sq, bare, rest] }) => ({
      at,
      written: dq ?? sq ?? bare,
      key: (dq ?? sq ?? bare).trim(),
      raw: (rest ?? "").replace(/\s+#.*$/, "").trim(),
    }));
}

// Validate a whole document. Returns problems as { kind, key, msg, fixable };
// [] means valid. kind is "parse" (the file does not parse), "file" (another
// problem with the whole file), "unknown" (a key outside the schema, ignored)
// or "value" (a problem on the schema key named by key). fixable marks a value
// apply may overwrite.
function validate(text, { keys, parser, exactKeyNames = false, schemaKey = false }) {
  const parsed = spawnSync("awk", ["-f", parser], {
    input: text,
    encoding: "utf8",
    env: { ...process.env, LC_ALL: "C" },
  });
  if (parsed.error) refuse(`cannot run awk: ${why(parsed.error)}`, 2);
  if (parsed.status !== 0) {
    const err = (parsed.stdout ?? "").split("\n").find((l) => l.startsWith("error\t")) ?? "error\t?\tunreadable";
    const [, line, msg] = err.split("\t");
    return [{ kind: "parse", key: null, msg: `line ${line}: ${msg}`, fixable: false }];
  }
  const records = parsed.stdout
    .split("\n")
    .filter(Boolean)
    .map((r) => {
      const path = r.slice(0, r.indexOf("\t"));
      const dot = path.indexOf(".");
      return { top: (dot === -1 ? path : path.slice(0, dot)).trim(), nested: dot !== -1, value: r.slice(r.indexOf("\t") + 1) };
    });
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
    const line = tops.find((t) => t.key === k);
    if (!line) continue;
    const values = allowedText(spec);
    const { raw } = line;
    if (records.some((r) => r.top === k && r.nested) || /^[[{]/.test(raw)) {
      add("value", `${k} holds a map or a list${raw ? ` (${k}=${raw})` : ""}; it takes ${values}`, k);
    } else if (raw === '""' || raw === "''") {
      add("value", `${k} is an empty string (${k}=${raw}); it takes ${values}`, k);
    } else if (raw === "") {
      add("value", `${k} is empty; it takes ${values}`, k, true);
    } else if (/^(null|Null|NULL|~)$/.test(raw)) {
      add("value", `${k} is null; ${k}=${raw} is not ${values}`, k, true);
    } else if (!allows(spec, raw)) {
      add("value", `${k}=${raw} is not ${values}`, k, true);
    }
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
  process.stdout.write(problems.map((p) => `WARN ${rel}: ${p.msg}\n`).join(""));
  if (problems.some((p) => p.kind === "parse" || p.kind === "file")) return 1;
  for (const k of Object.keys(keys)) {
    if (problems.some((p) => p.key === k)) continue;
    process.stdout.write(`PASS ${k}: ${value(k) || "(unset)"}\n`);
  }
  return problems.length ? 1 : 0;
}
export function wholeFileReport({ rel, keys, problems, value }) {
  process.stdout.write(problems.map((p) => `WARN ${rel}: ${p.msg}\n`).join(""));
  if (problems.some((p) => p.kind !== "unknown")) return 1;
  for (const k of Object.keys(keys)) process.stdout.write(`PASS ${k}: ${value(k) || "(unset)"}\n`);
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
    process.stderr.write(`setup-apply: ${String(message).replace(/[\r\n]+/g, " ")}\n`);
    process.exitCode = e instanceof Refusal ? e.code : 1;
  }
}

function main(config, argv) {
  const name = `${config.plugin}.yaml`;
  const rel = `docs/conventions/${name}`;
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
  const target = join(root, rel);

  const checkRoot = () => {
    const realRoot = real(root, "root");
    const home = process.env.HOME || homedir();
    if (home) {
      let realHome = home;
      try {
        realHome = realpathSync(home);
      } catch {
        // An unresolvable home is compared as given.
      }
      if (realHome === realRoot || realHome.startsWith(realRoot.endsWith(sep) ? realRoot : realRoot + sep)) {
        refuse(`the root ${root} is $HOME or an ancestor of it, not a repository; nothing written`);
      }
    }
    return realRoot;
  };

  // Refuse any path shape that could send a write somewhere other than
  // <root>/docs/conventions/<plugin>.yaml. Returns true when the target exists.
  const checkPath = () => {
    const realRoot = checkRoot();
    for (const part of ["docs", "docs/conventions"]) {
      const st = lstatOrNull(join(root, part), part);
      if (!st) return false;
      if (st.isSymbolicLink()) refuse(`${part} is a symlink; refusing to write through it`);
      if (!st.isDirectory()) refuse(`${part} exists and is not a directory; nothing written`);
      if (real(join(root, part), part) !== join(realRoot, part)) refuse(`${part} resolves outside the repository; nothing written`);
    }
    const st = lstatOrNull(target, rel);
    if (!st) return false;
    if (st.isSymbolicLink()) refuse(`${rel} is a symlink; refusing to write through it`);
    if (st.isDirectory()) refuse(`${rel} is a directory where a file belongs; nothing written`);
    if (!st.isFile()) refuse(`${rel} exists and is not a regular file; nothing written`);
    if (st.nlink > 1) refuse(`${rel} has ${st.nlink} hard links; refusing to write through it`);
    return true;
  };

  const readTarget = () => {
    if (!checkPath()) return null;
    try {
      return readFileSync(target, "utf8");
    } catch (e) {
      refuse(`${rel}: could not read it (${why(e)}); nothing written`);
    }
  };

  // expected is the file as read at the start (null when absent); a target
  // that no longer matches it is refused rather than overwritten.
  const writeTarget = (text, expected) => {
    for (const part of ["docs", "docs/conventions"]) {
      checkPath();
      if (lstatOrNull(join(root, part), part)) continue;
      try {
        mkdirSync(join(root, part));
      } catch (e) {
        refuse(`${part}: could not create it (${why(e)}); nothing written`);
      }
    }
    if (readTarget() !== expected) refuse(`${rel} changed while this ran; nothing written, run again`);
    const tmpRel = `docs/conventions/.${name}.${config.fixedTemp ? "" : `${process.pid}.`}tmp`;
    const tmp = join(root, tmpRel);
    const flags = constants.O_WRONLY | constants.O_CREAT | constants.O_EXCL | (constants.O_NOFOLLOW ?? 0);
    let fd = -1;
    try {
      fd = openSync(tmp, flags, 0o644);
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
      checkPath();
      renameSync(tmp, target);
    } catch (e) {
      try {
        if (fd >= 0) closeSync(fd);
      } catch {}
      try {
        rmSync(tmp, { force: true });
      } catch {}
      if (e instanceof Refusal) throw e;
      refuse(`${rel}: could not write it (${why(e)}); nothing written`);
    }
  };

  // The file as committed at --ref: { sha, text }, text null when the commit
  // has no such path. Every git argument is the validated ref, a resolved
  // object id or a fixed string, passed without a shell.
  const readAtRef = () => {
    checkRoot();
    const ref = opts.ref;
    const git = (...a) => spawnSync("git", ["-C", root, ...a], { encoding: "utf8" });
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

  // Command-line pairs are checked before the file is read, so a bad request
  // is refused the same way whether the file exists or not.
  const wanted = new Map();
  for (const pair of opts.pairs) {
    const eq = pair.indexOf("=");
    const k = pair.slice(0, eq).trim();
    const v = pair.slice(eq + 1);
    if (wanted.has(k)) refuse(`${k} is given more than once; pass each key once; nothing written`);
    if (!Object.hasOwn(keys, k)) refuse(`${k} is not a key of ${rel} (keys: ${Object.keys(keys).join(", ")}); nothing written`);
    if (/^["']/.test(v) || !allows(keys[k], v)) refuse(`${k}=${v} is not ${allowedText(keys[k])}; nothing written`);
    wanted.set(k, v);
  }

  let existing = null;
  if (opts.ref !== null) {
    const at = readAtRef();
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
    const value = (k) => spawnSync("bash", [config.reader, "-", k], { input: existing, encoding: "utf8" }).stdout.trim();
    return (config.report ?? perKeyReport)({ rel, keys, problems: check(existing), value });
  }

  if (existing !== null) {
    const found = check(existing);
    const blocking = found.filter((p) => p.kind !== "unknown" && !(p.fixable && wanted.has(p.key)));
    if (blocking.length) refuse(`${rel}: ${blocking.map((p) => p.msg).join("; ")}; fix the file by hand, nothing written`);
    for (const p of found.filter((p) => p.kind === "unknown")) {
      process.stderr.write(`setup-apply: WARN ${rel}: ${p.msg}; it is ignored and its line is kept as written\n`);
    }
  }

  let proposed;
  if (existing === null) {
    proposed = `# yaml-language-server: $schema=${schema.$id}\n${[...wanted].map(([k, v]) => `${k}: ${v}\n`).join("")}`;
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
    for (const [k, v] of wanted) {
      const line = tops.find((t) => t.key === k);
      if (line) lines[line.at] = `${lines[line.at].match(/^\s*/)[0]}${k}: ${v}`;
      else lines.push(`${k}: ${v}`);
    }
    proposed = `${lines.join(eol)}${eol}`;
  }

  const problems = check(proposed).filter((p) => p.kind !== "unknown");
  if (problems.length) refuse(`the result would not validate: ${problems.map((p) => p.msg).join("; ")}; nothing written`);

  if (existing !== null && proposed === existing) {
    process.stdout.write(`${rel}: already configured; nothing written\n`);
    return 0;
  }

  if (existing !== null && !opts.yes) {
    const diff = spawnSync("diff", ["-u", "--label", `a/${rel}`, "--label", `b/${rel}`, target, "-"], {
      input: proposed,
      encoding: "utf8",
    });
    process.stdout.write(diff.stdout);
    process.stdout.write(`${rel} exists and would change; nothing written. Show this diff, and re-run with --yes once the operator confirms.\n`);
    return 3;
  }

  writeTarget(proposed, existing);
  process.stdout.write(`wrote ${rel}\n${proposed}`);
  return 0;
}
