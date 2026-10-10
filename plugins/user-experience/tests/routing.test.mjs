import { strict as assert } from "node:assert";
import { existsSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

const PLUGIN = join(dirname(fileURLToPath(import.meta.url)), "..");
const REPO = join(PLUGIN, "../..");
const read = (p) => JSON.parse(readFileSync(join(PLUGIN, p), "utf8"));
const readRepo = (p) => JSON.parse(readFileSync(join(REPO, p), "utf8"));
const routing = read("reference/routing.json");
const schema = read("reference/routing.schema.json");
const SLASH_ID = /^\/[a-z0-9-]+(:[a-z0-9-]+)?$/;
const PLUGIN_SKILL_ID = /^\/([a-z0-9-]+):([a-z0-9-]+)$/;
const JOBS = schema.properties.rows.items.properties.job.enum;
const repoSkillExists = (plugin, skill) => existsSync(join(REPO, "plugins", plugin, "skills", skill, "SKILL.md"));
/** A row for one of this marketplace's own plugin skills: a bare detect and a `/<plugin>:<skill>` id. */
const isOwn = (r) => r.kind === "skill" && !r.detect.includes("@") && PLUGIN_SKILL_ID.test(r.id);
/** True when a detect or id names a release (`name@1.2.0`, `name@v2`, `pkg-1.2`) rather than an alias. */
const pinsVersion = (s) => /\d+\.\d+|@v?\d/.test(s);

/** Errors for `value` against the schema keywords routing.schema.json uses. Object, array and string
 * keywords apply to any value of that shape, whether or not the sub-schema states `type`. */
function validate(s, value, at = "$") {
  const errors = [];
  const fail = (msg) => errors.push(`${at}: ${msg}`);
  const isObject = typeof value === "object" && value !== null && !Array.isArray(value);
  if ("const" in s && value !== s.const) fail(`must be ${s.const}`);
  if (s.enum && !s.enum.includes(value)) fail(`must be one of ${s.enum.join(", ")}`);
  if (s.type === "object" && !isObject) return [`${at}: must be an object`];
  if (s.type === "array" && !Array.isArray(value)) return [`${at}: must be an array`];
  if (s.type === "string" && typeof value !== "string") return [`${at}: must be a string`];
  if (isObject) {
    for (const k of s.required ?? []) if (!(k in value)) fail(`missing ${k}`);
    for (const [k, v] of Object.entries(value)) {
      if (s.properties?.[k]) errors.push(...validate(s.properties[k], v, `${at}.${k}`));
      else if (s.additionalProperties === false) fail(`unknown key ${k}`);
    }
  }
  if (Array.isArray(value)) {
    if (value.length < (s.minItems ?? 0)) fail(`needs at least ${s.minItems} items`);
    if (s.uniqueItems && new Set(value).size !== value.length) fail("items must be unique");
    if (s.items) value.forEach((v, i) => errors.push(...validate(s.items, v, `${at}[${i}]`)));
  }
  if (typeof value === "string") {
    if (value.length < (s.minLength ?? 0)) fail("too short");
    if (s.pattern && !new RegExp(s.pattern).test(value)) fail(`must match ${s.pattern}`);
  }
  if (s.type === "integer" && (!Number.isInteger(value) || value < (s.minimum ?? -Infinity))) fail(`must be an integer >= ${s.minimum}`);
  for (const sub of s.allOf ?? []) errors.push(...validate(sub, value, at));
  if (s.if) {
    const branch = validate(s.if, value, at).length === 0 ? s.then : s.else;
    if (branch) errors.push(...validate(branch, value, at));
  }
  if (s.not && validate(s.not, value, at).length === 0) fail("must not match a forbidden shape");
  return errors;
}

/** Schema errors for routing.json holding one row: fixed shared fields plus `fields`. */
function rowErrors(fields) {
  const shared = { job: "synthesis", rank: 1, account: "none", status: "unconfirmed", as_of: "2026-10-09" };
  return validate(schema, { ...routing, rows: [{ ...shared, ...fields }] });
}
const EXTERNAL = { kind: "skill", id: "/field-notes:affinity", detect: "field-notes@fixture-market" };
const CITED = { pointer: "https://example.com/field-notes", recheck: "the field-notes README changes" };

test("the validator handles allOf, if/then/else and not", () => {
  const s = {
    type: "object",
    allOf: [
      { if: { required: ["k"], properties: { k: { const: "a" } } }, then: { required: ["x"] }, else: { not: { required: ["x"] } } },
      { properties: { y: { pattern: "^z", minLength: 2 } } },
    ],
  };
  assert.deepEqual(validate(s, { k: "a", x: 1 }), []);
  assert.deepEqual(validate(s, { k: "a" }), ["$: missing x"]);
  assert.deepEqual(validate(s, { k: "b" }), []);
  assert.deepEqual(validate(s, { k: "b", x: 1 }), ["$: must not match a forbidden shape"]);
  assert.deepEqual(validate(s, { x: 1 }), ["$: must not match a forbidden shape"], "a missing key fails the if");
  assert.deepEqual(validate(s, { y: "q" }), ["$.y: too short", "$.y: must match ^z"]);
  assert.deepEqual(validate(s, { y: "zz" }), []);
});

test("routing.json matches its schema", () => {
  assert.deepEqual(validate(schema, routing), []);
});

test("the schema check rejects a bad row", () => {
  const bad = structuredClone(routing);
  Object.assign(bad.rows[0], { rank: 0, account: "free", job: "visual-direction", extra: true });
  const errors = validate(schema, bad).join("\n");
  assert.match(errors, /rank: must be an integer >= 1/);
  assert.match(errors, /account: must be one of/);
  assert.match(errors, /job: must be one of/);
  assert.match(errors, /unknown key extra/);
});

test("the schema rejects an as_of that is not YYYY-MM-DD", () => {
  assert.deepEqual(rowErrors({ ...EXTERNAL, ...CITED }), []);
  for (const as_of of ["2026-10-9", "10/09/2026", "2026-10-09T00:00"]) {
    assert.match(rowErrors({ ...EXTERNAL, ...CITED, as_of }).join("\n"), /as_of: must match/, as_of);
  }
});

test("every job has at least one route row", () => {
  const routed = new Set(routing.rows.map((r) => r.job));
  assert.deepEqual(JOBS.filter((j) => !routed.has(j)), []);
});

test("kind: skill ids are slash invocations", () => {
  const skills = routing.rows.filter((r) => r.kind === "skill");
  assert.ok(skills.length > 0);
  for (const r of skills) assert.match(r.id, SLASH_ID, `${r.job}/${r.id}`);
});

test("the schema rejects a skill id without a slash", () => {
  assert.deepEqual(rowErrors({ ...EXTERNAL, ...CITED }), []);
  assert.match(rowErrors({ ...EXTERNAL, ...CITED, id: "field-notes:affinity" }).join("\n"), /\.id: must match/);
});

test("the schema rejects a pointer on an own-skill row", () => {
  const own = { kind: "skill", id: "/field-notes:affinity", detect: "field-notes" };
  assert.deepEqual(rowErrors(own), []);
  assert.notDeepEqual(rowErrors({ ...own, pointer: "https://example.com/field-notes" }), []);
});

test("the schema rejects an external row with no pointer or no recheck trigger", () => {
  for (const row of [
    EXTERNAL,
    { kind: "skill", id: "/affinity", detect: "affinity" },
    { kind: "plugin", id: "field-notes@fixture-market", detect: "field-notes@fixture-market" },
    { kind: "mcp", id: "field-notes", detect: "field-notes" },
  ]) {
    assert.match(rowErrors({ ...row, recheck: CITED.recheck }).join("\n"), /missing pointer/, row.id);
    assert.match(rowErrors({ ...row, pointer: CITED.pointer }).join("\n"), /missing recheck/, row.id);
    assert.deepEqual(rowErrors({ ...row, ...CITED }), [], row.id);
  }
});

test("only id, detect and pointer route-row fields carry @", () => {
  const fields = routing.rows.flatMap((r) => Object.entries(r).map(([k, v]) => [`${r.job}/${r.id} ${k}`, k, JSON.stringify(v)]));
  assert.ok(fields.length > 0);
  assert.deepEqual(fields.filter(([, k, v]) => !["id", "detect", "pointer"].includes(k) && v.includes("@")).map(([at]) => at), []);
});

const byJob = Map.groupBy(routing.rows, (r) => r.job);

test("ids are unique within each job", () => {
  for (const [job, rows] of byJob) {
    const ids = rows.map((r) => r.id);
    assert.equal(new Set(ids).size, ids.length, `duplicate id in ${job}`);
  }
});

test("ranks in each job run 1..n", () => {
  for (const [job, rows] of byJob) {
    const ranks = rows.map((r) => r.rank).sort((a, b) => a - b);
    assert.deepEqual(ranks, rows.map((_, i) => i + 1), `ranks in ${job}`);
  }
});

test("own rows have a bare detect, no pointer, a repo skill and matching entry and manifest names", () => {
  const ownRows = routing.rows.filter(isOwn);
  assert.ok(ownRows.length > 0);
  const entries = readRepo(".claude-plugin/marketplace.json").plugins;
  for (const r of ownRows) {
    const [, plugin, skill] = r.id.match(PLUGIN_SKILL_ID);
    assert.equal(r.detect, plugin, r.id);
    assert.ok(!("pointer" in r), `${r.id} has a pointer`);
    assert.ok(repoSkillExists(plugin, skill), `${r.id} not found`);
    const manifest = readRepo(`plugins/${plugin}/.claude-plugin/plugin.json`);
    assert.equal(manifest.name, plugin, `${r.id} manifest name`);
    assert.equal(entries.find((e) => e.source === `./plugins/${plugin}`)?.name, manifest.name, `${r.id} marketplace entry name`);
  }
});

test("colon-id rows for repo skills have a bare detect", () => {
  const repoRows = routing.rows.filter((r) => {
    const m = r.kind === "skill" && r.id.match(/^\/?([a-z0-9-]+):([a-z0-9-]+)$/);
    return m && repoSkillExists(m[1], m[2]);
  });
  assert.ok(repoRows.length > 0);
  for (const r of repoRows) assert.ok(!r.detect.includes("@"), `${r.job}/${r.id} detect ${r.detect}`);
});

test("a /plugin:skill row detects the plugin its id names", () => {
  const rows = routing.rows.filter((r) => r.kind === "skill" && PLUGIN_SKILL_ID.test(r.id));
  assert.ok(rows.some((r) => r.detect.includes("@")), "no third-party /plugin:skill row to check");
  for (const r of rows) {
    const [, plugin] = r.id.match(PLUGIN_SKILL_ID);
    assert.equal(r.detect.split("@")[0], plugin, `${r.job}/${r.id} detect ${r.detect}`);
  }
});

test("a kind: plugin row detects itself", () => {
  const rows = routing.rows.filter((r) => r.kind === "plugin");
  assert.ok(rows.length > 0);
  for (const r of rows) assert.equal(r.detect, r.id, `${r.job}/${r.id}`);
});

test("this repo's skills rank ahead of third parties in each job", () => {
  for (const [job, rows] of byJob) {
    const ordered = rows.toSorted((a, b) => a.rank - b.rank).map(isOwn);
    assert.deepEqual(ordered, ordered.toSorted((a, b) => b - a), `order in ${job}`);
  }
});

test("account-bound rows are never unconfirmed", () => {
  const bound = routing.rows.filter((r) => r.account !== "none");
  assert.ok(bound.length > 0);
  for (const r of bound) assert.notEqual(r.status, "unconfirmed", `${r.job}/${r.id}`);
});

test("the pinned-version check tells a release from an alias", () => {
  for (const pinned of ["design@1.2.0", "design@knowledge-work-plugins@1.2.0", "dovetail@v0.3", "@mixpanel/mcp@2"]) assert.ok(pinsVersion(pinned), pinned);
  for (const alias of ["design@knowledge-work-plugins", "/design:user-research", "mixpanel", "figma@claude-plugins-official"]) assert.ok(!pinsVersion(alias), alias);
});

test("no row detects or names a pinned version", () => {
  assert.deepEqual(routing.rows.filter((r) => pinsVersion(r.detect) || pinsVersion(r.id)).map((r) => `${r.job}/${r.id}`), []);
});
