import assert from "node:assert/strict";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";

import { tempDir } from "../../../lib/test-tmp.mjs";
import { changedFiles, factsOf, issueText, main } from "./input.mjs";

const HEAD = "a".repeat(40);
const BASE = "b".repeat(40);
const REPO = "example-org/example-repo";

test("changedFiles lists each diffed path once, renames by their new path", () => {
  const diff = ["diff --git a/x.js b/x.js", "--- a/x.js", "+++ b/x.js", "diff --git a/old.md b/new.md", "rename from old.md", "diff --git a/x.js b/x.js"].join("\n");
  assert.deepEqual(changedFiles(diff), ["x.js", "new.md"]);
});

test("factsOf takes the trusted title and body, never the raw ones", () => {
  const context = { pr: { number: 7, title: "feat: x", body: "Closes #3" } };
  const facts = factsOf({ context, repository: REPO, pr: 7, head: HEAD, base: BASE, files: ["x.js"] });
  assert.deepEqual(facts, {
    number: 7,
    url: `https://github.com/${REPO}/pull/7`,
    title: "feat: x",
    body: "Closes #3",
    headRefOid: HEAD,
    baseRefOid: BASE,
    files: [{ path: "x.js" }],
  });
  assert.equal(factsOf({ context: { pr: { title: "", body: null } }, repository: REPO, pr: 7, head: HEAD, base: BASE, files: [] }).body, "");
});

test("issueText writes each closing issue, and says so when none was read", () => {
  assert.match(issueText([]), /No closing issue was read/);
  const text = issueText([{ number: 3, spec_kind: "closes", body: "the spec", comments: ["a refinement"] }]);
  assert.match(text, /^## Issue #3 \(closes\)\n\nthe spec\n/);
  assert.match(text, /### Comment 1\n\na refinement/);
  assert.match(issueText([{ number: 3, spec_kind: "refs", body: null, comments: [] }]), /no trusted body/);
});

test("main writes facts.json, issue.md and pr.diff, and refuses an oversized diff", () => {
  const dir = tempDir("merge-risk-input-");
  const data = join(dir, "data");
  const write = (name, value) => {
    const file = join(dir, name);
    writeFileSync(file, typeof value === "string" ? value : JSON.stringify(value));
    return file;
  };
  const env = {
    DATA: data,
    DIFF_FILE: write("diff.patch", "diff --git a/x.js b/x.js\n+1\n"),
    CONTEXT_FILE: write("context.json", { pr: { title: "t", body: "b" } }),
    SPEC_TEXT_FILE: write("spec-text.json", []),
    GITHUB_REPOSITORY: REPO,
    PR_NUMBER: "7",
    HEAD_SHA: HEAD,
    BASE_SHA: BASE,
    MAX_DIFF_BYTES: "1000",
  };
  assert.equal(main(env), 0);
  assert.equal(JSON.parse(readFileSync(join(data, "facts.json"), "utf8")).headRefOid, HEAD);
  assert.match(readFileSync(join(data, "issue.md"), "utf8"), /No closing issue/);
  assert.equal(readFileSync(join(data, "pr.diff"), "utf8"), "diff --git a/x.js b/x.js\n+1\n");
  assert.equal(main({ ...env, DATA: join(dir, "d2"), MAX_DIFF_BYTES: "5" }), 1);
  assert.equal(existsSync(join(dir, "d2", "facts.json")), false);
  assert.equal(main({ ...env, DATA: join(dir, "d3"), HEAD_SHA: "nope" }), 1);
});
