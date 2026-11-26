// GENERATED from lib/config-cascade.mjs by scripts/sync-shared-copies.sh. Do not edit this copy:
// edit the canonical source, then rerun the script.
import { lstatSync, readdirSync, readFileSync, realpathSync } from "node:fs";
import { homedir } from "node:os";
import { basename, dirname, isAbsolute, join, relative, resolve as resolvePath, sep } from "node:path";
import { parse } from "./yaml-subset.mjs";

const PLUGIN = /^[A-Za-z0-9][A-Za-z0-9._-]*$/;
const SCALARS = ["string", "integer", "number", "boolean", "null"];
const DIRECTIONS = ["no-floor", "team-only", "lowest-value", "any-layer-wins", "stricter-value"];
const clip = (text) => (text.length > 60 ? `${text.slice(0, 60)}...` : text);
const quote = (text) => JSON.stringify(clip(text));
const show = (value) => clip(JSON.stringify(value) ?? String(value));
const put = (object, key, value) => Object.defineProperty(object, key, { value, enumerable: true, writable: true, configurable: true });
const isMapping = (v) => v !== null && typeof v === "object" && !Array.isArray(v);
const RESERVED = new Set(["__proto__", "constructor", "prototype"]);
const WRITER_KEYS = new Set(["written_against", "provenance"]);
const isWriterKey = (parts, key) => !parts.length && WRITER_KEYS.has(key);
const newLayer = (name, path, state, errors = [], error_keys = errors.map(() => null)) => ({ name, path, state, errors, error_keys });
/** Records an error on `layer`, tagged with the dotted key it names, or null for a file-level one. */
const record = (layer, message, key = null) => {
  layer.errors.push(message);
  layer.error_keys.push(key);
};
/** Records `message` on `layer`, prefixed with the layer's name and path. */
const recordOn = (layer, message, key) => record(layer, `${layer.name}${layer.path ? ` (${layer.path})` : ""}: ${message}`, key);

function checkPlugin(plugin) {
  if (typeof plugin !== "string" || !PLUGIN.test(plugin)) throw new Error(`config-cascade: plugin name ${JSON.stringify(plugin)} is not a plain name`);
}

/** The convention home, whether a relative one escapes projectRoot, and the [name, stem] of each file layer. */
function fileLayersOf(plugin, projectRoot, home) {
  const homeDir = resolvePath(projectRoot, home);
  const homeEscapes = !isAbsolute(home) && escapes(homeDir, projectRoot);
  const outside = homeEscapes ? homeDir : null;
  let local = [join(homeDir, `${plugin}.local`), outside];
  const main = !homeEscapes && !isAbsolute(home) && !hasLayerFile(local[0]) && mainCheckoutOfLinkedWorktree(projectRoot);
  if (main) {
    const mainHome = resolvePath(main, home);
    local = [join(mainHome, `${plugin}.local`), escapes(mainHome, main) ? mainHome : null];
  }
  const stems = [
    ["team", join(homeDir, plugin), outside],
    ["local", ...local],
  ];
  return { homeDir, homeEscapes, stems };
}

const exists = (path) => {
  const state = fileState(path);
  return Boolean(state.ok || state.refused);
};
const hasLayerFile = (stem) => exists(`${stem}.yaml`) || exists(`${stem}.md`);
const isDirectory = (path) => {
  try {
    return lstatSync(path).isDirectory();
  } catch {
    return false;
  }
};

function mainCheckoutOfLinkedWorktree(root) {
  const gitFile = join(root, ".git");
  const pointer = fileState(gitFile).ok && readText(gitFile)?.match(/^gitdir: *(.+?)\s*$/m)?.[1];
  if (!pointer) return null;
  const gitDir = resolvePath(root, pointer);
  const commonFile = join(gitDir, "commondir");
  const common = fileState(commonFile).ok && readText(commonFile)?.trim();
  if (!common) return null;
  const commonDir = resolvePath(gitDir, common);
  if (basename(commonDir) !== ".git" || !isDirectory(commonDir)) return null;
  const main = dirname(commonDir);
  return resolvePath(main) === resolvePath(root) ? null : main;
}

const escapedLayer = (name, stem, homeDir) =>
  newLayer(name, `${stem}.yaml`, "invalid", [`${name} (${homeDir}): the convention home resolves outside the project; a repository layer stays inside it`]);

/** {ok} for a readable repository layer file, {refused: why} for one that must not be read, {} when
 * absent. A symlink is refused, since it could reach a file outside the checkout, and so is anything
 * but a regular file, since a device or FIFO never finishes reading. */
export function fileState(path) {
  let st;
  try {
    st = lstatSync(path);
  } catch {
    return {};
  }
  if (st.isSymbolicLink()) return { refused: "is a symlink; a repository layer reads only regular files" };
  return st.isFile() ? { ok: true } : { refused: "is not a regular file" };
}

/** True when `dir` exists and its real path lies outside the real path of `root`. */
export function escapes(dir, root) {
  try {
    const rel = relative(realpathSync(root), realpathSync(dir));
    return rel === ".." || rel.startsWith(`..${sep}`) || isAbsolute(rel);
  } catch {
    return false;
  }
}
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
  if (typeof value === "number" && typeof node.minimum === "number" && value < node.minimum) return [`${prefix}${show(value)} must be at least ${node.minimum}`];
  if (typeof value === "number" && typeof node.maximum === "number" && value > node.maximum) return [`${prefix}${show(value)} must be at most ${node.maximum}`];
  if (Array.isArray(value) && typeof node.minItems === "number" && value.length < node.minItems) return [`${prefix}needs at least ${node.minItems} items, got ${value.length}`];
  if (Array.isArray(value) && typeof node.maxItems === "number" && value.length > node.maxItems) return [`${prefix}allows at most ${node.maxItems} items, got ${value.length}`];
  if (Array.isArray(value)) return value.flatMap((item, i) => check(item, isMapping(node.items) ? node.items : {}, `${at}[${i}]`));
  if (!isMapping(value)) return [];
  return Object.keys(value).flatMap((key) => {
    const where = `${at}.${quote(key)}`;
    if (RESERVED.has(key)) return [`${where}: a reserved name, never a config key`];
    const sub = child(node, key);
    if (sub === false) return [`${where}: unknown key`];
    return check(value[key], sub ?? {}, where);
  });
}

/** The accepted leaves of one layer's mapping, as [parts, value] pairs; rejections go to `fail`
 * with the dotted key, and `true` third when the value itself was the problem. */
function leaves(data, schema, { teamOnly, allowTeamOnly, fail }) {
  const out = [];
  const walk = (object, node, parts) => {
    for (const key of Object.keys(object)) {
      if (isWriterKey(parts, key)) continue;
      const path = [...parts, key];
      const dotted = path.join(".");
      const sub = child(node, key);
      const value = object[key];
      if (RESERVED.has(key)) fail(`${quote(dotted)}: a reserved name, never a config key`, dotted);
      else if (key.includes(".")) fail(`${quote(dotted)}: a key may not contain "."; nest it instead`, dotted);
      else if (sub === false) fail(`${quote(dotted)}: unknown key`, dotted);
      else if (teamOnly.has(dotted) && !allowTeamOnly) fail(`${quote(dotted)}: accepted only in the team layer`, dotted);
      else if (sub && isBranch(sub, dotted, teamOnly)) {
        if (isMapping(value)) walk(value, sub, path);
        else if (value !== null) fail(`${quote(dotted)}: expected a mapping, got ${show(value)}`, dotted, true);
      } else {
        const problems = check(value, sub ?? {});
        if (problems.length) fail(`${quote(dotted)}: ${problems.join("; ")}`, dotted, true);
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
      if (isWriterKey(parts, key)) continue;
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
    if (teamOnly.has(leaf.dotted)) fail(`${quote(leaf.dotted)}: accepted only in the team layer`, leaf.dotted);
    else if (types && !types.every((t) => SCALARS.includes(t))) fail(`${quote(leaf.dotted)}: lists and mappings are set only in files`, leaf.dotted);
    else {
      const value = coerce(raw, leaf.node);
      const problems = check(value, leaf.node);
      if (problems.length) fail(`${quote(leaf.dotted)}: ${problems.join("; ")}`, leaf.dotted, true);
      else out.push([leaf.path, value]);
    }
  }
  return out;
}

/** One file layer: its report entry, its parsed mapping (or null), and its prose path (or null). */
function readLayer(name, stem) {
  const path = `${stem}.yaml`;
  const md = `${stem}.md`;
  const layer = newLayer(name, path, "absent");
  const mdFile = fileState(md);
  if (mdFile.refused) {
    layer.state = "invalid";
    record(layer, `${name} (${md}): ${mdFile.refused}`);
  }
  const prose = mdFile.ok ? md : null;
  if (prose) layer.state = "loaded";
  const yamlFile = fileState(path);
  if (yamlFile.refused) {
    layer.state = "invalid";
    record(layer, `${name} (${path}): ${yamlFile.refused}`);
  }
  if (!yamlFile.ok) return { layer, data: null, prose };
  return { layer, data: parseInto(layer, () => readFileSync(path, "utf8")), prose };
}

/** The mapping `text()` parses to, loading `layer`; null, with the layer invalid, when it does not parse or is not a mapping. */
function parseInto(layer, text) {
  try {
    const doc = parse(text()) ?? {};
    if (!isMapping(doc)) throw new Error("the top level must be a mapping");
    if (layer.state !== "invalid") layer.state = "loaded";
    return doc;
  } catch (e) {
    layer.state = "invalid";
    record(layer, `${layer.name} (${layer.path}): ${e.message}`);
    return null;
  }
}

/** The body of the first ```<lang> config block outside any other fence in a Markdown text, running to
 * the end when unclosed; null when there is none. */
export function configBlockBody(text) {
  let fence = null; // the open fence's marker run, backticks or tildes
  let body = null;
  for (const line of text.split(/\r\n|\r|\n/)) {
    const run = line.match(/^(`{3,}|~{3,})/)?.[0];
    if (fence) {
      if (run?.[0] === fence[0] && run.length >= fence.length && line.trimEnd().length === run.length) {
        if (body) return body.join("\n");
        fence = null;
      } else body?.push(line);
    } else if (/^```[A-Za-z0-9_-]+ config\s*$/.test(line)) [fence, body] = ["```", []];
    else if (run) fence = run;
  }
  return body?.join("\n") ?? null;
}

/** True when the Markdown file holds a ```<lang> config block outside any other fence. */
function hasConfigBlock(path) {
  const text = fileState(path).ok ? readText(path) : null;
  return text !== null && configBlockBody(text) !== null;
}

/** A Markdown text as [{heading, text}], split at each H2 outside a code fence; the first entry holds
 * the text before the first H2 (heading null) and is dropped when empty. */
function splitSections(text) {
  const out = [{ heading: null, lines: [] }];
  let fence = null;
  for (const line of text.split(/(?<=\n)/)) {
    const run = line.match(/^ {0,3}(`{3,}|~{3,})/)?.[1];
    if (fence) {
      if (run?.[0] === fence[0] && run.length >= fence.length && line.trim().length === run.length) fence = null;
    } else if (run) fence = run;
    else {
      const h = line.match(/^## +(.*?)(?: +#+)?\s*$/);
      if (h) {
        out.push({ heading: h[1].replace(/\s+/g, " ").trim(), lines: [line] });
        continue;
      }
    }
    out.at(-1).lines.push(line);
  }
  return out.map(({ heading, lines }) => ({ heading, text: lines.join("") })).filter((s) => s.heading !== null || s.text.trim() !== "");
}

function readText(path) {
  try {
    return readFileSync(path, "utf8");
  } catch {
    return null;
  }
}

/** The team sections with each same-heading local section in its place, then the local sections the
 * team lacks. The first team section with a heading is replaced; a later team repeat of it is dropped. */
function mergeSections(teamText, localText) {
  const team = teamText === null ? [] : splitSections(teamText).map((s) => ({ ...s, layer: "team" }));
  const local = localText === null ? [] : splitSections(localText).map((s) => ({ ...s, layer: "local" }));
  const replacement = new Map(local.filter((s) => s.heading !== null).map((s) => [s.heading, s]));
  const used = new Set();
  const out = [];
  for (const s of team) {
    if (s.heading === null || !replacement.has(s.heading)) out.push(s);
    else if (!used.has(s.heading)) {
      used.add(s.heading);
      out.push(replacement.get(s.heading));
    }
  }
  const teamHeadings = new Set(team.map((s) => s.heading));
  for (const s of local) {
    const fresh = s.heading === null ? team.length === 0 : !teamHeadings.has(s.heading) && replacement.get(s.heading) === s;
    if (fresh) out.push(s);
  }
  return out;
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

/** Validated floors: dotted key to {direction, scale}. */
function normalizeFloors(floors) {
  if (!isMapping(floors)) throw new Error("config-cascade: floors must be a mapping of key path to Floor direction");
  const out = new Map();
  for (const [key, raw] of Object.entries(floors)) {
    const direction = typeof raw === "string" ? raw : raw?.direction;
    if (!DIRECTIONS.includes(direction)) throw new Error(`config-cascade: floor ${JSON.stringify(key)} has direction ${show(direction)}, not one of ${DIRECTIONS.join(", ")}`);
    out.set(key, { direction, scale: isMapping(raw) && Array.isArray(raw.scale) ? raw.scale : null });
  }
  return out;
}

function nodeAt(schema, parts) {
  let node = schema;
  for (const part of parts) {
    node = node && child(node, part);
    if (!node) return null;
  }
  return node;
}

const tightening = (v) => v === true || v === "report";

/** Why `personal` loosens `team` in the floor's direction, or null when it does not. */
function looser(floor, personal, team, node) {
  if (JSON.stringify(personal) === JSON.stringify(team)) return null;
  switch (floor.direction) {
    case "team-only":
      if (Array.isArray(personal) && Array.isArray(team) && team.every((t) => personal.some((p) => JSON.stringify(p) === JSON.stringify(t)))) return null;
      return `${show(personal)} differs from the team value ${show(team)}, and the team value wins`;
    case "lowest-value":
      if (typeof personal === "number" && typeof team === "number" && personal <= team) return null;
      return `${show(personal)} is not lower than or equal to the team value ${show(team)}`;
    case "any-layer-wins":
      if (!tightening(team) || tightening(personal)) return null;
      return `${show(personal)} drops the team value ${show(team)}, which is the tightening one`;
    case "stricter-value": {
      const scale = floor.scale ?? node?.enum ?? [];
      const a = scale.findIndex((v) => JSON.stringify(v) === JSON.stringify(personal));
      const b = scale.findIndex((v) => JSON.stringify(v) === JSON.stringify(team));
      if (a >= 0 && b >= 0 && a >= b) return null;
      return `${show(personal)} is not as strict as the team value ${show(team)} on the scale ${show(scale)}`;
    }
    default:
      return null;
  }
}

export function resolve({ plugin, projectRoot, home = "docs/conventions", schema, defaults, userConfig, teamOnly = [], floors = {}, userHome = homedir() }) {
  checkPlugin(plugin);
  const only = new Set(teamOnly);
  const floorMap = normalizeFloors(floors);
  const names = flatNames(schema, only);
  const { homeDir, homeEscapes, stems } = fileLayersOf(plugin, projectRoot, home);
  const layers = [];
  const contributions = []; // [layer name, [[parts, value]], dotted keys whose value was invalid]
  const prose = [];
  const proseText = {};

  const take = (layer, pairsOf) => {
    const invalid = new Set();
    const fail = (message, key, valueFailed = false) => {
      recordOn(layer, message, key);
      if (valueFailed) invalid.add(key);
    };
    if (pairsOf) contributions.push([layer.name, pairsOf(fail), invalid]);
    layers.push(layer);
  };
  const fileLeaves = (data, allowTeamOnly) => data && ((fail) => leaves(data, schema, { teamOnly: only, allowTeamOnly, fail }));

  const shaped = (name, given) => {
    if (given === undefined || given === null) return { layer: newLayer(name, null, "absent"), ok: false };
    if (isMapping(given)) return { layer: newLayer(name, null, "loaded"), ok: true };
    return { layer: newLayer(name, null, "invalid", [`${name}: expected a mapping, got ${show(given)}`]), ok: false };
  };
  const d = shaped("defaults", defaults);
  take(d.layer, d.ok && fileLeaves(defaults, true));
  const u = shaped("userConfig", userConfig);
  take(u.layer, u.ok && ((fail) => userConfigLeaves(userConfig, names, only, fail)));
  for (const [name, stem, outside] of stems) {
    if (outside) {
      take(escapedLayer(name, stem, outside));
      continue;
    }
    const read = readLayer(name, stem);
    take(read.layer, fileLeaves(read.data, name === "team"));
    if (read.prose) {
      prose.push(read.prose);
      proseText[name] = readText(read.prose);
    }
  }

  const merged = new Map(); // dotted -> {parts, value, from}
  let base = new Map(); // the defaults layer's entries, where an invalid higher value falls back to
  const within = (dotted, key) => dotted === key || dotted.startsWith(`${key}.`);
  for (const [name, pairs, invalid] of contributions) {
    if (name !== "local") {
      for (const key of invalid) {
        for (const dotted of [...merged.keys()]) if (within(dotted, key)) merged.delete(dotted);
        for (const [dotted, entry] of base) if (within(dotted, key)) merged.set(dotted, entry);
      }
    }
    const layer = layers.find((l) => l.name === name);
    for (const [parts, value] of pairs) {
      const dotted = parts.join(".");
      const prior = merged.get(dotted);
      const floor = floorMap.get(dotted);
      const union = parts.at(-1) === "disable" && Array.isArray(value);
      if (name === "local" && floor && floor.direction !== "no-floor" && !union && prior && [prior.from].flat().includes("team")) {
        const why = looser(floor, value, prior.value, nodeAt(schema, parts));
        if (why) {
          record(layer, `local (${layer.path}): ${quote(dotted)}: loosens the ${floor.direction} policy floor: ${why}`, dotted);
          continue;
        }
      }
      if (union) {
        const items = Array.isArray(prior?.value) ? [...prior.value] : [];
        const seen = new Set(items.map((i) => JSON.stringify(i)));
        for (const item of value) {
          const key = JSON.stringify(item);
          if (!seen.has(key)) items.push(item);
          seen.add(key);
        }
        const from = Array.isArray(prior?.from) ? prior.from : [];
        merged.set(dotted, { parts, value: items, from: value.length > 0 || !prior ? [...from, name] : from });
      } else merged.set(dotted, { parts, value, from: name });
    }
    if (name === "defaults") base = new Map(merged);
  }
  const values = {};
  const provenance = {};
  for (const [dotted, { parts, value, from }] of merged) {
    setPath(values, parts, value);
    put(provenance, dotted, from);
  }

  const legacy = legacyOf(plugin, userHome, projectRoot, !homeEscapes && `${join(homeDir, plugin)}.md`);
  const sections = mergeSections(proseText.team ?? null, proseText.local ?? null).map(({ heading, text, layer }) => ({ heading, text, layer }));
  return { values, provenance, prose, sections, layers, legacy };
}

/** The legacy locations that exist; `teamMd` (or false) is the team .md checked for a fenced config block. */
function legacyOf(plugin, userHome, projectRoot, teamMd) {
  const found = [
    ...legacyFiles(join(userHome, ".claude"), plugin, () => "claude-user"),
    ...(projectRoot ? legacyFiles(join(projectRoot, ".claude"), plugin, (n) => (n.startsWith(`${plugin}.local.`) ? "claude-local" : "claude-project")) : []),
    ...(teamMd && hasConfigBlock(teamMd) ? [{ path: teamMd, kind: "fenced-block" }] : []),
  ];
  return found.filter((entry, i) => found.findIndex((e) => e.path === entry.path) === i);
}

/**
 * Each layer's own accepted values, unmerged, for a caller that weighs the layers itself (the
 * rendered-views publish rule reads every layer separately: lib/view-settings.mjs). The same reader,
 * refusals and schema check as resolve(), with no precedence, floors or invalid-value fallback: an
 * invalid value leaves only its own layer. Layers: "userConfig", then "team" and "local" when
 * projectRoot is set. `team`, as {path, text}, replaces the working-tree team file (text null:
 * absent), for a caller reading it from a git ref.
 *   readLayers({plugin, projectRoot, home, schema, userConfig, teamOnly, team, userHome})
 *     -> {layers: [{name, path, state, errors, error_keys, values: {"a.b": value}}], legacy}
 */
export function readLayers({ plugin, projectRoot = null, home = "docs/conventions", schema, userConfig, teamOnly = [], team, userHome = homedir() }) {
  checkPlugin(plugin);
  const only = new Set(teamOnly);
  const layers = [];
  const add = (layer, pairsOf) => {
    const values = {};
    for (const [parts, value] of pairsOf ? pairsOf((message, key) => recordOn(layer, message, key)) : []) put(values, parts.join("."), value);
    layers.push({ ...layer, values });
  };
  if (isMapping(userConfig)) add(newLayer("userConfig", null, "loaded"), (fail) => userConfigLeaves(userConfig, flatNames(schema, only), only, fail));
  if (!projectRoot) return { layers, legacy: legacyOf(plugin, userHome, null, false) };
  const { homeDir, homeEscapes, stems } = fileLayersOf(plugin, projectRoot, home);
  for (const [name, stem, outside] of stems) {
    const fileLeaves = (data) => data && ((fail) => leaves(data, schema, { teamOnly: only, allowTeamOnly: name === "team", fail }));
    if (name === "team" && team) {
      const layer = newLayer(name, team.path, "absent");
      add(layer, typeof team.text === "string" && fileLeaves(parseInto(layer, () => team.text)));
    } else if (outside) {
      add(escapedLayer(name, stem, outside));
    } else {
      const read = readLayer(name, stem);
      add(read.layer, fileLeaves(read.data));
    }
  }
  return { layers, legacy: legacyOf(plugin, userHome, projectRoot, !homeEscapes && `${join(homeDir, plugin)}.md`) };
}
