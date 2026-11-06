// merge-path.mjs: the agent-authored rule as #13601 states it (a body marker
// and a Co-Authored-By: Claude trailer), the path a merge takes, the labels the
// canary pass writes, and the rollup read back from them.
import assert from "node:assert/strict";
import { test } from "node:test";

import { formatRollup, isAgentAuthored, label, labelPlan, pathOf, resolvePaths, rollup } from "./merge-path.mjs";

const REPO = "o/r";
const IDENTITY = "melodic-automation-lanes[bot]";
const CONFIG = { agentIdentity: IDENTITY, paths: { "owner-agent": { mode: "record", enqueuers: ["kyle-sexton"] } } };
const PATHS = resolvePaths(CONFIG.paths);
const TRAILER = "feat: x\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>";
const SESSION_BODY = "Closes #1\n\n<!-- session: aee81595 -->";
const FOOTER_BODY = "## Summary\n\n🤖 Generated with [Claude Code](https://claude.com/claude-code)";

const user = (login) => ({ __typename: "User", login });
const lanesBot = { __typename: "Bot", login: "melodic-automation-lanes" };
const pr = (number, { by = user("kyle-sexton"), body = SESSION_BODY, commits = [TRAILER], labels = [], title = "feat: x", mergedAt } = {}) => ({
  number,
  title,
  body,
  labels,
  mergedAt,
  commitMessages: commits,
  queue: by ? { actor: by, enqueuer: by } : null,
});

test("agent-authored needs a body marker and a Claude co-author trailer", () => {
  assert.equal(isAgentAuthored({ body: SESSION_BODY, commitMessages: [TRAILER] }), true);
  assert.equal(isAgentAuthored({ body: FOOTER_BODY, commitMessages: ["fix: y", TRAILER] }), true);
  assert.equal(isAgentAuthored({ body: SESSION_BODY, commitMessages: ["feat: x\n\nCo-authored-by: claude <x>"] }), true, "git trailer keys are case-insensitive");
  assert.equal(isAgentAuthored({ body: SESSION_BODY, commitMessages: ["feat: x"] }), false, "a marker without the trailer");
  assert.equal(isAgentAuthored({ body: "Closes #1", commitMessages: [TRAILER] }), false, "a trailer without a marker");
  assert.equal(isAgentAuthored({ body: SESSION_BODY, commitMessages: ["feat: x\n\nCo-Authored-By: Alice <a@x>"] }), false, "another co-author");
  assert.equal(isAgentAuthored({ body: "say <!-- session: -->", commitMessages: [TRAILER] }), false, "an empty session marker");
  assert.equal(isAgentAuthored({ body: "Generated with Claude Code", commitMessages: [TRAILER] }), false, "the footer without its link text");
  assert.equal(isAgentAuthored({ body: SESSION_BODY, commitMessages: ["feat: x\n\nsee Co-Authored-By: Claude"] }), false, "a trailer mid-line");
});

test("a merge's path: lanes by the agent identity, a record path by enqueuer and authorship, else none", () => {
  assert.equal(pathOf(pr(1, { by: lanesBot }), { identity: IDENTITY, paths: PATHS }), "lanes");
  assert.equal(pathOf(pr(2, { by: lanesBot, body: "no marker" }), { identity: IDENTITY, paths: PATHS }), "lanes");
  assert.equal(pathOf(pr(3), { identity: IDENTITY, paths: PATHS }), "owner-agent");
  assert.equal(pathOf(pr(4, { by: user("Kyle-Sexton") }), { identity: IDENTITY, paths: PATHS }), "owner-agent", "logins match case-insensitively");
  assert.equal(pathOf(pr(5, { body: "Closes #1" }), { identity: IDENTITY, paths: PATHS }), null, "a person's own PR through the owner login");
  assert.equal(pathOf(pr(6, { by: user("alice") }), { identity: IDENTITY, paths: PATHS }), null, "an enqueuer on no path");
  assert.equal(pathOf(pr(7, { by: null }), { identity: IDENTITY, paths: PATHS }), null, "no merge-queue event");
  const lanesArmedOwnerEnqueued = { ...pr(8), queue: { actor: lanesBot, enqueuer: user("kyle-sexton") } };
  assert.equal(pathOf(lanesArmedOwnerEnqueued, { identity: IDENTITY, paths: PATHS }), "lanes", "the lanes test wins, as the alert's classify");
});

test("only well-formed record paths resolve", () => {
  assert.deepEqual(
    resolvePaths({
      "owner-agent": { mode: "record", enqueuers: ["Kyle-Sexton", "bad login!"] },
      lanes: { mode: "record", enqueuers: ["x"] },
      acting: { mode: "act", enqueuers: ["x"] },
      empty: { mode: "record", enqueuers: [] },
      "Bad Name": { mode: "record", enqueuers: ["x"] },
    }),
    { "owner-agent": { mode: "record", enqueuers: ["kyle-sexton"] } },
  );
});

test("the label plan: the path label on a record-path merge, post-merge:reverted on its revert, nothing on lanes", () => {
  const prs = [
    pr(10),
    pr(11, { labels: ["merge-path:owner-agent"] }),
    pr(12, { labels: ["merge-path:owner-agent"] }),
    pr(13, { by: lanesBot }),
    pr(14, { body: "Closes #1" }),
  ];
  assert.deepEqual(labelPlan(prs, { identity: IDENTITY, paths: PATHS, reverted: new Set([12, 13]) }), [
    { number: 10, labels: ["merge-path:owner-agent"] },
    { number: 12, labels: ["post-merge:reverted"] },
  ]);
});

// A fake gh: answers the pull-request query from `nodes`, 404s each label in
// `missing`, and logs every write.
function fakeGh({ nodes, missing = [], failLabel = [] }) {
  const writes = [];
  const gh = (args) => {
    if (args[1] === "graphql") {
      const repository = Object.fromEntries(nodes.map((n) => [`p${n.number}`, n]));
      return JSON.stringify({ data: { repository } });
    }
    if (args[1] === "-X") {
      writes.push(args.slice(3));
      if (failLabel.some((n) => args[3] === `repos/${REPO}/issues/${n}/labels`)) throw new Error("HTTP 403");
      return "{}";
    }
    if (missing.some((l) => args[1] === `repos/${REPO}/labels/${encodeURIComponent(l)}`)) throw new Error("HTTP 404");
    return "{}";
  };
  return { gh, writes };
}
const node = (number, { login = "kyle-sexton", typename = "User", body = SESSION_BODY, commits = [TRAILER], labels = [] } = {}) => ({
  number,
  body,
  labels: { nodes: labels.map((name) => ({ name })) },
  commits: { nodes: commits.map((message) => ({ commit: { message } })) },
  timelineItems: { nodes: [{ actor: { __typename: typename, login }, enqueuer: { __typename: typename, login } }] },
});

test("label: an owner-login agent merge gets its path label, its revert post-merge:reverted, and a lane PR nothing", () => {
  const { gh, writes } = fakeGh({
    nodes: [node(20), node(21, { labels: ["merge-path:owner-agent"] }), node(22, { login: "melodic-automation-lanes", typename: "Bot" })],
    missing: ["post-merge:reverted"],
  });
  const result = label({ repo: REPO, merged: [20], reverted: [21, 22], config: CONFIG, gh, log: () => {} });
  assert.equal(result.failed, 0);
  assert.deepEqual(writes, [
    [`repos/${REPO}/issues/20/labels`, "-f", "labels[]=merge-path:owner-agent"],
    [`repos/${REPO}/labels`, "-f", "name=post-merge:reverted", "-f", "color=c5def5", "-f", "description=Post-merge accounting record (README.md, Merge paths)"],
    [`repos/${REPO}/issues/21/labels`, "-f", "labels[]=post-merge:reverted"],
  ]);
  assert.ok(!writes.some((w) => w[0].includes("/issues/22")), "the lane PR is not labeled");
  assert.ok(!writes.some((w) => w[0] === `repos/${REPO}/issues` || w[0].endsWith("/comments")), "no issue and no comment");
});

test("label: a revert of an unlabeled owner-agent PR adds both labels in one write", () => {
  const { gh, writes } = fakeGh({ nodes: [node(30)] });
  label({ repo: REPO, merged: [], reverted: [30], config: CONFIG, gh, log: () => {} });
  assert.deepEqual(writes, [[`repos/${REPO}/issues/30/labels`, "-f", "labels[]=merge-path:owner-agent", "-f", "labels[]=post-merge:reverted"]]);
});

test("label: a failed label write is counted, the rest still go", () => {
  const { gh, writes } = fakeGh({ nodes: [node(40), node(41)], failLabel: [40] });
  const result = label({ repo: REPO, merged: [40, 41], reverted: [], config: CONFIG, gh, log: () => {} });
  assert.equal(result.failed, 1);
  assert.equal(writes.at(-1)[0], `repos/${REPO}/issues/41/labels`);
});

test("label: with no record path configured nothing is read or written", () => {
  let calls = 0;
  const result = label({ repo: REPO, merged: [50], reverted: [], config: { agentIdentity: IDENTITY, paths: {} }, gh: () => (calls++, "{}"), log: () => {} });
  assert.deepEqual(result, { plan: [], failed: 0 });
  assert.equal(calls, 0);
});

test("rollup: merges, reverts and escapes per path for merges in the window", () => {
  const at = (d) => `2026-10-${d}T12:00:00Z`;
  const merged = [
    pr(100, { labels: ["merge-path:owner-agent"], mergedAt: at(17) }),
    pr(101, { labels: ["merge-path:owner-agent", "post-merge:reverted"], mergedAt: at(18) }),
    pr(102, { by: lanesBot, mergedAt: at(18) }),
    pr(103, { by: lanesBot, mergedAt: at(19) }),
    pr(104, { by: user("alice"), mergedAt: at(19) }),
    pr(105, { labels: ["merge-path:owner-agent"], mergedAt: at(25) }),
    pr(106, { title: "fix(ci): repair the gate", body: "Refs: #100, https://github.com/o/r/pull/103", by: user("alice"), mergedAt: at(26) }),
    pr(107, { title: "docs: mention #104", body: "Refs: #104", by: user("alice"), mergedAt: at(26) }),
    pr(108, { title: "fix: earlier", body: "Refs: #105", by: user("alice"), mergedAt: at(16) }),
  ];
  const revertRecords = ["<!-- babysit-merge-demotion sha=x signal=revert -->\n\n- Reverted pull request: https://github.com/o/r/pull/102\n"];
  const result = rollup({ repo: REPO, since: "2026-10-17", until: "2026-10-19", merged, revertRecords, identity: IDENTITY });
  assert.deepEqual(result.paths, {
    "owner-agent": { merges: 2, reverts: 1, escapes: 1 },
    lanes: { merges: 2, reverts: 1, escapes: 1 },
    other: { merges: 1, reverts: 0, escapes: 0 },
  });
  assert.equal(
    formatRollup(result),
    [
      "o/r merges 2026-10-17..2026-10-19 (UTC, both days included)",
      "| Path | Merges | Reverts | Escaped defects (cited by a later fix, upper bound) |",
      "|---|---:|---:|---:|",
      "| lanes | 2 | 1 | 1 |",
      "| other | 1 | 0 | 0 |",
      "| owner-agent | 2 | 1 | 1 |",
    ].join("\n"),
  );
});
