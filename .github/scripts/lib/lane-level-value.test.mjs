import assert from "node:assert/strict";
import { test } from "node:test";

import { effectiveLevel, encodeLevel, LEVEL_VARIABLE, levelSettings, parseLevel, variableOf } from "./lane-level-value.mjs";

// 2026-11-10T23:00:00Z, in epoch seconds.
const NOW_S = 1794351600;
const NOW = NOW_S * 1000;
const live = levelSettings({ shadow: false });

test("a value round-trips as <level>@<valid-until>", () => {
  assert.equal(encodeLevel(4, NOW_S + 9000), "4@1794360600");
  assert.deepEqual(parseLevel("4@1794360600"), { level: 4, validUntil: 1794360600 });
});

test("live: an unexpired value is the level, clamped to floor 2 and ceiling 4", () => {
  for (const [value, level] of [
    [`4@${NOW_S + 60}`, 4],
    [`2@${NOW_S + 60}`, 2],
    [`9@${NOW_S + 60}`, 4],
    [`1@${NOW_S + 60}`, 2],
    ["4@1794360600", 4],
  ]) {
    const read = effectiveLevel({ value, settings: live, now: NOW });
    assert.deepEqual(read, { level, published: level, reason: "published", shadow: false }, value);
  }
});

test("live: an empty, expired or malformed value reads as the default 3", () => {
  for (const [value, reason] of [
    [undefined, "empty"],
    ["", "empty"],
    [`4@${NOW_S}`, "expired"],
    [`4@${NOW_S - 1}`, "expired"],
    ["4", "malformed"],
    ["four@1794360600", "malformed"],
    ["4@1794360600 ", "malformed"],
    ["0@1794360600", "malformed"],
    ["-4@1794360600", "malformed"],
    // valid-minutes (150) from now is 1794360600: one second past it was set by hand.
    ["4@1794360601", "malformed"],
    ["4@999999999999", "malformed"],
  ]) {
    assert.deepEqual(effectiveLevel({ value, settings: live, now: NOW }), { level: 3, published: 3, reason, shadow: false }, String(value));
  }
});

test("shadow (the default): the consumer gets the default 3 and the published level is only reported", () => {
  const read = effectiveLevel({ value: `4@${NOW_S + 60}`, now: NOW });
  assert.deepEqual(read, { level: 3, published: 4, reason: "published", shadow: true });
});

test("the default is clamped too", () => {
  assert.equal(effectiveLevel({ value: "", settings: levelSettings({ shadow: false, floor: 4, ceiling: 6, default: 3 }), now: NOW }).level, 4);
});

test("the variable is read from toJSON(vars) under the configured name only", () => {
  const vars = JSON.stringify({ CLAUDE_LANE_LEVEL: "4@1794360600", OTHER_LANE_LEVEL: "2@1794360600" });
  assert.equal(variableOf(vars), "4@1794360600");
  assert.equal(variableOf(vars, levelSettings({ variable: "OTHER_LANE_LEVEL" })), "2@1794360600");
  assert.equal(variableOf("{}"), undefined);
  assert.equal(variableOf("not json"), undefined);
  assert.equal(variableOf(undefined), undefined);
});

test("only a *_LANE_LEVEL name is a level variable; neither lanes kill switch is", () => {
  assert.ok(LEVEL_VARIABLE.test("CLAUDE_LANE_LEVEL"));
  for (const name of ["CLAUDE_LANES_DISABLED", "CLAUDE_LANES_REPO_DISABLED", "LANES_BROKER_URL", "CLAUDE_LANE_LEVEL_X", "claude_lane_level", "_LANE_LEVEL"]) {
    assert.ok(!LEVEL_VARIABLE.test(name), name);
  }
});
