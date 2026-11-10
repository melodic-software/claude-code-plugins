import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { decide, LANE_LEVEL_DEFAULTS } from "./lane-level.mjs";
import { apiLimits } from "../../actions/log-api-budget/rate-guard.mjs";

const VECTORS = JSON.parse(readFileSync(new URL("./lane-level.vectors.json", import.meta.url), "utf8"));

// A vector's config overrides the base per block and per pool.
function configOf(override = {}) {
  const base = VECTORS.config;
  const api = { ...base.api };
  for (const [pool, values] of Object.entries(override.api ?? {})) {
    api[pool] = { ...api[pool], ...values };
  }
  return { "lane-level": { ...base["lane-level"], ...(override["lane-level"] ?? {}) }, api };
}

test("the vectors file holds well-formed vectors covering every reason", () => {
  const reasons = new Set();
  for (const vector of VECTORS.vectors) {
    assert.deepEqual(Object.keys(vector.expect).sort(), ["holdUntil", "level", "reason", "streak"], vector.name);
    reasons.add(vector.expect.reason);
  }
  assert.deepEqual([...reasons].sort(), ["ceiling", "hold", "hot", "missing-data", "no-demand", "no-fit", "step-down", "step-up", "streak"]);
});

// The truth table exercises the numbers that ship, not numbers of its own.
test("the vectors' base config is the shipped lane-level and lanes-app defaults", () => {
  const shipped = apiLimits({ resolvedPath: "" });
  assert.deepEqual(VECTORS.config["lane-level"], { ...LANE_LEVEL_DEFAULTS, pools: [...LANE_LEVEL_DEFAULTS.pools] });
  for (const pool of ["lanes-app", "github-token"]) {
    assert.equal(VECTORS.config.api[pool].plan, shipped[pool].plan, pool);
    assert.equal(VECTORS.config.api[pool]["writer-pause"], shipped[pool]["writer-pause"], pool);
  }
});

for (const vector of VECTORS.vectors) {
  test(`vector: ${vector.name}`, () => {
    assert.deepEqual(decide(vector.previous, vector.readings, vector.demand, configOf(vector.config)), vector.expect);
  });
}

test("an unset lane-level block takes the defaults: a first busy window starts at 3", () => {
  const readings = { at: 1794340800, pools: { "lanes-app": { used: 100, limit: 5000 } }, signals: [] };
  const result = decide(null, readings, { waiting: 1, running: 3 }, { api: VECTORS.config.api });
  assert.deepEqual(result, { level: 3, streak: 1, holdUntil: 0, reason: "streak" });
});

test("repeated quiet busy windows climb one level per two windows and stop at the ceiling 4", () => {
  const config = configOf();
  let state = null;
  const levels = [];
  for (let hour = 0; hour < 12; hour += 1) {
    const readings = { at: 1794340800 + hour * 3600, pools: { "lanes-app": { used: 100, limit: 5000 } }, signals: [] };
    state = decide(state, readings, { waiting: 5, running: 6 }, config);
    levels.push(state.level);
  }
  assert.deepEqual(levels, [3, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4]);
});

test("with ceiling 6 the same windows climb to 6", () => {
  const config = configOf({ "lane-level": { ceiling: 6 } });
  let state = null;
  const levels = [];
  for (let hour = 0; hour < 8; hour += 1) {
    const readings = { at: 1794340800 + hour * 3600, pools: { "lanes-app": { used: 100, limit: 5000 } }, signals: [] };
    state = decide(state, readings, { waiting: 5, running: 6 }, config);
    levels.push(state.level);
  }
  assert.deepEqual(levels, [3, 4, 4, 5, 5, 6, 6, 6]);
});
