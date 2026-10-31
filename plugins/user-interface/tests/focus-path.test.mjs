import { strict as assert } from "node:assert";
import { spawnSync } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { focusPath } from "../scripts/focus-path.mjs";

const SCRIPT = join(dirname(fileURLToPath(import.meta.url)), "../scripts/focus-path.mjs");
const run = (args) => spawnSync(process.execPath, [SCRIPT, ...args], { encoding: "utf8" });
const box = (x, y, width, height) => ({ x, y, width, height });

// The onboarding card from the focus-order lesson: Name and Email stacked, then a footer row with
// Back on the left and Continue on the right. The DOM puts Continue before Back, so focus runs
// 1 Name, 2 Email, 3 Continue, 4 Back, and the lesson flags only 3 -> 4: focus jumps backward from
// the right-hand Continue to the left-hand Back.
const lessonCard = [
  { name: "Name", tabIndex: 0, domIndex: 0, rect: box(24, 100, 320, 36) },
  { name: "Email", tabIndex: 0, domIndex: 1, rect: box(24, 150, 320, 36) },
  { name: "Continue", tabIndex: 0, domIndex: 2, rect: box(260, 210, 84, 36) },
  { name: "Back", tabIndex: 0, domIndex: 3, rect: box(24, 210, 60, 36) },
];

// The same card with the markup reordered so Back comes before Continue: the path reads left to
// right and top to bottom, so nothing is flagged.
const fixedCard = [
  { name: "Name", tabIndex: 0, domIndex: 0, rect: box(24, 100, 320, 36) },
  { name: "Email", tabIndex: 0, domIndex: 1, rect: box(24, 150, 320, 36) },
  { name: "Back", tabIndex: 0, domIndex: 2, rect: box(24, 210, 60, 36) },
  { name: "Continue", tabIndex: 0, domIndex: 3, rect: box(260, 210, 84, 36) },
];

test("the lesson card flags the one backward jump from Continue to Back", () => {
  assert.deepEqual(focusPath(lessonCard), {
    order: ["Name", "Email", "Continue", "Back"],
    issues: [{ kind: "backward", step: 4, from: "Continue", to: "Back" }],
  });
});

test("the card with Back first in the markup flags nothing", () => {
  assert.deepEqual(focusPath(fixedCard), { order: ["Name", "Email", "Back", "Continue"], issues: [] });
});

// Expected order from the HTML tabindex rules (MDN tabindex; HTML "The tabindex attribute"): a
// negative value is left out of sequential navigation; positive values come first, lowest number
// first, equal numbers in document order; zero comes after them, in document order. Here:
// c (1), b (2, dom 1), e (2, dom 4), then a and f (0); d (-1) is left out.
test("positive tabindex values come first by number, then zero in document order", () => {
  const row = (name, tabIndex, domIndex) => ({ name, tabIndex, domIndex, rect: box(domIndex * 100, 0, 80, 36) });
  const { order } = focusPath([row("a", 0, 0), row("b", 2, 1), row("c", 1, 2), row("d", -1, 3), row("e", 2, 4), row("f", 0, 5)]);
  assert.deepEqual(order, ["c", "b", "e", "a", "f"]);
});

// The same stops as above handed over in reverse document order: the order comes from tabIndex and
// domIndex, never from where a stop sits in the input, so the expected order is unchanged.
test("stops listed out of document order are still put in tabindex, then document, order", () => {
  const row = (name, tabIndex, domIndex) => ({ name, tabIndex, domIndex, rect: box(domIndex * 100, 0, 80, 36) });
  const { order } = focusPath([row("f", 0, 5), row("e", 2, 4), row("d", -1, 3), row("c", 1, 2), row("b", 2, 1), row("a", 0, 0)]);
  assert.deepEqual(order, ["c", "b", "e", "a", "f"]);
});

// One row, laid out left to right in document order, so no stop moves backward: the only issues are
// the two positive values, in the order focus reaches them.
test("every positive tabindex is flagged", () => {
  const row = (name, tabIndex, domIndex) => ({ name, tabIndex, domIndex, rect: box(domIndex * 100, 0, 80, 36) });
  assert.deepEqual(focusPath([row("a", 1, 0), row("b", 2, 1), row("c", 0, 2)]), {
    order: ["a", "b", "c"],
    issues: [
      { kind: "positive-tabindex", step: 1, name: "a", tabIndex: 1 },
      { kind: "positive-tabindex", step: 2, name: "b", tabIndex: 2 },
    ],
  });
});

// Two stacked fields, then a button placed above them by the layout: from the lower field focus
// moves up a row, which is backward whatever the horizontal position.
test("a jump to a row above is backward", () => {
  const result = focusPath([
    { name: "First", tabIndex: 0, domIndex: 0, rect: box(24, 100, 320, 36) },
    { name: "Second", tabIndex: 0, domIndex: 1, rect: box(24, 150, 320, 36) },
    { name: "Help", tabIndex: 0, domIndex: 2, rect: box(400, 20, 60, 36) },
  ]);
  assert.deepEqual(result.issues, [{ kind: "backward", step: 3, from: "Second", to: "Help" }]);
});

// Right to left the footer reads from the right edge: Continue on the left and Back on the right,
// Continue first in the DOM. Under rtl the move from Continue to Back goes toward the start of the
// line, so it is backward; under the default ltr the same geometry reads forward.
test("rtl reverses the horizontal direction within a row", () => {
  const footer = [
    { name: "Continue", tabIndex: 0, domIndex: 0, rect: box(24, 210, 84, 36) },
    { name: "Back", tabIndex: 0, domIndex: 1, rect: box(284, 210, 60, 36) },
  ];
  assert.deepEqual(focusPath(footer, { direction: "rtl" }).issues, [{ kind: "backward", step: 2, from: "Continue", to: "Back" }]);
  assert.deepEqual(focusPath(footer).issues, []);
});

// Two stops on one row whose left edges and right edges disagree: one box sits inside the other's
// horizontal extent. ltr compares left edges and rtl compares right edges (the script's header), so
// the wide box after the narrow one is backward in both directions (its left edge is further left,
// its right edge further right), and the narrow one after the wide one is backward in neither.
test("ltr compares left edges and rtl compares right edges", () => {
  const narrowThenWide = [
    { name: "Narrow", tabIndex: 0, domIndex: 0, rect: box(100, 0, 100, 36) },
    { name: "Wide", tabIndex: 0, domIndex: 1, rect: box(0, 0, 300, 36) },
  ];
  const wideThenNarrow = [
    { name: "Wide", tabIndex: 0, domIndex: 0, rect: box(0, 0, 300, 36) },
    { name: "Narrow", tabIndex: 0, domIndex: 1, rect: box(100, 0, 100, 36) },
  ];
  const backward = [{ kind: "backward", step: 2, from: "Narrow", to: "Wide" }];
  assert.deepEqual(focusPath(narrowThenWide).issues, backward);
  assert.deepEqual(focusPath(narrowThenWide, { direction: "rtl" }).issues, backward);
  assert.deepEqual(focusPath(wideThenNarrow).issues, []);
  assert.deepEqual(focusPath(wideThenNarrow, { direction: "rtl" }).issues, []);
});

// Rows that only touch are two rows (the script's header): the second starts at y 36, where the
// first ends, so it is the row below and reads forward even though it sits further left. A stop
// overlapping the first row by one pixel shares its row, so the same move is backward.
test("rows that exactly touch are separate rows; overlapping ones are one row", () => {
  const top = { name: "Right", tabIndex: 0, domIndex: 0, rect: box(200, 0, 60, 36) };
  assert.deepEqual(focusPath([top, { name: "Left", tabIndex: 0, domIndex: 1, rect: box(0, 36, 60, 36) }]).issues, []);
  assert.deepEqual(focusPath([top, { name: "Left", tabIndex: 0, domIndex: 1, rect: box(0, 35, 60, 36) }]).issues, [
    { kind: "backward", step: 2, from: "Right", to: "Left" },
  ]);
});

// Zero-height stops with level tops share a row (the script's header), so a move left along that
// line is backward and a move right is not.
test("zero-height stops on one line share a row", () => {
  const right = { name: "Right", tabIndex: 0, domIndex: 0, rect: box(200, 50, 60, 0) };
  const left = { name: "Left", tabIndex: 0, domIndex: 1, rect: box(0, 50, 60, 0) };
  assert.deepEqual(focusPath([right, left]).issues, [{ kind: "backward", step: 2, from: "Right", to: "Left" }]);
  assert.deepEqual(focusPath([{ ...left, domIndex: 0 }, { ...right, domIndex: 1 }]).issues, []);
});

test("malformed stops are refused", () => {
  const ok = { name: "A", tabIndex: 0, domIndex: 0, rect: box(0, 0, 10, 10) };
  assert.throws(() => focusPath([ok, { ...ok, name: "B" }]), /domIndex 0 appears twice/);
  assert.throws(() => focusPath([{ ...ok, tabIndex: 0.5 }]), /tabIndex must be a whole number/);
  assert.throws(() => focusPath([{ ...ok, rect: { x: 0, y: 0, width: -1, height: 10 } }]), /rect/);
  assert.throws(() => focusPath([{ ...ok, name: "" }]), /name/);
  assert.throws(() => focusPath([ok], { direction: "up" }), /direction/);
  assert.throws(() => focusPath({}), /array/);
  assert.throws(() => focusPath([{ ...ok, domIndex: -1 }]), /domIndex must be a whole number of at least 0/);
  assert.throws(() => focusPath([{ ...ok, rect: { x: Infinity, y: 0, width: 10, height: 10 } }]), /rect/);
  assert.throws(() => focusPath([{ ...ok, rect: { x: 0, y: Number.NaN, width: 10, height: 10 } }]), /rect/);
  assert.throws(() => focusPath([{ ...ok, rect: { x: 0, y: 0, width: 10, height: Infinity } }]), /rect/);
  assert.throws(() => focusPath([{ ...ok, rect: undefined }]), /rect/);
});

function withInput(content, fn) {
  const dir = mkdtempSync(join(tmpdir(), "focus-path-"));
  try {
    const file = join(dir, "stops.json");
    writeFileSync(file, content);
    return fn(file);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

test("the CLI prints the path as JSON and exits 1 when it flags an issue", () => {
  withInput(JSON.stringify({ stops: lessonCard }), (file) => {
    const r = run(["--input", file]);
    assert.equal(r.status, 1, r.stderr);
    assert.deepEqual(JSON.parse(r.stdout), { order: ["Name", "Email", "Continue", "Back"], issues: [{ kind: "backward", step: 4, from: "Continue", to: "Back" }] });
  });
});

test("the CLI exits 0 on a clean path and reads the direction from the input", () => {
  withInput(JSON.stringify({ stops: fixedCard }), (file) => {
    const r = run(["--input", file]);
    assert.equal(r.status, 0, r.stderr);
    assert.deepEqual(JSON.parse(r.stdout).issues, []);
  });
  const footer = [
    { name: "Continue", tabIndex: 0, domIndex: 0, rect: box(24, 210, 84, 36) },
    { name: "Back", tabIndex: 0, domIndex: 1, rect: box(284, 210, 60, 36) },
  ];
  withInput(JSON.stringify({ direction: "rtl", stops: footer }), (file) => {
    assert.equal(run(["--input", file]).status, 1);
  });
});

test("the CLI exits 2 on unreadable or malformed input", () => {
  withInput("{not json", (file) => {
    const r = run(["--input", file]);
    assert.equal(r.status, 2);
    assert.match(r.stderr, /^focus-path: /);
  });
  withInput(JSON.stringify({ stops: [{ name: "A", tabIndex: "0", domIndex: 0, rect: box(0, 0, 1, 1) }] }), (file) => {
    assert.equal(run(["--input", file]).status, 2);
  });
  assert.equal(run([]).status, 2);
});

test("the CLI exits 2 on a missing input file", () => {
  withInput("{}", (file) => {
    const r = run(["--input", join(dirname(file), "absent.json")]);
    assert.equal(r.status, 2);
    assert.match(r.stderr, /^focus-path: cannot read /);
  });
});

test("the CLI never echoes the file's contents or a raw control character", () => {
  withInput("{not json PRIVATE-TEXT", (file) => {
    const r = run(["--input", file]);
    assert.equal(r.status, 2);
    assert.equal(r.stderr, "focus-path: the input is not valid JSON\n");
  });
  const name = "\u001b[31mred";
  withInput(JSON.stringify({ stops: [{ name, tabIndex: "0", domIndex: 0, rect: box(0, 0, 1, 1) }] }), (file) => {
    const r = run(["--input", file]);
    assert.equal(r.status, 2);
    assert.ok(!r.stderr.includes("\u001b"), r.stderr);
    assert.ok(r.stderr.includes(JSON.stringify(name)), r.stderr);
  });
});
