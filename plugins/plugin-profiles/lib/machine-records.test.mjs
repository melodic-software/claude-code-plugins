import assert from "node:assert/strict";
import { readdirSync, readFileSync, realpathSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";
import { listRecords, machineSettingsFiles, readPointers, sessionFolders, writePointer } from "./machine-records.mjs";
import { recordPath, swapRecord } from "./record.mjs";
import { knownFolders } from "./usage.mjs";
import { tempDir, writeTree } from "../tests/temp.mjs";

const record = (settingsFile, profile = "build") => ({
  schema: 1, profile, target: "folder", settingsFile, appliedAt: "2026-11-01T00:00:00.000Z", pluginVersion: "0.6.1", phase: "applied", pending: {},
  createdFile: false, createdFolder: false, containers: { enabledPlugins: true, skillOverrides: false }, installed: [],
  entries: { "songwriting@melodic-software": { before: true, after: false } }, skillOverrides: {},
});

/** Writes rec into home as apply would, and returns its path. */
function saved(home, rec) {
  const path = recordPath(home, rec.settingsFile);
  writeTree(home, { [`records/${path.split(/[\\/]/).pop()}`]: rec });
  return path;
}

test("#17354: records of one settings file in two homes give one entry, planned from the first", () => {
  const root = realpathSync(tempDir());
  const file = join(root, "project", ".claude", "settings.local.json");
  writeTree(root, { "project/.claude/settings.local.json": "{}\n" });
  const git = join(root, "project", ".git", "plugin-profiles");
  const data = join(root, "data");
  const first = saved(git, record(file, "build"));
  const second = saved(data, record(file, "review"));
  const found = machineSettingsFiles({ homes: [data, git], homesOf: () => [git, data], recordOf: () => ({ found: first, record: record(file, "build") }) });
  assert.equal(found.length, 1);
  assert.equal(found[0].settingsFile, file);
  assert.equal(found[0].recordPath, first);
  assert.equal(found[0].record.profile, "build");
  assert.deepEqual(found[0].copies.map((c) => c.path).sort(), [first, second].sort());
});

test("#17354: one pointer per record home, written again without a second file, and read back", () => {
  const config = tempDir();
  const home = join(tempDir(), ".git", "plugin-profiles");
  writePointer(config, home);
  writePointer(config, home);
  writePointer(config, join(tempDir(), ".git", "plugin-profiles"));
  assert.equal(readdirSync(join(config, "plugin-profiles-state", "repositories")).length, 2);
  assert.ok(readPointers(config).includes(home));
  assert.deepEqual(readPointers(tempDir()), [], "no pointers folder reads as none");
});

test("#17354: an unreadable record, a temp file and a pointer that is not JSON are passed over", () => {
  const config = tempDir();
  const home = tempDir();
  writeTree(home, { "records/a.json": "{not json", "records/.a.json.1.2.tmp": "{}", "records/b.json": record(join(home, "x", ".claude", "settings.local.json")) });
  assert.deepEqual(listRecords(home).map((r) => r.path), [join(home, "records", "b.json")]);
  writeTree(config, { "plugin-profiles-state/repositories/bad.json": "nope" });
  assert.deepEqual(readPointers(config), []);
});

test("#17354: a record whose folder is gone is marked missing, and a git-home one names the file of the repository where it is now", () => {
  const root = realpathSync(tempDir());
  writeTree(root, { "moved/.git/HEAD": "ref: refs/heads/main\n" });
  const home = join(root, "moved", ".git", "plugin-profiles");
  const gone = join(root, "old-place", ".claude", "settings.local.json");
  saved(home, record(gone));
  const [found] = machineSettingsFiles({ homes: [home], homesOf: () => [], recordOf: () => ({ found: null, record: null }) });
  assert.equal(found.missing, true);
  assert.equal(found.movedTo, join(root, "moved", ".claude", "settings.local.json"));
  assert.equal(found.recordPath, recordPath(home, gone), "with no lookup hit, the entry is planned from its own copy");
});

test("#17354: a known folder's file is adopted, or listed with its entries when it has neither a record nor an adopted one", () => {
  const root = realpathSync(tempDir());
  const adopted = join(root, "wt", ".claude", "settings.local.json");
  const loose = join(root, "loose", ".claude", "settings.local.json");
  const empty = join(root, "empty", ".claude", "settings.local.json");
  writeTree(root, {
    "wt/.claude/settings.local.json": "{}\n",
    "loose/.claude/settings.local.json": { enabledPlugins: { "a@m": true }, skillOverrides: { "s:k": "off" } },
    "empty/.claude/settings.local.json": { permissions: {} },
  });
  const knownFiles = [
    { file: adopted, found: { found: null, record: record(adopted) } },
    { file: loose, found: { found: null, record: null } },
    { file: empty, found: { found: null, record: null } },
  ];
  const found = machineSettingsFiles({ homes: [], homesOf: () => [], recordOf: () => ({ found: null, record: null }), knownFiles });
  assert.deepEqual(found.map((f) => [f.settingsFile, f.adopted, Boolean(f.record)]), [[adopted, true, true], [loose, false, false]]);
  assert.deepEqual(found[1].entries, ["a@m", "skill s:k"]);
});

test("#17354: ~/.claude.json is read tolerantly: a missing file or a missing or reshaped projects key gives no folders", () => {
  const read = (text) => () => text;
  assert.deepEqual(knownFolders("/x", read(JSON.stringify({ projects: { "/a": {}, "/b": {} } }))), ["/a", "/b"]);
  assert.deepEqual(knownFolders(join(tempDir(), "absent.json")), []);
  for (const text of ["{", "{}", JSON.stringify({ projects: ["/a"] }), JSON.stringify({ projects: "/a" }), JSON.stringify({ projects: null })]) {
    assert.deepEqual(knownFolders("/x", read(text)), [], text);
  }
});

test("#17354: a record is swapped only while it still holds what reset read, so an apply that saved one first keeps it", () => {
  const dir = tempDir();
  const path = join(dir, "records", "r.json");
  writeTree(dir, { "records/r.json": "applied by another terminal\n" });
  assert.equal(swapRecord(path, "read by reset\n", "restoring\n"), false);
  assert.equal(readFileSync(path, "utf8"), "applied by another terminal\n");
  assert.deepEqual(readdirSync(join(dir, "records")), ["r.json"], "no temp file left behind");
  assert.equal(swapRecord(path, "applied by another terminal\n", "restoring\n"), true);
  assert.equal(readFileSync(path, "utf8"), "restoring\n");
});

test("#17354: session records give the folder each one-session terminal started in", () => {
  const data = tempDir();
  writeTree(data, { "sessions/by-id/a.json": { folder: "/one" }, "sessions/by-id/b.json": { folder: 7 }, "sessions/by-id/c.json": "nope" });
  assert.deepEqual(sessionFolders([data, tempDir()]), ["/one"]);
});
