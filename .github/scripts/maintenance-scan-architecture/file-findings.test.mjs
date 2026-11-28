// test-scope: .github/actions/resolve-config/package.json plugins/improvement/scripts/filing-plan.mjs
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import process from "node:process";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

import { tempDir } from "../../../lib/test-tmp.mjs";
import { fileFindings, ISSUE_TYPE, main, readItems, summary, trustedShape, withoutSecurityDefects, withoutTrustedShapes } from "./file-findings.mjs";
import { forge, ISSUE } from "./forge.fixtures.mjs";
import { SOURCE_LABEL } from "./lane.mjs";

const item = (n) => ({ title: `Deepen module ${n}`, body: `Evidence: \`src/m${n}.mjs:1\`.\n\n## Done when\n\n- [ ] One seam.` });
const doc = (items) => JSON.stringify({ items });

test("check reads the opened findings, which open-lane-output writes read-only, and writes the kept items to CHECKED_FILE", async () => {
  const dir = tempDir("scan-architecture-check-");
  const opened = join(dir, "scan-in", "findings.json");
  const source = doc([item(1), { title: "t", body: "<!-- monitor-signal key=1 -->" }]);
  mkdirSync(join(dir, "scan-in"), { mode: 0o700 });
  writeFileSync(opened, source, { mode: 0o444 });
  const checked = join(dir, "scan-checked", "findings.json");
  await main("check", { FINDINGS_FILE: opened, CHECKED_FILE: checked });
  assert.deepEqual(JSON.parse(readFileSync(checked, "utf8")).items.map((i) => i.title), ["Deepen module 1"]);
  assert.equal(readFileSync(opened, "utf8"), source, "the opened file is left as it was");
  await assert.rejects(() => main("check", { FINDINGS_FILE: opened, CHECKED_FILE: checked }), /EEXIST/, "a second check never overwrites the checked file");
  await assert.rejects(() => main("check", { FINDINGS_FILE: opened }), /CHECKED_FILE/);
});

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

const FILING_PLAN = fileURLToPath(new URL("../../../plugins/improvement/scripts/filing-plan.mjs", import.meta.url));

test("the lane and /improvement:find's filing-plan command make the same filing decisions on the same items", async () => {
  for (const scenario of [{}, { open: 4 }, { open: 5 }, { filed: ["deepen  MODULE 2"] }, { open: 3, filed: ["Deepen module 1"] }]) {
    const lane = forge(scenario);
    const items = [item(1), item(2), item(3), item(1)];
    const result = await fileFindings({ items, cap: 5, call: lane.call, repository: "o/r" });
    const read = forge(scenario);
    const open = (await read.call("GET", "/repos/o/r/issues?state=open&per_page=100")).filter((entry) => !entry.pull_request).length;
    const existingTitles = (await read.call("GET", "/repos/o/r/issues?state=all&per_page=100")).map((entry) => entry.title);
    const request = { label: SOURCE_LABEL, labelExists: true, team: 5, open, existingTitles, candidates: items.map((entry) => entry.title) };
    const find = JSON.parse(execFileSync(process.execPath, [FILING_PLAN], { input: JSON.stringify(request), encoding: "utf8" }));
    const label = JSON.stringify(scenario);
    assert.deepEqual(result.filed.map((issue) => issue.title), find.file.map((index) => items[index].title), label);
    assert.deepEqual(result.skipped, find.skipped, label);
  }
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
    { title: "The lanes token reaches the step summary unmasked", body: "b" },
    { title: "t", body: "Path traversal through the record flag" },
    { title: "t", body: "An XSS through the rendered page" },
    { title: "t", body: "SSRF via the fetch helper" },
    { title: "t", body: "RCE in the loader" },
    { title: "t", body: "A sandbox escape through the helper" },
    { title: "t", body: "The key can leak into the log" },
    { title: "t", body: "Unsanitized input reaches the shell" },
    { title: "t", body: "A TOCTOU race on the lock file" },
  ];
  const { kept, dropped } = withoutSecurityDefects([item(1), ...named, item(2)]);
  assert.deepEqual(kept, [item(1), item(2)]);
  assert.equal(dropped, named.length);
  assert.deepEqual(withoutSecurityDefects([{ title: "Secure the seam", body: "No defect named here; the author module stays shallow." }]).dropped, 0);
  const cited = [
    { title: "Deepen the leg generator", body: "Evidence: `scripts/credential-legs/maintenance-scan-architecture.mjs:1`" },
    { title: "Merge the credential helpers", body: "Evidence: .github/scripts/lib/model-credential.mjs:12 and `select-model-credential`" },
  ];
  assert.equal(withoutSecurityDefects(cited).dropped, 2, "a term in a cited path or code span still drops the item: the screen errs toward keeping a security detail out of a public issue");
  assert.equal(withoutSecurityDefects([{ title: "t", body: "Evidence: `token/secret` in src/a.mjs:4" }]).dropped, 1);
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
