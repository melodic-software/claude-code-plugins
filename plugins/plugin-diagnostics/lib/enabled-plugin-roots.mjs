// GENERATED from lib/enabled-plugin-roots.mjs by scripts/sync-shared-copies.sh. Do not edit this copy:
// edit the canonical source, then rerun the script.
import { existsSync, readFileSync, realpathSync, statSync } from "node:fs";
import path from "node:path";
import process from "node:process";

const RANK = { user: 0, project: 1, local: 2, managed: 3 };

const realOr = (p) => {
  try {
    return realpathSync(p);
  } catch {
    return path.resolve(p);
  }
};
const sameDir = (a, b) => Boolean(a && b) && realOr(a) === realOr(b);
const isFile = (p) => existsSync(p) && statSync(p).isFile();

function readJson(file) {
  try {
    return JSON.parse(readFileSync(file, "utf8"));
  } catch {
    return undefined;
  }
}

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

export const SESSION_SETTINGS_VAR = "SESSION_SETTINGS_FILE";

export const sessionSettingsFile = (env = process.env) => (env[SESSION_SETTINGS_VAR] ? path.resolve(env[SESSION_SETTINGS_VAR]) : "");

// Managed files are read last: nothing in a user's own settings overrides a managed key:
// https://code.claude.com/docs/en/settings#settings-precedence
export function rootsFromSettings(config, project, managed = [], env = process.env) {
  const files = [path.join(config, "settings.json"), path.join(config, "settings.local.json")];
  if (project) {
    files.push(path.join(project, ".claude", "settings.json"), path.join(project, ".claude", "settings.local.json"));
  }
  const session = sessionSettingsFile(env);
  if (session) files.push(session);
  files.push(...managed);
  const state = {};
  let read = false;
  for (const file of files) {
    if (!isFile(file)) continue;
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
  const hasInstalled = isFile(installedFile);
  if (hasInstalled) read = true;
  if (!enabled.length || !hasInstalled) return { read, roots: [] };
  const installed = readJson(installedFile)?.plugins ?? {};
  const rows = enabled.sort().flatMap((id) => {
    const records = installed[id] ?? [];
    return (Array.isArray(records) ? records : [records])
      .filter((r) => r && typeof r === "object")
      .map((r) => ({ ...r, id, enabled: true }));
  });
  return { read, roots: rootsFromListing(rows, project) };
}
