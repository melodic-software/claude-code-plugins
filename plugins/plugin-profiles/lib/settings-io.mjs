import { createHash } from "node:crypto";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { removeFile, replaceFile } from "./atomic-file.mjs";
import { folderLevel } from "./folder-file.mjs";
import { realPath } from "./record.mjs";

export class SettingsError extends Error {}
export class SettingsConflict extends Error {}

const ABSENT = "absent";
const KEYS = ["enabledPlugins", "skillOverrides", "env"];
const isObject = (v) => v !== null && typeof v === "object" && !Array.isArray(v);
export const hashOf = (text) => (text === null ? ABSENT : createHash("sha256").update(text).digest("hex"));

/** local is the folder file lib/folder-file.mjs resolves; earlier is the folder's own file when that differs, which Claude Code still reads below local; project is null when it is the user file, as in the home folder. */
export function settingsPaths({ configDir, projectDir, home }) {
  const local = folderLevel(projectDir, home ? { home } : {}).file;
  const own = join(projectDir, ".claude", "settings.local.json");
  const user = join(configDir, "settings.json");
  const project = join(projectDir, ".claude", "settings.json");
  return {
    user,
    project: realPath(project) === realPath(user) ? null : project,
    local,
    earlier: realPath(own) === realPath(local) ? null : own,
  };
}

function readText(path) {
  try {
    return readFileSync(path, "utf8");
  } catch (error) {
    if (error.code === "ENOENT") return null;
    throw new SettingsError(`${path} cannot be read (${error.code ?? error.message})`);
  }
}

export function readSettings(path) {
  const text = readText(path);
  let doc = {};
  if (text !== null && text.trim()) {
    try {
      doc = JSON.parse(text);
    } catch (error) {
      throw new SettingsError(`${path} is not valid JSON (${error.message}); fix it before applying a profile`);
    }
    if (!isObject(doc)) throw new SettingsError(`${path} is not a JSON object`);
  }
  for (const key of KEYS) {
    if (key in doc && !isObject(doc[key])) throw new SettingsError(`${key} in ${path} is not an object`);
  }
  return { path, exists: text !== null, text, hash: hashOf(text), doc };
}

const layerOf = (doc) => ({ enabledPlugins: { ...doc.enabledPlugins }, skillOverrides: { ...doc.skillOverrides } });

/** The plugin and skill entries of each level; local holds earlier's entries with local's over them. */
export function readLayers({ paths, managedFiles }) {
  const managed = { enabledPlugins: {}, skillOverrides: {} };
  for (const file of managedFiles) {
    if (!existsSync(file)) continue;
    const layer = layerOf(readSettings(file).doc);
    Object.assign(managed.enabledPlugins, layer.enabledPlugins);
    Object.assign(managed.skillOverrides, layer.skillOverrides);
  }
  const level = (path) => layerOf(path ? readSettings(path).doc : {});
  const local = level(paths.local);
  if (paths.earlier) {
    const earlier = level(paths.earlier);
    for (const key of Object.keys(local)) local[key] = { ...earlier[key], ...local[key] };
  }
  return { managed, user: level(paths.user), project: level(paths.project), local };
}

function formatOf(text) {
  if (!text) return { indent: 2, eol: "\n", finalNewline: true };
  const eol = text.includes("\r\n") ? "\r\n" : "\n";
  const second = text.split(eol)[1] ?? "";
  const indent = /^\s+/.exec(second)?.[0] ?? "";
  return { indent: indent.startsWith("\t") ? "\t" : indent.length, eol, finalNewline: text.endsWith(eol) };
}

export function editText(settings, edits, { dropEmpty = [] } = {}) {
  const doc = structuredClone(settings.doc);
  for (const [key, changes] of Object.entries(edits)) {
    if (!KEYS.includes(key)) throw new SettingsError(`refusing to write ${key}: only ${KEYS.join(", ")} are this tool's`);
    if (!Object.keys(changes).length) continue;
    const into = isObject(doc[key]) ? doc[key] : {};
    for (const [name, value] of Object.entries(changes)) {
      if (value === null) delete into[name];
      else into[name] = value;
    }
    if (Object.keys(into).length === 0 && dropEmpty.includes(key)) delete doc[key];
    else doc[key] = into;
  }
  const { indent, eol, finalNewline } = formatOf(settings.text);
  const body = JSON.stringify(doc, null, indent).replaceAll("\n", eol);
  return finalNewline ? `${body}${eol}` : body;
}

const guard = (path, baseHash) => () => {
  const now = hashOf(readText(path));
  if (now !== baseHash) throw new SettingsConflict(`${path} changed while this apply ran`);
};

export function writeSettings(path, baseHash, text) {
  replaceFile(path, text, { beforeRename: guard(path, baseHash) });
}

export function deleteSettings(path, baseHash) {
  guard(path, baseHash)();
  removeFile(path);
}
