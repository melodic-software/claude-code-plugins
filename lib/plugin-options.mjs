import { readdirSync, readFileSync, statSync } from "node:fs";
import { join } from "node:path";

const MANAGED_DIRS = {
  darwin: "/Library/Application Support/ClaudeCode",
  linux: "/etc/claude-code",
  win32: "C:\\Program Files\\ClaudeCode",
};

export class OptionsError extends Error {}

const isObject = (value) => value !== null && typeof value === "object" && !Array.isArray(value);

export function managedSettingsFiles(platform = process.platform) {
  const dir = MANAGED_DIRS[platform];
  if (!dir) return [];
  const dropin = join(dir, "managed-settings.d");
  let names = [];
  try {
    names = readdirSync(dropin);
  } catch (error) {
    if (error.code !== "ENOENT" && error.code !== "ENOTDIR") {
      throw new OptionsError(`managed settings directory ${dropin} cannot be read (${error.code ?? error.message})`);
    }
  }
  const dropins = names.filter((n) => n.endsWith(".json") && !n.startsWith(".")).sort();
  return [join(dir, "managed-settings.json"), ...dropins.map((name) => join(dropin, name))];
}

export function resolveInstall(pluginRoot) {
  const parts = pluginRoot.replaceAll("\\", "/").split("/");
  const at = parts.lastIndexOf("cache");
  if (at > 0 && parts[at - 1] === "plugins" && parts.length - at === 4 && parts.slice(at + 1).every(Boolean)) {
    const [marketplace, name] = parts.slice(at + 1, at + 3);
    const configRoot = parts.slice(0, at - 1).join("/") || "/";
    return { pluginId: `${name}@${marketplace}`, name, userSettings: join(configRoot, "settings.json") };
  }
  let name = null;
  try {
    name = JSON.parse(readFileSync(join(pluginRoot, ".claude-plugin", "plugin.json"), "utf8")).name;
  } catch {
  }
  return { pluginId: null, name: typeof name === "string" && name ? name : null, userSettings: null };
}

function optionsIn(file, install) {
  let text;
  try {
    if (!statSync(file).isFile()) throw new OptionsError(`settings file ${file} is not a regular file`);
    text = readFileSync(file, "utf8");
  } catch (error) {
    if (error instanceof OptionsError) throw error;
    if (error.code === "ENOENT") return [];
    throw new OptionsError(`settings file ${file} cannot be read (${error.code ?? error.message})`);
  }
  let settings;
  try {
    settings = JSON.parse(text);
  } catch (error) {
    throw new OptionsError(`settings file ${file} is not valid JSON (${error.message})`);
  }
  if (!isObject(settings)) throw new OptionsError(`settings file ${file} is not a JSON object`);
  if (!Object.hasOwn(settings, "pluginConfigs")) return [];
  const configs = settings.pluginConfigs;
  if (!isObject(configs)) throw new OptionsError(`pluginConfigs in ${file} is not an object`);
  const matches = (key) =>
    install.pluginId !== null ? key === install.pluginId : key === install.name || key.startsWith(`${install.name}@`);
  if (install.pluginId === null && install.name === null) return [];
  return Object.keys(configs)
    .filter(matches)
    .sort()
    .flatMap((key) => {
      const entry = configs[key];
      if (!isObject(entry)) throw new OptionsError(`pluginConfigs["${key}"] in ${file} is not an object`);
      if (!Object.hasOwn(entry, "options")) return [];
      if (!isObject(entry.options)) throw new OptionsError(`pluginConfigs["${key}"].options in ${file} is not an object`);
      return [entry.options];
    });
}

export function readOperatorOptions(install, managedFiles, keys, { booleans = false } = {}) {
  const user = {};
  const managed = {};
  const take = (file, scope, into) => {
    for (const options of optionsIn(file, install)) {
      for (const key of keys) {
        if (!Object.hasOwn(options, key)) continue;
        const value = booleans && typeof options[key] === "boolean" ? String(options[key]) : options[key];
        if (typeof value !== "string") throw new OptionsError(`${key} in ${file} is not a string`);
        into[key] = { value, scope, file };
      }
    }
  };
  if (install.userSettings !== null) take(install.userSettings, "user", user);
  for (const file of managedFiles) take(file, "managed", managed);
  return { ...user, ...managed };
}
