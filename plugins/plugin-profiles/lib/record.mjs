// The applied-profile record: what this tool changed in one settings file, so status can compare
// and clear can put every entry back. One JSON file per settings file, under a record home: the
// repository's .git/plugin-profiles for a folder in git, ~/.claude/plugin-profiles-state for user
// settings, else the plugin data folder (scripts/profiles.mjs homesOf; scenario row 5 of
// https://github.com/melodic-software/claude-code-plugins/blob/main/plugins/plugin-profiles/reference/scenarios.md):
//
//   recordPath(dataDir, settingsFile) -> <dataDir>/records/<sha256 of the settings file's real path>.json
//   readRecord(path) / saveRecord(path, record) / deleteRecord(path)
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
import { readdirSync, readFileSync, realpathSync } from "node:fs";
import { basename, dirname, join, resolve } from "node:path";
import { readText, removeFile, replaceFile } from "./atomic-file.mjs";

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

export function recordPath(home, settingsFile) {
  const key = createHash("sha256").update(realPath(settingsFile)).digest("hex");
  return join(home, "records", `${key}.json`);
}

export function readRecord(path) {
  try {
    return JSON.parse(readFileSync(path, "utf8"));
  } catch (error) {
    if (error.code === "ENOENT") return null;
    throw new Error(`the applied-profile record ${path} cannot be read (${error.code ?? error.message})`);
  }
}

/** The record of settingsFile from the first home holding one; path is where the first home keeps it. */
export function findRecord(homes, settingsFile) {
  for (const home of homes) {
    const found = recordPath(home, settingsFile);
    const record = readRecord(found);
    if (record) return { path: recordPath(homes[0], settingsFile), found, record };
  }
  return { path: recordPath(homes[0], settingsFile), found: null, record: null };
}

/** True when doc holds every entry the record wrote, one entry at least, apart from the ones a switch still owes. */
export const holdsEveryEntry = (record, doc) => {
  const written = Object.entries(SECTIONS).flatMap(([key, section]) => Object.entries(record[section] ?? {}).map(([name, { after }]) => [key, name, after]));
  return written.length > 0 && written.every(([key, name, after]) => record.pending?.[name] !== undefined || (doc[key]?.[name] ?? ABSENT) === after);
};

/** The record with only the entries doc still holds as the record wrote them, apart from the ones a switch still owes. */
export function stillWritten(record, doc) {
  const out = { ...record };
  for (const [key, section] of Object.entries(SECTIONS)) {
    out[section] = Object.fromEntries(Object.entries(record[section] ?? {}).filter(([name, { after }]) => record.pending?.[name] === undefined && (doc[key]?.[name] ?? ABSENT) === after));
  }
  return out;
}

export const recordText = (record) => `${JSON.stringify(record, null, 2)}\n`;
export const saveRecord = (path, record) => replaceFile(path, recordText(record));
export const restoringRecord = (record, { restoredHash, fromHash }) => ({ ...record, phase: "restoring", restoredHash, fromHash });
export const deleteRecord = (path) => removeFile(path);

/** Where reset notes a file it restored, beside where a record of that file would sit in the same home. */
const restoredPath = (home, settingsFile) => join(home, "restored", basename(recordPath(home, settingsFile)));

/** The hash of the bytes reset left in settingsFile, from the first of homes holding a note of it; null with none. */
export function restoredHashOf(homes, settingsFile) {
  for (const home of homes) {
    try {
      const hash = JSON.parse(readFileSync(restoredPath(home, settingsFile), "utf8")).restoredHash;
      if (typeof hash === "string") return hash;
    } catch {}
  }
  return null;
}

/** Notes that reset left settingsFile holding the bytes whose hash is restoredHash, in the home where a record of it is saved. */
export const noteRestored = (home, settingsFile, restoredHash) => replaceFile(restoredPath(home, settingsFile), recordText({ schema: SCHEMA, settingsFile, restoredHash }));

/** Removes every note of settingsFile from homes. */
export const forgetRestored = (homes, settingsFile) => {
  for (const home of homes) removeFile(restoredPath(home, settingsFile));
};

/** Removes each note in home whose file no longer holds the noted bytes; hashOfFile(path) gives a file's hash now. */
export function forgetStaleRestored(home, hashOfFile) {
  let names;
  try {
    names = readdirSync(join(home, "restored")).filter((name) => name.endsWith(".json") && !name.startsWith("."));
  } catch {
    return;
  }
  for (const name of names) {
    const path = join(home, "restored", name);
    let note = null;
    try {
      note = JSON.parse(readFileSync(path, "utf8"));
    } catch {}
    if (typeof note?.settingsFile !== "string" || hashOfFile(note.settingsFile) !== note.restoredHash) removeFile(path);
  }
}

class RecordChanged extends Error {}

/** Replaces a record only while it still holds expected, checked just before the rename as the settings hash guard is; false when it changed. */
export function swapRecord(path, expected, text) {
  try {
    replaceFile(path, text, {
      beforeRename: () => {
        if (readText(path) !== expected) throw new RecordChanged();
      },
    });
    return true;
  } catch (error) {
    if (error instanceof RecordChanged) return false;
    throw error;
  }
}

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
    createdFolder: previous?.createdFolder ?? apply.createdFolder === true,
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
