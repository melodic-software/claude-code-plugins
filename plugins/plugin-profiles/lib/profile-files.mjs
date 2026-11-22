// Profile files: one YAML file per profile, at three levels, resolved into one catalog.
//
//   profileLevels({pluginRoot, configDir, projectDir, conventionHome}) -> [{level, dir}], lowest first
//   readProfileFiles(levels) -> [{level, name, path, def}], each file validated, or throws ProfileError
//   resolveCatalog(files) -> {alwaysOn, profiles: Map<name, profile>}, each profile also carrying
//                            fromRepository {plugins, hideSkills} and ignored [{file, list, id}]
//   readCatalog(levels) = resolveCatalog(readProfileFiles(levels))
//   parseProfile(text, where) -> {description, plugins, optional, remove, exclude, hideSkills}, validated
//   profileText(def) -> the file text for a def, which parseProfile reads back as the same def
//
// Levels: shipped <plugin root>/profiles, user <config dir>/plugin-profiles, repository
// <project>/<convention home>/plugin-profiles (ADR 0075; default home docs/conventions).
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { parse } from "./yaml-subset.mjs";

export class ProfileError extends Error {}

export const ALWAYS_ON = "always-on";
export const PLUGIN_ID = /^[A-Za-z0-9][A-Za-z0-9._-]*@[A-Za-z0-9][A-Za-z0-9._-]*$/;
const LISTS = { plugins: "plugins", optional: "optional", remove: "remove", exclude: "exclude", hide_skills: "hideSkills" };
const IDS = new Set(["plugins", "optional", "remove", "exclude"]);
const EMPTY = { description: null, alwaysOn: null, plugins: [], optional: [], remove: [], exclude: [], hideSkills: [] };

export function profileLevels({ pluginRoot, configDir, projectDir, conventionHome = "docs/conventions" }) {
  return [
    { level: "shipped", dir: join(pluginRoot, "profiles") },
    { level: "user", dir: join(configDir, "plugin-profiles") },
    { level: "repository", dir: join(projectDir, conventionHome, "plugin-profiles") },
  ];
}

function validateProfile(doc, where) {
  const fail = (why) => {
    throw new ProfileError(`${where}: ${why}`);
  };
  if (doc === null || typeof doc !== "object" || Array.isArray(doc)) fail("the file is not a mapping of profile keys");
  const out = { description: null, alwaysOn: null };
  for (const key of Object.values(LISTS)) out[key] = [];
  for (const [key, value] of Object.entries(doc)) {
    if (key === "description") {
      if (typeof value !== "string" || !value || value.includes("\n")) fail("description must be one line of text");
      out.description = value;
    } else if (key === "always_on") {
      if (typeof value !== "boolean") fail("always_on must be true or false");
      out.alwaysOn = value;
    } else if (key in LISTS) {
      if (!Array.isArray(value) || !value.every((v) => typeof v === "string" && v)) fail(`${key} must be a list of names`);
      const bad = IDS.has(key) ? value.filter((v) => !PLUGIN_ID.test(v)) : [];
      if (bad.length) fail(`${key} names ${bad.join(", ")}; write every plugin as name@marketplace`);
      out[LISTS[key]] = value;
    } else {
      fail(`unknown key ${JSON.stringify(key)}; a profile takes description, always_on, ${Object.keys(LISTS).join(", ")}`);
    }
  }
  return out;
}

export function parseProfile(text, where) {
  let doc;
  try {
    doc = parse(text) ?? {};
  } catch (error) {
    throw new ProfileError(`${where}: ${error.message}`);
  }
  return validateProfile(doc, where);
}

function readProfileFile(path) {
  let text;
  try {
    text = readFileSync(path, "utf8");
  } catch (error) {
    throw new ProfileError(`${path}: ${error.message}`);
  }
  return parseProfile(text, path);
}

/** A list in the order a profile file keeps it: sorted by code unit, the same on every machine. */
export const alphabetical = (names) => [...names].sort();

export function profileText(def) {
  const lines = def.description ? [`description: ${JSON.stringify(def.description)}`] : [];
  if (typeof def.alwaysOn === "boolean") lines.push(`always_on: ${def.alwaysOn}`);
  for (const [key, field] of Object.entries(LISTS)) {
    if (def[field]?.length) lines.push(`${key}:`, ...alphabetical(def[field]).map((v) => `  - ${JSON.stringify(v)}`));
  }
  return `${lines.join("\n")}\n`;
}

const emptyProfile = (name) => ({
  name,
  description: null,
  keepsAlwaysOn: true,
  plugins: new Set(),
  optional: new Set(),
  exclude: new Set(),
  hideSkills: new Set(),
  fromRepository: { plugins: new Set(), hideSkills: new Set() },
  ignored: [],
});

function extend(lower, file, name, { repository = false, ignored = [] } = {}) {
  const base = lower ?? emptyProfile(name);
  const plugins = new Set([...base.plugins, ...file.plugins]);
  const optional = new Set([...base.optional, ...file.optional]);
  for (const id of file.remove) {
    plugins.delete(id);
    optional.delete(id);
  }
  const added = (ids, had) => (repository ? ids.filter((id) => !had.has(id)) : []);
  return {
    name,
    description: file.description ?? base.description,
    keepsAlwaysOn: file.alwaysOn ?? base.keepsAlwaysOn,
    plugins,
    optional,
    exclude: new Set([...base.exclude, ...file.exclude]),
    hideSkills: new Set([...base.hideSkills, ...file.hideSkills]),
    fromRepository: {
      plugins: new Set([...base.fromRepository.plugins, ...added([...file.plugins, ...file.optional], new Set([...base.plugins, ...base.optional]))]),
      hideSkills: new Set([...base.fromRepository.hideSkills, ...added(file.hideSkills, base.hideSkills)]),
    },
    ignored: [...base.ignored, ...ignored],
  };
}

/** What the preview and check print for a repository line that would switch off an always-on member. */
export const ignoredLine = ({ file, list, id, key, value }) =>
  `Ignored, from ${file}: ${key ? `${key}: ${value}` : `${list} ${id}`}. A repository profile cannot switch off an always-on member; a user-level profile can.`;

function yamlFiles(dir) {
  try {
    return readdirSync(dir, { withFileTypes: true })
      .filter((e) => e.isFile() && e.name.endsWith(".yaml"))
      .map((e) => e.name)
      .sort();
  } catch (error) {
    if (error.code === "ENOENT" || error.code === "ENOTDIR") return [];
    throw new ProfileError(`${dir}: ${error.message}`);
  }
}

/** Every profile file, lowest level first: [{level, name, path, def}], def as validated from the file. */
export function readProfileFiles(levels) {
  return levels.flatMap(({ level, dir }) =>
    yamlFiles(dir).map((file) => ({ level, name: file.slice(0, -".yaml".length), path: join(dir, file), def: readProfileFile(join(dir, file)) })),
  );
}

/**
 * The catalog the files resolve to, each same-named file extending the one below it. A repository
 * file's remove and exclude lines that name a member of always-on as the shipped and user files
 * resolve it, and its always_on: false, are left out and listed in the profile's ignored.
 */
export function resolveCatalog(files) {
  const own = files.filter((f) => f.name === ALWAYS_ON && f.level !== "repository").reduce((p, f) => extend(p, f.def, ALWAYS_ON), null);
  const guarded = new Set(own ? [...own.plugins, ...own.optional] : []);
  const resolved = new Map();
  for (const { level, name, path, def } of files) {
    const repository = level === "repository";
    const ignored = repository ? ["remove", "exclude"].flatMap((list) => def[list].filter((id) => guarded.has(id)).map((id) => ({ file: path, list, id }))) : [];
    if (repository && def.alwaysOn === false) ignored.push({ file: path, key: "always_on", value: false });
    const kept = ignored.length
      ? { ...def, alwaysOn: def.alwaysOn || null, remove: def.remove.filter((id) => !guarded.has(id)), exclude: def.exclude.filter((id) => !guarded.has(id)) }
      : def;
    resolved.set(name, extend(resolved.get(name), kept, name, { repository, ignored }));
  }
  const alwaysOn = resolved.get(ALWAYS_ON) ?? extend(null, EMPTY, ALWAYS_ON);
  resolved.delete(ALWAYS_ON);
  return { alwaysOn, profiles: resolved };
}

/** The profiles an apply of profile merges: always-on and the profile, or the profile alone when it sets always_on: false. */
export const sourcesOf = (catalog, profile) => (profile.keepsAlwaysOn && profile !== catalog.alwaysOn ? [catalog.alwaysOn, profile] : [profile]);

/** Every profile of a catalog, always-on first. */
export const everyProfile = (catalog) => [catalog.alwaysOn, ...catalog.profiles.values()];

/** The catalog's profile of that name, always-on included, or undefined. */
export const profileNamed = (catalog, name) => (name === catalog.alwaysOn.name ? catalog.alwaysOn : catalog.profiles.get(name));

export const readCatalog = (levels) => resolveCatalog(readProfileFiles(levels));

