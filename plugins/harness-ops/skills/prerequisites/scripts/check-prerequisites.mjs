#!/usr/bin/env node
// Read-only fleet prerequisite table. Never installs.
//
//   check-prerequisites.mjs --plugin-root <dir> [--plugin-root <dir>...]
//   check-prerequisites.mjs
//
// With no roots and a claude executable on PATH, read the enabled set and each
// install path from `claude plugin list --json`: user and managed rows, plus
// project and local rows whose projectPath is the current project
// ($CLAUDE_PROJECT_DIR, else the git toplevel); the most specific scope wins per
// id. When claude is absent or prints nothing, merge enabledPlugins from
// settings.json and settings.local.json in ~/.claude (or $CLAUDE_CONFIG_DIR) and
// the project's .claude directory instead, skipping a whole file whose
// enabledPlugins holds a non-Boolean value (Claude Code ignores that file's
// keys); that fallback does not read the managed scope. Output that is not a
// JSON list is an error (exit 2), never a fallback. Only when none of that state
// exists and this repo has plugins/*/prerequisites.json, scan those.
//
// The table is lib/prerequisites.mjs report mode:
//   plugin id kind need status check install
// then `missing=N present=M`. Exit 0 when no required entry is missing, 1 when
// one is, 2 on a usage error, an unreadable listing or a manifest that fails
// the schema.
import { spawnSync } from "node:child_process";
import { existsSync, readdirSync, readFileSync, realpathSync, statSync } from "node:fs";
import { homedir } from "node:os";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";
import { report, which } from "../../../lib/prerequisites.mjs";

const RANK = { user: 0, project: 1, local: 2, managed: 3 };
const LISTING_TIMEOUT_MS = 30_000;
const LISTING_MAX_BYTES = 256 * 1024 * 1024;

const USAGE = [
  "usage: check-prerequisites.mjs --plugin-root <dir> [--plugin-root <dir>...]",
  "       check-prerequisites.mjs",
  "exit 0 when no required entry is missing, 1 when one is, 2 on a usage error",
].join("\n");

class UsageError extends Error {}

const realOr = (p) => {
  try {
    return realpathSync(p);
  } catch {
    return path.resolve(p);
  }
};
const sameDir = (a, b) => Boolean(a && b) && realOr(a) === realOr(b);

function readJson(file) {
  try {
    return JSON.parse(readFileSync(file, "utf8"));
  } catch {
    return undefined;
  }
}

function gitToplevel(cwd) {
  const r = spawnSync("git", ["rev-parse", "--show-toplevel"], { cwd, encoding: "utf8" });
  return r.status === 0 ? r.stdout.trim() : "";
}

// The text of `claude plugin list --json`, or "" when claude is absent or fails.
function claudeListing(env, platform) {
  const claude = which("claude", env, platform);
  if (!claude) return "";
  const r = spawnSync(claude, ["plugin", "list", "--json"], {
    encoding: "utf8",
    timeout: LISTING_TIMEOUT_MS,
    maxBuffer: LISTING_MAX_BYTES,
    stdio: ["ignore", "pipe", "ignore"],
    shell: /\.(cmd|bat)$/i.test(claude),
  });
  return r.stdout ?? "";
}

// Install paths of the enabled rows; the most specific scope wins per id.
export function rootsFromListing(rows, project) {
  const best = new Map();
  for (const row of rows) {
    if (!row || typeof row !== "object" || !row.id || !(row.scope in RANK)) continue;
    if ((row.scope === "project" || row.scope === "local") && !sameDir(row.projectPath ?? "", project)) continue;
    const held = best.get(row.id);
    if (!held || RANK[row.scope] >= RANK[held.scope]) best.set(row.id, row);
  }
  return [...best.keys()]
    .sort()
    .map((id) => best.get(id))
    .filter((row) => row.enabled === true && row.installPath)
    .map((row) => row.installPath);
}

// { read, roots } from enabledPlugins in the settings files and installed_plugins.json.
export function rootsFromSettings(config, project) {
  // User, then project, then local: a later scope's true/false wins.
  const files = [path.join(config, "settings.json"), path.join(config, "settings.local.json")];
  if (project) {
    files.push(path.join(project, ".claude", "settings.json"), path.join(project, ".claude", "settings.local.json"));
  }
  const state = {};
  let read = false;
  for (const file of files) {
    if (!existsSync(file) || !statSync(file).isFile()) continue;
    const doc = readJson(file);
    if (doc === undefined) continue;
    read = true;
    const plugins = doc?.enabledPlugins;
    if (!plugins || typeof plugins !== "object" || Array.isArray(plugins)) continue;
    if (!Object.values(plugins).every((v) => typeof v === "boolean")) continue;
    Object.assign(state, plugins);
  }
  const enabled = Object.keys(state).filter((key) => state[key]);
  const installedFile = path.join(config, "plugins", "installed_plugins.json");
  const hasInstalled = existsSync(installedFile) && statSync(installedFile).isFile();
  if (hasInstalled) read = true;
  const roots = [];
  if (enabled.length && hasInstalled) {
    const installed = readJson(installedFile)?.plugins ?? {};
    for (const key of enabled.sort()) {
      let records = installed[key] ?? [];
      if (!Array.isArray(records)) records = [records];
      let installPath = "";
      for (const record of records) {
        if (record && typeof record === "object" && record.installPath) {
          installPath = record.installPath;
          if (record.scope === "user") break;
        }
      }
      if (installPath) roots.push(installPath);
    }
  }
  return { read, roots };
}

function parseArgs(argv) {
  const roots = [];
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === "--help" || arg === "-h") return { help: true, roots };
    if (arg === "--plugin-root") {
      if (!argv[i + 1]) throw new UsageError("--plugin-root needs a directory");
      roots.push(argv[++i]);
    } else {
      throw new UsageError(`unknown argument ${arg} (see --help)`);
    }
  }
  return { help: false, roots };
}

// run(argv, ctx, io) -> exit code. ctx and io are injectable.
export function run(argv, ctx = {}, io = {}) {
  const env = ctx.env ?? process.env;
  const platform = ctx.platform ?? process.platform;
  const cwd = ctx.cwd ?? process.cwd();
  const out = io.stdout ?? ((s) => console.log(s));
  const err = io.stderr ?? ((s) => console.error(s));
  let args;
  try {
    args = parseArgs(argv);
  } catch (e) {
    if (!(e instanceof UsageError)) throw e;
    err(`check-prerequisites.mjs: ${e.message}`);
    return 2;
  }
  if (args.help) {
    out(USAGE);
    return 0;
  }
  let roots = args.roots;
  let stateRead = false;
  if (roots.length === 0) {
    const config = env.CLAUDE_CONFIG_DIR || path.join(env.HOME || homedir(), ".claude");
    const project = env.CLAUDE_PROJECT_DIR || gitToplevel(cwd);
    const listing = claudeListing(env, platform);
    if (listing.trim()) {
      let rows;
      let detail = "not a JSON list";
      try {
        rows = JSON.parse(listing);
      } catch (e) {
        detail = e.message;
      }
      if (!Array.isArray(rows)) {
        err(`check-prerequisites.mjs: claude plugin list --json: ${detail}`);
        return 2;
      }
      stateRead = true;
      roots = rootsFromListing(rows, project);
    } else {
      const found = rootsFromSettings(config, project);
      stateRead = found.read;
      roots = found.roots;
    }
    // The repository scan stands in only when no settings or install state exists;
    // a read state with nothing enabled is an empty fleet, not a reason to scan.
    if (roots.length === 0 && !stateRead) {
      const repo = gitToplevel(cwd);
      const pluginsDir = path.join(repo, "plugins");
      if (repo && existsSync(pluginsDir)) {
        roots = readdirSync(pluginsDir)
          .sort()
          .map((name) => path.join(pluginsDir, name))
          .filter((dir) => existsSync(path.join(dir, "prerequisites.json")));
      }
    }
    if (roots.length === 0 && !stateRead) {
      err("check-prerequisites.mjs: no plugin roots to read");
      return 2;
    }
  }
  return report(roots, { env, platform, cwd }, { stdout: out, stderr: err });
}

if (process.argv[1] && realOr(process.argv[1]) === realOr(fileURLToPath(import.meta.url))) {
  process.exitCode = run(process.argv.slice(2));
}
