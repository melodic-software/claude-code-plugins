// The five-layer plugin config cascade (docs/adr/0061): later layers win per key.
//
//   resolve({plugin, projectRoot, home, schema, defaults, userConfig, teamOnly, userHome})
//     -> {values, provenance: {"a.b": layer | [layers]}, prose: [paths],
//         layers: [{name, path, state: "loaded" | "absent" | "invalid", errors}], legacy: [{path, kind}]}
//
// Layers, in order: "defaults" (the `defaults` object, already parsed by the caller), "userConfig"
// (the plugin's userConfig values, flattened names), "user" (<userHome>/docs/conventions/<plugin>),
// "team" (<home>/<plugin>), "local" (<home>/<plugin>.local). A file layer reads <stem>.yaml for
// config and <stem>.md for prose; it is absent when neither file exists. `home` is the convention
// home the caller resolved, relative to projectRoot unless absolute (default docs/conventions).
// `userHome` defaults to os.homedir(). `schema` is a JSON Schema object; the subset honored is type
// (object, string, array, null, integer, number, boolean), enum, properties, additionalProperties
// (false or a schema) and items.
//
// A key is a schema leaf: any node that is not an object with `properties`, or a path named in
// `teamOnly`. Each layer's leaves are checked one by one; a leaf that fails is dropped from that layer
// with an error naming layer, file and key, and the lower layer keeps it. A team-only key is
// accepted in "defaults" and "team" and rejected elsewhere. A YAML file that does not parse, or
// whose top level is not a mapping, makes its layer invalid and contributes no values; its .md
// file still supplies prose. A leaf whose last segment is `disable` and whose value is a list is the
// union of every layer's list, and its provenance lists each layer that set it; any other key's
// provenance is the one layer that supplied the value.
//
// userConfig maps each schema leaf path to its name joined with `_` (widget.limit is widget_limit);
// two leaves with one name throw. An empty string or an unrendered `${user_config.` placeholder is
// unset, names outside the schema are ignored, and a list, mapping or team-only key is rejected.
// A string value takes the leaf's integer, number or boolean type when the leaf does not accept
// strings. Legacy locations (.claude/<plugin>.* under userHome and projectRoot, and a fenced
// `yaml config` block in the team .md) are reported in `legacy`, never read for values.
// This module reads files only. File contents are data; error messages quote them as JSON strings.
import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import { homedir } from "node:os";
import { join, resolve as resolvePath } from "node:path";
import { parse } from "./yaml-subset.mjs";

const PLUGIN = /^[A-Za-z0-9][A-Za-z0-9._-]*$/;
const SCALARS = ["string", "integer", "number", "boolean", "null"];
const quote = (text) => JSON.stringify(text.length > 60 ? `${text.slice(0, 60)}...` : text);
const show = (value) => quote(JSON.stringify(value) ?? String(value));
const put = (object, key, value) => Object.defineProperty(object, key, { value, enumerable: true, writable: true, configurable: true });
const isMapping = (v) => v !== null && typeof v === "object" && !Array.isArray(v);
const isFile = (p) => existsSync(p) && statSync(p).isFile();
const typesOf = (node) => (node.type === undefined ? null : [node.type].flat());

const fits = {
  object: isMapping,
  array: Array.isArray,
  string: (v) => typeof v === "string",
  integer: Number.isInteger,
  number: (v) => typeof v === "number" && Number.isFinite(v),
  boolean: (v) => typeof v === "boolean",
  null: (v) => v === null,
};

/** The schema for `key` under `node`: a schema, null when anything goes, false when it is unknown. */
function child(node, key) {
  if (isMapping(node.properties) && Object.hasOwn(node.properties, key)) return node.properties[key];
  if (node.additionalProperties === false) return false;
  return isMapping(node.additionalProperties) ? node.additionalProperties : null;
}

const isBranch = (node, path, teamOnly) =>
  isMapping(node) && isMapping(node.properties) && !teamOnly.has(path) && (typesOf(node)?.includes("object") ?? true);

/** Why `value` does not fit `node`, as messages relative to the key; empty when it fits. */
function check(value, node, at = "") {
  const prefix = at ? `${at}: ` : "";
  const types = typesOf(node);
  if (types && !types.some((t) => fits[t]?.(value))) return [`${prefix}expected ${types.join(" or ")}, got ${show(value)}`];
  if (Array.isArray(node.enum) && !node.enum.includes(value)) return [`${prefix}${show(value)} is not one of ${node.enum.map(show).join(", ")}`];
  if (Array.isArray(value) && isMapping(node.items)) return value.flatMap((item, i) => check(item, node.items, `${at}[${i}]`));
  if (!isMapping(value)) return [];
  return Object.keys(value).flatMap((key) => {
    const sub = child(node, key);
    const where = `${at}.${quote(key)}`;
    if (sub === false) return [`${where}: unknown key`];
    return sub ? check(value[key], sub, where) : [];
  });
}

/** The accepted leaves of one layer's mapping, as [parts, value] pairs; rejections go to `fail`. */
function leaves(data, schema, { teamOnly, allowTeamOnly, fail }) {
  const out = [];
  const walk = (object, node, parts) => {
    for (const key of Object.keys(object)) {
      const path = [...parts, key];
      const dotted = path.join(".");
      const sub = child(node, key);
      const value = object[key];
      if (sub === false) fail(`${quote(dotted)}: unknown key`);
      else if (teamOnly.has(dotted) && !allowTeamOnly) fail(`${quote(dotted)}: accepted only in the team layer`);
      else if (sub && isBranch(sub, dotted, teamOnly)) {
        if (isMapping(value)) walk(value, sub, path);
        else if (value !== null) fail(`${quote(dotted)}: expected a mapping, got ${show(value)}`);
      } else {
        const problems = sub ? check(value, sub) : [];
        if (problems.length) fail(`${quote(dotted)}: ${problems.join("; ")}`);
        else out.push([path, value]);
      }
    }
  };
  walk(data, schema, []);
  return out;
}

/** Flattened userConfig name to {path, node} for every schema leaf. */
function flatNames(schema, teamOnly) {
  const names = new Map();
  const walk = (node, parts) => {
    for (const key of Object.keys(isMapping(node.properties) ? node.properties : {})) {
      const path = [...parts, key];
      const dotted = path.join(".");
      const sub = node.properties[key];
      if (isBranch(sub, dotted, teamOnly)) {
        walk(sub, path);
        continue;
      }
      const name = path.join("_");
      if (names.has(name)) throw new Error(`config-cascade: schema keys ${names.get(name).dotted} and ${dotted} both flatten to userConfig name ${name}`);
      names.set(name, { path, dotted, node: sub });
    }
  };
  walk(schema, []);
  return names;
}

function coerce(raw, node) {
  const types = typesOf(node) ?? [];
  if (typeof raw !== "string" || types.includes("string")) return raw;
  if ((types.includes("integer") || types.includes("number")) && /^[-+]?\d+(\.\d+)?$/.test(raw)) return Number(raw);
  if (types.includes("boolean") && (raw === "true" || raw === "false")) return raw === "true";
  return raw;
}

function userConfigLeaves(userConfig, names, teamOnly, fail) {
  const out = [];
  for (const [name, raw] of Object.entries(userConfig)) {
    if (raw === undefined || raw === null || raw === "" || (typeof raw === "string" && raw.startsWith("${user_config."))) continue;
    const leaf = names.get(name);
    if (!leaf) continue;
    const types = typesOf(leaf.node);
    if (teamOnly.has(leaf.dotted)) fail(`${quote(leaf.dotted)}: accepted only in the team layer`);
    else if (types && !types.every((t) => SCALARS.includes(t))) fail(`${quote(leaf.dotted)}: lists and mappings are set only in files`);
    else {
      const value = coerce(raw, leaf.node);
      const problems = check(value, leaf.node);
      if (problems.length) fail(`${quote(leaf.dotted)}: ${problems.join("; ")}`);
      else out.push([leaf.path, value]);
    }
  }
  return out;
}

/** One file layer: its report entry, its parsed mapping (or null), and its prose path (or null). */
function readLayer(name, stem) {
  const path = `${stem}.yaml`;
  const md = `${stem}.md`;
  const prose = isFile(md) ? md : null;
  const layer = { name, path, state: prose ? "loaded" : "absent", errors: [] };
  if (!existsSync(path)) return { layer, data: null, prose };
  try {
    const doc = parse(readFileSync(path, "utf8")) ?? {};
    if (!isMapping(doc)) throw new Error("the top level must be a mapping");
    layer.state = "loaded";
    return { layer, data: doc, prose };
  } catch (e) {
    layer.state = "invalid";
    layer.errors.push(`${name} (${path}): ${e.message}`);
    return { layer, data: null, prose };
  }
}

/** True when the Markdown file holds a ```<lang> config block outside any other fence. */
function hasConfigBlock(path) {
  let text;
  try {
    text = readFileSync(path, "utf8");
  } catch {
    return false;
  }
  let fence = 0;
  for (const line of text.split(/\r\n|\r|\n/)) {
    const ticks = line.match(/^`{3,}/)?.[0].length ?? 0;
    if (fence) {
      if (ticks >= fence && line.trimEnd().length === ticks) fence = 0;
    } else if (/^```[A-Za-z0-9_-]+ config\s*$/.test(line)) return true;
    else if (ticks) fence = ticks;
  }
  return false;
}

function legacyFiles(dir, plugin, kind) {
  let entries;
  try {
    entries = readdirSync(dir, { withFileTypes: true });
  } catch {
    return [];
  }
  return entries.filter((e) => e.isFile() && e.name.startsWith(`${plugin}.`)).map((e) => ({ path: join(dir, e.name), kind: kind(e.name) }));
}

function setPath(object, parts, value) {
  let at = object;
  for (const part of parts.slice(0, -1)) {
    if (!Object.hasOwn(at, part) || !isMapping(at[part])) put(at, part, {});
    at = at[part];
  }
  put(at, parts.at(-1), value);
}

export function resolve({ plugin, projectRoot, home = "docs/conventions", schema, defaults, userConfig, teamOnly = [], userHome = homedir() }) {
  if (typeof plugin !== "string" || !PLUGIN.test(plugin)) throw new Error(`config-cascade: plugin name ${JSON.stringify(plugin)} is not a plain name`);
  const only = new Set(teamOnly);
  const names = flatNames(schema, only);
  const homeDir = resolvePath(projectRoot, home);
  const layers = [];
  const contributions = []; // [layer name, [[parts, value]]]
  const prose = [];

  // pairsOf(fail) returns the layer's accepted [parts, value] pairs; falsy when it contributes none.
  const take = (layer, pairsOf) => {
    const fail = (message) => layer.errors.push(`${layer.name}${layer.path ? ` (${layer.path})` : ""}: ${message}`);
    if (pairsOf) contributions.push([layer.name, pairsOf(fail)]);
    layers.push(layer);
  };
  const fileLeaves = (data, allowTeamOnly) => data && ((fail) => leaves(data, schema, { teamOnly: only, allowTeamOnly, fail }));

  const shaped = (name, given) => {
    if (given === undefined || given === null) return { layer: { name, path: null, state: "absent", errors: [] }, ok: false };
    if (isMapping(given)) return { layer: { name, path: null, state: "loaded", errors: [] }, ok: true };
    return { layer: { name, path: null, state: "invalid", errors: [`${name}: expected a mapping, got ${show(given)}`] }, ok: false };
  };
  const d = shaped("defaults", defaults);
  take(d.layer, d.ok && fileLeaves(defaults, true));
  const u = shaped("userConfig", userConfig);
  take(u.layer, u.ok && ((fail) => userConfigLeaves(userConfig, names, only, fail)));
  for (const [name, stem] of [
    ["user", join(userHome, "docs/conventions", plugin)],
    ["team", join(homeDir, plugin)],
    ["local", join(homeDir, `${plugin}.local`)],
  ]) {
    const read = readLayer(name, stem);
    take(read.layer, fileLeaves(read.data, name === "team"));
    if (read.prose) prose.push(read.prose);
  }

  const merged = new Map(); // dotted -> {parts, value, from}
  for (const [name, pairs] of contributions) {
    for (const [parts, value] of pairs) {
      const dotted = parts.join(".");
      const prior = merged.get(dotted);
      if (parts.at(-1) === "disable" && Array.isArray(value)) {
        const items = Array.isArray(prior?.value) ? [...prior.value] : [];
        const seen = new Set(items.map((i) => JSON.stringify(i)));
        for (const item of value) {
          const key = JSON.stringify(item);
          if (!seen.has(key)) items.push(item);
          seen.add(key);
        }
        merged.set(dotted, { parts, value: items, from: [...(Array.isArray(prior?.from) ? prior.from : []), name] });
      } else merged.set(dotted, { parts, value, from: name });
    }
  }
  const values = {};
  const provenance = {};
  for (const [dotted, { parts, value, from }] of merged) {
    setPath(values, parts, value);
    put(provenance, dotted, from);
  }

  const teamMd = `${join(homeDir, plugin)}.md`;
  const legacy = [
    ...legacyFiles(join(userHome, ".claude"), plugin, () => "claude-user"),
    ...legacyFiles(join(projectRoot, ".claude"), plugin, (n) => (n.startsWith(`${plugin}.local.`) ? "claude-local" : "claude-project")),
    ...(hasConfigBlock(teamMd) ? [{ path: teamMd, kind: "fenced-block" }] : []),
  ];
  return { values, provenance, prose, layers, legacy };
}
