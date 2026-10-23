// Unit tests for dimensions.mjs: one reader of an issue's Size, Complexity and
// Uncertainty fields, and the run budget they set. Field and option ids are
// the org's live ones (gh api orgs/melodic-software/issue-fields, 2026-10-18).
import assert from "node:assert/strict";
import { test } from "node:test";

import { checkDimensions, dimensionBudget, issueDimensions, parsePin } from "./dimensions.mjs";
import { Rejection } from "./resolve.mjs";

const HUMAN = 153232337;
const LANES_APP = 337595936;
const OTHER_BOT = 49699333;
const STRANGER = 42;
const TRUSTED = {
  version: 1,
  actors: [
    { id: HUMAN, login: "kyle-sexton", kind: "human" },
    { id: LANES_APP, login: "melodic-automation-lanes[bot]", kind: "bot" },
    { id: OTHER_BOT, login: "dependabot[bot]", kind: "bot" },
  ],
};
const CONFIG = {
  fields: {
    size: { "field-id": 15462270, options: { 27053568: "small", 27053567: "medium", 27053566: "large" } },
    complexity: { "field-id": 48625720, options: { 85127651: "low", 85127652: "medium", 85127653: "high" } },
    uncertainty: { "field-id": 48625721, options: { 85127654: "known", 85127655: "knowable", 85127656: "unknown" } },
  },
  sizes: { small: { "base-turns": 40, "timeout-minutes": 20 }, medium: { "base-turns": 80, "timeout-minutes": 45 }, large: "split" },
  complexity: { low: 1, medium: 1.5, high: 2 },
  uncertainty: { known: "run", knowable: "research-first", unknown: "probe-first" },
};

// The REST issue-field-values rows and the GraphQL setter per field id.
const facts = ({ size = 27053568, complexity = 85127651, uncertainty = 85127654, setter = HUMAN, setters = {} } = {}) => {
  const rows = [
    [15462270, size],
    [48625720, complexity],
    [48625721, uncertainty],
  ].filter(([, option]) => option !== null);
  return {
    fieldValues: rows.map(([field, option]) => ({ field, option })),
    fieldSetters: Object.fromEntries(rows.map(([field]) => [String(field), Object.hasOwn(setters, field) ? setters[field] : setter])),
  };
};
const read = (options) => issueDimensions(facts(options), CONFIG, TRUSTED);

test("each option id maps to its internal key", () => {
  assert.deepEqual(read({ size: 27053567, complexity: 85127653, uncertainty: 85127655 }), {
    size: "medium",
    complexity: "high",
    uncertainty: "knowable",
  });
});

test("a field with no value reads as small, medium or known", () => {
  assert.deepEqual(read({ size: 27053567, complexity: null }), { size: "medium", complexity: "medium", uncertainty: "known" });
  assert.deepEqual(read({ size: null, complexity: 85127653, uncertainty: null }), { size: "small", complexity: "high", uncertainty: "known" });
});

test("a value the lanes App set counts", () => {
  assert.equal(read({ setter: LANES_APP }).size, "small");
});

for (const [who, id] of [
  ["an account not on the trusted list", STRANGER],
  ["a listed bot other than the lanes App", OTHER_BOT],
  ["an unknown setter", null],
]) {
  test(`a value whose latest setter is ${who} is ignored and reads as unset`, () => {
    assert.equal(read({ size: 27053567, setters: { 15462270: id } }).size, "small");
  });
}

test("an option id the config does not map stops with unmapped-dimension", () => {
  assert.throws(
    () => read({ size: 99999999 }),
    (error) => error instanceof Rejection && error.code === "unmapped-dimension" && /99999999/.test(error.message),
  );
});

test("an unmapped option an untrusted account set reads as unset, not a failure", () => {
  assert.equal(read({ size: 99999999, setters: { 15462270: STRANGER } }).size, "small");
});

test("a field the config does not name is ignored", () => {
  const extra = facts();
  extra.fieldValues.push({ field: 777, option: 1 });
  assert.equal(issueDimensions(extra, CONFIG, TRUSTED).size, "small");
});

// Turn cap = the size's base turns times the complexity factor, rounded up.
for (const [size, complexity, turns, minutes] of [
  ["small", "low", 40, 20],
  ["small", "high", 80, 20],
  ["medium", "medium", 120, 45],
  ["medium", "high", 160, 45],
]) {
  test(`${size} ${complexity} known runs at ${turns} turns for ${minutes} minutes`, () => {
    assert.deepEqual(dimensionBudget({ size, complexity, uncertainty: "known" }, CONFIG), {
      skip: null,
      "max-turns": turns,
      "timeout-minutes": minutes,
      pin: `${size}/${complexity}/known`,
    });
  });
}

test("a fractional product rounds up", () => {
  const config = { ...CONFIG, sizes: { ...CONFIG.sizes, small: { "base-turns": 75, "timeout-minutes": 20 } } };
  assert.equal(dimensionBudget({ size: "small", complexity: "medium", uncertainty: "known" }, config)["max-turns"], 113);
});

for (const [why, dims, skip] of [
  ["a missing size", { size: null, complexity: "low", uncertainty: "known" }, "not-assessed"],
  ["a missing uncertainty", { size: "small", complexity: "low", uncertainty: null }, "not-assessed"],
  ["a large size", { size: "large", complexity: "low", uncertainty: "known" }, "split-required"],
  ["a knowable issue", { size: "small", complexity: "low", uncertainty: "knowable" }, "research-first"],
  ["an unknown issue", { size: "small", complexity: "low", uncertainty: "unknown" }, "probe-first"],
  ["a large unknown issue", { size: "large", complexity: "low", uncertainty: "unknown" }, "probe-first"],
]) {
  test(`${why} skips with ${skip} at the shortest timeout`, () => {
    const budget = dimensionBudget(dims, CONFIG);
    assert.equal(budget.skip, skip);
    assert.equal(budget["timeout-minutes"], 20);
    assert.equal(budget["max-turns"], undefined);
  });
}

test("a not-assessed budget pins not-assessed", () => {
  assert.equal(dimensionBudget({ size: null, complexity: null, uncertainty: null }, CONFIG).pin, "not-assessed");
});

test("a pin round-trips to the dimensions it names", () => {
  assert.deepEqual(parsePin("medium/high/known", CONFIG), { size: "medium", complexity: "high", uncertainty: "known" });
  assert.deepEqual(parsePin("not-assessed", CONFIG), { size: null, complexity: null, uncertainty: null });
});

for (const pin of ["huge/low/known", "small/low", "small/low/known/x", "small/extreme/known"]) {
  test(`pin \`${pin}\` is rejected`, () => {
    assert.throws(() => parsePin(pin, CONFIG), (error) => error instanceof Rejection && error.code === "undefined-dimension");
  });
}

test("the config passes the check with the keys an unset field reads as", () => {
  assert.doesNotThrow(() => checkDimensions(CONFIG));
});

for (const [why, config] of [
  ["no small size", { ...CONFIG, sizes: { medium: CONFIG.sizes.medium } }],
  ["no medium complexity", { ...CONFIG, complexity: { low: 1, high: 2 } }],
  ["no known uncertainty", { ...CONFIG, fields: { ...CONFIG.fields, uncertainty: { "field-id": 48625721, options: { 85127655: "knowable" } } }, uncertainty: { knowable: "run" } }],
  ["a small size that splits", { ...CONFIG, sizes: { ...CONFIG.sizes, small: "split" } }],
]) {
  test(`a config with ${why} fails the check, since an unset field must run`, () => {
    assert.throws(() => checkDimensions(config), (error) => error instanceof Rejection && error.code === "undefined-dimension");
  });
}
