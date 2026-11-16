// Profile files: one YAML file per profile, at three levels, resolved into one catalog.
//
//   profileLevels({pluginRoot, configDir, projectDir, conventionHome}) -> [{level, dir}], lowest first
//   readCatalog(levels) -> {alwaysOn, profiles: Map<name, profile>}, or throws ProfileError
//
// Levels: shipped <plugin root>/profiles, user <config dir>/plugin-profiles, repository
// <project>/<convention home>/plugin-profiles (ADR 0075; default home docs/conventions).
// A same-named file at a higher level extends the one below: plugins = lower + plugins - remove;
// optional, exclude and hide_skills add up; description is the highest one set. always-on.yaml
// resolves the same way and is kept apart from the named profiles.
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { parse } from "./yaml-subset.mjs";

export class ProfileError extends Error {}

export const ALWAYS_ON = "always-on";
export const PLUGIN_ID = /^[A-Za-z0-9][A-Za-z0-9._-]*@[A-Za-z0-9][A-Za-z0-9._-]*$/;
const LISTS = { plugins: "plugins", optional: "optional", remove: "remove", exclude: "exclude", hide_skills: "hideSkills" };
const IDS = new Set(["plugins", "optional", "remove", "exclude"]);
const EMPTY = { description: null, plugins: [], optional: [], remove: [], exclude: [], hideSkills: [] };

export function profileLevels({ pluginRoot, configDir, projectDir, conventionHome = "docs/conventions" }) {
  return [
    { level: "shipped", dir: join(pluginRoot, "profiles") },
    { level: "user", dir: join(configDir, "plugin-profiles") },
    { level: "repository", dir: join(projectDir, conventionHome, "plugin-profiles") },
  ];
}

/** One file's {description, plugins, optional, remove, exclude, hideSkills}, validated. */
function readProfileFile(path) {
  const fail = (why) => {
    throw new ProfileError(`${path}: ${why}`);
  };
  let doc;
  try {
    doc = parse(readFileSync(path, "utf8")) ?? {};
  } catch (error) {
    fail(error.message);
  }
  if (typeof doc !== "object" || Array.isArray(doc)) fail("the file is not a mapping of profile keys");
  const out = { description: null };
  for (const key of Object.values(LISTS)) out[key] = [];
  for (const [key, value] of Object.entries(doc)) {
    if (key === "description") {
      if (typeof value !== "string" || !value) fail("description must be one line of text");
      out.description = value;
    } else if (key in LISTS) {
      if (!Array.isArray(value) || !value.every((v) => typeof v === "string" && v)) fail(`${key} must be a list of names`);
      const bad = IDS.has(key) ? value.filter((v) => !PLUGIN_ID.test(v)) : [];
      if (bad.length) fail(`${key} names ${bad.join(", ")}; write every plugin as name@marketplace`);
      out[LISTS[key]] = value;
    } else {
      fail(`unknown key ${JSON.stringify(key)}; a profile takes description, ${Object.keys(LISTS).join(", ")}`);
    }
  }
  return out;
}

function extend(lower, file, name) {
  const base = lower ?? { name, description: null, plugins: new Set(), optional: new Set(), exclude: new Set(), hideSkills: new Set() };
  const plugins = new Set([...base.plugins, ...file.plugins]);
  for (const id of file.remove) plugins.delete(id);
  return {
    name,
    description: file.description ?? base.description,
    plugins,
    optional: new Set([...base.optional, ...file.optional]),
    exclude: new Set([...base.exclude, ...file.exclude]),
    hideSkills: new Set([...base.hideSkills, ...file.hideSkills]),
  };
}

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

export function readCatalog(levels) {
  const resolved = new Map();
  for (const { dir } of levels) {
    for (const file of yamlFiles(dir)) {
      const name = file.slice(0, -".yaml".length);
      resolved.set(name, extend(resolved.get(name), readProfileFile(join(dir, file)), name));
    }
  }
  const alwaysOn = resolved.get(ALWAYS_ON) ?? extend(null, EMPTY, ALWAYS_ON);
  resolved.delete(ALWAYS_ON);
  return { alwaysOn, profiles: resolved };
}

