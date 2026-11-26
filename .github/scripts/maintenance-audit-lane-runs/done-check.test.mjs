import assert from "node:assert/strict";
import { test } from "node:test";

import { applyPlan, DIGEST_MARKER, DIGEST_TITLE, findDigest, parkedForDoneCheck, planDigest } from "./done-check.mjs";

const REPO = "melodic-software/claude-code-plugins";
const OWNER_ID = 153232337;
const APP_ID = 337595936;
const humans = new Set([OWNER_ID]);

const pull = (number, mergedAt, body, merged = true) => ({ source: { number, merged, mergedAt, body, repository: { nameWithOwner: REPO } } });
const decision = (createdAt) => ({ createdAt, body: "**Decision recorded.**\n\nOption 1.", lastEditedAt: null, author: { __typename: "User", databaseId: OWNER_ID }, editor: null });
const issueNode = ({ pulls = [], comments = [] }) => ({ createdAt: "2026-11-01T00:00:00Z", comments: { nodes: comments }, timelineItems: { nodes: pulls } });

const NODES = {
  10: issueNode({ pulls: [pull(20, "2026-11-05T00:00:00Z", "Fixes a thing.\n\nRefs: #10")] }),
  11: issueNode({ pulls: [pull(21, "2026-11-05T00:00:00Z", "Refs: #11")], comments: [decision("2026-11-06T00:00:00Z")] }),
  12: issueNode({ pulls: [pull(22, "2026-11-05T00:00:00Z", "Related to #12, see there.")] }),
  13: issueNode({ pulls: [pull(23, null, "Refs: #13", false)] }),
};

function graphql({ fail = false } = {}) {
  const calls = [];
  const github = async (method, path, body) => {
    calls.push([method, path]);
    assert.equal(`${method} ${path}`, "POST /graphql");
    if (fail) throw new Error("HTTP 502");
    const repository = Object.fromEntries([...body.query.matchAll(/i(\d+): issue/g)].map(([, n]) => [`i${n}`, NODES[n]]));
    return { data: { repository } };
  };
  return { github, calls };
}

const listing = (numbers, held = []) => {
  const seen = [];
  const issuesByStatus = async (_github, repository, states) => {
    seen.push([repository, states]);
    const found = numbers.map((number) => ({ number, labels: [], state: "confirmed" }));
    Object.defineProperty(found, "held", { value: held.map((number) => ({ number })) });
    return found;
  };
  return { issuesByStatus, seen };
};

test("lists a confirmed issue a merged Refs pull request names after its newest decision, and only that one", async () => {
  const { github } = graphql();
  const { issuesByStatus, seen } = listing([13, 12, 11, 10], [14]);
  const result = await parkedForDoneCheck({ github, repository: REPO, config: {}, trustedActors: {}, issuesByStatus, humans, appId: APP_ID });
  assert.deepEqual(result.parked, [[10, [20]]], "#11's decision came after #21; #12 has no Refs line; #23 never merged");
  assert.deepEqual(result.held, [14]);
  assert.deepEqual(seen, [[REPO, ["confirmed"]]], "only Work status confirmed is listed");
});

test("a failed merged-Refs read fails the listing instead of reading as none parked", async () => {
  const { github } = graphql({ fail: true });
  const { issuesByStatus } = listing([10]);
  await assert.rejects(parkedForDoneCheck({ github, repository: REPO, config: {}, trustedActors: {}, issuesByStatus, humans, appId: APP_ID }), /merged Refs pull requests were not read/);
});

test("no confirmed issue makes no read", async () => {
  const { github, calls } = graphql();
  const { issuesByStatus } = listing([]);
  assert.deepEqual((await parkedForDoneCheck({ github, repository: REPO, config: {}, trustedActors: {}, issuesByStatus, humans, appId: APP_ID })).parked, []);
  assert.deepEqual(calls, []);
});

test("the digest body opens with its marker and lists each parked issue with its pull requests", () => {
  const { body } = planDigest({ parked: [[10, [20]], [16765, [16975, 17001]]], digest: null });
  const lines = body.split("\n");
  assert.equal(lines[0], DIGEST_MARKER);
  assert.ok(lines.includes("- #10: merged #20"));
  assert.ok(lines.includes("- #16765: merged #16975, #17001"));
  assert.match(body, /close it if the work is done, or post a comment whose first line is `\*\*Decision recorded\.\*\*`/);
});

test("the digest is created, rewritten, closed and reopened as the list changes, and a muted one stays closed", () => {
  const parked = [[10, [20]]];
  const body = planDigest({ parked, digest: null }).body;
  const cases = [
    ["no digest, nothing parked", { parked: [], digest: null }, "none"],
    ["no digest, one parked", { parked, digest: null }, "create"],
    ["open, same list", { parked, digest: { state: "open", body } }, "none"],
    ["open, list changed", { parked: [[11, [21]]], digest: { state: "open", body } }, "edit"],
    ["open, list empty", { parked: [], digest: { state: "open", body } }, "close"],
    ["closed as completed, list filled", { parked, digest: { state: "closed", state_reason: "completed", body } }, "reopen"],
    ["closed as completed, list empty", { parked: [], digest: { state: "closed", state_reason: "completed", body } }, "none"],
    ["closed as not planned, list filled", { parked, digest: { state: "closed", state_reason: "not_planned", body } }, "none"],
  ];
  for (const [name, input, action] of cases) {
    assert.equal(planDigest(input).action, action, name);
  }
});

test("finds the job token's digest by its first line across pages, skipping pull requests and other issues", async () => {
  const page1 = Array.from({ length: 100 }, (_, i) => ({ number: 1000 + i, body: "<!-- lane-sweep-digest -->\nother" }));
  const page2 = [
    { number: 5, pull_request: {}, body: `${DIGEST_MARKER}\npr` },
    { number: 6, body: `quoted:\n${DIGEST_MARKER}` },
    { number: 7, body: `${DIGEST_MARKER}\nlist`, state: "closed" },
  ];
  const paths = [];
  const github = async (method, path) => {
    paths.push(path);
    return path.endsWith("page=1") ? page1 : page2;
  };
  assert.equal((await findDigest(github, REPO)).number, 7);
  assert.equal(paths.length, 2);
  assert.match(paths[0], /creator=github-actions%5Bbot%5D&state=all/);
  assert.equal(await findDigest(async () => [], REPO), null);
});

test("each plan writes the digest issue with exactly its call", async () => {
  const digest = { number: 7 };
  const cases = [
    [{ action: "create", body: "B" }, null, ["POST", `/repos/${REPO}/issues`, { title: DIGEST_TITLE, body: "B" }]],
    [{ action: "edit", body: "B" }, digest, ["PATCH", `/repos/${REPO}/issues/7`, { body: "B" }]],
    [{ action: "close", body: "B" }, digest, ["PATCH", `/repos/${REPO}/issues/7`, { body: "B", state: "closed", state_reason: "completed" }]],
    [{ action: "reopen", body: "B" }, digest, ["PATCH", `/repos/${REPO}/issues/7`, { body: "B", state: "open" }]],
  ];
  for (const [plan, existing, call] of cases) {
    const calls = [];
    const number = await applyPlan(async (...args) => (calls.push(args), { number: 9 }), REPO, existing, plan);
    assert.deepEqual(calls, [call], plan.action);
    assert.equal(number, existing ? 7 : 9, plan.action);
  }
  const calls = [];
  assert.equal(await applyPlan(async (...args) => calls.push(args), REPO, digest, { action: "none" }), 7);
  assert.deepEqual(calls, [], "none writes nothing");
});
