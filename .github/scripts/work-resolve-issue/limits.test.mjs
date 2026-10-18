import assert from "node:assert/strict";
import { test } from "node:test";

import { DEFAULT_LIMITS as RESOLVER_DEFAULTS, withLimitDefaults } from "../../actions/resolve-config/limits.mjs";
import { DEFAULT_LIMITS, HOUR_MS } from "./limits.mjs";

test("the scripts' default limits are the resolver's", () => {
  assert.deepEqual(DEFAULT_LIMITS, RESOLVER_DEFAULTS);
  assert.deepEqual(withLimitDefaults(undefined), RESOLVER_DEFAULTS);
  assert.deepEqual(withLimitDefaults({ "restarts-per-run": 2 }), { ...RESOLVER_DEFAULTS, "restarts-per-run": 2 });
});

test("the defaults are the values the lanes used before they were configurable", () => {
  assert.deepEqual(DEFAULT_LIMITS, {
    "fallback-reset": 5,
    "reset-clamp-min": 1,
    "reset-clamp-max": 7 * 24,
    "restarts-per-run": 5,
    "limit-stops-per-head": 3,
    "limit-stops-per-issue": 3,
  });
  assert.equal(HOUR_MS, 60 * 60 * 1000);
});
