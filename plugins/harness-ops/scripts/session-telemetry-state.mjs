#!/usr/bin/env node
// Whether session-telemetry records this project's sessions, and where its records are, read
// through docs/contracts/session-telemetry-data. Read-only; always exits 0.
//
//   session-telemetry-state.mjs [--project <dir>]     (default $CLAUDE_PROJECT_DIR)
//
// Prints, one per line:
//   session-telemetry: enabled  |  session-telemetry: not enabled, ...  plus the lines that turn it on
//   data_dir=<its plugin data directory>
//   option <key>=<value>   each option its hooks last ran with (options.json), else its manifest default
// Enabled means enabledPlugins in the user, project, session and managed settings, the rule
// /harness-ops:prerequisites reads (lib/enabled-plugin-roots.mjs); a --plugin-dir session is not seen.
import { existsSync, readFileSync, realpathSync } from "node:fs";
import { homedir } from "node:os";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";
import { rootsFromSettings } from "../lib/enabled-plugin-roots.mjs";
import { managedSettingsFiles, resolveInstall } from "../lib/plugin-options.mjs";

const NAME = "session-telemetry";
const OWN_ROOT = path.dirname(path.dirname(realpathSync(fileURLToPath(import.meta.url))));

const readJson = (file) => {
  try {
    return JSON.parse(readFileSync(file, "utf8"));
  } catch {
    return undefined;
  }
};

function args(argv) {
  const i = argv.indexOf("--project");
  return { project: i >= 0 ? (argv[i + 1] ?? "") : (process.env.CLAUDE_PROJECT_DIR ?? "") };
}

export function state({ project, env = process.env, ownRoot = OWN_ROOT }) {
  const own = resolveInstall(ownRoot);
  const marketplace = own.pluginId?.split("@")[1] ?? "inline";
  const config = own.userSettings
    ? path.dirname(own.userSettings)
    : env.CLAUDE_CONFIG_DIR || path.join(env.HOME || homedir(), ".claude");
  const id = `${NAME}@${marketplace}`;
  let managed = [];
  try {
    managed = managedSettingsFiles();
  } catch {
    // No documented managed path on this platform.
  }
  const nameOf = (root) => readJson(path.join(root, ".claude-plugin", "plugin.json"))?.name;
  const enabledRoot = rootsFromSettings(config, project, managed, env).roots.find((root) => nameOf(root) === NAME);
  const records = readJson(path.join(config, "plugins", "installed_plugins.json"))?.plugins?.[id];
  const installedRoot = [records ?? []].flat().find((r) => r?.installPath && existsSync(r.installPath))?.installPath;
  const root = enabledRoot ?? installedRoot;
  const dataDir = path.join(config, "plugins", "data", id.replace(/[^A-Za-z0-9_-]/g, "-"));
  const defaults = Object.fromEntries(
    Object.entries(root ? (readJson(path.join(root, ".claude-plugin", "plugin.json"))?.userConfig ?? {}) : {})
      .filter(([, spec]) => spec && Object.hasOwn(spec, "default"))
      .map(([key, spec]) => [key, String(spec.default)]),
  );
  const recorded = readJson(path.join(dataDir, "options.json"))?.options ?? {};
  return { id, enabled: Boolean(enabledRoot), installed: Boolean(installedRoot), dataDir, options: { ...defaults, ...recorded } };
}

export function render(s) {
  const lines = s.enabled
    ? [`${NAME}: enabled`]
    : [
        `${NAME}: not enabled, so this session records no hook runs, session events or skill use; reports read only what earlier sessions left. To turn it on, run:`,
        ...(s.installed ? [] : [`  claude plugin install ${s.id}`]),
        `  claude plugin enable ${s.id}`,
        "  then start a new session.",
      ];
  lines.push(`data_dir=${s.dataDir}`);
  for (const key of Object.keys(s.options).sort()) lines.push(`option ${key}=${s.options[key]}`);
  return `${lines.join("\n")}\n`;
}

if (process.argv[1] && realpathSync(process.argv[1]) === realpathSync(fileURLToPath(import.meta.url))) {
  try {
    process.stdout.write(render(state(args(process.argv.slice(2)))));
  } catch (error) {
    process.stdout.write(`${NAME}: state unknown (${error.message})\n`);
  }
}
