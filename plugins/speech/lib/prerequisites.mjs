#!/usr/bin/env node
// GENERATED from lib/prerequisites.mjs by scripts/sync-shared-copies.sh. Do not edit this copy:
// edit the canonical source, then rerun the script.
// Read a plugin's prerequisites.json and report which declared dependencies resolve.
// The contract is docs/conventions/prerequisites/README.md; the schema sits beside it.
//
//   prerequisites.mjs report --plugin-root <dir> [--plugin-root <dir>...]
//   prerequisites.mjs check <plugin-root> [--for <scope>] [--data-dir <dir>]
//   prerequisites.mjs probe <plugin-root>
//
// report  One TSV table across plugins, then a missing/present summary line.
// check   One line per entry with the remediation, for setup and check skills.
//         --for keeps the entries scoped to that skill, hook or MCP server, plus
//         the plugin-wide ones. --data-dir is the plugin data directory, which a
//         command run through the Bash tool does not get in its environment.
// probe   A SessionStart hook. Notifies once per session for each missing entry a
//         hook needs, on both hook channels. Always exits 0 on a valid manifest,
//         because Claude Code reads hook JSON only from a zero exit.
//
// Exit 0: every required entry resolves. Exit 1: a required entry is missing or
// below its version floor. Exit 2: a usage error or a manifest that fails the schema.
// Standard library only. It never installs anything and never prints an env value.
import { spawnSync } from "node:child_process";
import {
  accessSync,
  constants,
  existsSync,
  mkdirSync,
  readFileSync,
  realpathSync,
  statSync,
  writeFileSync,
} from "node:fs";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

export const KINDS = ["cli", "runtime", "system-lib", "python-pkg", "node-pkg", "env", "mcp"];
export const NEEDS = ["required", "optional"];
const ENTRY_KEYS = ["id", "kind", "need", "for", "detect", "degrade", "install", "check"];
const DETECT_KEYS = {
  cli: { required: ["any"], optional: ["local_bin", "version"] },
  runtime: { required: ["any"], optional: ["local_bin", "version"] },
  "system-lib": { required: ["probe"], optional: [] },
  "python-pkg": { required: ["any", "import"], optional: [] },
  "node-pkg": { required: ["module", "paths"], optional: [] },
  env: { required: ["name"], optional: [] },
  mcp: { required: ["server"], optional: [] },
};
const ID_RE = /^[a-z0-9][a-z0-9._+-]*$/;
const FOR_RE = /^(plugin|(skill|hook|mcp):[A-Za-z0-9._/-]+)$/;
const CHECK_RE = /^\/[a-z0-9-]+:[a-z0-9-]+( [^\n]+)?$/;
const MIN_RE = /^\d+(\.\d+)*$/;
const MODULE_RE = /^[A-Za-z_]\w*(\.[A-Za-z_]\w*)*$/;
const NPM_RE = /^(@[a-z0-9._-]+\/)?[a-z0-9._-]+$/;
const ENV_RE = /^[A-Za-z_]\w*$/;
const SERVER_RE = /^[A-Za-z0-9._-]+$/;
const MANAGER_RE = /^[a-z][a-z0-9-]*$/;
const PROBE_TIMEOUT_MS = 5000;
const LOCAL_BIN_DEPTH = 8;

const isObject = (v) => v !== null && typeof v === "object" && !Array.isArray(v);
const isText = (v) => typeof v === "string" && v.trim() !== "";
const isTextList = (v) => Array.isArray(v) && v.length > 0 && v.every(isText);

function keysErrors(obj, allowed, where) {
  return Object.keys(obj)
    .filter((k) => !allowed.includes(k))
    .map((k) => `${where}: unknown key "${k}"`);
}

function patternErrors(pattern, where, needsGroup) {
  if (!isText(pattern)) return [`${where}.pattern must be a non-empty string`];
  try {
    const groups = new RegExp(`${pattern}|`).exec("").length - 1;
    if (needsGroup && groups < 1) return [`${where}.pattern needs a capture group for the version`];
  } catch (err) {
    return [`${where}.pattern is not a valid regular expression: ${err.message}`];
  }
  return [];
}

function relativePathErrors(list, where) {
  if (!isTextList(list)) return [`${where} must be a non-empty list of paths`];
  return list
    .filter((p) => path.isAbsolute(p) || p.split(/[\\/]/).includes(".."))
    .map((p) => `${where}: "${p}" must be relative and stay inside its base`);
}

function detectErrors(kind, detect, where) {
  if (!isObject(detect)) return [`${where} must be an object`];
  const shape = DETECT_KEYS[kind];
  const errors = keysErrors(detect, [...shape.required, ...shape.optional], where);
  for (const key of shape.required) {
    if (!(key in detect)) errors.push(`${where}.${key} is required for kind ${kind}`);
  }
  if ("any" in detect && !isTextList(detect.any)) errors.push(`${where}.any must be a non-empty list of names`);
  if ("local_bin" in detect) errors.push(...relativePathErrors(detect.local_bin, `${where}.local_bin`));
  if ("version" in detect) {
    const v = detect.version;
    const vw = `${where}.version`;
    if (!isObject(v)) {
      errors.push(`${vw} must be an object`);
    } else {
      errors.push(...keysErrors(v, ["args", "pattern", "min"], vw));
      if (!Array.isArray(v.args) || !v.args.every((a) => typeof a === "string")) {
        errors.push(`${vw}.args must be a list of strings`);
      }
      errors.push(...patternErrors(v.pattern, vw, true));
      if (typeof v.min !== "string" || !MIN_RE.test(v.min))
        errors.push(`${vw}.min must be a dotted number such as 2.94.0`);
    }
  }
  if ("probe" in detect) {
    const p = detect.probe;
    const pw = `${where}.probe`;
    if (!isObject(p)) {
      errors.push(`${pw} must be an object`);
    } else {
      errors.push(...keysErrors(p, ["args", "pattern"], pw));
      if (!isTextList(p.args)) errors.push(`${pw}.args must be a non-empty list; the first item is the binary`);
      errors.push(...patternErrors(p.pattern, pw, false));
    }
  }
  if ("import" in detect && !(typeof detect.import === "string" && MODULE_RE.test(detect.import))) {
    errors.push(`${where}.import must be a Python module name`);
  }
  if ("module" in detect && !(typeof detect.module === "string" && NPM_RE.test(detect.module))) {
    errors.push(`${where}.module must be an npm package name`);
  }
  if ("paths" in detect) {
    // A path is relative to the plugin root, or starts with ${CLAUDE_PLUGIN_ROOT} or ${CLAUDE_PLUGIN_DATA}.
    const strip = (p) => (typeof p === "string" ? p.replace(/^\$\{CLAUDE_PLUGIN_(DATA|ROOT)\}\/?/, "") || "." : p);
    errors.push(
      ...relativePathErrors(Array.isArray(detect.paths) ? detect.paths.map(strip) : detect.paths, `${where}.paths`),
    );
  }
  if ("name" in detect && !(typeof detect.name === "string" && ENV_RE.test(detect.name))) {
    errors.push(`${where}.name must be an environment variable name`);
  }
  if ("server" in detect && !(typeof detect.server === "string" && SERVER_RE.test(detect.server))) {
    errors.push(`${where}.server must be an MCP server name`);
  }
  return errors;
}

function entryErrors(entry, where) {
  if (!isObject(entry)) return [`${where} must be an object`];
  const errors = keysErrors(entry, ENTRY_KEYS, where);
  for (const key of ENTRY_KEYS) {
    if (!(key in entry)) errors.push(`${where}.${key} is required`);
  }
  if ("id" in entry && !(typeof entry.id === "string" && ID_RE.test(entry.id))) {
    errors.push(`${where}.id must match ${ID_RE.source}`);
  }
  if ("kind" in entry && !KINDS.includes(entry.kind)) errors.push(`${where}.kind must be one of ${KINDS.join(", ")}`);
  if ("need" in entry && !NEEDS.includes(entry.need)) errors.push(`${where}.need must be one of ${NEEDS.join(", ")}`);
  if ("for" in entry) {
    const scopes = entry.for;
    if (!Array.isArray(scopes) || scopes.length === 0) {
      errors.push(`${where}.for must be a non-empty list`);
    } else {
      for (const s of scopes) {
        if (typeof s !== "string" || !FOR_RE.test(s)) {
          errors.push(`${where}.for: "${s}" must be plugin, skill:<name>, hook:<script> or mcp:<server>`);
        }
      }
      if (new Set(scopes).size !== scopes.length) errors.push(`${where}.for repeats a scope`);
    }
  }
  if ("detect" in entry && KINDS.includes(entry.kind))
    errors.push(...detectErrors(entry.kind, entry.detect, `${where}.detect`));
  if ("degrade" in entry && !isText(entry.degrade)) errors.push(`${where}.degrade must say what stops working`);
  if ("install" in entry) {
    const inst = entry.install;
    if (!isObject(inst) || Object.keys(inst).length === 0) {
      errors.push(`${where}.install must be an object with at least one hint`);
    } else {
      for (const [k, v] of Object.entries(inst)) {
        if (!MANAGER_RE.test(k)) errors.push(`${where}.install: "${k}" is not a package-manager key`);
        if (!isText(v)) errors.push(`${where}.install.${k} must be a non-empty string`);
      }
    }
  }
  if ("check" in entry && !(typeof entry.check === "string" && CHECK_RE.test(entry.check))) {
    errors.push(`${where}.check must name a skill, such as /<plugin>:check`);
  }
  return errors;
}

// validateManifest(value) -> list of schema errors; empty means valid.
export function validateManifest(manifest) {
  if (!isObject(manifest)) return ["the manifest must be a JSON object"];
  const errors = keysErrors(manifest, ["$schema", "requires"], "manifest");
  if ("$schema" in manifest && typeof manifest.$schema !== "string") errors.push("manifest.$schema must be a string");
  if (!Array.isArray(manifest.requires) || manifest.requires.length === 0) {
    errors.push("manifest.requires must be a non-empty list");
    return errors;
  }
  const seen = new Set();
  manifest.requires.forEach((entry, i) => {
    errors.push(...entryErrors(entry, `requires[${i}]`));
    if (isObject(entry) && typeof entry.id === "string") {
      if (seen.has(entry.id)) errors.push(`requires[${i}].id "${entry.id}" is declared twice`);
      seen.add(entry.id);
    }
  });
  return errors;
}

// loadManifest(root) -> { plugin, manifest, errors, absent }
export function loadManifest(root) {
  let plugin = path.basename(path.resolve(root));
  try {
    const name = JSON.parse(readFileSync(path.join(root, ".claude-plugin", "plugin.json"), "utf8")).name;
    if (isText(name)) plugin = name;
  } catch {
    // The directory name stands in when plugin.json is absent or unreadable.
  }
  const file = path.join(root, "prerequisites.json");
  if (!existsSync(file)) return { plugin, manifest: null, errors: [], absent: true };
  let manifest;
  try {
    manifest = JSON.parse(readFileSync(file, "utf8"));
  } catch (err) {
    return { plugin, manifest: null, errors: [`prerequisites.json is not valid JSON: ${err.message}`], absent: false };
  }
  return { plugin, manifest, errors: validateManifest(manifest), absent: false };
}

// compareVersions("2.10", "2.9") -> 1. Missing parts count as 0.
export function compareVersions(a, b) {
  const pa = a.split(".").map(Number);
  const pb = b.split(".").map(Number);
  for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
    const d = (pa[i] ?? 0) - (pb[i] ?? 0);
    if (d !== 0) return Math.sign(d);
  }
  return 0;
}

function isExecutable(file, platform) {
  try {
    if (!statSync(file).isFile()) return false;
    if (platform !== "win32") accessSync(file, constants.X_OK);
    return true;
  } catch {
    return false;
  }
}

// which(name) -> absolute path of the first PATH match, or null.
export function which(name, env = process.env, platform = process.platform) {
  const pathVar = env.PATH ?? env.Path ?? "";
  const exts = platform === "win32" ? ["", ...(env.PATHEXT ?? ".COM;.EXE;.BAT;.CMD").split(";").filter(Boolean)] : [""];
  for (const dir of pathVar.split(path.delimiter)) {
    if (!dir) continue;
    for (const ext of exts) {
      const candidate = path.join(dir, name + ext);
      if (isExecutable(candidate, platform)) return candidate;
    }
  }
  return null;
}

function findLocalBin(rels, cwd, platform) {
  for (const rel of rels ?? []) {
    let dir = path.resolve(cwd);
    for (let i = 0; i < LOCAL_BIN_DEPTH; i++) {
      const candidate = path.join(dir, rel);
      if (isExecutable(candidate, platform)) return candidate;
      const parent = path.dirname(dir);
      if (parent === dir) break;
      dir = parent;
    }
  }
  return null;
}

function run(file, args) {
  const r = spawnSync(file, args, { encoding: "utf8", timeout: PROBE_TIMEOUT_MS, stdio: ["ignore", "pipe", "pipe"] });
  return { ok: !r.error && r.status === 0, out: `${r.stdout ?? ""}${r.stderr ?? ""}` };
}

function firstOnPath(names, ctx) {
  for (const name of names) {
    const found = which(name, ctx.env, ctx.platform);
    if (found) return found;
  }
  return null;
}

// The data directory comes from --data-dir, else the environment. Hooks get
// CLAUDE_PLUGIN_DATA in their environment; a command run through the Bash tool
// does not, so a skill passes --data-dir "${CLAUDE_PLUGIN_DATA}" instead.
function expandPluginPath(p, ctx) {
  if (p.startsWith("${CLAUDE_PLUGIN_DATA}")) {
    const data = ctx.dataDir ?? ctx.env.CLAUDE_PLUGIN_DATA;
    if (!data) return null;
    return path.join(data, p.slice("${CLAUDE_PLUGIN_DATA}".length));
  }
  return path.join(ctx.root, p.replace(/^\$\{CLAUDE_PLUGIN_ROOT\}/, ""));
}

// detectEntry(entry, ctx) -> { status, detail }. status is present, missing,
// outdated (below the version floor), unverified (the version could not be
// read) or agent-check (an MCP server only the agent can see).
export function detectEntry(entry, ctx) {
  const d = entry.detect;
  switch (entry.kind) {
    case "cli":
    case "runtime": {
      const found = firstOnPath(d.any, ctx) ?? findLocalBin(d.local_bin, ctx.cwd, ctx.platform);
      if (!found) {
        const where = d.local_bin ? `on PATH or as ${d.local_bin.join(", ")}` : "on PATH";
        return { status: "missing", detail: `${d.any.join(" or ")} was not found ${where}` };
      }
      if (!d.version) return { status: "present", detail: found };
      const match = new RegExp(d.version.pattern).exec(run(found, d.version.args).out);
      if (!match?.[1] || !MIN_RE.test(match[1])) {
        return { status: "unverified", detail: `${found}: could not read a version to compare with ${d.version.min}` };
      }
      if (compareVersions(match[1], d.version.min) < 0) {
        return { status: "outdated", detail: `${found} is ${match[1]}; ${d.version.min} or newer is needed` };
      }
      return { status: "present", detail: `${found} ${match[1]}` };
    }
    case "system-lib": {
      const [bin, ...args] = d.probe.args;
      const found = which(bin, ctx.env, ctx.platform);
      if (!found) return { status: "missing", detail: `${bin} was not found on PATH to probe` };
      if (new RegExp(d.probe.pattern).test(run(found, args).out)) return { status: "present", detail: found };
      return { status: "missing", detail: `${bin} ${args.join(" ")} did not report ${d.probe.pattern}` };
    }
    case "python-pkg": {
      const found = firstOnPath(d.any, ctx);
      if (!found) return { status: "missing", detail: `no Python interpreter (${d.any.join(", ")}) on PATH` };
      if (run(found, ["-c", `import ${d.import}`]).ok)
        return { status: "present", detail: `${found} imports ${d.import}` };
      return { status: "missing", detail: `${found} cannot import ${d.import}` };
    }
    case "node-pkg": {
      let unresolved = false;
      for (const p of d.paths) {
        const dir = expandPluginPath(p, ctx);
        unresolved ||= dir === null;
        if (dir && existsSync(path.join(dir, d.module, "package.json"))) {
          return { status: "present", detail: path.join(dir, d.module) };
        }
      }
      if (unresolved) {
        return {
          status: "unverified",
          detail: `${d.module}: the plugin data directory is unknown here; pass --data-dir`,
        };
      }
      return { status: "missing", detail: `${d.module} is not installed under ${d.paths.join(", ")}` };
    }
    case "env":
      return ctx.env[d.name]
        ? { status: "present", detail: `${d.name} is set` }
        : { status: "missing", detail: `${d.name} is not set` };
    case "mcp":
      return { status: "agent-check", detail: `only the agent can see whether MCP server ${d.server} is connected` };
    default:
      return { status: "missing", detail: `unknown kind ${entry.kind}` };
  }
}

const isFailure = (status) => status === "missing" || status === "outdated";

function installText(entry) {
  return Object.entries(entry.install)
    .map(([k, v]) => `${k}: ${v}`)
    .join("; ");
}

function remediation(entry) {
  return `${entry.degrade} Install (${installText(entry)}). Then run ${entry.check}.`;
}

function inScope(entry, scope) {
  return !scope || entry.for.includes("plugin") || entry.for.includes(scope);
}

const USAGE = [
  "usage: prerequisites.mjs report --plugin-root <dir> [--plugin-root <dir>...]",
  "       prerequisites.mjs check <plugin-root> [--for <scope>] [--data-dir <dir>]",
  "       prerequisites.mjs probe <plugin-root>",
].join("\n");

class UsageError extends Error {}

function parseArgs(argv) {
  const [mode, ...rest] = argv;
  if (!["report", "check", "probe"].includes(mode))
    throw new UsageError(mode ? `unknown mode: ${mode}` : "no mode given");
  const opts = { mode, roots: [], scope: null, dataDir: null };
  for (let i = 0; i < rest.length; i++) {
    const arg = rest[i];
    if (arg === "--plugin-root" && mode === "report") {
      if (!rest[i + 1]) throw new UsageError("--plugin-root needs a directory");
      opts.roots.push(rest[++i]);
    } else if (arg === "--for" && mode === "check") {
      if (!rest[i + 1] || !FOR_RE.test(rest[i + 1])) throw new UsageError("--for needs a scope such as skill:<name>");
      opts.scope = rest[++i];
    } else if (arg === "--data-dir" && mode === "check") {
      if (!rest[i + 1]) throw new UsageError("--data-dir needs a directory");
      opts.dataDir = rest[++i];
    } else if (!arg.startsWith("--") && mode !== "report" && opts.roots.length === 0) {
      opts.roots.push(arg);
    } else {
      throw new UsageError(`unexpected argument: ${arg}`);
    }
  }
  if (opts.roots.length === 0) throw new UsageError(`${mode} needs a plugin root`);
  for (const root of opts.roots) {
    if (!existsSync(root) || !statSync(root).isDirectory()) throw new UsageError(`not a directory: ${root}`);
  }
  return opts;
}

function readHookInput(stdin) {
  try {
    const raw = stdin();
    const id = JSON.parse(raw || "{}").session_id;
    return typeof id === "string" && id ? id.replace(/[^A-Za-z0-9_-]/g, "-") : "no-session";
  } catch {
    return "no-session";
  }
}

// Once per session per entry, with the marker name hook::notice_once uses for
// its prerequisite class, so a bash probe and this one share a latch.
function firstNoticeThisSession(plugin, id, session, env) {
  if (!env.CLAUDE_PLUGIN_DATA) return true;
  const dir = path.join(env.CLAUDE_PLUGIN_DATA, "skip-notices");
  const marker = path.join(dir, `${plugin}-${id}.${session}.session`);
  try {
    if (existsSync(marker)) return false;
    mkdirSync(dir, { recursive: true });
    writeFileSync(marker, "1\n");
  } catch {
    // An unwritable data directory still gets the notice.
  }
  return true;
}

function cmdCheck(opts, ctx, out) {
  const root = opts.roots[0];
  const { plugin, manifest, errors, absent } = loadManifest(root);
  if (absent) {
    out.stdout(`${plugin}: no prerequisites.json; this plugin declares no external dependency.`);
    return 0;
  }
  if (errors.length) {
    out.stderr(`${plugin}: prerequisites.json fails the schema:\n  ${errors.join("\n  ")}`);
    return 2;
  }
  const local = { ...ctx, root, dataDir: opts.dataDir };
  const counts = { failed: 0, warned: 0, passed: 0 };
  for (const entry of manifest.requires.filter((e) => inScope(e, opts.scope))) {
    const { status, detail } = detectEntry(entry, local);
    const label = `${entry.id} (${entry.kind}, ${entry.need})`;
    if (status === "present") {
      counts.passed++;
      out.stdout(`PASS  ${label}: ${detail}`);
    } else if (status === "agent-check") {
      out.stdout(`INFO  ${label}: ${detail}. Check the session's tool list; if it is absent: ${remediation(entry)}`);
    } else if (status === "unverified") {
      counts.warned++;
      out.stdout(`WARN  ${label}: ${detail}`);
    } else if (entry.need === "required") {
      counts.failed++;
      out.stdout(`FAIL  ${label}: ${detail}. ${remediation(entry)}`);
    } else {
      counts.warned++;
      out.stdout(`WARN  ${label}: ${detail}. ${remediation(entry)}`);
    }
  }
  out.stdout(`${plugin}: failed=${counts.failed} warned=${counts.warned} passed=${counts.passed}`);
  return counts.failed ? 1 : 0;
}

function cmdReport(opts, ctx, out) {
  out.stdout(["plugin", "id", "kind", "need", "status", "check", "install"].join("\t"));
  let missing = 0;
  let present = 0;
  let requiredMissing = false;
  let invalid = false;
  for (const root of opts.roots) {
    const { plugin, manifest, errors, absent } = loadManifest(root);
    if (absent) continue;
    if (errors.length) {
      invalid = true;
      out.stderr(`${plugin}: prerequisites.json fails the schema:\n  ${errors.join("\n  ")}`);
      continue;
    }
    for (const entry of manifest.requires) {
      const { status } = detectEntry(entry, { ...ctx, root });
      if (isFailure(status)) {
        missing++;
        if (entry.need === "required") requiredMissing = true;
      } else if (status === "present") {
        present++;
      }
      out.stdout([plugin, entry.id, entry.kind, entry.need, status, entry.check, installText(entry)].join("\t"));
    }
  }
  out.stdout(`missing=${missing} present=${present}`);
  if (invalid) return 2;
  return requiredMissing ? 1 : 0;
}

function cmdProbe(opts, ctx, out) {
  const root = opts.roots[0];
  const { plugin, manifest, errors, absent } = loadManifest(root);
  if (absent) return 0;
  if (errors.length) {
    out.stderr(`${plugin}: prerequisites.json fails the schema:\n  ${errors.join("\n  ")}`);
    return 2;
  }
  const session = readHookInput(ctx.stdin);
  const notices = [];
  for (const entry of manifest.requires.filter((e) => e.for.some((s) => s.startsWith("hook:")))) {
    const { status, detail } = detectEntry(entry, { ...ctx, root });
    if (!isFailure(status) || !firstNoticeThisSession(plugin, entry.id, session, ctx.env)) continue;
    notices.push(
      `${plugin}: ${detail}. Hooks that need ${entry.id} skip until it is installed. ${remediation(entry)} It does not install.`,
    );
  }
  if (notices.length) {
    const msg = notices.join("\n");
    out.stdout(
      JSON.stringify({
        hookSpecificOutput: { hookEventName: "SessionStart", additionalContext: msg },
        systemMessage: msg,
      }),
    );
  }
  return 0;
}

// main(argv, ctx, out) -> exit code. ctx and out are injectable for tests.
export function main(argv, ctx = {}, out = {}) {
  const context = {
    env: ctx.env ?? process.env,
    platform: ctx.platform ?? process.platform,
    cwd: ctx.cwd ?? process.cwd(),
    stdin: ctx.stdin ?? (() => (process.stdin.isTTY ? "" : readFileSync(0, "utf8"))),
  };
  const io = { stdout: out.stdout ?? ((s) => console.log(s)), stderr: out.stderr ?? ((s) => console.error(s)) };
  let opts;
  try {
    opts = parseArgs(argv);
  } catch (err) {
    if (!(err instanceof UsageError)) throw err;
    io.stderr(`prerequisites.mjs: ${err.message}\n${USAGE}`);
    return 2;
  }
  if (opts.mode === "report") return cmdReport(opts, context, io);
  if (opts.mode === "check") return cmdCheck(opts, context, io);
  return cmdProbe(opts, context, io);
}

// Node realpaths the main entry, so compare real paths: a launch through a
// symlinked checkout path must still reach main().
function realPath(p) {
  try {
    return realpathSync(p);
  } catch {
    return path.resolve(p);
  }
}

if (process.argv[1] && realPath(process.argv[1]) === realPath(fileURLToPath(import.meta.url))) {
  process.exitCode = main(process.argv.slice(2));
}
