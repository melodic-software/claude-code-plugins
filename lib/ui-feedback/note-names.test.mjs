import { strict as assert } from "node:assert";
import { test } from "node:test";
import { readerName } from "./note-model.mjs";

const TABLE_TEXT = "Candidate Badge Solution S1. Give the ledger register one owner Strong One ledger-grammar module";

test("an element note is named by its own visible text and its card's heading", () => {
  const note = { kind: "element", anchor: { tag: "img", cssPath: "div:nth-of-type(2) > img:nth-of-type(1)", testid: "diagram-s1", testidIndex: 0 } };
  assert.equal(readerName(note, { text: "Before diagram", card: "S1 Give the ledger register one owner" }), "Before diagram, S1 Give the ledger register one owner");
});

test("a region note is named by the element holding it, a long text giving way to what the element is", () => {
  const note = { kind: "region", anchor: { tag: "table", cssPath: "table:nth-of-type(1)" }, rect: { x: 1, y: 2, w: 3, h: 4 }, elements: [] };
  assert.equal(readerName(note, { text: TABLE_TEXT, card: "All candidates" }), "Region over Table, All candidates");
});

test("a text note is named by its quote", () => {
  const note = { kind: "text", anchor: { tag: "p", cssPath: "p:nth-of-type(1)", textQuote: { exact: "Two parsers already read the same ledger differently" } } };
  assert.equal(readerName(note, { text: "Two parsers already read the same ledger differently, so this is a live defect", card: "S1 Give the ledger register one owner" }),
    "Text: “Two parsers already read the same ledger differently”");
});

test("a long quote is cut with an ellipsis", () => {
  const note = { kind: "text", anchor: { tag: "p", cssPath: "p", textQuote: { exact: "a".repeat(70) } } };
  assert.equal(readerName(note, null), `Text: “${"a".repeat(60)}…”`);
});

test("a move note names both ends", () => {
  const note = { kind: "move", anchor: { tag: "span", cssPath: "span" }, to: { point: { x: 1, y: 1 }, anchor: { tag: "p", cssPath: "p" } } };
  assert.equal(readerName(note, { text: "Strong", card: "S1 Give the ledger register one owner", toText: "Deepening review", toCard: "" }),
    "Move Strong, S1 Give the ledger register one owner to Deepening review");
});

test("a move to a bare point says so", () => {
  const note = { kind: "move", anchor: { tag: "span", cssPath: "span" }, to: { point: { x: 1, y: 1 } } };
  assert.equal(readerName(note, { text: "Strong", card: "" }), "Move Strong to a point on the page");
});

test("before the mockup has named a note, it is named by what its element is", () => {
  assert.equal(readerName({ kind: "element", anchor: { tag: "img", cssPath: "img" } }, null), "Image");
  assert.equal(readerName({ kind: "element", anchor: { tag: "div", role: "button", cssPath: "div" } }, null), "Button");
  assert.equal(readerName({ kind: "region", anchor: { tag: "x-widget", cssPath: "x-widget" } }, undefined), "Region over Element");
});

test("a card heading that repeats the element's own text is said once", () => {
  const note = { kind: "element", anchor: { tag: "h2", cssPath: "h2" } };
  assert.equal(readerName(note, { text: "All candidates", card: "All candidates" }), "All candidates");
});
