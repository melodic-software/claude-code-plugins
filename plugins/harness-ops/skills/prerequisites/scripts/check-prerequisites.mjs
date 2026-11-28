#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import { existsSync, readdirSync, realpathSync } from "node:fs";
import { homedir } from "node:os";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";
import { rootsFromListing, rootsFromSettings, sessionSettingsFile } from "../../../lib/enabled-plugin-roots.mjs";
import { managedSettingsFiles } from "../../../lib/plugin-options.mjs";
import { report, which } from "../../../lib/prerequisites.mjs";

export { rootsFromListing, rootsFromSettings };

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

function gitToplevel(cwd) {
  const r = spawnSync("git", ["rev-parse", "--show-toplevel"], { cwd, encoding: "utf8" });
  return r.status === 0 ? r.stdout.trim() : "";
}

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

function managedFiles() {
  try {
    return managedSettingsFiles();
  } catch {
    return [];
  }
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
    const listing = sessionSettingsFile(env) ? "" : claudeListing(env, platform);
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
      const found = rootsFromSettings(config, project, ctx.managed ?? managedFiles(), env);
      stateRead = found.read;
      roots = found.roots;
    }
    if (roots.length === 0 && !stateRead) {
      const repo = gitToplevel(cwd);
      const pluginsDir = path.join(repo, "plugins");
      if (repo && existsSync(pluginsDir)) {
        roots = readdirSync(pluginsDir)
          .sort()
          .map((name) => path.join(pluginsDir, name))
          .filter((dir) => existsSync(path.join(dir, "prerequisites.json")));
      }
      if (roots.length === 0) {
        err("check-prerequisites.mjs: no plugin roots to read");
        return 2;
      }
    }
  }
  return report(roots, { env, platform, cwd }, { stdout: out, stderr: err });
}

if (process.argv[1] && realOr(process.argv[1]) === realOr(fileURLToPath(import.meta.url))) {
  process.exitCode = run(process.argv.slice(2));
}
