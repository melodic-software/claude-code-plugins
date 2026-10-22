#!/usr/bin/env node
// Node half of tools/findings-buffer/buffer.sh. Three subcommands:
//   adapter --project DIR   print the bound adapter: `local-file`, or the physical directory of the
//                           plugin adapter <home>/findings-buffer.yaml (overlay .local.yaml) names,
//                           resolved through the config cascade (lib/config-cascade.mjs, ADR 0075).
//                           Only the plugin's own tools/findings-buffer/adapters/ are run: a binding
//                           is repository-writable, so it never names repository code.
//                           A missing or unusable binding prints `local-file` and says why on stderr.
//   prepare                 JSONL rows on stdin (already redacted) -> capped rows with obs_id and ts.
//   dedupe                  JSONL rows on stdin -> the first row per obs_id, as read.
// Exit: 0 ok, 1 failure (an unreadable row on dedupe), 2 usage or a line that is not a JSON object.
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { accessSync, constants, mkdtempSync, readFileSync, realpathSync, rmSync, statSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve as resolvePath, sep } from "node:path";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";
import { resolve } from "./lib/config-cascade.mjs";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const PLUGIN = "findings-buffer";
const DEFAULT_HOME = "docs/conventions";
const CAP = 2048;
// The stored row adds `"obs_id":"<16 hex>",` (28 bytes) and `"ts":"<ts>",` (8 + up to 30 bytes) to
// the content, so the content is capped to a budget that holds for every ts this keeps.
const BUDGET = CAP - 28 - 38;
const FLOOR = 64;
const OBS_ID = /^[0-9a-f]{16}$/;
const TS = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,9})?Z$/;
const ADAPTERS = join(ROOT, "tools/findings-buffer/adapters");
const NAME = /^[A-Za-z0-9._-]+$/;

const say = (text) => process.stderr.write(`findings-buffer: ${text}\n`);
const bytes = (value) => Buffer.byteLength(JSON.stringify(value), "utf8");
const isContainer = (v) => v !== null && typeof v === "object";

function lines(text) {
  return text.split("\n").filter((line) => /\S/.test(line));
}

// ---------- adapter ----------

function gitRoot(dir) {
  const r = spawnSync("git", ["-C", dir, "rev-parse", "--show-toplevel"], { cwd: ROOT, encoding: "utf8" });
  return r.status === 0 ? r.stdout.trim() : dir;
}

/** {home} or {home: null, why} from the project's pointer line, as lib/resolve-convention-home.sh reports it. */
function conventionHome(project) {
  const r = spawnSync("bash", [join(ROOT, "lib/resolve-convention-home.sh"), "--root", project], { cwd: ROOT, encoding: "utf8", timeout: 15_000 });
  if (r.status === 0) return { home: r.stdout.trim() };
  if (r.status === 1) return { home: DEFAULT_HOME };
  if (r.status === 4) return { home: null, why: "the repository declined a convention home" };
  if (r.status === 5) return { home: null, why: "no convention home applies to this project" };
  const cause = r.error?.code || r.stderr?.trim().split("\n").at(-1) || `exit ${r.status}`;
  return { home: null, why: `the convention home is unresolved (${cause})` };
}

/** Why the plugin adapter named `token` is unusable, or {dir} with its physical path. */
function checkAdapter(token) {
  if (!NAME.test(token) || token === "." || token === "..") {
    return { why: "not the bare name of a plugin adapter; a repository path is never run" };
  }
  let base;
  let dir;
  try {
    base = realpathSync(ADAPTERS);
    dir = realpathSync(join(ADAPTERS, token));
  } catch {
    return { why: "the plugin ships no adapter by that name" };
  }
  if (!dir.startsWith(base + sep)) return { why: "it resolves outside the plugin's adapters directory" };
  if (!statSync(dir).isDirectory()) return { why: "not a directory" };
  for (const verb of ["append.sh", "read.sh"]) {
    let real;
    try {
      real = realpathSync(join(dir, verb));
    } catch {
      return { why: `${verb} is missing` };
    }
    if (!real.startsWith(dir + sep) || !statSync(real).isFile()) return { why: `${verb} is not a regular file inside the adapter directory` };
    try {
      accessSync(real, constants.X_OK);
    } catch {
      return { why: `${verb} is not executable` };
    }
  }
  let caps;
  try {
    caps = JSON.parse(readFileSync(join(dir, "capabilities.json"), "utf8"));
  } catch {
    return { why: "capabilities.json is missing or not JSON" };
  }
  const major = /^(\d+)\.\d+$/.exec(typeof caps?.schema_version === "string" ? caps.schema_version : "")?.[1];
  if (major !== "1") return { why: `capabilities.json schema_version ${JSON.stringify(caps?.schema_version)} is not 1.x` };
  return { dir };
}

function adapter(project) {
  const schema = JSON.parse(readFileSync(join(ROOT, "schemas/findings-buffer.schema.json"), "utf8"));
  const { home, why } = conventionHome(project);
  if (home === null) {
    say(`${why}, so no binding is read; using local-file`);
    return "local-file";
  }
  const scratch = mkdtempSync(join(tmpdir(), "findings-buffer-"));
  let out;
  try {
    out = resolve({ plugin: PLUGIN, projectRoot: project, home, schema, defaults: { adapter: "local-file" }, userHome: scratch });
  } finally {
    rmSync(scratch, { recursive: true, force: true });
  }
  for (const layer of out.layers) for (const error of layer.errors) say(error);
  const token = out.values.adapter;
  const from = out.provenance.adapter;
  if (from === "defaults") {
    say(`no adapter bound in ${home}/${PLUGIN}.yaml; using local-file`);
    return "local-file";
  }
  if (token === "local-file") return "local-file";
  const file = out.layers.find((l) => l.name === from)?.path ?? `${home}/${PLUGIN}.yaml`;
  const checked = checkAdapter(token);
  if (checked.why) {
    say(`adapter ${JSON.stringify(token)} from ${file} is refused (${checked.why}); using local-file`);
    return "local-file";
  }
  return checked.dir;
}

// ---------- prepare ----------

/** RFC 8785 canonical JSON: keys sorted by UTF-16 code units, leaves as JSON.stringify writes them. */
function canonical(value) {
  if (Array.isArray(value)) return `[${value.map(canonical).join(",")}]`;
  if (isContainer(value)) {
    return `{${Object.keys(value)
      .sort()
      .map((k) => `${JSON.stringify(k)}:${canonical(value[k])}`)
      .join(",")}}`;
  }
  return JSON.stringify(value);
}

/** Every [holder, key] under `value`, depth first in sorted key order, whose value matches `pick`. */
function slots(value, pick, out = []) {
  // Sorted, as in `canonical`, so a reordered row trims the same field and keeps its obs_id.
  for (const key of Object.keys(value).sort()) {
    const v = value[key];
    if (pick(v)) out.push([value, key]);
    if (isContainer(v)) slots(v, pick, out);
  }
  return out;
}

/** The slot with the largest serialized value; the first one wins a tie. */
function largest(list) {
  let best = null;
  let size = -1;
  for (const slot of list) {
    const s = bytes(slot[0][slot[1]]);
    if (s > size) [best, size] = [slot, s];
  }
  return best;
}

/** Caps `content` to BUDGET bytes without regard to ts, so a retried row keeps its obs_id. Mutates. */
function cap(content) {
  if (bytes(content) <= BUDGET) return content;
  content.truncated = true;
  // 1. Trim the longest strings, never below FLOOR code points.
  for (;;) {
    const excess = bytes(content) - BUDGET;
    if (excess <= 0) return content;
    const slot = largest(slots(content, (v) => typeof v === "string" && [...v].length > FLOOR));
    if (!slot) break;
    // Keep the longest whole-code-point prefix whose encoding fits, and at least FLOOR code points.
    const chars = [...slot[0][slot[1]]];
    let room = bytes(slot[0][slot[1]]) - 2 - excess;
    let keep = 0;
    while (keep < chars.length) {
      room -= bytes(chars[keep]) - 2;
      if (room < 0 && keep >= FLOOR) break;
      keep++;
    }
    slot[0][slot[1]] = chars.slice(0, keep).join("");
  }
  // 2. Replace the largest nested arrays and objects with a size note.
  for (;;) {
    if (bytes(content) <= BUDGET) return content;
    const slot = largest(slots(content, (v) => isContainer(v) && bytes(v) > 32));
    if (!slot) break;
    slot[0][slot[1]] = `[omitted: ${bytes(slot[0][slot[1]])} bytes]`;
  }
  // 3. Drop the largest top-level fields.
  while (bytes(content) > BUDGET) {
    const key = Object.keys(content)
      .sort()
      .filter((k) => k !== "truncated")
      .reduce((a, k) => (a === null || bytes(content[k]) + k.length > bytes(content[a]) + a.length ? k : a), null);
    if (key === null) break;
    delete content[key];
  }
  return content;
}

function prepare(text) {
  const now = new Date().toISOString().replace(/\.\d{3}Z$/, "Z");
  const out = [];
  for (const [n, line] of lines(text).entries()) {
    let row;
    try {
      row = JSON.parse(line);
    } catch {
      row = undefined;
    }
    if (!isContainer(row) || Array.isArray(row)) {
      say(`row ${n + 1} is not a JSON object; nothing appended`);
      process.exit(2);
    }
    const { obs_id: id, ts, ...content } = row;
    cap(content);
    const obsId = typeof id === "string" && OBS_ID.test(id) ? id : createHash("sha256").update(canonical(content)).digest("hex").slice(0, 16);
    out.push(JSON.stringify({ obs_id: obsId, ts: typeof ts === "string" && TS.test(ts) ? ts : now, ...content }));
  }
  return out;
}

// ---------- dedupe ----------

function dedupe(text) {
  const seen = new Set();
  const out = [];
  for (const line of lines(text)) {
    let row;
    try {
      row = JSON.parse(line);
    } catch {
      say("an adapter returned a line that is not JSON; refusing to return a partial read");
      process.exit(1);
    }
    const id = isContainer(row) && typeof row.obs_id === "string" ? row.obs_id : null;
    if (id !== null) {
      if (seen.has(id)) continue;
      seen.add(id);
    }
    out.push(line.trim());
  }
  return out;
}

const { values: opts, positionals } = parseArgs({ allowPositionals: true, options: { project: { type: "string" } } });
const command = positionals[0];
const stdin = () => readFileSync(0, "utf8");
const print = (rows) => process.stdout.write(rows.map((r) => `${r}\n`).join(""));
if (command === "adapter" && positionals.length === 1) {
  console.log(adapter(resolvePath(opts.project ?? gitRoot(process.cwd()))));
} else if (command === "prepare" && positionals.length === 1) {
  print(prepare(stdin()));
} else if (command === "dedupe" && positionals.length === 1) {
  print(dedupe(stdin()));
} else {
  say("usage: findings-buffer.mjs adapter [--project DIR] | prepare | dedupe");
  process.exit(2);
}
