import assert from "node:assert/strict";
import { test } from "node:test";

import { projectedLeft } from "./projection.mjs";

const NOW = 1_800_000_000;
const near = (actual, expected, label) => assert.ok(Math.abs(actual - expected) < 1e-9, `${label}: ${actual} is not ${expected}`);
const half = { limit: 5000, remaining: 3000, reset: NOW + 1800 };

test("the projection runs the window's burn rate to the horizon, or to the reset when that comes first", () => {
  near(projectedLeft(half, NOW, 600), (3000 - 2000 / 3) / 5000, "30 min in, 2000 used, 600 s ahead spends 666.7");
  near(projectedLeft(half, NOW), 0.2, "to the reset 2000 more leaves 1000");
  near(projectedLeft(half, NOW, 7200), 0.2, "a horizon past the reset stops at the reset");
});

test("the first minute and a spent projection are pinned, and an unreadable reading projects nothing", () => {
  assert.equal(projectedLeft({ limit: 5000, remaining: 4000, reset: NOW + 3590 }, NOW, 1200), 0.8, "first minute: remaining alone");
  assert.equal(projectedLeft({ limit: 1000, remaining: 100, reset: NOW + 1800 }, NOW), 0, "clamped at 0");
  for (const reading of [{}, { limit: 0, remaining: 0, reset: NOW + 60 }, { limit: 5000, remaining: 100, reset: NOW - 10 }, { limit: 5000, remaining: 6000, reset: NOW + 60 }]) {
    assert.equal(projectedLeft(reading, NOW, 600), null, JSON.stringify(reading));
  }
  assert.equal(projectedLeft(half, NOW, -1), null, "a negative horizon");
});
