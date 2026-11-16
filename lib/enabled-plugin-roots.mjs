// The install roots of the plugins enabled for a project, read from settings files and
// installed_plugins.json, never from `claude plugin list`, which starts a nested claude.
//
//   rootsFromSettings(<config dir>, <project dir or "">, [<managed settings file>...]) -> {read, roots}
//   rootsFromListing(<rows of `claude plugin list --json`>, <project dir>) -> [<install path>...]
//
// A settings file whose enabledPlugins holds a non-Boolean value is skipped whole, as Claude Code
// ignores that file's keys. Per id, the most specific scope's install record wins, and another
// project's project or local record drops out, the rule `claude plugin list` applies.
import { existsSync, readFileSync, realpathSync, statSync } from "node:fs";
import path from "node:path";

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

// managed: managed settings files, applied last so a managed true/false wins.
export function rootsFromSettings(config, project, managed = []) {
  const files = [path.join(config, "settings.json"), path.join(config, "settings.local.json")];
  if (project) {
    files.push(path.join(project, ".claude", "settings.json"), path.join(project, ".claude", "settings.local.json"));
  }
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
