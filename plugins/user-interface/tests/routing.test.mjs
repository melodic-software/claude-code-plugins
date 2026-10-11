import { strict as assert } from "node:assert";
import { existsSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { validate } from "../scripts/lib/routing-validate.mjs";

const PLUGIN = join(dirname(fileURLToPath(import.meta.url)), "..");
const REPO = join(PLUGIN, "../..");
const read = (p) => JSON.parse(readFileSync(join(PLUGIN, p), "utf8"));
const readRepo = (p) => JSON.parse(readFileSync(join(REPO, p), "utf8"));
const routing = read("reference/routing.json");
const schema = read("reference/routing.schema.json");
const SLASH_ID = /^\/[a-z0-9-]+(:[a-z0-9-]+)?$/;
const PLUGIN_SKILL_ID = /^\/([a-z0-9-]+):([a-z0-9-]+)$/;
const repoSkillExists = (plugin, skill) => existsSync(join(REPO, "plugins", plugin, "skills", skill, "SKILL.md"));
/** A row for one of this marketplace's own plugin skills: a bare detect and a `/<plugin>:<skill>` id. */
const isOwn = (r) => r.kind === "skill" && !r.detect.includes("@") && PLUGIN_SKILL_ID.test(r.id);

/** Schema errors for routing.json holding one row: the first row's shared fields plus `fields`. */
function rowErrors(fields) {
  const { concern, rank, account, status, platforms, as_of } = routing.rows[0];
  return validate(schema, { ...routing, rows: [{ concern, rank, account, status, platforms, as_of, ...fields }] });
}

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
  Object.assign(bad.rows[0], { rank: 0, account: "free", extra: true });
  const errors = validate(schema, bad).join("\n");
  assert.match(errors, /rank: must be an integer >= 1/);
  assert.match(errors, /account: must be one of/);
  assert.match(errors, /unknown key extra/);
});

test("kind: skill ids are slash invocations", () => {
  const skills = routing.rows.filter((r) => r.kind === "skill");
  assert.ok(skills.length > 0);
  for (const r of skills) assert.match(r.id, SLASH_ID, `${r.concern}/${r.id}`);
});

test("the schema rejects a skill id without a slash", () => {
  const external = { kind: "skill", detect: "pixel-art@fixture-market", pointer: "https://example.com/pixel-art" };
  assert.deepEqual(rowErrors({ ...external, id: "/pixel-art:ui" }), []);
  assert.match(rowErrors({ ...external, id: "pixel-art:ui" }).join("\n"), /\.id: must match/);
});

test("the schema rejects a pointer on an own-skill row", () => {
  const own = { kind: "skill", id: "/pixel-art:ui", detect: "pixel-art" };
  assert.deepEqual(rowErrors(own), []);
  assert.notDeepEqual(rowErrors({ ...own, pointer: "https://example.com/pixel-art" }), []);
});

test("the schema rejects an external row with no pointer", () => {
  for (const row of [
    { kind: "skill", id: "/design:ux-copy", detect: "design@knowledge-work-plugins" },
    { kind: "skill", id: "/animate", detect: "animate" },
    { kind: "plugin", id: "figma@claude-plugins-official", detect: "figma@claude-plugins-official" },
  ]) {
    assert.match(rowErrors(row).join("\n"), /missing pointer/, row.id);
  }
});

test("the schema accepts a standalone /animate row with a pointer", () => {
  assert.deepEqual(rowErrors({ kind: "skill", id: "/animate", detect: "animate", pointer: "https://skills.sh/emilkowalski/skills" }), []);
});

test("only id, detect and pointer route-row fields carry @", () => {
  const fields = routing.rows.flatMap((r) => Object.entries(r).map(([k, v]) => [`${r.concern}/${r.id} ${k}`, k, JSON.stringify(v)]));
  assert.ok(fields.length > 0);
  assert.deepEqual(fields.filter(([, k, v]) => !["id", "detect", "pointer"].includes(k) && v.includes("@")).map(([at]) => at), []);
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
  for (const r of repoRows) assert.ok(!r.detect.includes("@"), `${r.concern}/${r.id} detect ${r.detect}`);
});

test("this repo's skills rank ahead of third parties in each concern", () => {
  for (const [concern, rows] of byConcern) {
    const ordered = rows.toSorted((a, b) => a.rank - b.rank).map(isOwn);
    assert.deepEqual(ordered, ordered.toSorted((a, b) => b - a), `order in ${concern}`);
  }
});

test("Mac-only rows are deferred and account-bound rows are never unconfirmed", () => {
  for (const r of routing.rows) {
    const macOnly = r.platforms.length === 1 && r.platforms[0] === "macos";
    if (macOnly) assert.equal(r.status, "deferred", `${r.concern}/${r.id}`);
    if (r.account !== "none") assert.notEqual(r.status, "unconfirmed", `${r.concern}/${r.id}`);
  }
});
