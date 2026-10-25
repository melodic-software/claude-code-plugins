#!/usr/bin/env node
// Node half of tools/findings-buffer/buffer.sh. Three subcommands:
//   adapter --project DIR   print the bound adapter: `local-file`, or the physical directory of the
//                           adapter the user-scope binding names for this repository, else of the
//                           plugin adapter <home>/findings-buffer.yaml (overlay .local.yaml) names,
//                           both resolved through the config cascade (lib/config-cascade.mjs, ADR 0075).
//                           The repository files are repository-writable, so they name only the
//                           plugin's own tools/findings-buffer/adapters/. Repository code runs only
//                           from the user-scope binding: the userConfig options
//                           findings_buffer_adapter_repository (the git common directory it applies
//                           to) and findings_buffer_adapter_path (relative to the checkout root), read
//                           from user and managed settings only (lib/plugin-options.mjs).
//                           A missing or unusable binding prints `local-file` and says why on stderr.
//   prepare                 JSONL rows on stdin (already redacted) -> capped rows with obs_id and ts.
//   dedupe                  JSONL rows on stdin -> the first row per obs_id, as read.
// Exit: 0 ok, 1 failure (an unreadable row on dedupe), 2 usage or a line that is not a JSON object.
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { accessSync, constants, mkdtempSync, readFileSync, realpathSync, rmSync, statSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, isAbsolute, join, resolve as resolvePath, sep } from "node:path";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";
import { resolve } from "./lib/config-cascade.mjs";
import { managedSettingsFiles, OptionsError, readOperatorOptions, resolveInstall } from "./lib/plugin-options.mjs";

// The plugin root from this script's real path, never from the environment: it anchors the user settings read.
const ROOT = resolvePath(dirname(realpathSync.native(fileURLToPath(import.meta.url))), "..");
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
// The user-scope binding's keys, outside schemas/findings-buffer.schema.json, so the repository files never set them.
const USER_KEYS = ["findings_buffer_adapter_repository", "findings_buffer_adapter_path"];
const USER_SCHEMA = {
  type: "object",
  properties: {
    findings_buffer: { type: "object", properties: { adapter_repository: { type: "string" }, adapter_path: { type: "string" } } },
  },
};
// A repository's settings env block reaches this process, and GIT_* there could point git at another repository.
const GIT_ENV = Object.fromEntries(Object.entries(process.env).filter(([key]) => !key.startsWith("GIT_")));

const say = (text) => process.stderr.write(`findings-buffer: ${text}\n`);
const bytes = (value) => Buffer.byteLength(JSON.stringify(value), "utf8");
const isContainer = (v) => v !== null && typeof v === "object";

function lines(text) {
  return text.split("\n").filter((line) => /\S/.test(line));
}

// ---------- adapter ----------

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

/** Why the adapter directory `candidate` is unusable, or {dir} with its physical path, which must lie inside `base`. */
function checkAdapter(base, candidate, { where, missing }) {
  let root;
  let dir;
  try {
    root = realpathSync(base);
    dir = realpathSync(candidate);
  } catch {
    return { why: missing };
  }
  if (!dir.startsWith(root + sep)) return { why: `it does not resolve inside ${where}` };
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

/** checkAdapter for the plugin adapter named `token`. */
function pluginAdapter(token) {
  if (!NAME.test(token) || token === "." || token === "..") {
    return { why: "not the bare name of a plugin adapter; a repository path is bound only in user scope" };
  }
  return checkAdapter(ADAPTERS, join(ADAPTERS, token), { where: "the plugin's adapters directory", missing: "the plugin ships no adapter by that name" });
}

/** stdout of `git -C dir args...` with no GIT_* variables, or null when it fails. */
function git(dir, ...args) {
  const r = spawnSync("git", ["-C", dir, ...args], { cwd: ROOT, encoding: "utf8", env: GIT_ENV });
  return r.status === 0 ? r.stdout.trim() : null;
}

function physical(path) {
  try {
    return realpathSync(path);
  } catch {
    return null;
  }
}

/** The adapter the user-scope binding names for the checkout at `project`: {dir}, {why} when it is
 * refused, or null when no binding is set or it names another repository. */
function userBinding(project, scratch) {
  let options;
  try {
    options = readOperatorOptions(resolveInstall(ROOT), managedSettingsFiles(), USER_KEYS);
  } catch (error) {
    if (!(error instanceof OptionsError)) throw error;
    return { why: error.message };
  }
  const userConfig = Object.fromEntries(Object.entries(options).map(([key, { value }]) => [key, value]));
  // The scratch home holds no file, so only the userConfig layer can set a value.
  const out = resolve({ plugin: PLUGIN, projectRoot: project, home: scratch, schema: USER_SCHEMA, defaults: {}, userConfig, userHome: scratch });
  for (const layer of out.layers) for (const error of layer.errors) say(error);
  const { adapter_repository: repository, adapter_path: path } = out.values.findings_buffer ?? {};
  if (repository === undefined && path === undefined) return null;
  if (repository === undefined || path === undefined) return { why: `it needs both ${USER_KEYS.join(" and ")}` };
  if (!isAbsolute(repository)) return { why: "findings_buffer_adapter_repository is not an absolute path" };
  const here = owner(project);
  if (here === null) return { why: "git cannot name this checkout's repository" };
  const bound = physical(repository);
  if (bound !== null && bound === here.top) return { why: "findings_buffer_adapter_repository names the checkout root, not the git common directory" };
  if (bound === null || bound !== here.common) return null;
  if (isAbsolute(path)) return { why: "findings_buffer_adapter_path is not relative to the repository root" };
  const checked = checkAdapter(here.top, resolvePath(here.top, path), { where: "this checkout", missing: "no such directory in this checkout" });
  if (checked.why) return checked;
  // The directory and each verb's real location belong to this checkout, not to a repository nested in it.
  for (const dir of [checked.dir, ...["append.sh", "read.sh"].map((verb) => dirname(realpathSync(join(checked.dir, verb))))]) {
    const found = owner(dir);
    if (found === null || found.top !== here.top || found.common !== here.common) return { why: "it lies inside another git repository nested in this one" };
  }
  return checked;
}

/** The physical checkout root and git common directory git reports for `dir`, or null. */
function owner(dir) {
  const out = git(dir, "rev-parse", "--show-toplevel", "--git-common-dir")?.split("\n");
  if (out?.length !== 2) return null;
  const top = physical(out[0]);
  const common = physical(resolvePath(dir, out[1]));
  return top === null || common === null ? null : { top, common };
}

function adapter(project) {
  const scratch = mkdtempSync(join(tmpdir(), "findings-buffer-"));
  try {
    const user = userBinding(project, scratch);
    if (user?.dir) return user.dir;
    if (user?.why) say(`the user-scope adapter binding is refused (${user.why}); reading the repository binding`);
    return fileBinding(project, scratch);
  } finally {
    rmSync(scratch, { recursive: true, force: true });
  }
}

function fileBinding(project, scratch) {
  const schema = JSON.parse(readFileSync(join(ROOT, "schemas/findings-buffer.schema.json"), "utf8"));
  const { home, why } = conventionHome(project);
  if (home === null) {
    say(`${why}, so no binding is read; using local-file`);
    return "local-file";
  }
  const out = resolve({ plugin: PLUGIN, projectRoot: project, home, schema, defaults: { adapter: "local-file" }, userHome: scratch });
  for (const layer of out.layers) for (const error of layer.errors) say(error);
  const token = out.values.adapter;
  const from = out.provenance.adapter;
  if (from === "defaults") {
    say(`no adapter bound in ${home}/${PLUGIN}.yaml; using local-file`);
    return "local-file";
  }
  if (token === "local-file") return "local-file";
  const file = out.layers.find((l) => l.name === from)?.path ?? `${home}/${PLUGIN}.yaml`;
  const checked = pluginAdapter(token);
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
  console.log(adapter(resolvePath(opts.project ?? git(process.cwd(), "rev-parse", "--show-toplevel") ?? process.cwd())));
} else if (command === "prepare" && positionals.length === 1) {
  print(prepare(stdin()));
} else if (command === "dedupe" && positionals.length === 1) {
  print(dedupe(stdin()));
} else {
  say("usage: findings-buffer.mjs adapter [--project DIR] | prepare | dedupe");
  process.exit(2);
}
