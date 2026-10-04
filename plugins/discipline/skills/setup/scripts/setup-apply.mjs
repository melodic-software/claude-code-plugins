#!/usr/bin/env node
// Write or check the repository layer of the discipline plugin's settings,
// docs/conventions/discipline.yaml, against schemas/discipline.schema.json.
//
// Usage:
//   setup-apply.mjs [--root <dir>] [--yes] <key>=<value> ...
//   setup-apply.mjs [--root <dir>] --check
//
//   --root <dir>  repository root; default: git's toplevel for the current
//                 directory. The file is always <root>/docs/conventions/discipline.yaml.
//   --yes         the operator has seen the diff and confirmed it; needed to
//                 change a file that already exists.
//   --check       validate the existing file and print one INFO, PASS or WARN
//                 line per finding; write nothing.
//
// validate(text) accepts a document only when it parses as the YAML subset,
// sets each top-level key once (keys compared after trimming), writes every key
// exactly as the schema names it, and gives each schema key one non-empty
// scalar from its list (its enum, or the bare words true and false for a
// boolean key, so a quoted "true" is invalid): no empty or empty-quoted value,
// no block or flow map or list; a $schema key, which apply never writes, must
// hold one non-empty, non-null string. Apply runs it on the existing file first and refuses that file unless
// every problem is an empty, null or out-of-list value on a key it writes, then
// runs it on the result. A key given twice on the command line is refused.
// The root may not be $HOME or an ancestor of it. checkPath() refuses a
// docs/ or docs/conventions/ that is not a real directory inside the root, and
// a target that is not a regular file with one link; it runs before reading,
// before each mkdir, and again right before the write and the rename. The write
// goes to an O_EXCL|O_NOFOLLOW temp file in the same directory, renamed over
// the target. Every refusal and filesystem failure is one stderr line, and a
// failed write removes its temp file.
//
// Exit codes: 0 written, already configured, or --check found a valid or
// absent file; 1 refused (invalid value or key, an invalid existing file, an
// unsafe path or root); 2 usage or environment error; 3 the existing file would
// change and --yes was not given (the diff is on stdout).

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

const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
const SCHEMA_PATH = join(SCRIPT_DIR, "..", "..", "..", "schemas", "discipline.schema.json");
const READER = join(SCRIPT_DIR, "parse-concern-value.sh");
const PARSER = join(SCRIPT_DIR, "yaml-subset.awk");
const NAME = "discipline.yaml";
const REL = `docs/conventions/${NAME}`;

class Refusal extends Error {
  constructor(message, code = 1) {
    super(message);
    this.code = code;
  }
}

function fsRefusal(what, e) {
  return new Refusal(`${what}: ${e?.code ?? e?.message ?? e}; nothing written`);
}

function lstatOrNull(p) {
  try {
    return lstatSync(p);
  } catch (e) {
    if (e.code === "ENOENT") return null;
    throw fsRefusal(p, e);
  }
}

function realpath(p) {
  try {
    return realpathSync(p);
  } catch (e) {
    throw fsRefusal(p, e);
  }
}

function parseArgs(args) {
  const opts = { root: "", yes: false, check: false, pairs: [] };
  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    if (a === "--root") {
      if (i + 1 >= args.length) throw new Refusal("--root needs a directory", 2);
      opts.root = args[++i];
    } else if (a === "--yes") opts.yes = true;
    else if (a === "--check") opts.check = true;
    else if (/^[^=-][^=]*=/.test(a)) opts.pairs.push(a);
    else {
      throw new Refusal(
        `unexpected argument: ${a}; usage: setup-apply.mjs [--root <dir>] [--yes] <key>=<value> ... | --check`,
        2,
      );
    }
  }
  if (opts.check && opts.pairs.length) throw new Refusal("--check takes no <key>=<value> arguments", 2);
  if (!opts.check && !opts.pairs.length) throw new Refusal("nothing to write; pass at least one <key>=<value>", 2);
  return opts;
}

// Top-level lines as written, in order, at the document's base indent:
// the raw key, the trimmed key, and the value text with any comment removed.
function topLevelLines(text) {
  const lines = text
    .split(/\r?\n/)
    .filter((l) => l.trim() && !/^\s*#/.test(l) && !/^(---|\.\.\.|%)/.test(l));
  const base = lines.length ? lines[0].match(/^\s*/)[0].length : 0;
  return lines
    .filter((l) => l.match(/^\s*/)[0].length === base)
    .map((l) => l.trim().match(/^(?:"([^"]*)"|'([^']*)'|([^"':#][^:]*?))\s*:(?:\s+|$)(.*)$/))
    .filter(Boolean)
    .map(([, dq, sq, bare, rest]) => {
      const raw = dq ?? sq ?? bare;
      return { raw, key: raw.trim(), value: rest.replace(/(^|\s+)#.*$/, "").trim() };
    });
}

const values = (spec) => (spec.type === "boolean" ? ["true", "false"] : spec.enum);

// Validate a whole document. Returns problems as { msg, key, fixable }; []
// means valid. A fixable problem is an empty (`key:`), null, ~ or other
// out-of-list value: apply clears it by writing a scalar over that key, and
// refuses a file with any other problem.
function validate(text, keys) {
  const parsed = spawnSync("awk", ["-f", PARSER], {
    input: text,
    encoding: "utf8",
    env: { ...process.env, LC_ALL: "C" },
  });
  if (parsed.status !== 0) {
    const err = parsed.stdout?.split("\n").find((l) => l.startsWith("error\t")) ?? "error\t?\tunreadable";
    const [, line, msg] = err.split("\t");
    return [{ msg: `line ${line}: ${msg}`, fixable: false }];
  }
  const records = parsed.stdout
    .split("\n")
    .filter(Boolean)
    .map((r) => {
      const tab = r.indexOf("\t");
      return { path: r.slice(0, tab), value: r.slice(tab + 1) };
    });
  const problems = [];
  const bad = (msg, key = null) => problems.push({ msg, key, fixable: key !== null });
  const tops = topLevelLines(text);
  const seen = new Set();
  for (const { raw, key } of tops) {
    if (seen.has(key)) bad(`key ${key} is set more than once`);
    seen.add(key);
    if (raw !== key) bad(`key "${raw}" has spaces around its name`);
    else if (key !== "$schema" && !Object.hasOwn(keys, key)) bad(`key ${key} is not in the schema`);
  }
  for (const { path } of records) {
    const top = path.split(".")[0];
    if (top !== "$schema" && !Object.hasOwn(keys, top.trim())) bad(`key ${top} is not in the schema`);
  }
  for (const [k, spec] of Object.entries(keys)) {
    const lines = tops.filter((t) => t.key === k);
    if (!lines.length) continue;
    const allowed = values(spec).join(", ");
    const scalar = records.find((r) => r.path.trim() === k);
    if (records.some((r) => r.path.trim().startsWith(`${k}.`)) || lines.some((t) => /^[[{]/.test(t.value))) {
      bad(`${k} holds a map or a list; it takes one of ${allowed}`);
    } else if (scalar?.value === "") {
      bad(`${k} is an empty string; it takes one of ${allowed}`);
    } else if (!scalar) {
      bad(`${k} is empty; it takes one of ${allowed}`, k);
    } else {
      // A boolean is read as written: the parser unquotes "true" to true.
      const v = spec.type === "boolean" ? lines[0].value : scalar.value;
      if (!values(spec).includes(v)) bad(`${k}=${v} is not one of ${allowed}`, k);
    }
  }
  // Apply never writes $schema, so a bad value there is never fixable.
  const schemaLine = tops.find((t) => t.key === "$schema");
  if (schemaLine) {
    const scalar = records.find((r) => r.path.trim() === "$schema");
    if (records.some((r) => r.path.trim().startsWith("$schema.")) || /^[[{]/.test(schemaLine.value)) {
      bad("$schema holds a map or a list; it takes one schema URL string");
    } else if (!scalar || scalar.value === "" || /^(~|null|Null|NULL)$/.test(schemaLine.value)) {
      bad("$schema is empty or null; it takes one schema URL string");
    }
  }
  return [...new Map(problems.map((p) => [p.msg, p])).values()];
}

function main(argv) {
  const opts = parseArgs(argv);
  let root = opts.root;
  if (!root) {
    const git = spawnSync("git", ["rev-parse", "--show-toplevel"], { encoding: "utf8" });
    if (git.status !== 0) throw new Refusal("not inside a git working tree; pass --root <dir>", 2);
    root = git.stdout.trim();
  }
  if (!lstatOrNull(root)?.isDirectory()) throw new Refusal(`root is not a directory: ${root}`, 2);
  const realRoot = realpath(root);

  // Root rule: the repository layer does not apply at $HOME or above it.
  const home = process.env.HOME || homedir();
  if (home && lstatOrNull(home)) {
    const realHome = realpath(home);
    const prefix = realRoot.endsWith(sep) ? realRoot : realRoot + sep;
    if (realRoot === realHome || realHome.startsWith(prefix)) {
      throw new Refusal(`root ${realRoot} is $HOME or an ancestor of it; the repository layer does not apply there; nothing written`);
    }
  }

  let schema;
  try {
    schema = JSON.parse(readFileSync(SCHEMA_PATH, "utf8"));
  } catch (e) {
    throw new Refusal(`cannot read the schema ${SCHEMA_PATH}: ${e.code ?? e.message}`, 2);
  }
  const keys = Object.fromEntries(Object.entries(schema.properties).filter(([k]) => k !== "$schema"));
  const target = join(root, REL);
  const conventions = join(root, "docs", "conventions");

  // Refuse any path shape that could send a write somewhere other than
  // <root>/docs/conventions/discipline.yaml. Returns true when the target exists.
  const checkPath = () => {
    for (const part of ["docs", "docs/conventions"]) {
      const st = lstatOrNull(join(root, part));
      if (!st) return false;
      if (st.isSymbolicLink()) throw new Refusal(`${part} is a symlink; refusing to write through it`);
      if (!st.isDirectory()) throw new Refusal(`${part} exists and is not a directory; nothing written`);
    }
    if (realpath(conventions) !== join(realRoot, "docs", "conventions")) {
      throw new Refusal("docs/conventions resolves outside the repository; nothing written");
    }
    const st = lstatOrNull(target);
    if (!st) return false;
    if (st.isSymbolicLink()) throw new Refusal(`${REL} is a symlink; refusing to write through it`);
    if (!st.isFile()) throw new Refusal(`${REL} exists and is not a regular file; nothing written`);
    if (st.nlink > 1) throw new Refusal(`${REL} has ${st.nlink} hard links; refusing to write through it`);
    return true;
  };

  const writeTarget = (text) => {
    // checkPath() runs before each mkdir, so a docs/ swapped for a symlink
    // after the first mkdir stops the second one.
    for (const part of ["docs", "docs/conventions"]) {
      checkPath();
      if (lstatOrNull(join(root, part))) continue;
      try {
        mkdirSync(join(root, part));
      } catch (e) {
        throw fsRefusal(part, e);
      }
    }
    checkPath();
    const tmp = join(conventions, `.${NAME}.${process.pid}.tmp`);
    const flags = constants.O_WRONLY | constants.O_CREAT | constants.O_EXCL | (constants.O_NOFOLLOW ?? 0);
    let fd = -1;
    try {
      fd = openSync(tmp, flags, 0o644);
    } catch (e) {
      throw fsRefusal(`${REL} temp file`, e);
    }
    try {
      writeSync(fd, text);
      // close(2) releases the descriptor even when it reports an error, so
      // the cleanup below must never close it a second time.
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
      throw e instanceof Refusal ? e : fsRefusal(REL, e);
    }
  };

  // Every pair is checked before the file is read or written.
  const wanted = [];
  for (const pair of opts.pairs) {
    const eq = pair.indexOf("=");
    const k = pair.slice(0, eq);
    const v = pair.slice(eq + 1);
    if (!Object.hasOwn(keys, k)) {
      throw new Refusal(`${k} is not a key of ${REL} (keys: ${Object.keys(keys).join(", ")}); nothing written`);
    }
    if (wanted.some(([seen]) => seen === k)) throw new Refusal(`${k} is given more than once; nothing written`);
    if (!values(keys[k]).includes(v)) throw new Refusal(`${k}=${v} is not one of ${values(keys[k]).join(", ")}; nothing written`);
    wanted.push([k, v]);
  }

  let existing = null;
  if (checkPath()) {
    try {
      existing = readFileSync(target, "utf8");
    } catch (e) {
      throw fsRefusal(REL, e);
    }
  }

  if (opts.check) {
    if (existing === null) {
      process.stdout.write(`INFO ${REL}: absent; every key resolves from userConfig or its default\n`);
      return 0;
    }
    const problems = validate(existing, keys);
    if (problems.length) {
      process.stdout.write(problems.map((p) => `WARN ${REL}: ${p.msg}\n`).join(""));
      return 1;
    }
    for (const k of Object.keys(keys)) {
      const v = spawnSync("bash", [READER, "-", k], { input: existing, encoding: "utf8" }).stdout.trim();
      process.stdout.write(`PASS ${k}: ${v || "(unset)"}\n`);
    }
    return 0;
  }

  // The existing file is validated first: apply overwrites only a fixable
  // value on a key it writes, and refuses the file for anything else.
  if (existing !== null) {
    const writing = new Set(wanted.map(([k]) => k));
    const blocking = validate(existing, keys).filter((p) => !(p.fixable && writing.has(p.key)));
    if (blocking.length) {
      throw new Refusal(`${REL}: ${blocking.map((p) => p.msg).join("; ")}; fix the file by hand, nothing written`);
    }
  }

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

  const problems = validate(proposed, keys);
  if (problems.length) {
    throw new Refusal(`the result would not validate (${problems.map((p) => p.msg).join("; ")}); nothing written`);
  }

  if (existing !== null && proposed === existing) {
    process.stdout.write(`${REL}: already configured; nothing written\n`);
    return 0;
  }

  if (existing !== null && !opts.yes) {
    const diff = spawnSync("diff", ["-u", "--label", `a/${REL}`, "--label", `b/${REL}`, target, "-"], {
      input: proposed,
      encoding: "utf8",
    });
    process.stdout.write(diff.stdout);
    process.stdout.write(
      `${REL} exists and would change; nothing written. Show this diff, and re-run with --yes once the operator confirms.\n`,
    );
    return 3;
  }

  writeTarget(proposed);
  process.stdout.write(`wrote ${REL}\n${proposed}`);
  return 0;
}

try {
  process.exitCode = main(process.argv.slice(2));
} catch (e) {
  // Any failure, expected or not, is one stderr line with no stack trace.
  const message = e instanceof Refusal ? e.message : `${e?.code ?? e?.message ?? e}; nothing written`;
  process.stderr.write(`setup-apply: ${String(message).split("\n")[0]}\n`);
  process.exitCode = e instanceof Refusal ? e.code : 1;
}
