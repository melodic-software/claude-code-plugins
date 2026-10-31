#!/usr/bin/env node
// Walks a page's focusable elements in sequential focus order and flags where the path goes wrong,
// printing JSON: {"order": [names], "issues": [...]}.
// Each stop is {name, tabIndex, domIndex, rect: {x, y, width, height}}, rect in page coordinates.
// Order follows the HTML tabindex rules: a negative tabIndex is left out; positive values come first,
// lowest first, equal values in document order (domIndex); zero comes after them in document order.
// Issues, in the order focus reaches them:
//   {"kind": "positive-tabindex", "step", "name", "tabIndex"}: a positive tabindex reorders focus.
//   {"kind": "backward", "step", "from", "to"}: focus moves against the reading order. Two stops
//   share a row when their vertical extents overlap or their tops are level, so zero-height stops
//   on one line share it; extents that only touch (one ends where the next begins) are two rows.
//   Within a row, ltr reading moves right, so a stop whose left edge sits left of the previous
//   stop's is backward (rtl mirrors it: a right edge further right). Across rows, a stop whose top
//   sits above the previous stop's is backward.
// step is the 1-based position in the order of the stop the issue is about. A flag marks a place to
// look: a deliberate order (a column-wise form) can be right and still be flagged.
// Usage: focus-path.mjs --input FILE, where FILE holds {"direction": "ltr"|"rtl", "stops": [...]}
// (direction optional, default ltr). Exit 0 with no issues, 1 with issues, 2 on bad input.
import { readFileSync, realpathSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";

const finite = (value) => typeof value === "number" && Number.isFinite(value);

function check(stops, direction) {
  if (!Array.isArray(stops)) throw new TypeError("stops must be an array");
  // Values from the input are JSON-quoted in messages, so control characters cannot reach the terminal raw.
  const quote = (value) => JSON.stringify(value) ?? String(value);
  if (direction !== "ltr" && direction !== "rtl") throw new RangeError(`direction must be ltr or rtl, got ${quote(direction)}`);
  const seen = new Set();
  for (const stop of stops) {
    const { name, tabIndex, domIndex, rect } = stop ?? {};
    if (typeof name !== "string" || name === "") throw new TypeError("every stop needs a non-empty name");
    if (!Number.isInteger(tabIndex)) throw new RangeError(`${quote(name)}: tabIndex must be a whole number, got ${quote(tabIndex)}`);
    if (!Number.isInteger(domIndex) || domIndex < 0) throw new RangeError(`${quote(name)}: domIndex must be a whole number of at least 0, got ${quote(domIndex)}`);
    if (seen.has(domIndex)) throw new RangeError(`domIndex ${domIndex} appears twice`);
    seen.add(domIndex);
    const ok = rect && finite(rect.x) && finite(rect.y) && finite(rect.width) && finite(rect.height) && rect.width >= 0 && rect.height >= 0;
    if (!ok) throw new RangeError(`${quote(name)}: rect needs finite x and y and a width and height of at least 0`);
  }
}

/** True when b comes before a in reading order, a being the previous stop. */
function isBackward(a, b, direction) {
  const sameRow = a.y === b.y || (b.y < a.y + a.height && a.y < b.y + b.height);
  if (!sameRow) return b.y < a.y;
  return direction === "ltr" ? b.x < a.x : b.x + b.width > a.x + a.width;
}

/** The sequential focus order of the stops and the issues along it. */
export function focusPath(stops, { direction = "ltr" } = {}) {
  check(stops, direction);
  const byNumberThenDom = (a, b) => a.tabIndex - b.tabIndex || a.domIndex - b.domIndex;
  const positive = stops.filter((s) => s.tabIndex > 0).sort(byNumberThenDom);
  const zero = stops.filter((s) => s.tabIndex === 0).sort(byNumberThenDom);
  const path = [...positive, ...zero];
  const issues = [];
  path.forEach((stop, i) => {
    const step = i + 1;
    if (stop.tabIndex > 0) issues.push({ kind: "positive-tabindex", step, name: stop.name, tabIndex: stop.tabIndex });
    if (i > 0 && isBackward(path[i - 1].rect, stop.rect, direction)) issues.push({ kind: "backward", step, from: path[i - 1].name, to: stop.name });
  });
  return { order: path.map((s) => s.name), issues };
}

function main() {
  const { values } = parseArgs({ options: { input: { type: "string" } }, strict: true });
  if (values.input === undefined) throw new Error("pass --input FILE");
  let text;
  try {
    text = readFileSync(values.input, "utf8");
  } catch {
    throw new Error(`cannot read ${JSON.stringify(values.input)}`);
  }
  let input;
  try {
    input = JSON.parse(text);
  } catch {
    throw new Error("the input is not valid JSON"); // never echo the file's contents
  }
  const { direction = "ltr", stops } = input ?? {};
  const result = focusPath(stops, { direction });
  console.log(JSON.stringify(result));
  return result.issues.length === 0 ? 0 : 1;
}

if (process.argv[1] && realpathSync(process.argv[1]) === realpathSync(fileURLToPath(import.meta.url))) {
  try {
    process.exitCode = main();
  } catch (error) {
    console.error(`focus-path: ${error.message}`);
    process.exit(2);
  }
}
