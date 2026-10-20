// The four-layer plugin config cascade (docs/adr/0075): later layers win per key.
//
//   resolve({plugin, projectRoot, home, schema, defaults, userConfig, teamOnly, floors, userHome})
//     -> {values, provenance: {"a.b": layer | [layers]}, prose: [paths], sections: [{heading, text, layer}],
//         layers: [{name, path, state: "loaded" | "absent" | "invalid", errors}], legacy: [{path, kind}]}
//
// Layers, in order: "defaults" (the `defaults` object, already parsed by the caller), "userConfig"
// (the plugin's userConfig values, flattened names), "team" (<home>/<plugin>) and "local", the
// personal overlay (<home>/<plugin>.local). A file layer reads <stem>.yaml for config and <stem>.md
// for prose; it is absent when neither file exists. `home` is the convention home the caller
// resolved, relative to projectRoot unless absolute (default docs/conventions). There is no
// user-global file layer: a file under <userHome>/docs/conventions is never read, and `userHome`
// (default os.homedir()) only locates the legacy files reported in `legacy`. `schema` is a JSON
// Schema object; the subset honored is type (object, string, array, null, integer, number, boolean),
// enum, properties, additionalProperties (false or a schema), items, minimum, minItems and maxItems.
//
// A key is a schema leaf: any node that is not an object with `properties`, or a path named in
// `teamOnly`. Each layer's leaves are checked one by one; a leaf whose value fails the schema is
// dropped from that layer with an error naming layer, file and key, and a lower layer's value is
// then never used (ADR 0075, the invalid-value rule): a valid higher layer still wins, otherwise the
// key takes its default. The personal overlay is the one exception, because it refines the team
// file: an invalid personal value leaves the team value standing. A key containing `.` is
// rejected the same way, since keys are joined with `.` into paths, and so are `__proto__`,
// `constructor` and `prototype`, at any depth inside a value too, which a caller's merge would treat
// as more than data. A refused file makes its layer invalid; the layer's other file still applies. The team and
// local layers come from the repository: each reads only regular files, never a symlink, and is
// invalid when a relative `home` resolves outside projectRoot. A team-only key is
// accepted in "defaults" and "team" and rejected elsewhere. A YAML file that does not parse, or
// whose top level is not a mapping, makes its layer invalid and contributes no values; its .md
// file still supplies prose. A leaf whose last segment is `disable` and whose value is a list is the
// union of every layer's list, and its provenance is an array of the layer names that set it, in
// layer order; every other key's provenance is a single layer-name string.
//
// Policy floors. `floors` maps a key path to a `Floor direction` value (the Implementers table of
// docs/conventions/config-cascade/README.md; the closed set is no-floor, team-only, lowest-value,
// any-layer-wins and stricter-value), or to {direction, scale} where stricter-value takes a scale
// from loosest to strictest (default: the leaf's schema `enum` order). When the team layer set a
// floor key, a personal value is accepted only if it is no looser in that direction: team-only takes
// an equal value (a list must keep every team item); lowest-value a number no higher; any-layer-wins
// a tightening value (`true` or "report") whenever the team value is one; stricter-value a value at
// or beyond the team value on the scale. A looser value is dropped with an error naming the layer,
// file and key, and the team value stands. Floors bind the personal overlay; a `*.disable` union key
// is not compared.
//
// userConfig maps each schema leaf path to its name joined with `_` (widget.limit is widget_limit);
// two leaves with one name throw. An empty string or an unrendered `${user_config.` placeholder is
// unset, names outside the schema are ignored, and a list, mapping or team-only key is rejected.
// A string value takes the leaf's integer, number or boolean type when the leaf does not accept
// strings. Legacy locations (.claude/<plugin>.* under userHome and projectRoot, and a fenced
// `yaml config` block in the team .md) are reported in `legacy`, never read for values.
//
// Prose. A `.local.md` H2 section (a `## ` heading outside a code fence) replaces the team `.md`
// section with the same heading; every other team section is kept, a local section with a new
// heading follows them, and the team text before the first H2 is kept. `sections` lists the result in
// order, each with the layer it came from (`heading` is null for text before the first H2).
// This module reads files only. File contents are data; error messages quote them as JSON strings.
import { lstatSync, readdirSync, readFileSync, realpathSync, statSync } from "node:fs";
import { homedir } from "node:os";
import { isAbsolute, join, relative, resolve as resolvePath, sep } from "node:path";
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

/** {ok} for a readable layer file, {refused: why} for one that must not be read, {} when absent. A
 * repository layer refuses a symlink, which could reach a file outside the checkout; every layer
 * refuses anything but a regular file, since a device or FIFO never finishes reading. */
function fileState(path, repo) {
  let st;
  try {
    st = lstatSync(path);
  } catch {
    return {};
  }
  if (st.isSymbolicLink()) {
    if (repo) return { refused: "is a symlink; a repository layer reads only regular files" };
    try {
      st = statSync(path);
    } catch {
      return {};
    }
  }
  return st.isFile() ? { ok: true } : { refused: "is not a regular file" };
}

/** True when `dir` exists and its real path lies outside the real path of `root`. */
function escapes(dir, root) {
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
  if (Array.isArray(value) && typeof node.minItems === "number" && value.length < node.minItems) return [`${prefix}needs at least ${node.minItems} items, got ${value.length}`];
  if (Array.isArray(value) && typeof node.maxItems === "number" && value.length > node.maxItems) return [`${prefix}allows at most ${node.maxItems} items, got ${value.length}`];
  // An open node ({}) checks nothing but reserved names, which are refused at every depth.
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

/** The accepted leaves of one layer's mapping, as [parts, value] pairs; rejections go to `fail`,
 * which gets the dotted key as a second argument when the value itself was the problem. */
function leaves(data, schema, { teamOnly, allowTeamOnly, fail }) {
  const out = [];
  const walk = (object, node, parts) => {
    for (const key of Object.keys(object)) {
      const path = [...parts, key];
      const dotted = path.join(".");
      const sub = child(node, key);
      const value = object[key];
      if (RESERVED.has(key)) fail(`${quote(dotted)}: a reserved name, never a config key`);
      else if (key.includes(".")) fail(`${quote(dotted)}: a key may not contain "."; nest it instead`);
      else if (sub === false) fail(`${quote(dotted)}: unknown key`);
      else if (teamOnly.has(dotted) && !allowTeamOnly) fail(`${quote(dotted)}: accepted only in the team layer`);
      else if (sub && isBranch(sub, dotted, teamOnly)) {
        if (isMapping(value)) walk(value, sub, path);
        else if (value !== null) fail(`${quote(dotted)}: expected a mapping, got ${show(value)}`, dotted);
      } else {
        const problems = check(value, sub ?? {});
        if (problems.length) fail(`${quote(dotted)}: ${problems.join("; ")}`, dotted);
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
      if (problems.length) fail(`${quote(leaf.dotted)}: ${problems.join("; ")}`, leaf.dotted);
      else out.push([leaf.path, value]);
    }
  }
  return out;
}

/** One file layer: its report entry, its parsed mapping (or null), and its prose path (or null). */
function readLayer(name, stem, repo) {
  const path = `${stem}.yaml`;
  const md = `${stem}.md`;
  const layer = { name, path, state: "absent", errors: [] };
  const mdFile = fileState(md, repo);
  if (mdFile.refused) {
    layer.state = "invalid";
    layer.errors.push(`${name} (${md}): ${mdFile.refused}`);
  }
  const prose = mdFile.ok ? md : null;
  if (prose) layer.state = "loaded";
  const yamlFile = fileState(path, repo);
  if (yamlFile.refused) {
    layer.state = "invalid";
    layer.errors.push(`${name} (${path}): ${yamlFile.refused}`);
  }
  if (!yamlFile.ok) return { layer, data: null, prose };
  try {
    const doc = parse(readFileSync(path, "utf8")) ?? {};
    if (!isMapping(doc)) throw new Error("the top level must be a mapping");
    if (layer.state !== "invalid") layer.state = "loaded";
    return { layer, data: doc, prose };
  } catch (e) {
    layer.state = "invalid";
    layer.errors.push(`${name} (${path}): ${e.message}`);
    return { layer, data: null, prose };
  }
}

/** True when the Markdown file holds a ```<lang> config block outside any other fence. */
function hasConfigBlock(path) {
  if (!fileState(path, true).ok) return false;
  let text;
  try {
    text = readFileSync(path, "utf8");
  } catch {
    return false;
  }
  let fence = null; // the open fence's marker run, backticks or tildes
  for (const line of text.split(/\r\n|\r|\n/)) {
    const run = line.match(/^(`{3,}|~{3,})/)?.[0];
    if (fence) {
      if (run?.[0] === fence[0] && run.length >= fence.length && line.trimEnd().length === run.length) fence = null;
    } else if (/^```[A-Za-z0-9_-]+ config\s*$/.test(line)) return true;
    else if (run) fence = run;
  }
  return false;
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
    // Text before the first H2 follows the team's own only when the team has no file; a repeated heading keeps its last section.
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
  if (typeof plugin !== "string" || !PLUGIN.test(plugin)) throw new Error(`config-cascade: plugin name ${JSON.stringify(plugin)} is not a plain name`);
  const only = new Set(teamOnly);
  const floorMap = normalizeFloors(floors);
  const names = flatNames(schema, only);
  const homeDir = resolvePath(projectRoot, home);
  // A relative home is inside the checkout by intent; a committed symlink must not carry it out.
  const homeEscapes = !isAbsolute(home) && escapes(homeDir, projectRoot);
  const layers = [];
  const contributions = []; // [layer name, [[parts, value]], dotted keys whose value was invalid]
  const prose = [];
  const proseText = {};

  // pairsOf(fail) returns the layer's accepted [parts, value] pairs; falsy when it contributes none.
  const take = (layer, pairsOf) => {
    const invalid = new Set();
    const fail = (message, key) => {
      layer.errors.push(`${layer.name}${layer.path ? ` (${layer.path})` : ""}: ${message}`);
      if (key !== undefined) invalid.add(key);
    };
    if (pairsOf) contributions.push([layer.name, pairsOf(fail), invalid]);
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
    ["team", join(homeDir, plugin)],
    ["local", join(homeDir, `${plugin}.local`)],
  ]) {
    if (homeEscapes) {
      const why = "the convention home resolves outside the project; a repository layer stays inside it";
      take({ name, path: `${stem}.yaml`, state: "invalid", errors: [`${name} (${homeDir}): ${why}`] });
      continue;
    }
    const read = readLayer(name, stem, true);
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
    // A lower layer's value is never used for an invalid one; the personal overlay refines the team file, so its keys fall to team.
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
          layer.errors.push(`local (${layer.path}): ${quote(dotted)}: loosens the ${floor.direction} policy floor: ${why}`);
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
        // An empty list adds nothing, so its layer is credited only when no layer set the key before.
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

  const teamMd = `${join(homeDir, plugin)}.md`;
  const found = [
    ...legacyFiles(join(userHome, ".claude"), plugin, () => "claude-user"),
    ...legacyFiles(join(projectRoot, ".claude"), plugin, (n) => (n.startsWith(`${plugin}.local.`) ? "claude-local" : "claude-project")),
    ...(!homeEscapes && hasConfigBlock(teamMd) ? [{ path: teamMd, kind: "fenced-block" }] : []),
  ];
  // The project root may be the user home, so a file is reported under its first kind only.
  const legacy = found.filter((entry, i) => found.findIndex((e) => e.path === entry.path) === i);
  const sections = mergeSections(proseText.team ?? null, proseText.local ?? null).map(({ heading, text, layer }) => ({ heading, text, layer }));
  return { values, provenance, prose, sections, layers, legacy };
}
