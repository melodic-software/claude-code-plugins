import { strict as assert } from "node:assert";
import { existsSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

const PLUGIN = join(dirname(fileURLToPath(import.meta.url)), "..");
const REPO = join(PLUGIN, "../..");
const read = (p) => JSON.parse(readFileSync(join(PLUGIN, p), "utf8"));
const routing = read("reference/routing.json");
const schema = read("reference/routing.schema.json");
const REPO_SKILL = /^https:\/\/github\.com\/melodic-software\/claude-code-plugins\/tree\/main\/plugins\/([^/]+)\/skills\/([^/]+)$/;

/** Errors for `value` against the schema keywords routing.schema.json uses. */
function validate(s, value, at = "$") {
  const errors = [];
  const fail = (msg) => errors.push(`${at}: ${msg}`);
  if ("const" in s && value !== s.const) fail(`must be ${s.const}`);
  if (s.enum && !s.enum.includes(value)) fail(`must be one of ${s.enum.join(", ")}`);
  if (s.type === "object") {
    if (typeof value !== "object" || value === null || Array.isArray(value)) return [`${at}: must be an object`];
    for (const k of s.required ?? []) if (!(k in value)) fail(`missing ${k}`);
    for (const [k, v] of Object.entries(value)) {
      if (s.properties?.[k]) errors.push(...validate(s.properties[k], v, `${at}.${k}`));
      else if (s.additionalProperties === false) fail(`unknown key ${k}`);
    }
  }
  if (s.type === "array") {
    if (!Array.isArray(value)) return [`${at}: must be an array`];
    if (value.length < (s.minItems ?? 0)) fail(`needs at least ${s.minItems} items`);
    if (s.uniqueItems && new Set(value).size !== value.length) fail("items must be unique");
    value.forEach((v, i) => errors.push(...validate(s.items, v, `${at}[${i}]`)));
  }
  if (s.type === "string") {
    if (typeof value !== "string") return [`${at}: must be a string`];
    if (value.length < (s.minLength ?? 0)) fail("too short");
    if (s.pattern && !new RegExp(s.pattern).test(value)) fail(`must match ${s.pattern}`);
  }
  if (s.type === "integer" && (!Number.isInteger(value) || value < (s.minimum ?? -Infinity))) fail(`must be an integer >= ${s.minimum}`);
  return errors;
}

test("routing.json matches its schema", () => {
  assert.deepEqual(validate(schema, routing), []);
});

test("the schema check rejects a bad row", () => {
  const bad = structuredClone(routing);
  Object.assign(bad.rows[0], { rank: 0, account: "free", extra: true });
  const errors = validate(schema, bad).join("\n");
  assert.match(errors, /rank: must be an integer >= 1/);
  assert.match(errors, /account: must be one of/);
  assert.match(errors, /unknown key extra/);
});

const byConcern = Map.groupBy(routing.rows, (r) => r.concern);

test("ids are unique within each concern", () => {
  for (const [concern, rows] of byConcern) {
    const ids = rows.map((r) => r.id);
    assert.equal(new Set(ids).size, ids.length, `duplicate id in ${concern}`);
  }
});

test("ranks in each concern run 1..n", () => {
  for (const [concern, rows] of byConcern) {
    const ranks = rows.map((r) => r.rank).sort((a, b) => a - b);
    assert.deepEqual(ranks, rows.map((_, i) => i + 1), `ranks in ${concern}`);
  }
});

test("every repo-skill row names a skill that exists here, by its own id", () => {
  const repoRows = routing.rows.filter((r) => REPO_SKILL.test(r.pointer));
  assert.ok(repoRows.length > 0);
  for (const r of repoRows) {
    const [, plugin, skill] = r.pointer.match(REPO_SKILL);
    assert.equal(r.id, `${plugin}:${skill}`);
    assert.ok(existsSync(join(REPO, "plugins", plugin, "skills", skill, "SKILL.md")), `${r.id} not found`);
  }
});

test("this repo's skills rank ahead of third parties in each concern", () => {
  for (const [concern, rows] of byConcern) {
    const ordered = rows.toSorted((a, b) => a.rank - b.rank).map((r) => REPO_SKILL.test(r.pointer));
    assert.deepEqual(ordered, ordered.toSorted((a, b) => b - a), `order in ${concern}`);
  }
});

test("Mac-only and account-bound rows are deferred", () => {
  for (const r of routing.rows) {
    const macOnly = r.platforms.length === 1 && r.platforms[0] === "macos";
    if (macOnly || r.account !== "none") assert.equal(r.status, "deferred", `${r.concern}/${r.id}`);
  }
});
