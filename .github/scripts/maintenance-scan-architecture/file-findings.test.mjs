// test-scope: .github/actions/resolve-config/package.json
import assert from "node:assert/strict";
import { test } from "node:test";

import { fileFindings, ISSUE_TYPE, readItems, summary } from "./file-findings.mjs";

const item = (n) => ({ title: `Deepen module ${n}`, body: `Evidence: \`src/m${n}.mjs:1\`.\n\n## Done when\n\n- [ ] One seam.` });
const doc = (items) => JSON.stringify({ items });

function forge({ open = 0, existing = [], label = true } = {}) {
  const posts = [];
  const call = async (method, path, body) => {
    if (method === "POST") {
      posts.push(body);
      return { number: 100 + posts.length };
    }
    if (path.includes("/labels/")) return label ? { name: "source: architecture-improve" } : null;
    if (path.includes("state=open")) return /&page=1\b/.test(path) ? Array.from({ length: open }, (_, i) => ({ number: i + 1, title: `open ${i}` })) : [];
    if (path.includes("state=all")) return /&page=1\b/.test(path) ? existing.map((title, i) => ({ number: 50 + i, title })) : [];
    throw new Error(`unexpected ${method} ${path}`);
  };
  return { call, posts };
}

test("every filing carries exactly one label, source: architecture-improve, and the Task type", async () => {
  const { call, posts } = forge();
  const result = await fileFindings({ items: [item(1), item(2)], cap: 5, call, repository: "o/r" });
  assert.deepEqual(result.filed.map((issue) => issue.number), [101, 102]);
  assert.equal(posts.length, 2);
  for (const post of posts) {
    assert.deepEqual(post.labels, ["source: architecture-improve"]);
    assert.equal(post.type, ISSUE_TYPE);
  }
  assert.equal(posts[0].title, "Deepen module 1");
});

test("filing stops at the room left under the cap, counted again at filing time", async () => {
  const { call, posts } = forge({ open: 4 });
  const result = await fileFindings({ items: [item(1), item(2), item(3)], cap: 5, call, repository: "o/r" });
  assert.equal(posts.length, 1);
  assert.equal(result.skipped.length, 2);
  assert.match(result.skipped[0].why, /reached the cap of 5/);
});

test("an item whose title an issue with the label already holds is skipped, whatever its case or spacing", async () => {
  const { call, posts } = forge({ existing: ["deepen  MODULE 1"] });
  const result = await fileFindings({ items: [item(1), item(2)], cap: 5, call, repository: "o/r" });
  assert.deepEqual(posts.map((post) => post.title), ["Deepen module 2"]);
  assert.match(result.skipped[0].why, /already carries/);
});

test("a missing label files nothing, since the lane never creates one", async () => {
  const { call, posts } = forge({ label: false });
  await assert.rejects(fileFindings({ items: [item(1)], cap: 5, call, repository: "o/r" }), /never creates a label/);
  assert.equal(posts.length, 0);
});

test("no items reads nothing and files nothing", async () => {
  const result = await fileFindings({ items: [], cap: 5, call: async () => assert.fail("no read"), repository: "o/r" });
  assert.deepEqual(result.filed, []);
});

test("readItems accepts the schema's shape and refuses anything else", () => {
  assert.deepEqual(readItems(doc([item(1)])), [item(1)]);
  assert.deepEqual(readItems(doc([{ title: "  Spaced  ", body: "b" }]))[0].title, "Spaced");
  for (const [name, text] of [
    ["no list", JSON.stringify({})],
    ["over ten", doc(Array.from({ length: 11 }, (_, i) => item(i)))],
    ["an extra key", doc([{ ...item(1), labels: ["agent-ready"] }])],
    ["a two-line title", doc([{ title: "a\nb", body: "b" }])],
    ["a long title", doc([{ title: "t".repeat(121), body: "b" }])],
    ["an empty body", doc([{ title: "t", body: " " }])],
    ["a long body", doc([{ title: "t", body: "b".repeat(6001) }])],
  ]) {
    assert.throws(() => readItems(text), Error, name);
  }
});

test("the summary names each filed issue and why each other item was skipped", () => {
  const text = summary({ filed: [{ number: 7, title: "x" }], skipped: [{ title: "y", why: "a reason" }] });
  assert.match(text, /Filed 1, skipped 1\./);
  assert.match(text, /- filed #7/);
  assert.match(text, /- skipped one item: a reason/);
});
