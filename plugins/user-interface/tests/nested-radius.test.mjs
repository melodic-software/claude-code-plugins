import { strict as assert } from "node:assert";
import { spawnSync } from "node:child_process";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { innerRadius } from "../scripts/nested-radius.mjs";

const SCRIPT = join(dirname(fileURLToPath(import.meta.url)), "../scripts/nested-radius.mjs");
const run = (args) => spawnSync(process.execPath, [SCRIPT, ...args], { encoding: "utf8" });

// Expected values: the rule "inner radius = outer radius minus the parent's border width minus the
// padding, floored at zero", worked by hand. The gap is border plus padding; past_max_gap is the gap
// exceeding the limit.
//   photo card:        20 - 0 - 8  = 12, gap 8
//   frame and card:    16 - 0 - 4  = 12, gap 4
//   bordered frame:    16 - 1 - 4  = 11, gap 5
//   padding past it:    8 - 0 - 12 = -4, floored to 0, gap 12
//   gap at the limit:  30 - 0 - 24 = 6, gap 24, 24 > 24 is false
//   gap past it:       30 - 1 - 24 = 5, gap 25, 25 > 24 is true
test("the inner radius is the outer minus the border minus the padding", () => {
  assert.deepEqual(innerRadius({ outerPx: 20, borderPx: 0, paddingPx: 8, maxGapPx: 24 }), { inner_px: 12, gap_px: 8, max_gap_px: 24, past_max_gap: false });
  assert.deepEqual(innerRadius({ outerPx: 16, borderPx: 0, paddingPx: 4, maxGapPx: 24 }), { inner_px: 12, gap_px: 4, max_gap_px: 24, past_max_gap: false });
  assert.deepEqual(innerRadius({ outerPx: 16, borderPx: 1, paddingPx: 4, maxGapPx: 24 }), { inner_px: 11, gap_px: 5, max_gap_px: 24, past_max_gap: false });
});

test("padding larger than the outer radius floors the inner radius at zero", () => {
  assert.deepEqual(innerRadius({ outerPx: 8, borderPx: 0, paddingPx: 12, maxGapPx: 24 }), { inner_px: 0, gap_px: 12, max_gap_px: 24, past_max_gap: false });
});

test("a gap past the limit is reported, a gap at the limit is not", () => {
  assert.deepEqual(innerRadius({ outerPx: 30, borderPx: 0, paddingPx: 24, maxGapPx: 24 }), { inner_px: 6, gap_px: 24, max_gap_px: 24, past_max_gap: false });
  assert.deepEqual(innerRadius({ outerPx: 30, borderPx: 1, paddingPx: 24, maxGapPx: 24 }), { inner_px: 5, gap_px: 25, max_gap_px: 24, past_max_gap: true });
});

test("a negative or missing length is refused", () => {
  assert.throws(() => innerRadius({ outerPx: 16, borderPx: 0, paddingPx: -1, maxGapPx: 24 }), RangeError);
  assert.throws(() => innerRadius({ outerPx: Number.NaN, borderPx: 0, paddingPx: 4, maxGapPx: 24 }), RangeError);
  assert.throws(() => innerRadius({ outerPx: 16, borderPx: 0, paddingPx: 4 }), RangeError);
});

// Expected: team.schema.json types css.concentric_radius.max_gap_px as an integer, so 24.5 is refused;
// lengths stay fractional (a 0.5px hairline border): 16 - 0.5 - 4 = 11.5, gap 4.5.
test("the limit must be a whole number of px, the lengths need not be", () => {
  assert.throws(() => innerRadius({ outerPx: 16, borderPx: 0, paddingPx: 4, maxGapPx: 24.5 }), RangeError);
  assert.deepEqual(innerRadius({ outerPx: 16, borderPx: 0.5, paddingPx: 4, maxGapPx: 24 }), { inner_px: 11.5, gap_px: 4.5, max_gap_px: 24, past_max_gap: false });
  const r = run(["--outer", "16", "--border", "0", "--padding", "4", "--max-gap-px", "24.5"]);
  assert.equal(r.status, 2);
  assert.match(r.stderr, /maxGapPx must be a whole number/);
});

test("the CLI prints the result as JSON", () => {
  const r = run(["--outer", "16", "--border", "1", "--padding", "4", "--max-gap-px", "24"]);
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(JSON.parse(r.stdout), { inner_px: 11, gap_px: 5, max_gap_px: 24, past_max_gap: false });
});

test("the CLI exits 2 on a length that is not a number", () => {
  const r = run(["--outer", "16px", "--border", "0", "--padding", "4", "--max-gap-px", "24"]);
  assert.equal(r.status, 2);
  assert.match(r.stderr, /outerPx must be a number of at least 0/);
  assert.equal(run(["--outer", "16", "--border", "0", "--max-gap-px", "24"]).status, 2);
});

// Expected: 30 - 1 - 24 = 5 inner; gap 1 + 24 = 25, past the bundled limit of 24.
test("without --max-gap-px the CLI reads the bundled limit", () => {
  const r = run(["--outer", "30", "--border", "1", "--padding", "24"]);
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(JSON.parse(r.stdout), { inner_px: 5, gap_px: 25, max_gap_px: 24, past_max_gap: true });
});
