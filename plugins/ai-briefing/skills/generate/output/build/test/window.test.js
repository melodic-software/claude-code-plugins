import assert from "node:assert/strict";
import test from "node:test";

import { formatWindow, parseWindowRange } from "../lib/window.js";

const OPEN = "2026-04-24T19:00:00Z";
const CLOSE = "2026-05-05T20:30:00Z";

test("parses the Unicode-arrow window header", () => {
  assert.deepEqual(parseWindowRange(`${OPEN} → ${CLOSE} (~11 days)`), {
    open: OPEN,
    close: CLOSE,
  });
});

// Regression (#3364): the old `([0-9T:Z-]+)\s*[→-]+\s*([0-9T:Z-]+)` could not
// place the `>` of an ASCII arrow, so it backtracked and split INSIDE the first
// timestamp — yielding open="2026", close="04-24T19:00:00Z" and a nonsense
// rendered window. Both spellings must yield the same full pair.
test("parses the ASCII-arrow window header into the same full timestamps", () => {
  assert.deepEqual(parseWindowRange(`${OPEN} -> ${CLOSE} (~11 days)`), {
    open: OPEN,
    close: CLOSE,
  });
});

test("both separator spellings render an identical window string", () => {
  const unicode = parseWindowRange(`${OPEN} → ${CLOSE} (~11 days)`);
  const ascii = parseWindowRange(`${OPEN} -> ${CLOSE} (~11 days)`);
  assert.equal(
    formatWindow(ascii.open, ascii.close),
    formatWindow(unicode.open, unicode.close),
  );
  assert.equal(formatWindow(ascii.open, ascii.close), "2026-04-24 to 2026-05-05 (~11 days)");
});

test("accepts a bare hyphen and an en/em dash between full timestamps", () => {
  for (const sep of ["-", "–", "—", "-->"]) {
    assert.deepEqual(
      parseWindowRange(`${OPEN} ${sep} ${CLOSE}`),
      { open: OPEN, close: CLOSE },
      `separator ${sep} must not split a timestamp`,
    );
  }
});

test("accepts date-only endpoints", () => {
  assert.deepEqual(parseWindowRange("2026-04-24 -> 2026-05-05"), {
    open: "2026-04-24",
    close: "2026-05-05",
  });
});

test("returns null when the header carries no range", () => {
  assert.equal(parseWindowRange("rolling window"), null);
  assert.equal(parseWindowRange(undefined), null);
});
