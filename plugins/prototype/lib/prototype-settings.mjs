#!/usr/bin/env node
// The prototype plugin's settings, resolved through the config cascade (lib/config-cascade.mjs,
// ADR 0075): the shipped default (reference/levels.default.yaml and the schema's `level` default),
// the userConfig option, the team file <home>/prototype.yaml and the personal override
// <home>/prototype.local.yaml, <home> from the convention-home pointer line. Keys and their meaning:
// reference/config.md; schema: schemas/prototype.schema.json.
//
// `level` is checked against the names of the resolved `levels` map, not a fixed list, so a team
// file can add a level. Two passes through the cascade do that: the first resolves `levels`, the
// second resolves `level` with the schema's `enum` set to the complete levels' names, so the
// cascade's own invalid-value rule applies (an invalid value drops its layer; a valid higher layer
// still wins, else the default; an invalid personal value leaves the team value standing). A level
// is complete when it sets every required dimension and its name fits NAME. Above the files, a
// `--argument` (the reader's --level) beats a `--prompt` (a level the request names); either is
// ignored, with a notice, when it names no complete level.
//
//   prototype-settings.mjs resolve --option <user_config.level> [--prompt <name>] [--argument <name>] [--project DIR]
// Prints one JSON line {level, layer, path, definition, phrases, notices}, then the report line
// `level: <name> (<layer>)`, then one `notice: ` line per notice. Exit 0 resolved, 2 usage.

import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, isAbsolute, join, relative, resolve as resolvePath } from "node:path";
import { fileURLToPath } from "node:url";
import { resolve as cascade } from "./config-cascade.mjs";
import { parse } from "./yaml-subset.mjs";

const PLUGIN = "prototype";
const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const DEFAULT_HOME = "docs/conventions";
const NAME = /^[a-z][a-z0-9-]{0,31}$/;
const REQUIRED = ["variants", "screens", "states", "evidence"];
const LISTS = ["extra_states", "offers", "phrases"];
const LAYER = { defaults: "default", userConfig: "userConfig", team: "team", local: "personal" };

/** The schema with each local `#/$defs/<name>` reference replaced by its definition: the cascade's schema subset has no `$ref`. */
export function loadSchema(path = join(ROOT, "schemas/prototype.schema.json")) {
  const schema = JSON.parse(readFileSync(path, "utf8"));
  const inline = (node) => {
    if (Array.isArray(node)) return node.map(inline);
    if (node === null || typeof node !== "object") return node;
    const ref = typeof node.$ref === "string" && /^#\/\$defs\/([^/]+)$/.exec(node.$ref);
    if (ref) return inline(schema.$defs[ref[1]]);
    return Object.fromEntries(Object.entries(node).filter(([k]) => k !== "$defs").map(([k, v]) => [k, inline(v)]));
  };
  return inline(schema);
}

/** The default layer: the schema's `level` default and the shipped levels. */
export function loadDefaults(schema, path = join(ROOT, "reference/levels.default.yaml")) {
  return { level: schema.properties.level.default, levels: parse(readFileSync(path, "utf8")).levels };
}

const errorsOf = (out, keep) =>
  out.layers.flatMap(({ errors, error_keys }) => errors.filter((_, i) => keep(error_keys[i] ?? null)));

/**
 * @param {{projectRoot: string, home: string|null, userConfig?: string|null, prompt?: string|null, argument?: string|null}} request
 *   `home` null reads neither file layer.
 */
export function resolveLevel({ projectRoot, home, userConfig = null, prompt = null, argument = null }, { schema = loadSchema(), defaults = loadDefaults(schema) } = {}) {
  // The scratch directory stands in for the user home (only legacy files are looked up there) and,
  // with no usable convention home, for the home itself, so neither file layer is read.
  const scratch = mkdtempSync(join(tmpdir(), "prototype-settings-"));
  try {
    const run = (s) => cascade({ plugin: PLUGIN, projectRoot, home: home ?? scratch, schema: s, defaults, userConfig: { level: userConfig ?? "" }, userHome: scratch });
    const first = run(schema);
    const notices = errorsOf(first, (key) => key !== "level");
    const complete = {};
    for (const [name, raw] of Object.entries(first.values.levels ?? {})) {
      const missing = REQUIRED.filter((d) => raw?.[d] === undefined);
      if (!NAME.test(name)) notices.push(`level ${JSON.stringify(name)}: a level name is lowercase letters, digits and hyphens, at most 32; not a level`);
      else if (missing.length) notices.push(`level ${name}: sets no ${missing.join(", ")}; not a level`);
      else complete[name] = { ...Object.fromEntries(LISTS.map((d) => [d, []])), ...raw };
    }
    const names = Object.keys(complete);
    const second = run({ ...schema, properties: { ...schema.properties, level: { ...schema.properties.level, enum: names } } });
    notices.push(...errorsOf(second, (key) => key === "level"));

    let level = second.values.level;
    let layer = LAYER[second.provenance.level ?? "defaults"];
    let path = second.layers.find((l) => l.name === (second.provenance.level ?? "defaults"))?.path ?? null;
    if (!Object.hasOwn(complete, level)) {
      notices.push(`the default level ${JSON.stringify(level)} is not a complete level; standard is used`);
      [level, layer, path] = ["standard", "default", null];
    }
    for (const [given, from] of [
      [prompt, "prompt"],
      [argument, "argument"],
    ]) {
      if (given === null || given === undefined || given === "") continue;
      if (Object.hasOwn(complete, given)) [level, layer, path] = [given, from, null];
      else notices.push(`${from} level ${JSON.stringify(given)} is not one of ${names.join(", ")}; ignored`);
    }
    const shown = path && isAbsolute(path) ? relative(projectRoot, path).split("\\").join("/") : path;
    const phrases = Object.fromEntries(names.map((n) => [n, complete[n].phrases]));
    return { level, layer, path: shown, definition: complete[level], phrases, notices };
  } finally {
    rmSync(scratch, { recursive: true, force: true });
  }
}

export const reportLine = ({ level, layer }) => `level: ${level} (${layer})`;

/** {home} or {home: null, why} from the project's pointer line, as lib/resolve-convention-home.sh reports it. */
function conventionHome(project) {
  const r = spawnSync("bash", [join(ROOT, "lib/resolve-convention-home.sh"), "--root", project], { cwd: ROOT, encoding: "utf8", timeout: 15_000 });
  if (r.status === 0) return { home: r.stdout.trim() };
  if (r.status === 1) return { home: DEFAULT_HOME };
  if (r.status === 4) return { home: null, why: "the repository declined a convention home" };
  if (r.status === 5) return { home: null, why: "no convention home applies to this project" };
  const cause = r.error?.code || r.stderr?.trim().split("\n").at(-1) || `exit ${r.status}`;
  return { home: null, why: `the convention home is unresolved (${cause})` };
}

function gitRoot(dir) {
  const r = spawnSync("git", ["-C", dir, "rev-parse", "--show-toplevel"], { encoding: "utf8" });
  return r.status === 0 ? r.stdout.trim() : dir;
}

const USAGE = "usage: prototype-settings.mjs resolve --option <user_config.level> [--prompt <name>] [--argument <name>] [--project DIR]\n";

/** CLI: the argument vector after the script path; returns the exit code. */
export function main(argv) {
  const [action, ...rest] = argv;
  const flags = { "--option": "userConfig", "--prompt": "prompt", "--argument": "argument", "--project": "project" };
  const request = {};
  for (let i = 0; i < rest.length; i += 2) {
    const key = flags[rest[i]];
    if (!key || rest[i + 1] === undefined || Object.hasOwn(request, key)) return usage();
    request[key] = rest[i + 1];
  }
  if (action !== "resolve" || request.userConfig === undefined) return usage();
  const projectRoot = resolvePath(request.project ?? gitRoot(process.cwd()));
  const { home, why } = conventionHome(projectRoot);
  const resolution = resolveLevel({ projectRoot, home, userConfig: request.userConfig, prompt: request.prompt, argument: request.argument });
  if (home === null) resolution.notices.unshift(`${why}, so no settings file is read`);
  const notices = resolution.notices.map((n) => `notice: ${n}`);
  process.stdout.write(`${JSON.stringify(resolution)}\n${[reportLine(resolution), ...notices].join("\n")}\n`);
  return 0;
}

function usage() {
  process.stderr.write(USAGE);
  return 2;
}

if (process.argv[1] && resolvePath(process.argv[1]) === fileURLToPath(import.meta.url)) {
  process.exitCode = main(process.argv.slice(2));
}
