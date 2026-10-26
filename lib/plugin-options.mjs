// Reads a plugin's userConfig options from the operator's own settings, channel F of
// docs/conventions/hook-config-delivery: pluginConfigs["<name>@<marketplace>"].options in the
// fixed-path managed settings files and in the user settings.json, the latter located only from
// this install's own path. Nothing here reads the environment: a repository's settings env block
// reaches every process a session starts and carries no provenance, so CLAUDE_CONFIG_DIR, HOME,
// %ProgramFiles% and the CLAUDE_PLUGIN_OPTION_* mirror are never consulted, and neither is any
// file in the checkout (a project .claude/settings.json).
//
//   readOperatorOptions(resolveInstall(<plugin root, from the caller's own real path>), managedSettingsFiles(), keys)
//     -> {<key>: {value, scope: "user" | "managed", file}} for each key a source sets
//
// Sources, highest precedence first (managed settings page, "How Claude Code combines managed
// sources" and "managed-settings.d", https://code.claude.com/docs/en/managed-settings, read
// 2026-10-11; recheck when that section or the settings-reference pluginConfigs scope changes):
//   1. managed-settings.json then every non-hidden *.json in managed-settings.d/ in alphabetical
//      order, a later file replacing an earlier one's value; the system directory is a fixed
//      literal per platform, chosen by process.platform.
//   2. <config>/settings.json, where <config> is the prefix before plugins/cache/<marketplace>/
//      <name>/<version> in this install's real path. An install outside that layout (a
//      --plugin-dir checkout) has no trusted user-settings location, so only managed settings
//      count there, matched by manifest name.
// Not visible here, so not honored: a session's --settings file, server-managed (remote) and MDM
// policies. A value supplied only there reads as unset.

import { readdirSync, readFileSync, statSync } from "node:fs";
import { join } from "node:path";

const MANAGED_DIRS = {
  darwin: "/Library/Application Support/ClaudeCode",
  linux: "/etc/claude-code",
  win32: "C:\\Program Files\\ClaudeCode",
};

export class OptionsError extends Error {}

// The managed settings files in merge order, or [] on a platform with no documented path.
export function managedSettingsFiles(platform = process.platform) {
  const dir = MANAGED_DIRS[platform];
  if (!dir) return [];
  const files = [join(dir, "managed-settings.json")];
  const dropin = join(dir, "managed-settings.d");
  let names = [];
  try {
    names = readdirSync(dropin);
  } catch (error) {
    if (error.code !== "ENOENT" && error.code !== "ENOTDIR") {
      throw new OptionsError(`managed settings directory ${dropin} cannot be read (${error.code ?? error.message})`);
    }
  }
  for (const name of names.filter((n) => n.endsWith(".json") && !n.startsWith(".")).sort()) {
    files.push(join(dropin, name));
  }
  return files;
}

// This install's identity and, when it sits in the plugin cache, its user settings file.
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
    // An unreadable manifest leaves no name to match, so no settings entry applies.
  }
  return { pluginId: null, name: typeof name === "string" && name ? name : null, userSettings: null };
}

// The options object(s) for this install in one settings file, or [] when the file is absent.
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
  if (settings === null || typeof settings !== "object" || Array.isArray(settings)) {
    throw new OptionsError(`settings file ${file} is not a JSON object`);
  }
  // A malformed pluginConfigs or matching entry fails closed rather than contributing no verdict,
  // so a broken managed file cannot let the user scope decide.
  const isObject = (value) => value !== null && typeof value === "object" && !Array.isArray(value);
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

// Resolves each of `keys` to {value, scope, file}; a key no source configures is absent.
// Throws OptionsError when a source that could hold a value cannot be read, its pluginConfigs,
// this plugin's entry or its options is not an object, or a configured value is not a string
// (null included): either way the operator's value is not known, and the caller fails closed.
export function readOperatorOptions(install, managedFiles, keys) {
  const user = {};
  const managed = {};
  const take = (file, scope, into) => {
    for (const options of optionsIn(file, install)) {
      for (const key of keys) {
        if (!Object.hasOwn(options, key)) continue;
        if (typeof options[key] !== "string") throw new OptionsError(`${key} in ${file} is not a string`);
        into[key] = { value: options[key], scope, file };
      }
    }
  };
  if (install.userSettings !== null) take(install.userSettings, "user", user);
  for (const file of managedFiles) take(file, "managed", managed);
  return { ...user, ...managed };
}
