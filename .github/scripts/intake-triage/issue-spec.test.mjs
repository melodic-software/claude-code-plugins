import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

const STATIC = /^\s*(?:import|export)\b[^;]*?\bfrom\s+"(\.{1,2}\/[^"]+)"/gm;

const reachable = (entry) => {
  const seen = new Set();
  const visit = (url) => {
    if (seen.has(url.href)) {
      return;
    }
    seen.add(url.href);
    for (const [, specifier] of readFileSync(url, "utf8").matchAll(STATIC)) {
      visit(new URL(specifier, url));
    }
  };
  visit(new URL(entry, import.meta.url));
  return seen;
};

const at = (name) => new URL(name, import.meta.url).href;

test("size-split.mjs reaches admit.mjs through no static import, so admit.mjs importing it forms no cycle", () => {
  const graph = reachable("./size-split.mjs");
  assert.ok(graph.has(at("./issue-spec.mjs")), "size-split.mjs reads its spec readers from issue-spec.mjs");
  assert.equal(graph.has(at("./admit.mjs")), false, "size-split.mjs must not reach admit.mjs");
});

test("issue-spec.mjs reaches neither admit.mjs nor size-split.mjs, so both import it without a cycle", () => {
  const graph = reachable("./issue-spec.mjs");
  assert.equal(graph.has(at("./admit.mjs")), false, "issue-spec.mjs must not reach admit.mjs");
  assert.equal(graph.has(at("./size-split.mjs")), false, "issue-spec.mjs must not reach size-split.mjs");
});

test("admit.mjs still imports size-split.mjs, the edge the cycle ran back along", () => {
  assert.ok(reachable("./admit.mjs").has(at("./size-split.mjs")), "admit.mjs reaches size-split.mjs");
});
