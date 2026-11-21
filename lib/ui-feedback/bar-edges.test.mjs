import { strict as assert } from "node:assert";
import { test } from "node:test";
import { edges } from "./bar-edges.mjs";

test("a bar 600px wide in a 374px view, scrolled to its start, hides tools past its end only", () => {
  assert.deepEqual(edges(0, 600, 374), { start: false, end: true });
});

test("the same bar scrolled to its end hides tools before its start only", () => {
  assert.deepEqual(edges(226, 600, 374), { start: true, end: false });
});

test("the same bar scrolled part way hides tools on both sides", () => {
  assert.deepEqual(edges(100, 600, 374), { start: true, end: true });
});

test("a bar that fits its view hides nothing", () => {
  assert.deepEqual(edges(0, 374, 374), { start: false, end: false });
});

test("a fractional scroll position a pixel short of either edge counts as at that edge", () => {
  assert.deepEqual(edges(225.4, 600, 374), { start: true, end: false });
  assert.deepEqual(edges(0.6, 600, 374), { start: false, end: true });
});
