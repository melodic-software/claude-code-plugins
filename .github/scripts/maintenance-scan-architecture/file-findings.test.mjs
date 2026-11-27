// test-scope: .github/actions/resolve-config/package.json
import assert from "node:assert/strict";
import { test } from "node:test";

import { fileFindings, ISSUE_TYPE, readItems, summary, trustedShape, withoutSecurityDefects, withoutTrustedShapes } from "./file-findings.mjs";
import { forge, ISSUE } from "./forge.fixtures.mjs";

const item = (n) => ({ title: `Deepen module ${n}`, body: `Evidence: \`src/m${n}.mjs:1\`.\n\n## Done when\n\n- [ ] One seam.` });
const doc = (items) => JSON.stringify({ items });

test("every filing carries exactly one label, source: architecture-improve, and the Task type, and takes the number the create response names", async () => {
  const { call, posts } = forge();
  const result = await fileFindings({ items: [item(1), item(2)], cap: 5, call, repository: "o/r" });
  assert.deepEqual(result.filed.map((issue) => issue.number), [ISSUE.number + 1, ISSUE.number + 2]);
  assert.equal(posts.length, 2);
  for (const post of posts) {
    assert.deepEqual(post.labels, ["source: architecture-improve"]);
    assert.equal(post.type, ISSUE_TYPE);
  }
  assert.equal(posts[0].title, "Deepen module 1");
});

test("filing stops at the room left under the cap, counted again at filing time past the page's pull requests", async () => {
  const { call, posts } = forge({ open: 4 });
  const result = await fileFindings({ items: [item(1), item(2), item(3)], cap: 5, call, repository: "o/r" });
  assert.equal(posts.length, 1);
  assert.equal(result.skipped.length, 2);
  assert.match(result.skipped[0].why, /reached the cap of 5/);
});

test("an item whose title an issue with the label already holds is skipped, whatever its case or spacing", async () => {
  const { call, posts } = forge({ filed: ["deepen  MODULE 1"] });
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
  const { call, calls } = forge();
  assert.deepEqual((await fileFindings({ items: [], cap: 5, call, repository: "o/r" })).filed, []);
  assert.deepEqual(calls, []);
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

test("an item that names a security defect in its title or body is dropped, and the others are kept", () => {
  const named = [
    { title: "Security defect in the token path", body: "b" },
    { title: "t", body: "security-defect: withheld" },
    { title: "t", body: "A path traversal vulnerability in src/a.mjs:4" },
    { title: "t", body: "Matches CWE-22." },
    { title: "Patch CVE-2026-12345", body: "b" },
    { title: "t", body: "The lanes token is passed through an unvalidated path, an injection route" },
    { title: "Auth check bypassed in seam X", body: "b" },
    { title: "t", body: "A secret reaches the step summary" },
    { title: "t", body: "Credentials are read from the runner home" },
    { title: "t", body: "This lets a caller exfiltrate the key" },
    { title: "t", body: "A privilege escalation through the helper" },
    { title: "t", body: "An exploitable parse of the record" },
  ];
  const { kept, dropped } = withoutSecurityDefects([item(1), ...named, item(2)]);
  assert.deepEqual(kept, [item(1), item(2)]);
  assert.equal(dropped, named.length);
  assert.deepEqual(withoutSecurityDefects([{ title: "Secure the seam", body: "No defect named here; the author module stays shallow." }]).dropped, 0);
});

test("an item shaped like an issue another script trusts is dropped: an Upstream drift: title or any HTML comment marker", () => {
  const shaped = [
    { title: "Upstream drift: anthropics/claude-code", body: "Upstream `anthropics/claude-code` changed since the pin on its docs/upstream page." },
    { title: "t", body: "b\n<!-- recurring-schedule id=x -->" },
    { title: "t", body: "<!-- monitor-signal key=1 -->" },
  ];
  const { kept, dropped } = withoutTrustedShapes([item(1), ...shaped]);
  assert.deepEqual([kept, dropped], [[item(1)], 3]);
  assert.equal(trustedShape({ title: "Upstream drift notes for the seam", body: "b" }), false, "only the exact drift title form drops");
});

test("the summary heads as lane / activity, says the verdict, shows at most five bullets and puts the full list in details", () => {
  const few = summary({ filed: [{ number: 7, title: "x" }], skipped: [{ title: "y", why: "a reason" }] });
  assert.match(few, /^### maintenance-scan-architecture \/ file-findings\n\nFiled: 1 issue\(s\), skipped 1\.\n\n- filed #7\n- skipped one item: a reason\n/);
  assert.doesNotMatch(few, /<details>/);
  const many = summary({ filed: Array.from({ length: 7 }, (_, i) => ({ number: i + 1, title: "x" })), skipped: [] });
  const visible = many.split("<details>")[0];
  assert.equal(visible.match(/^- /gm).length, 5);
  assert.equal(many.split("<details>")[1].match(/^- filed #/gm).length, 7);
  assert.match(summary({ filed: [], skipped: [{ title: "y", why: "r" }] }), /\nFiled nothing: skipped 1\.\n/);
});
