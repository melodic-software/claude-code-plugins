#!/usr/bin/env node
// Prints codify's settings and the layer that set each, resolved through the config cascade
// (lib/config-cascade.mjs, ADR 0075): the schema default, the user option (two of the keys), the team
// file <home>/corrections.yaml and the personal overlay <home>/corrections.local.yaml, <home> from the
// convention-home pointer line.
//   {"min_occurrences": N, "layer": "defaults" | "team" | "local", "path": file relative to the project | null,
//    "ratchet_offer": {"value", "layer", "path"}, "review_mining_prs": {"value", "layer", "path"}}
// Both of the last two take "userConfig" as a layer too. --user-ratchet-offer and
// --user-review-mining-prs pass the options the skill body renders; an empty value, an unrendered
// placeholder or the default is unset.
// A value the schema refuses is named on stderr (the first five per layer, then a count of the rest)
// and dropped: an invalid team value falls to the
// default, never to a lower layer, an invalid personal value leaves the team value standing. A declined, not-applicable or
// broken pointer line leaves both files unread, said on stderr.
// Usage: codify-settings.mjs [--project DIR] [--user-ratchet-offer V] [--user-review-mining-prs V]
// (--project defaults to the git root of the current directory)
import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, relative, resolve as resolvePath } from "node:path";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";
import { resolve } from "./lib/config-cascade.mjs";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const PLUGIN = "corrections";
const KEY = "recurrence.min_occurrences";
const DEFAULT_HOME = "docs/conventions";
const SHOWN = 5;

const say = (text) => process.stderr.write(`codify-settings: ${text}\n`);

/** Each layer's first SHOWN errors on stderr, then a count of the rest, so a file of unknown keys cannot flood it. */
function sayErrors(layers) {
  for (const { name, path, errors } of layers) {
    for (const error of errors.slice(0, SHOWN)) say(error);
    if (errors.length > SHOWN) say(`${name}${path ? ` (${path})` : ""}: and ${errors.length - SHOWN} more`);
  }
}

function gitRoot(dir) {
  const r = spawnSync("git", ["-C", dir, "rev-parse", "--show-toplevel"], { cwd: ROOT, encoding: "utf8" });
  return r.status === 0 ? r.stdout.trim() : dir;
}

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

let opts;
try {
  ({ values: opts } = parseArgs({
    options: { project: { type: "string" }, "user-ratchet-offer": { type: "string" }, "user-review-mining-prs": { type: "string" } },
  }));
} catch {
  say("usage: codify-settings.mjs [--project DIR] [--user-ratchet-offer V] [--user-review-mining-prs V]");
  process.exit(2);
}
const project = resolvePath(opts.project ?? gitRoot(process.cwd()));
const schema = JSON.parse(readFileSync(join(ROOT, "schemas/corrections.schema.json"), "utf8"));
const fallback = schema.properties.recurrence.properties.min_occurrences.default;
const defaults = {
  recurrence: { min_occurrences: fallback },
  ratchet_offer: schema.properties.ratchet_offer.default,
  review_mining_prs: schema.properties.review_mining_prs.default,
};
// An option left alone renders its default, so a value equal to the default reads as unset.
const option = (given, key) => (given === String(defaults[key]) ? undefined : given);
const userConfig = {
  ratchet_offer: option(opts["user-ratchet-offer"], "ratchet_offer"),
  review_mining_prs: option(opts["user-review-mining-prs"], "review_mining_prs"),
};

const { home, why } = conventionHome(project);
// The scratch directory stands in for the user home (only legacy files are looked up there) and,
// with no usable convention home, for the home itself, so neither repository layer is read.
const scratch = mkdtempSync(join(tmpdir(), "codify-settings-"));
let out;
try {
  if (home === null) say(`${why}, so no settings file is read`);
  out = resolve({ plugin: PLUGIN, projectRoot: project, home: home ?? scratch, schema, defaults, userConfig, userHome: scratch });
} finally {
  rmSync(scratch, { recursive: true, force: true });
}
sayErrors(out.layers);
/** The layer that set a key and that layer's file relative to the project, or null. */
function source(key) {
  const layer = out.provenance[key] ?? "defaults";
  const file = out.layers.find((l) => l.name === layer)?.path;
  return { layer, path: file ? relative(project, file) : null };
}
console.log(
  JSON.stringify({
    min_occurrences: out.values.recurrence?.min_occurrences ?? fallback,
    ...source(KEY),
    ratchet_offer: { value: out.values.ratchet_offer, ...source("ratchet_offer") },
    review_mining_prs: { value: out.values.review_mining_prs, ...source("review_mining_prs") },
  }),
);
