import assert from "node:assert/strict";
import { test } from "node:test";

import { BASELINE, publishBaseline, pushBaseline } from "./native-baseline-publish.mjs";

const repository = "owner/repo";
const release = "2.1.330";
const branch = `chore/native-surfaces-baseline-${release}`;
const base = "a".repeat(40);
const head = "b".repeat(40);
const entry = { path: BASELINE, mode: "100644", type: "blob" };
const content = JSON.stringify({
  schema: 1, cli_version: release, native_build: true,
  integrity: { status: "degraded" }, surfaces: {}, detect: {},
});
const proposal = { release, base, entry, content };

function fake({ previous = "{}", baseline = entry, ref = null, pulls = [], parent = base } = {}) {
  const calls = [];
  const replies = new Map([
    [`git/commits/${base}`, { tree: { sha: "root" } }],
    [`git/commits/${head}`, { parents: [{ sha: parent }], tree: { sha: "updated" } }],
    ["git/trees/root", { tree: [{ path: "docs", sha: "docs", mode: "040000", type: "tree" }] }],
    ["git/trees/docs", { tree: [{ path: "upstream", sha: "upstream", mode: "040000", type: "tree" }] }],
    ["git/trees/upstream", { tree: [{ ...baseline, path: BASELINE.split("/").at(-1), sha: "old" }] }],
    ["git/blobs/old", { content: Buffer.from(previous).toString("base64"), encoding: "base64" }],
    [`git/ref/heads/${branch}`, ref],
    [`pulls?state=all&head=owner:${encodeURIComponent(branch)}`, pulls],
  ]);
  const writes = new Map([
    ["git/trees", { sha: "updated" }],
    ["git/commits", { sha: head }],
    ["git/refs", {}],
    ["pulls", {}],
  ]);
  const read = async (uri, { method = "GET", body } = {}) => {
    assert.ok(uri.startsWith(`/repos/${repository}/`));
    const path = uri.slice(`/repos/${repository}/`.length);
    const response = method === "GET" ? replies : writes;
    assert.ok(response.has(path), `${method} ${path}`);
    if (method !== "GET") calls.push([path, body]);
    return response.get(path);
  };
  return { read, calls };
}

test("refuses alternate paths, symlinks and mode changes before writing", async () => {
  for (const changed of [{ path: "docs/upstream/claude-code.md" }, { mode: "120000" }, { mode: "100755" }]) {
    const { read, calls } = fake();
    await assert.rejects(pushBaseline(read, repository, { ...proposal, entry: { ...entry, ...changed } }), /only the regular/);
    assert.deepEqual(calls, []);
  }
  const { read, calls } = fake({ baseline: { ...entry, mode: "120000" } });
  await assert.rejects(pushBaseline(read, repository, proposal), /only the regular/);
  assert.deepEqual(calls, []);
});

test("an unchanged baseline creates no Git objects or branch", async () => {
  const { read, calls } = fake({ previous: content });
  assert.equal(await pushBaseline(read, repository, proposal), null);
  assert.deepEqual(calls, []);
});

test("creates one commit and a release branch with only the baseline tree entry", async () => {
  const { read, calls } = fake();
  assert.equal(await pushBaseline(read, repository, proposal), head);
  assert.deepEqual(calls, [
    ["git/trees", { base_tree: "root", tree: [{ ...entry, content }] }],
    ["git/commits", { message: `chore(upstream): refresh native surfaces for Claude Code ${release}`, tree: "updated", parents: [base] }],
    ["git/refs", { ref: `refs/heads/${branch}`, sha: head }],
  ]);
});

test("reuses only an existing branch with the expected parent and tree", async () => {
  const ref = { object: { sha: head } };
  const valid = fake({ ref });
  assert.equal(await pushBaseline(valid.read, repository, proposal), head);
  assert.deepEqual(valid.calls.map(([path]) => path), ["git/trees"]);
  const different = fake({ ref, parent: head });
  await assert.rejects(pushBaseline(different.read, repository, proposal), /different changes/);
  assert.deepEqual(different.calls.map(([path]) => path), ["git/trees"]);
});

test("publishes a draft with the scripted report at the pushed head only once", async () => {
  const ref = { object: { sha: head } };
  const report = "Inventory self-check: **degraded**.\n\nSummary difference\n\nAdded: example.";
  const input = { release, head, report };
  const { read, calls } = fake({ ref });
  assert.equal(await publishBaseline(read, repository, input), true);
  assert.deepEqual(calls, [["pulls", {
    title: `chore(upstream): refresh native surfaces for Claude Code ${release}`,
    head: branch, base: "main", draft: true,
    body: `Refreshes the native-surface baseline for release ${release}.\n\n${report}`,
  }]]);
  const existing = fake({ ref, pulls: [{ number: 1 }] });
  assert.equal(await publishBaseline(existing.read, repository, input), false);
  assert.deepEqual(existing.calls, []);
  const moved = fake({ ref: { object: { sha: base } } });
  await assert.rejects(publishBaseline(moved.read, repository, input), /branch moved/);
  assert.deepEqual(moved.calls, []);
});
