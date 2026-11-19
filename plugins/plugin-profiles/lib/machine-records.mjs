// Every settings file on this machine that a profile changed, for reset. A record's file name is a
// hash of its settings file, so nothing lists the repositories a profile was applied in; reset reads
// the record homes it can reach: the user state home, each data folder, and the git common folder
// of each repository that a pointer, a folder Claude Code has opened, a session record or a live
// session names (scenario rows of
// https://github.com/melodic-software/claude-code-plugins/blob/main/plugins/plugin-profiles/reference/scenarios.md).
import { createHash } from "node:crypto";
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { basename, dirname, join } from "node:path";
import { replaceFile } from "./atomic-file.mjs";
import { folderLevel } from "./folder-file.mjs";
import { realPath } from "./record.mjs";
import { readSettings } from "./settings-io.mjs";

const pointersDir = (configDir) => join(configDir, "plugin-profiles-state", "repositories");
const readText = (path) => {
  try {
    return readFileSync(path, "utf8");
  } catch {
    return null;
  }
};
const parsed = (text) => {
  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
};
const filesIn = (dir) => {
  try {
    return readdirSync(dir).filter((name) => name.endsWith(".json") && !name.startsWith(".")).map((name) => join(dir, name));
  } catch {
    return [];
  }
};

export function writePointer(configDir, home) {
  const file = join(pointersDir(configDir), `${createHash("sha256").update(realPath(home)).digest("hex")}.json`);
  const text = `${JSON.stringify({ home }, null, 2)}\n`;
  if (readText(file) !== text) replaceFile(file, text);
}

export const readPointers = (configDir) =>
  filesIn(pointersDir(configDir)).map((path) => parsed(readText(path))?.home).filter((home) => typeof home === "string");

export function repositoryHome(folder, levelOptions = {}) {
  try {
    const level = folderLevel(folder, levelOptions);
    return level.recordInGit ? join(level.commonDir, "plugin-profiles") : null;
  } catch {
    return null;
  }
}

export const sessionFolders = (dataDirs) =>
  dataDirs.flatMap((dir) => filesIn(join(dir, "sessions", "by-id")).map((path) => parsed(readText(path))?.folder)).filter((f) => typeof f === "string");

export function listRecords(home) {
  return filesIn(join(home, "records")).flatMap((path) => {
    const text = readText(path);
    const record = text === null ? null : parsed(text);
    return record && typeof record.settingsFile === "string" ? [{ path, text, record }] : [];
  });
}

/** Whether folder was a linked worktree of the repository at commonDir, by the worktrees/<name>/gitdir git keeps until a prune. */
function wasWorktree(commonDir, folder) {
  let names;
  try {
    names = readdirSync(join(commonDir, "worktrees"));
  } catch {
    return false;
  }
  const own = realPath(join(folder, ".git"));
  return names.some((name) => {
    const gitdir = readText(join(commonDir, "worktrees", name, "gitdir"));
    return gitdir !== null && realPath(gitdir.trim()) === own;
  });
}

/** For a record of a main checkout's root file whose folder is gone, that repository's root file where it is now; none for a linked worktree of it. */
function movedFile(home, settingsFile) {
  const commonDir = dirname(home);
  if (basename(home) !== "plugin-profiles" || basename(commonDir) !== ".git") return undefined;
  if (wasWorktree(commonDir, dirname(dirname(settingsFile)))) return undefined;
  return join(dirname(commonDir), ".claude", "settings.local.json");
}

/** The plugin and skill entries a file holds, as preview names: plugin ids, then "skill <name>". */
function entriesOf(file) {
  try {
    const { doc } = readSettings(file);
    return [...Object.keys(doc.enabledPlugins ?? {}), ...Object.keys(doc.skillOverrides ?? {}).map((name) => `skill ${name}`)];
  } catch {
    return [];
  }
}

const isMissing = (settingsFile) => !existsSync(dirname(dirname(settingsFile)));

/**
 * Each settings file with a record, its copies grouped by real path. homesOf(file) names the homes a record of file may sit in;
 * a copy elsewhere is listed as ignored and never planned from, except a git home's copy for a folder that is gone, which stays
 * kept and may name its moved root file.
 */
export function machineSettingsFiles({ homes, homesOf, recordOf, knownFiles = [] }) {
  const seen = new Set();
  const groups = new Map();
  const out = [];
  for (const home of homes) {
    if (seen.has(realPath(home))) continue;
    seen.add(realPath(home));
    for (const copy of listRecords(home)) {
      const { settingsFile } = copy.record;
      const held = homesOf(settingsFile).some((h) => realPath(h) === realPath(home));
      if (!held && !(isMissing(settingsFile) && basename(home) === "plugin-profiles")) {
        out.push({ settingsFile, folder: dirname(dirname(settingsFile)), recordPath: copy.path, copies: [], record: null, adopted: false, missing: false, ignored: true });
        continue;
      }
      const key = realPath(settingsFile);
      if (!groups.has(key)) groups.set(key, []);
      groups.get(key).push({ ...copy, home, held });
    }
  }
  for (const copies of groups.values()) {
    const settingsFile = copies[0].record.settingsFile;
    const hit = recordOf(settingsFile);
    const planned = copies.find((c) => c.path === hit?.found) ?? copies[0];
    const missing = isMissing(settingsFile);
    out.push({
      settingsFile,
      folder: dirname(dirname(settingsFile)),
      recordPath: planned.path,
      copies: copies.map(({ path, text }) => ({ path, text })),
      record: planned.record,
      adopted: false,
      missing,
      movedTo: missing ? copies.filter((c) => !c.held).map((c) => movedFile(c.home, settingsFile)).find(Boolean) : undefined,
    });
  }
  for (const { file, found } of knownFiles) {
    const key = realPath(file);
    if (groups.has(key) || out.some((f) => !f.ignored && realPath(f.settingsFile) === key)) continue;
    const base = { settingsFile: file, folder: dirname(dirname(file)), recordPath: null, copies: [], missing: false };
    if (found?.record) out.push({ ...base, record: found.record, adopted: true });
    else {
      const entries = entriesOf(file);
      if (entries.length) out.push({ ...base, record: null, adopted: false, entries });
    }
  }
  return out.sort((a, b) => Number(b.adopted) - Number(a.adopted) || a.settingsFile.localeCompare(b.settingsFile));
}
