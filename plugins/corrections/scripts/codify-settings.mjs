#!/usr/bin/env node
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
const option = (given, key) => (given === String(defaults[key]) ? undefined : given);
const userConfig = {
  ratchet_offer: option(opts["user-ratchet-offer"], "ratchet_offer"),
  review_mining_prs: option(opts["user-review-mining-prs"], "review_mining_prs"),
};

const { home, why } = conventionHome(project);
const scratch = mkdtempSync(join(tmpdir(), "codify-settings-"));
let out;
try {
  if (home === null) say(`${why}, so no settings file is read`);
  out = resolve({ plugin: PLUGIN, projectRoot: project, home: home ?? scratch, schema, defaults, userConfig, userHome: scratch });
} finally {
  rmSync(scratch, { recursive: true, force: true });
}
sayErrors(out.layers);
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
