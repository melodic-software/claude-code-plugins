// The applied-profile record: what this tool changed in one settings file, so status can compare
// and clear can put every entry back. One JSON file per settings file, in the plugin data folder:
//
//   recordPath(dataDir, settingsFile) -> <dataDir>/records/<sha256 of the settings file's real path>.json
//   readRecord(path) / saveRecord(path, record) / deleteRecord(path)
//   findRecord(dataDir, settingsFile) -> {path, record}: the file's record; a linked git worktree with
//     none takes a copy of its main worktree's record when the file still holds every entry it wrote;
//     the copy is in memory, and only a command that writes (apply) saves it
//   baseline(doc, record) -> {enabledPlugins, skillOverrides}: the file's entries with each
//     recorded before-value put back, as if the earlier profile had been cleared
//   nextRecord(previous, apply) -> the record after this apply; before-values come from the first write
//   restoreEdits(record) -> {edits, dropEmpty}: the settings-io edits that clear the profile
//
// Record: {schema, profile, target, settingsFile, appliedAt, pluginVersion, phase: "applied" |
// "off-pending", pending: {id: false}, createdFile, containers: {enabledPlugins, skillOverrides},
// installed: [id], entries: {id: {before, after}}, skillOverrides: {name: {before, after}}}.
// A before or after value of "absent" means the file held no entry. off-pending marks a switch cut
// off after its first write: pending holds the entries the second write still has to switch off.
import { createHash } from "node:crypto";
import { readFileSync, realpathSync } from "node:fs";
import { basename, dirname, join, resolve } from "node:path";
import { removeFile, replaceFile } from "./atomic-file.mjs";

export const SCHEMA = 1;
export const ABSENT = "absent";
const SECTIONS = { enabledPlugins: "entries", skillOverrides: "skillOverrides" };

/** The path with symbolic links resolved as far as it exists, so one folder has one key. */
export function realPath(path) {
  for (let dir = resolve(path), rest = []; ; rest.unshift(basename(dir)), dir = dirname(dir)) {
    try {
      return join(realpathSync.native(dir), ...rest);
    } catch {
      if (dirname(dir) === dir) return resolve(path);
    }
  }
}

export function recordPath(dataDir, settingsFile) {
  const key = createHash("sha256").update(realPath(settingsFile)).digest("hex");
  return join(dataDir, "records", `${key}.json`);
}

export function readRecord(path) {
  try {
    return JSON.parse(readFileSync(path, "utf8"));
  } catch (error) {
    if (error.code === "ENOENT") return null;
    throw new Error(`the applied-profile record ${path} cannot be read (${error.code ?? error.message})`);
  }
}

/** The main worktree of the linked git worktree at folder, read from the files git writes; else null. */
function mainWorktree(folder) {
  try {
    const gitdir = /^gitdir:\s*(.+?)\s*$/m.exec(readFileSync(join(folder, ".git"), "utf8"));
    if (!gitdir) return null;
    const gitDir = resolve(folder, gitdir[1]);
    const common = resolve(gitDir, readFileSync(join(gitDir, "commondir"), "utf8").trim());
    return basename(common) === ".git" ? dirname(common) : null;
  } catch {
    return null;
  }
}

const holdsEveryEntry = (record, doc) =>
  Object.entries(SECTIONS).every(([key, section]) =>
    Object.entries(record[section] ?? {}).every(([name, { after }]) => record.pending?.[name] !== undefined || (doc[key]?.[name] ?? ABSENT) === after));

/** A worktree's settings file copied from the main worktree carries its entries but not its record. */
function adoptedRecord(dataDir, settingsFile) {
  const claudeDir = dirname(settingsFile);
  if (basename(claudeDir) !== ".claude") return null;
  const main = mainWorktree(dirname(claudeDir));
  if (!main || realPath(main) === realPath(dirname(claudeDir))) return null;
  try {
    const record = readRecord(recordPath(dataDir, join(main, ".claude", basename(settingsFile))));
    const doc = JSON.parse(readFileSync(settingsFile, "utf8"));
    return record && doc && typeof doc === "object" && holdsEveryEntry(record, doc) ? { ...record, settingsFile } : null;
  } catch {
    return null;
  }
}

export function findRecord(dataDir, settingsFile) {
  const path = recordPath(dataDir, settingsFile);
  return { path, record: readRecord(path) ?? adoptedRecord(dataDir, settingsFile) };
}

export const saveRecord = (path, record) => replaceFile(path, `${JSON.stringify(record, null, 2)}\n`);
export const deleteRecord = (path) => removeFile(path);

export function baseline(doc, record) {
  const out = {};
  for (const [key, section] of Object.entries(SECTIONS)) {
    const entries = { ...doc[key] };
    for (const [name, { before }] of Object.entries(record?.[section] ?? {})) {
      if (before === ABSENT) delete entries[name];
      else entries[name] = before;
    }
    out[key] = entries;
  }
  return out;
}

/** apply: {profile, target, settingsFile, pluginVersion, appliedAt, doc, exists, final, phase, pending, installed} */
export function nextRecord(previous, apply) {
  const record = {
    schema: SCHEMA,
    profile: apply.profile,
    target: apply.target,
    settingsFile: apply.settingsFile,
    appliedAt: apply.appliedAt,
    pluginVersion: apply.pluginVersion,
    phase: apply.phase,
    pending: apply.pending,
    createdFile: previous?.createdFile ?? !apply.exists,
    containers: previous?.containers ?? Object.fromEntries(Object.keys(SECTIONS).map((key) => [key, key in apply.doc])),
    installed: apply.installed,
  };
  for (const [key, section] of Object.entries(SECTIONS)) {
    const now = apply.doc[key] ?? {};
    const final = apply.final[key];
    const names = new Set([...Object.keys(previous?.[section] ?? {}), ...Object.keys(now), ...Object.keys(final)]);
    const entries = {};
    for (const name of names) {
      const before = previous?.[section]?.[name]?.before ?? now[name] ?? ABSENT;
      const after = final[name] ?? ABSENT;
      if (before !== after) entries[name] = { before, after };
    }
    record[section] = entries;
  }
  return record;
}

export function restoreEdits(record) {
  const edits = {};
  for (const [key, section] of Object.entries(SECTIONS)) {
    edits[key] = Object.fromEntries(Object.entries(record[section]).map(([name, { before }]) => [name, before === ABSENT ? null : before]));
  }
  return { edits, dropEmpty: Object.keys(SECTIONS).filter((key) => !record.containers[key]) };
}
