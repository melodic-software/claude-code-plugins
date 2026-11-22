import assert from "node:assert/strict";
import { readFileSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";
import { apiLimits, FILE_ONLY_FIELDS } from "./rate-guard.mjs";
import { tempDir } from "../../../lib/test-tmp.mjs";

const SCHEMA_PATH = new URL("../../../docs/conventions/pr-pipeline/pr-pipeline.schema.json", import.meta.url);

async function withDir(fn) {
  const dir = tempDir("rate-limits-");
  try {
    return await fn(dir);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

const DEFAULTS_PATH = new URL("./rate-limits.json", import.meta.url);

test("defaults come from rate-limits.json: a changed default changes the module's", () =>
  withDir((dir) => {
    const defaults = JSON.parse(readFileSync(DEFAULTS_PATH, "utf8"));
    const live = apiLimits({ resolvedPath: "", defaultsPath: DEFAULTS_PATH });
    defaults["lanes-app"]["read-floor"] = 0.25;
    defaults["content-creation"]["per-minute"] = 7;
    const path = join(dir, "rate-limits.json");
    writeFileSync(path, JSON.stringify(defaults));
    const changed = apiLimits({ resolvedPath: "", defaultsPath: path });
    assert.equal(changed["lanes-app"]["read-floor"], 0.25);
    assert.notEqual(live["lanes-app"]["read-floor"], 0.25);
    assert.equal(changed["content-creation"]["per-minute"], 7);
    assert.deepEqual(changed["github-token"], live["github-token"]);
  }));

test("a missing or invalid rate-limits.json throws, so the latch warns that the floor is unchecked", () =>
  withDir((dir) => {
    const valid = JSON.parse(readFileSync(DEFAULTS_PATH, "utf8"));
    const edits = {
      "not JSON": "{",
      "not an object": "[]",
      "a pool missing": JSON.stringify({ ...valid, graphql: undefined }),
      "an unknown pool": JSON.stringify({ ...valid, search: valid.graphql }),
      "a share missing": JSON.stringify({ ...valid, "lanes-app": { ...valid["lanes-app"], "read-floor": undefined } }),
      "a share past 1": JSON.stringify({ ...valid, "lanes-app": { ...valid["lanes-app"], "read-floor": 1.5 } }),
      "a share as text": JSON.stringify({ ...valid, "lanes-app": { ...valid["lanes-app"], breaker: "0.2" } }),
      "a plan of 0": JSON.stringify({ ...valid, graphql: { ...valid.graphql, plan: 0 } }),
      "a limit-cap, a field no pool takes": JSON.stringify({ ...valid, "github-token": { ...valid["github-token"], "limit-cap": 1000 } }),
      "per-minute off content-creation": JSON.stringify({ ...valid, "owner-token": { ...valid["owner-token"], "per-minute": 80 } }),
      "a per-hour of 0": JSON.stringify({ ...valid, "content-creation": { ...valid["content-creation"], "per-hour": 0 } }),
      "an unknown field": JSON.stringify({ ...valid, graphql: { ...valid.graphql, floor: 0.1 } }),
    };
    assert.throws(() => apiLimits({ resolvedPath: "", defaultsPath: join(dir, "missing.json") }), "missing");
    for (const [name, text] of Object.entries(edits)) {
      const path = join(dir, "rate-limits.json");
      writeFileSync(path, text);
      assert.throws(() => apiLimits({ resolvedPath: "", defaultsPath: path }), name);
    }
  }));

test("the schema states no limits.api default: rate-limits.json holds the only copy, for the schema's pools and fields", () => {
  const schema = JSON.parse(readFileSync(SCHEMA_PATH, "utf8"));
  const defaults = JSON.parse(readFileSync(DEFAULTS_PATH, "utf8"));
  const entries = schema.properties.limits.properties.api.properties;
  const pools = [schema.$defs["api-pool"], schema.$defs["api-content-pool"]];
  for (const [name, entry] of Object.entries(entries)) {
    assert.equal("default" in entry, false, name);
  }
  for (const pool of pools) {
    for (const [field, property] of Object.entries(pool.properties)) {
      assert.equal("default" in property, false, field);
    }
  }
  assert.deepEqual(Object.keys(defaults).sort(), Object.keys(entries).sort());
  for (const [name, fields] of Object.entries(defaults)) {
    const allowed = [...Object.keys(schema.$defs[name === "content-creation" ? "api-content-pool" : "api-pool"].properties), ...FILE_ONLY_FIELDS];
    assert.deepEqual(Object.keys(fields).filter((field) => !allowed.includes(field)), [], name);
  }
  for (const pool of pools) {
    for (const field of FILE_ONLY_FIELDS) {
      assert.equal(field in pool.properties, false, `${field} is file-only, so no pool's schema names it`);
    }
  }
  assert.equal(defaults["github-token"]["start-gate"], 0.1, "start-gate stays valid in rate-limits.json");
});

test("a resolved config's limits.api overrides the rate-limits.json default for that field only", () =>
  withDir((dir) => {
    const path = join(dir, "resolved.json");
    writeFileSync(path, JSON.stringify({ limits: { api: { "lanes-app": { "read-floor": 0.3 } } } }));
    const limits = apiLimits({ resolvedPath: path });
    const defaults = apiLimits({ resolvedPath: "" });
    assert.equal(limits["lanes-app"]["read-floor"], 0.3);
    assert.equal(limits["lanes-app"].plan, defaults["lanes-app"].plan);
    assert.deepEqual(limits["github-token"], defaults["github-token"]);
  }));
