// Expected values come from #9276's plan item 8 and the owner answers on it:
// a lanes App pull request is armed for native auto-merge (squash, at the head
// read) with no session, and is never armed, or is disarmed, while it carries
// a `Hold:` line, do-not-merge or the human-gated label. A Refs pull request
// is merged by a person (report-outcome.mjs), so it is never armed. The body
// hold is the gate's own rule, babysit_merge_policy.BODY_MERGE_HOLD_RE, so the
// parity test reads its verdicts from Python.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { test } from "node:test";

import { ARM_MUTATION, BODY_HOLD, DISARM_MUTATION, PULLS_QUERY, decide, main } from "./enable-auto-merge.mjs";

const REPO = "melodic-software/claude-code-plugins";
const LANES = { __typename: "Bot", login: "melodic-automation-lanes" };
const HEAD = "b".repeat(40);
const ENV = {
  GITHUB_REPOSITORY: REPO,
  KILL_SWITCH: "proceed",
  REPORT_ONLY: "false",
  LANES_BOT_LOGIN: "melodic-automation-lanes[bot]",
  TRACKER_CONFIG: "/nonexistent/.work-item-tracker.json",
};

const pull = (number, overrides = {}) => ({
  id: `PR_${number}`,
  number,
  isDraft: false,
  isCrossRepository: false,
  headRefOid: HEAD,
  body: `Closes #${number + 1000}\n\n## Summary\n\nDone.`,
  author: LANES,
  labels: { totalCount: 0, nodes: [] },
  autoMergeRequest: null,
  ...overrides,
});
const labels = (...names) => ({ totalCount: names.length, nodes: names.map((name) => ({ name })) });

function world(pulls, { failArm = false } = {}) {
  const calls = [];
  const github = async (method, path, body) => {
    calls.push({ method, path, body });
    assert.equal(`${method} ${path}`, "POST /graphql");
    if (body.query === PULLS_QUERY) {
      assert.deepEqual(body.variables, { owner: "melodic-software", name: "claude-code-plugins", after: null });
      return { data: { repository: { pullRequests: { pageInfo: { hasNextPage: false, endCursor: null }, nodes: pulls } } } };
    }
    if (body.query === ARM_MUTATION && failArm) {
      throw new Error("POST /graphql (GraphQL errors) failed with status 200");
    }
    return { data: {} };
  };
  const writes = () =>
    calls
      .filter(({ body }) => body.query !== PULLS_QUERY)
      .map(({ body }) => ({ mutation: body.query === ARM_MUTATION ? "arm" : body.query === DISARM_MUTATION ? "disarm" : "?", ...body.variables }));
  return { github, writes };
}

async function run(pulls, env = {}, options = {}) {
  const { github, writes } = world(pulls, options);
  const lines = [];
  const log = console.log;
  console.log = (line) => lines.push(line);
  try {
    const code = await main({ env: { ...ENV, ...env }, github });
    return { code, writes: writes(), lines };
  } finally {
    console.log = log;
  }
}

test("a lanes App pull request with no hold is armed, squash, at the head it read", async () => {
  const { code, writes } = await run([pull(7)]);
  assert.equal(code, 0);
  assert.deepEqual(writes, [{ mutation: "arm", id: "PR_7", head: HEAD }]);
  assert.match(ARM_MUTATION, /mergeMethod: SQUASH, expectedHeadOid: \$head/);
});

test("a Hold: line, do-not-merge or the human-gated label leaves it unarmed", async () => {
  const { code, writes } = await run([
    pull(1, { body: "Closes #5\n\nHold: a human merges this\n" }),
    pull(2, { body: "Closes #5\r\n  hold: wait for the canary" }),
    pull(3, { labels: labels("do-not-merge") }),
    pull(4, { labels: labels("Needs-Human") }),
    pull(5, { body: "Closes #5\n\nPlease do not merge yet." }),
  ]);
  assert.equal(code, 0);
  assert.deepEqual(writes, []);
});

test("the human-gated label comes from the tracker config", async () => {
  const config = fileURLToPath(new URL("./fixtures/enable-auto-merge-tracker.json", import.meta.url));
  const { writes } = await run([pull(1, { labels: labels("human-gated") }), pull(2, { labels: labels("needs-human") })], { TRACKER_CONFIG: config });
  assert.deepEqual(writes, [{ mutation: "arm", id: "PR_2", head: HEAD }]);
});

test("an armed pull request that now holds is disarmed", async () => {
  const armed = { enabledAt: "2026-10-23T10:00:00Z" };
  const { code, writes } = await run([
    pull(1, { autoMergeRequest: armed, body: "Closes #5\n\nHold: a human merges this" }),
    pull(2, { autoMergeRequest: armed, labels: labels("needs-human") }),
    pull(3, { autoMergeRequest: armed }),
  ]);
  assert.equal(code, 0);
  assert.deepEqual(writes, [
    { mutation: "disarm", id: "PR_1" },
    { mutation: "disarm", id: "PR_2" },
  ]);
});

test("only the lanes App's ready Closes pull requests from this repository are armed", async () => {
  const { writes } = await run([
    pull(1, { author: { __typename: "User", login: "kyle-sexton" } }),
    pull(2, { author: { __typename: "Bot", login: "dependabot" } }),
    pull(3, { author: { __typename: "User", login: "melodic-automation-lanes" } }),
    pull(4, { isDraft: true }),
    pull(5, { isCrossRepository: true }),
    pull(6, { body: "Refs: #12\n\n## Summary" }),
    pull(7, { body: "## Summary\n\nCloses #12" }),
    pull(8, { headRefOid: "abc" }),
    pull(9, { labels: { totalCount: 101, nodes: [] } }),
  ]);
  assert.deepEqual(writes, []);
});

test("report-only arms and disarms nothing", async () => {
  const { code, writes, lines } = await run([pull(1), pull(2, { autoMergeRequest: {}, labels: labels("do-not-merge") })], { REPORT_ONLY: "true" });
  assert.equal(code, 0);
  assert.deepEqual(writes, []);
  assert.ok(lines.some((line) => /#1 would arm \(report-only\)/.test(line)));
  assert.ok(lines.some((line) => /#2 would disarm \(report-only\)/.test(line)));
});

test("the kill switch stops it before any read", async () => {
  const { code, writes } = await run([pull(1)], { KILL_SWITCH: "" });
  assert.equal(code, 0);
  assert.deepEqual(writes, []);
});

test("a failed arm fails the run and still reaches the next pull request", async () => {
  const { code, writes, lines } = await run([pull(1), pull(2, { autoMergeRequest: {}, labels: labels("do-not-merge") })], {}, { failArm: true });
  assert.equal(code, 1);
  assert.deepEqual(writes, [
    { mutation: "arm", id: "PR_1", head: HEAD },
    { mutation: "disarm", id: "PR_2" },
  ]);
  assert.ok(lines.some((line) => line.startsWith("::error title=enable-auto-merge::#1 arm")));
});

test("a bad bot login or repository fails red", async () => {
  assert.equal((await run([pull(1)], { LANES_BOT_LOGIN: "kyle-sexton" })).code, 1);
  assert.equal((await run([pull(1)], { GITHUB_REPOSITORY: "nope" })).code, 1);
});

test("decide leaves a pull request with no labels read alone", () => {
  assert.deepEqual(decide(pull(1, { labels: null }), { bot: LANES.login, humanGated: "needs-human" }), {
    action: "none",
    reason: "its labels could not all be read",
  });
});

test("the body hold agrees with the gate's BODY_MERGE_HOLD_RE", () => {
  const bodies = [
    "Hold: a human merges this",
    "Closes #1\n\nHold: x",
    "Closes #1\r\n   HOLD: x",
    "Closes #1\rhold: x",
    "Closes #1\n\nthe hold: is not at the line start",
    "Closes #1\n\nDon't merge",
    "Closes #1\n\ndon’t  merge this",
    "Closes #1\n\nDo NOT\nmerge",
    "Closes #1\n\ndonut merge",
    "Closes #1\n\nwhat to do: merge it",
    "Closes #1\n\nnothing here",
    "",
  ];
  const scripts = fileURLToPath(new URL("../../../plugins/source-control/skills/babysit-prs/scripts", import.meta.url));
  const python = spawnSync(
    "python3",
    ["-c", "import json,sys\nfrom babysit_merge_policy import BODY_MERGE_HOLD_RE as R\nprint(json.dumps([bool(R.search(b)) for b in json.load(sys.stdin)]))"],
    { cwd: scripts, input: JSON.stringify(bodies), encoding: "utf8" },
  );
  assert.equal(python.status, 0, python.stderr);
  const expected = JSON.parse(python.stdout);
  assert.deepEqual(
    bodies.map((body) => BODY_HOLD.test(body)),
    expected,
  );
  assert.ok(expected.includes(true) && expected.includes(false));
});
