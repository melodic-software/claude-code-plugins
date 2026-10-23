// Expected values come from the native-merge plan's arm-merge item and the
// owner answers on it: a lanes App pull request is armed for native auto-merge (squash, at the head
// read) with no session, and is never armed, or is disarmed, while it carries
// a `Hold:` line, do-not-merge or the human-gated label. Its issue link is
// the gate's own rule (docs/conventions/pr-pipeline/README.md, "Eligibility":
// one closing issue, or one plain `Refs: #<n>` issue), read through the gate's
// Python, as is the body hold, babysit_merge_policy.BODY_MERGE_HOLD_RE, so
// the parity tests read their verdicts from Python.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";
import { test } from "node:test";

import {
  ARM_MUTATION,
  BODY_HOLD,
  DETAIL_QUERY,
  DISARM_MUTATION,
  HUMAN_VETO,
  PULLS_QUERY,
  decide,
  READER_EVENTS,
  main,
  pythonRoom,
  readRoom,
  verifyHold,
} from "./enable-auto-merge.mjs";
import { COMMENT_EDITED_QUERY, PULL_OPENED_QUERY, VERIFY_PATH, verdictHold } from "./merge-holds.mjs";
import { VERIFY_PATH as RESOLVER_VERIFY_PATH } from "../pr-verify/resolve-pr.mjs";
import { decide as decideOutcome } from "../work-resolve-issue/report-outcome.mjs";

const REPO = "melodic-software/claude-code-plugins";
const LANES = { __typename: "Bot", login: "melodic-automation-lanes" };
const HEAD = "b".repeat(40);
const ENV = {
  EVENT_NAME: "schedule",
  GITHUB_REPOSITORY: REPO,
  KILL_SWITCH: "proceed",
  REPORT_ONLY: "false",
  LANES_BOT_LOGIN: "melodic-automation-lanes[bot]",
  TRACKER_CONFIG: "/nonexistent/.work-item-tracker.json",
  RESOLVED_CONFIG: fileURLToPath(new URL("./fixtures/enable-auto-merge-resolved.json", import.meta.url)),
};

const pull = (number, overrides = {}) => ({
  id: `PR_${number}`,
  number,
  isDraft: false,
  isCrossRepository: false,
  headRefOid: HEAD,
  baseRefOid: "d".repeat(40),
  body: `Closes #${number + 1000}\n\n## Summary\n\nDone.`,
  author: LANES,
  labels: { totalCount: 0, nodes: [] },
  autoMergeRequest: null,
  ...overrides,
});
// One pull request's comments, reviews, inline comments and newest
// auto-merge-disabled event, as DETAIL_QUERY returns them.
const page = (nodes = []) => ({ totalCount: nodes.length, nodes });
function detail({ comments = [], reviews = [], inline = [], disabledBy = null } = {}) {
  return {
    comments: page(comments),
    reviews: page(reviews),
    reviewThreads: page(inline.length ? [{ comments: page(inline) }] : []),
    timelineItems: { nodes: disabledBy ? [{ actor: disabledBy }] : [] },
  };
}
const said = (login, body, at, association = "OWNER", typename = "User") => ({
  author: { __typename: typename, login },
  body,
  createdAt: at,
  authorAssociation: association,
});
const PASSED = { refusal: null, head: HEAD, ineligible: null, reviews: null };
const COST_LINK = `https://github.com/${REPO}/issues/1040#issuecomment-7`;
const COST_COMMENT = {
  issue_url: `https://api.github.com/repos/${REPO}/issues/1040`,
  user: { login: "kyle-sexton", id: 5, type: "User" },
  performed_via_github_app: null,
  body: "**Decision recorded.** Cost: approve it.",
  node_id: "IC_7",
  created_at: "2026-10-22T12:00:00Z",
};
// lane-room's answer for a lane with room: nothing in flight of five.
const ROOM = { refusal: null, unreadable: null, count: 0, cap: 5, queued: [] };
const room = (answer = ROOM) => async () => answer;
const labels = (...names) => ({ totalCount: names.length, nodes: names.map((name) => ({ name })) });

function world(pulls, { failArm = false } = {}) {
  const calls = [];
  const github = async (method, path, body) => {
    calls.push({ method, path, body });
    const listing = /^\/repos\/melodic-software\/claude-code-plugins\/pulls\/([0-9]+)\/files\?per_page=100&page=([0-9]+)$/.exec(path);
    if (method === "GET" && listing) {
      const files = pulls.find((candidate) => candidate.number === Number(listing[1]))?.files ?? [{ filename: "plugins/work-items/README.md" }];
      return files.slice((Number(listing[2]) - 1) * 100, Number(listing[2]) * 100);
    }
    // The cost decision reads (merge-holds.costDecision): the owner's comment
    // 7 on pull request 40's closing issue, and each pull request closes its own
    // number plus 1000.
    if (method === "GET" && path === "/repos/melodic-software/claude-code-plugins/issues/comments/7") {
      return COST_COMMENT;
    }
    assert.equal(`${method} ${path}`, "POST /graphql");
    if (body.query === PULL_OPENED_QUERY) {
      const nodes = [{ number: body.variables.number + 1000, repository: { nameWithOwner: REPO } }];
      return { data: { repository: { pullRequest: { createdAt: "2026-10-22T10:00:00Z", closingIssuesReferences: { totalCount: 1, nodes } } } } };
    }
    if (body.query === COMMENT_EDITED_QUERY) {
      return { data: { node: { lastEditedAt: null } } };
    }
    if (body.query === PULLS_QUERY) {
      assert.deepEqual(body.variables, { owner: "melodic-software", name: "claude-code-plugins", after: null });
      return { data: { repository: { pullRequests: { pageInfo: { hasNextPage: false, endCursor: null }, nodes: pulls } } } };
    }
    if (body.query === DETAIL_QUERY) {
      const found = pulls.find((candidate) => candidate.number === body.variables.number);
      return { data: { repository: { pullRequest: detail(found?.discussion) } } };
    }
    if (body.query === ARM_MUTATION && failArm) {
      throw new Error("POST /graphql (GraphQL errors) failed with status 200");
    }
    return { data: {} };
  };
  // The gate's verifier evidence: a pull request's `verdict` (a report, or
  // an Error to throw), else a pass at its head.
  const verified = [];
  const verify = async ({ number, headRefOid: head }) => {
    verified.push(number);
    const found = pulls.find((candidate) => candidate.number === number);
    if (found?.verdict instanceof Error) {
      throw found.verdict;
    }
    return found?.verdict ?? { refusal: null, head, ineligible: null, reviews: null };
  };
  const writes = () =>
    calls
      .filter(({ method, body }) => method === "POST" && ![PULLS_QUERY, DETAIL_QUERY, PULL_OPENED_QUERY, COMMENT_EDITED_QUERY].includes(body.query))
      .map(({ body }) => ({ mutation: body.query === ARM_MUTATION ? "arm" : body.query === DISARM_MUTATION ? "disarm" : "?", ...body.variables }));
  return { github, writes, verify, verified, calls };
}

async function run(pulls, env = {}, options = {}, lane = ROOM) {
  const { github, writes, verify, verified } = world(pulls, options);
  const lines = [];
  const log = console.log;
  console.log = (line) => lines.push(line);
  try {
    const code = await main({ env: { ...ENV, ...env }, github, verify, room: room(lane) });
    return { code, writes: writes(), lines, verified };
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

test("only the lanes App's ready pull requests from this repository are armed", async () => {
  const { writes } = await run([
    pull(1, { author: { __typename: "User", login: "kyle-sexton" } }),
    pull(2, { author: { __typename: "Bot", login: "dependabot" } }),
    pull(3, { author: { __typename: "User", login: "melodic-automation-lanes" } }),
    pull(4, { isDraft: true }),
    pull(5, { isCrossRepository: true }),
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

// The body the issue lane opens its pull request with (report-outcome.mjs
// decide), so a change to either side that stops a clean lane pull request
// from arming, or arms a held one, fails here.
test("report-outcome's own Closes and Refs pull request bodies arm, and its hold bodies do not", () => {
  const plan = (overrides) =>
    decideOutcome({
      outcome: { exit: "done", reason: "", title: "docs(work-items): fix a typo", summary: "Fixed it." },
      issueNumber: 77,
      issueLabels: ["agent-ready"],
      branch: "work-resolve-issue/issue-77-123-1",
      changedFiles: ["plugins/work-items/README.md"],
      holdPaths: [".github/**"],
      checks: { tip: HEAD, results: [] },
      ...overrides,
    });
  const verdict = (overrides) => {
    const opened = plan(overrides);
    assert.equal(opened.action, "open-pr");
    // Files outside the hold paths, so only the body decides.
    return decide(pull(1, { body: opened.body }), { bot: "melodic-automation-lanes", humanGated: "needs-human", holdPaths: [".github/**"] }, { ...detail(), files: [], verify: PASSED });
  };
  assert.deepEqual(verdict({}), { action: "arm", reason: "no hold" });
  assert.equal(verdict({ humanMerge: true }).action, "none");
  assert.equal(verdict({ changedFiles: [".github/workflows/x.yml"] }).action, "none");
  assert.deepEqual(verdict({ outcome: { exit: "done", reason: "", title: "t", summary: "s", link: "refs" } }), { action: "arm", reason: "no hold" });
});

// The gate's human veto (babysit_merge.human_veto_logins): each member's
// newest comment, review or inline comment with text decides, so a later
// comment lifts the hold; a non-member's, a bot's or an empty one counts for
// nothing. Native auto-merge skips that gate, so the arm rule applies it.
test("a member's newest comment saying not to merge holds, and a later one lifts it", async () => {
  const veto = said("kyle-sexton", "Please don't merge this yet.", "2026-10-23T10:00:00Z");
  const { code, writes } = await run([
    pull(1, { discussion: { comments: [veto] } }),
    pull(2, { discussion: { comments: [veto, said("kyle-sexton", "Go ahead.", "2026-10-23T11:00:00Z")] } }),
    pull(3, { discussion: { comments: [said("someone", "do not merge", "2026-10-23T10:00:00Z", "CONTRIBUTOR")] } }),
    pull(4, { discussion: { comments: [said("codex", "do not merge", "2026-10-23T10:00:00Z", "NONE", "Bot")] } }),
    pull(5, { discussion: { reviews: [{ ...veto, createdAt: undefined, submittedAt: veto.createdAt }] } }),
    pull(6, { discussion: { inline: [said("kyle-sexton", "do-not merge until the canary", "2026-10-23T10:00:00Z", "MEMBER")] } }),
    pull(7, { discussion: { comments: [veto, said("kyle-sexton", "", "2026-10-23T11:00:00Z")] } }),
  ]);
  assert.equal(code, 0);
  assert.deepEqual(
    writes.map(({ id }) => id),
    ["PR_2", "PR_3", "PR_4"],
  );
});

test("an armed pull request a member now vetoes is disarmed", async () => {
  const { writes } = await run([
    pull(1, { autoMergeRequest: {}, discussion: { comments: [said("kyle-sexton", "do not merge", "2026-10-23T10:00:00Z")] } }),
  ]);
  assert.deepEqual(writes, [{ mutation: "disarm", id: "PR_1" }]);
});

test("a pull request whose discussion cannot all be read is not armed", async () => {
  const cut = { totalCount: 101, nodes: [] };
  const options = { bot: LANES.login, humanGated: "needs-human", holdPaths: [] };
  assert.equal(decide(pull(1), options, { ...detail(), files: [], verify: PASSED }).action, "arm");
  const held = (pr) => decide(pull(1), options, { ...detail(), files: [], ...pr });
  assert.equal(held({ comments: cut }).action, "none");
  assert.equal(held({ reviews: cut }).action, "none");
  assert.equal(held({ reviewThreads: cut }).action, "none");
  assert.equal(held({ reviewThreads: page([{ comments: cut }]) }).action, "none");
  // A read that failed leaves it as it is, armed or not, until the next run.
  assert.equal(decide(pull(1), options, null).action, "none");
  assert.equal(decide(pull(1, { autoMergeRequest: {} }), options, null).action, "none");
});

test("auto-merge a person turned off stays off; one the lanes App turned off is armed again", async () => {
  const { writes } = await run([
    pull(1, { discussion: { disabledBy: { __typename: "User", login: "kyle-sexton" } } }),
    pull(2, { discussion: { disabledBy: { __typename: "Bot", login: "melodic-automation-lanes" } } }),
  ]);
  assert.deepEqual(writes, [{ mutation: "arm", id: "PR_2", head: HEAD }]);
});

test("the comment veto agrees with the gate's HUMAN_MERGE_VETO_RE", () => {
  const bodies = ["do not merge", "Don't merge", "don’t merge", "dont-merge", "do-not merge", "Do NOT\nmerge", "donut merge", "merge it", "doesn't merge", ""];
  const scripts = fileURLToPath(new URL("../../../plugins/source-control/skills/babysit-prs/scripts", import.meta.url));
  const python = spawnSync(
    "python3",
    ["-c", "import json,sys\nfrom babysit_merge import HUMAN_MERGE_VETO_RE as R\nprint(json.dumps([bool(R.search(b)) for b in json.load(sys.stdin)]))"],
    { cwd: scripts, input: JSON.stringify(bodies), encoding: "utf8" },
  );
  assert.equal(python.status, 0, python.stderr);
  const expected = JSON.parse(python.stdout);
  assert.deepEqual(
    bodies.map((body) => HUMAN_VETO.test(body)),
    expected,
  );
  assert.ok(expected.includes(true) && expected.includes(false));
});

// The merge lane's denied paths (report-outcome.readHoldPaths), on the head's
// files now: report-outcome's Hold: line covers only the files at opening, and
// a later push can add a held path to a pull request that is already armed.
test("a pull request whose head now changes a hold path is not armed, or is disarmed", async () => {
  const { writes } = await run([
    pull(1, { files: [{ filename: ".github/workflows/x.yml" }] }),
    pull(2, { autoMergeRequest: {}, files: [{ filename: "plugins/a/README.md" }, { filename: "docs/a.md", previous_filename: ".github/a.md" }] }),
    pull(3, { files: Array.from({ length: 301 }, (_, index) => ({ filename: `docs/${index}.md` })) }),
    pull(4, { files: [{ filename: "docs/held.md" }] }),
    pull(5),
  ]);
  assert.deepEqual(writes, [
    { mutation: "disarm", id: "PR_2" },
    { mutation: "arm", id: "PR_5", head: HEAD },
  ]);
});

// The gate scores the marketplace manifest HIGH (babysit_risk.is_manifest_path),
// so it is a hold path like every plugin manifest.
test("a pull request whose head changes the marketplace manifest is not armed, or is disarmed", () => {
  const options = { bot: LANES.login, humanGated: "needs-human", holdPaths: [] };
  const files = ["docs/a.md", ".claude-plugin/marketplace.json"];
  assert.deepEqual(decide(pull(1), options, { ...detail(), files, verify: PASSED }), {
    action: "none",
    reason: "it changes .claude-plugin/marketplace.json, a hold path",
  });
  assert.equal(decide(pull(1, { autoMergeRequest: {} }), options, { ...detail(), files, verify: PASSED }).action, "disarm");
});

// The gate holds a cost path (babysit_risk.COST_PATHS) until the body links
// the owner's cost decision (babysit_merge_policy.cost_decision).
test("a cost path holds until the body links the owner's cost decision", async () => {
  const options = { bot: LANES.login, humanGated: "needs-human", holdPaths: [] };
  const files = ["infra/Pulumi.prod.yaml"];
  assert.deepEqual(decide(pull(1), options, { ...detail(), files, verify: PASSED }), {
    action: "none",
    reason: "it changes infra/Pulumi.prod.yaml, a cost path",
  });
  assert.equal(decide(pull(1, { autoMergeRequest: {} }), options, { ...detail(), files, verify: PASSED }).action, "disarm");
  assert.equal(decide(pull(1), options, { ...detail(), files, costDecision: COST_LINK, verify: PASSED }).action, "arm");

  const dir = mkdtempSync(join(tmpdir(), "enable-auto-merge-"));
  writeFileSync(join(dir, "actors.json"), JSON.stringify({ actors: [{ kind: "human", login: "kyle-sexton", id: 5 }] }));
  const cost = [{ filename: "plugins/multi-agent/reference/defaults.yaml" }];
  const decided = `Closes #1040\n\nCost decision: ${COST_LINK}`;
  const { writes } = await run(
    [pull(40, { files: cost, body: decided }), pull(41, { files: cost }), pull(42, { files: cost, body: decided })],
    { TRUSTED_ACTORS: join(dir, "actors.json") },
  );
  // Pull request 41 links no decision; 42 closes a different issue, so pull
  // request 40's decision does not cover it.
  assert.deepEqual(writes, [{ mutation: "arm", id: "PR_40", head: HEAD }]);
  // A changed file's name cannot start a workflow command on its own line.
  const { lines } = await run([pull(43, { files: [{ filename: "x\n::warning::forged/main.tf" }] })]);
  assert.ok(lines.some((line) => line.includes("x ::warning::forged/main.tf, a cost path")));
  assert.ok(!lines.some((line) => /(^|\n)::warning::/.test(line)));
  // Not on the trusted-actor list, the commenter decides nothing.
  assert.deepEqual((await run([pull(40, { files: cost, body: decided })], { TRUSTED_ACTORS: "/nonexistent/actors.json" })).writes, []);
});

// ci-status runs merge-holds.mjs on the live files with the base config's
// denied paths, by the same pathHold that decides arming above.
test("merge-holds.mjs holds a changed or renamed-from hold path from the command line", () => {
  const dir = mkdtempSync(join(tmpdir(), "merge-holds-"));
  const head = "0123456789abcdef0123456789abcdef01234567";
  const cli = (files, denied, reviews = []) => {
    writeFileSync(join(dir, "body"), "Closes #1");
    writeFileSync(join(dir, "discussion"), reviews.map((row) => JSON.stringify(row)).join("\n"));
    writeFileSync(join(dir, "actors"), JSON.stringify({ actors: [{ kind: "human", login: "ana", id: 5 }] }));
    writeFileSync(join(dir, "files"), files.map((row) => JSON.stringify(row)).join("\n"));
    writeFileSync(join(dir, "denied"), JSON.stringify(denied));
    const args = [...["7", "body", "discussion", "files", "denied", "actors"].map((name, index) => (index ? join(dir, name) : name)), head];
    return spawnSync(process.execPath, [fileURLToPath(new URL("./merge-holds.mjs", import.meta.url)), ...args], { encoding: "utf8" });
  };
  assert.equal(cli([["docs/a.md"]], ["docs/held.md"]).status, 0);
  assert.match(cli([[".github/workflows/.x.yml"]], []).stdout, /it changes \.github\/workflows\/\.x\.yml, a hold path/);
  assert.match(cli([["plugins/a/.hidden"]], ["plugins/**"]).stdout, /it changes plugins\/a\/\.hidden, a hold path/);
  assert.equal(cli([["plugins/a/x.md"]], ["plugins/*.md"]).status, 0);
  const renamed = cli([["docs/a.md", ".github/a.md"]], []);
  assert.equal(renamed.status, 1);
  assert.match(renamed.stdout, /it changes \.github\/a\.md, a hold path/);
  assert.match(cli([["docs/held.md"]], ["docs/held.md"]).stdout, /it changes docs\/held\.md, a hold path/);
  assert.match(cli([["docs/a.md"]], "docs/held.md").stdout, /the hold paths could not be read/);
  const approve = (id, commit) => ({ user: { login: `u${id}`, id, type: "User" }, state: "APPROVED", commit_id: commit, submitted_at: "2026-10-23T11:00:00Z" });
  assert.equal(cli([["docs/held.md"]], ["docs/held.md"], [approve(5, head)]).status, 0);
  assert.equal(cli([["docs/held.md"]], ["docs/held.md"], [approve(6, head)]).status, 1);
  assert.equal(cli([["docs/held.md"]], ["docs/held.md"], [approve(5, "f".repeat(40))]).status, 1);
  assert.equal(cli([["docs/a.md"]], "docs/held.md", [approve(5, head)]).status, 1);
});

test("hold paths that cannot be read arm nothing", async () => {
  const { writes } = await run([pull(1)], { RESOLVED_CONFIG: "/nonexistent/resolved-config.json" });
  assert.deepEqual(writes, []);
});

// pr-merge's gate merges only on a pr-verify pass at the head, FAILs at fewer
// than merge.max-verify-fails heads (babysit_verify_evidence.py), and native
// auto-merge must not merge what the gate would refuse.
test("no pass at the head, a FAIL or the repeated-FAIL cap arms nothing", async () => {
  const { code, writes, verified } = await run([
    pull(1, { verdict: { refusal: "verify:missing", head: HEAD } }),
    pull(2, { verdict: { refusal: "verify:fail", head: HEAD } }),
    pull(3, { verdict: { refusal: "verify:repeated-fail", head: HEAD, needsHuman: true } }),
    pull(4, { verdict: { refusal: "verify:earlier-fail", head: HEAD } }),
    pull(5, { verdict: { refusal: null, head: "c".repeat(40) } }),
    pull(6, { verdict: new Error("gh: rate limited") }),
    pull(7, { verdict: { refusal: "verify:unreadable", head: HEAD } }),
    pull(8),
  ]);
  assert.equal(code, 0);
  assert.deepEqual(verified, [1, 2, 3, 4, 5, 6, 7, 8]);
  assert.deepEqual(writes, [{ mutation: "arm", id: "PR_8", head: HEAD }]);
});

test("an armed pull request whose head lost its pass, or passed the cap, is disarmed", async () => {
  const armed = { enabledAt: "2026-10-23T10:00:00Z" };
  const { writes, lines } = await run([
    // Armed on a passing head, then pushed: the gate finds no verdict at the new head.
    pull(1, { autoMergeRequest: armed, verdict: { refusal: "verify:missing", head: HEAD } }),
    pull(2, { autoMergeRequest: armed, verdict: { refusal: "verify:repeated-fail", head: HEAD } }),
    pull(3, { autoMergeRequest: armed, verdict: new Error("listing failed") }),
    pull(4, { autoMergeRequest: armed }),
  ]);
  assert.deepEqual(writes, [
    { mutation: "disarm", id: "PR_1" },
    { mutation: "disarm", id: "PR_2" },
    { mutation: "disarm", id: "PR_3" },
  ]);
  assert.ok(lines.some((line) => /#2 disarmed: pr-merge's gate refuses its verifier verdict \(verify:repeated-fail\)/.test(line)));
});

test("the verdict is read only for a lanes App pull request nothing else holds", async () => {
  const { writes, verified } = await run([
    pull(1, { author: { __typename: "User", login: "kyle-sexton" } }),
    pull(2, { labels: labels("do-not-merge") }),
    pull(3, { isDraft: true }),
    pull(4, { discussion: { comments: [said("kyle-sexton", "do not merge", "2026-10-23T10:00:00Z")] } }),
    pull(5, { discussion: { disabledBy: { __typename: "User", login: "kyle-sexton" } } }),
  ]);
  assert.deepEqual(writes, []);
  assert.deepEqual(verified, []);
});

test("verifyHold allows only the reader's null refusal at the head read", () => {
  assert.equal(verifyHold(PASSED, HEAD), null);
  assert.match(verifyHold({ refusal: null, head: "c".repeat(40) }, HEAD), /another head/);
  assert.match(verifyHold(null, HEAD), /could not be read/);
  assert.match(verifyHold({ head: HEAD }, HEAD), /could not be read/);
  assert.match(verifyHold({ refusal: "verify:too-old", head: HEAD, ineligible: null }, HEAD), /verify:too-old/);
  // The link's answer: a refusal names it, and a line without one allows nothing.
  assert.match(verifyHold({ refusal: "verify:ineligible", head: HEAD, ineligible: "refs-issues:2" }, HEAD), /does not take its issue link \(refs-issues:2\)/);
  assert.match(verifyHold({ refusal: null, head: HEAD }, HEAD), /issue link could not be read/);
  assert.match(verifyHold({ refusal: null, head: HEAD, ineligible: false }, HEAD), /issue link could not be read/);
  // The review lanes' answer: a hold names it, and a line without one allows nothing.
  assert.match(verifyHold({ refusal: null, head: HEAD, ineligible: null, reviews: "security-finding: 1 open" }, HEAD), /holds it on its review lanes \(security-finding: 1 open\)/);
  assert.match(verifyHold({ refusal: null, head: HEAD, ineligible: null }, HEAD), /review lanes could not be read/);
});

// The merge queue's check (merge-holds.mjs verdictHold): a pass counts only
// from pr-verify.yml's completed, successful workflow_run run on main here.
test("verdictHold counts a pass only from a successful pr-verify run on main", () => {
  const run = (overrides = {}) => ({
    id: 11,
    path: VERIFY_PATH,
    event: "workflow_run",
    head_branch: "main",
    status: "completed",
    conclusion: "success",
    repository: { full_name: REPO },
    head_repository: { full_name: REPO },
    ...overrides,
  });
  const hold = (records) => verdictHold(Array.isArray(records) ? records.map((record) => ({ runId: 11, ...record })) : records, REPO);
  assert.equal(hold([{ verdict: "pass", run: run() }]), null);
  assert.equal(hold([{ verdict: "pass-notes", run: run() }]), null);
  assert.equal(hold([{ verdict: "pass", run: run({ conclusion: "failure" }) }, { verdict: "pass-notes", run: run() }]), null);
  for (const bad of [
    { path: ".github/workflows/other.yml" },
    { event: "pull_request" },
    { head_branch: "feature" },
    { status: "in_progress", conclusion: null },
    { conclusion: "failure" },
    { repository: { full_name: "fork/claude-code-plugins" } },
    { head_repository: { full_name: "fork/claude-code-plugins" } },
  ]) {
    assert.match(hold([{ verdict: "pass", run: run(bad) }]), /has not passed this head/, JSON.stringify(bad));
  }
  assert.match(hold([{ verdict: "fail", run: run() }]), /has not passed this head/);
  // A record of another run than the one its artifact names counts nothing.
  assert.match(hold([{ verdict: "pass", runId: 12, run: run() }]), /has not passed this head/);
  assert.match(hold([{ verdict: "pass", runId: "11", run: run() }]), /has not passed this head/);
  assert.match(hold([]), /has not passed this head/);
  assert.match(hold(null), /could not be read/);
  assert.match(verdictHold([], "not a repo"), /could not be read/);
});

// test_verify_rules_sync.py ties the resolver's path to the gate's WORKFLOW_PATH.
test("verdictHold names the verifier workflow the resolver and the gate name", () => {
  assert.equal(VERIFY_PATH, RESOLVER_VERIFY_PATH);
});

// Only the gate's full reader arms, so native merge refuses what the gate
// refuses; an event run disarms on a hold and reads no verdict.
test("only the scheduled run and a hand-started one read the verdict and arm", () => {
  assert.deepEqual([...READER_EVENTS], ["schedule", "workflow_dispatch"]);
});

test("an event run arms nothing and reads neither discussion nor verdict for an unarmed pull request", async () => {
  for (const event of ["workflow_run", "pull_request_target"]) {
    const { code, writes, verified, lines } = await run([pull(1)], { EVENT_NAME: event });
    assert.equal(code, 0);
    assert.deepEqual(writes, []);
    assert.deepEqual(verified, []);
    assert.ok(lines.some((line) => /#1 left: only a scheduled or hand-started run arms it/.test(line)), event);
  }
});

test("an event run still disarms an armed pull request that now holds", async () => {
  const armed = { enabledAt: "2026-10-23T10:00:00Z" };
  const { writes, verified } = await run(
    [
      pull(1, { autoMergeRequest: armed, labels: labels("do-not-merge") }),
      pull(2, { autoMergeRequest: armed, discussion: { comments: [said("kyle-sexton", "do not merge", "2026-10-23T10:00:00Z")] } }),
      pull(3, { autoMergeRequest: armed }),
    ],
    { EVENT_NAME: "pull_request_target" },
  );
  assert.deepEqual(writes, [
    { mutation: "disarm", id: "PR_1" },
    { mutation: "disarm", id: "PR_2" },
  ]);
  assert.deepEqual(verified, []);
});

test("a reader that fails, prints no JSON or reports another head arms nothing and disarms", async () => {
  const dir = mkdtempSync(join(tmpdir(), "enable-auto-merge-"));
  const scripts = {
    exits: "import sys\nsys.stderr.write('boom\\n')\nsys.exit(1)\n",
    garbage: "print('not json')\n",
    other: `import json\nprint(json.dumps({"refusal": None, "head": "${"c".repeat(40)}"}))\n`,
    unlinked: `import json, sys\nprint(json.dumps({"refusal": None, "head": sys.argv[-1]}))\n`,
    passes: `import json, sys\nassert sys.argv[2:4] == ["--lane-link", "--lane-reviews"] and sys.argv[-4:-2] == ["--base-sha", "${"d".repeat(40)}"], sys.argv\nprint(json.dumps({"refusal": None, "head": sys.argv[-1], "ineligible": None, "reviews": None}))\n`,
  };
  for (const [name, body] of Object.entries(scripts)) {
    writeFileSync(join(dir, `${name}.py`), body);
  }
  const armed = { enabledAt: "2026-10-23T10:00:00Z" };
  for (const [name, want] of [
    ["exits", [{ mutation: "disarm", id: "PR_2" }]],
    ["garbage", [{ mutation: "disarm", id: "PR_2" }]],
    ["other", [{ mutation: "disarm", id: "PR_2" }]],
    ["unlinked", [{ mutation: "disarm", id: "PR_2" }]],
    ["passes", [{ mutation: "arm", id: "PR_1", head: HEAD }]],
  ]) {
    const { github, writes } = world([pull(1), pull(2, { autoMergeRequest: armed })]);
    const env = { ...ENV, EVENT_NAME: "schedule", PATH: process.env.PATH, VERIFY_EVIDENCE_SCRIPT: join(dir, `${name}.py`) };
    const log = console.log;
    console.log = () => {};
    try {
      await main({ env, github, room: room() });
    } finally {
      console.log = log;
    }
    assert.deepEqual(writes(), want, name);
  }
});

// The issue link through the gate's own CLI (`evidence --lane-link`) and rule
// (babysit_merge_policy._linked_issue), GitHub's answers stubbed at gh and the
// verdict a pass at the head, so only the link decides. Expected values are
// docs/conventions/pr-pipeline/README.md "Eligibility": one closing issue, or
// one plain `Refs: #<n>` issue; two `Refs:` issues refuse; a failed read refuses.
test("the gate's link rule arms a Closes or one plain Refs pull request, not two Refs or a failed read", async () => {
  const dir = mkdtempSync(join(tmpdir(), "enable-auto-merge-link-"));
  const wrapper = join(dir, "lane_link.py");
  writeFileSync(
    wrapper,
    `import json, os, subprocess, sys
sys.path.insert(0, os.environ["SCRIPTS"])
from unittest import mock
import babysit_merge_policy as policy
import babysit_postmerge as postmerge
import babysit_verify_evidence as ve

PULLS = json.loads(os.environ["PULLS"])

def gh(args, **_):
    n = next(a for a in args if a.startswith("n="))[2:]
    def ok(data):
        return subprocess.CompletedProcess(args, 0, json.dumps({"data": {"repository": data}}), "")
    if any("issueOrPullRequest" in a for a in args):
        node = {"__typename": "Issue", "number": int(n), "repository": {"nameWithOwner": os.environ["GITHUB_REPOSITORY"]}}
        return ok({"issueOrPullRequest": node})
    found = PULLS[n]
    if found.get("error"):
        return subprocess.CompletedProcess(args, 1, "", "gh: boom (HTTP 502)")
    nodes = [{"number": c, "repository": {"nameWithOwner": os.environ["GITHUB_REPOSITORY"]}} for c in found["closing"]]
    return ok({"pullRequest": {"body": found["body"], "closingIssuesReferences": {"totalCount": len(nodes), "nodes": nodes}}})

def passes(self, number, head, pr=None):
    return ve.Evidence(None, head, (ve.Verdict(head, "pass", 1),), 0)

argv = sys.argv[1:]
cut = argv.index("--base-sha")
del argv[cut : cut + 2]
pr = lambda repo, number: {"number": number, "head": {"sha": argv[-1]}}
with mock.patch.object(policy, "gh_capture", gh), mock.patch.object(postmerge, "gh_capture", gh), mock.patch.object(ve.Reader, "evidence", passes), mock.patch.object(policy, "pull_request", pr), mock.patch.object(ve, "lane_review_refusal", lambda repo, number, pr: None):
    sys.exit(ve.main(argv))
`,
  );
  const body = (text) => `${text}\n\n## Summary\n\nDone.`;
  const pulls = {
    1: { body: body("Closes #11"), closing: [11] },
    2: { body: body("Refs: #12"), closing: [] },
    3: { body: body("Refs: #12\nRefs: #13"), closing: [] },
    4: { body: body("Refs: #12"), closing: [], error: true },
    5: { body: body("Refs: #12\nRefs: #13"), closing: [] },
  };
  const armed = { enabledAt: "2026-10-23T10:00:00Z" };
  const { github, writes } = world([1, 2, 3, 4].map((n) => pull(n, { body: pulls[n].body })).concat(pull(5, { body: pulls[5].body, autoMergeRequest: armed })));
  const scripts = fileURLToPath(new URL("../../../plugins/source-control/skills/babysit-prs/scripts", import.meta.url));
  const env = { ...ENV, PATH: process.env.PATH, SCRIPTS: scripts, PULLS: JSON.stringify(pulls), VERIFY_EVIDENCE_SCRIPT: wrapper };
  const lines = [];
  const log = console.log;
  console.log = (line) => lines.push(line);
  try {
    assert.equal(await main({ env, github, room: room() }), 0);
  } finally {
    console.log = log;
  }
  assert.deepEqual(writes(), [
    { mutation: "arm", id: "PR_1", head: HEAD },
    { mutation: "arm", id: "PR_2", head: HEAD },
    { mutation: "disarm", id: "PR_5" },
  ]);
  assert.ok(lines.some((line) => /#3 left: pr-merge's lane does not take its issue link \(refs-issues:2\)/.test(line)), lines.join("\n"));
  assert.ok(lines.some((line) => /#4 left: pr-merge's lane does not take its issue link \(unreadable: /.test(line)), lines.join("\n"));
});

// An event run reads no link and no verdict, so it never disarms an armed
// Refs pull request on its link; the scheduled run judges it.
test("an event run leaves an armed Refs pull request armed", async () => {
  const armed = { enabledAt: "2026-10-23T10:00:00Z" };
  const { writes, verified } = await run([pull(1, { autoMergeRequest: armed, body: "Refs: #12\n\n## Summary" })], { EVENT_NAME: "pull_request_target" });
  assert.deepEqual(writes, []);
  assert.deepEqual(verified, []);
});

// The gate's run-level refusals, which native auto-merge would skip
// (babysit_merge_policy.lane_room): a demotion record or a rung held off
// stops the lane, and merge.max-in-flight caps what is in flight.
test("while the gate holds its lane off, nothing is armed and armed lane pull requests are disarmed", async () => {
  const armed = { enabledAt: "2026-10-23T10:00:00Z" };
  for (const refusal of ["rung-off:demotion", "rung-off:rungCap", "post-merge:failure:red-main#40"]) {
    const { writes, verified, lines } = await run(
      [pull(1), pull(2, { autoMergeRequest: armed }), pull(3, { author: { __typename: "User", login: "kyle-sexton" }, autoMergeRequest: armed })],
      {},
      {},
      { ...ROOM, refusal },
    );
    assert.deepEqual(writes, [{ mutation: "disarm", id: "PR_2" }], refusal);
    // A held lane reads no verdict.
    assert.deepEqual(verified, [], refusal);
    assert.ok(lines.some((line) => line.includes(`#1 left: pr-merge's gate holds its lane off (${refusal})`)), refusal);
  }
});

test("at merge.max-in-flight nothing more is armed, counting armed pull requests the queue has not taken", async () => {
  const armed = { enabledAt: "2026-10-23T10:00:00Z" };
  // Four in flight by the gate's count, one armed and not queued: the cap of five is reached.
  let result = await run([pull(1), pull(2, { autoMergeRequest: armed })], {}, {}, { ...ROOM, count: 4, cap: 5 });
  assert.deepEqual(result.writes, []);
  assert.deepEqual(result.verified, [2]);
  assert.ok(result.lines.some((line) => /#1 left: merge\.max-in-flight is 5 and 5 merges are in flight/.test(line)));
  // An armed pull request already in the queue is in the gate's count, not counted twice.
  result = await run([pull(1), pull(2, { autoMergeRequest: armed })], {}, {}, { ...ROOM, count: 4, cap: 5, queued: [2] });
  assert.deepEqual(result.writes, [{ mutation: "arm", id: "PR_1", head: HEAD }]);
  // Each arm in the run counts: three in flight of five arms two of three.
  result = await run([pull(1), pull(2), pull(3)], {}, {}, { ...ROOM, count: 3, cap: 5 });
  assert.deepEqual(
    result.writes.map(({ id }) => id),
    ["PR_1", "PR_2"],
  );
});

test("a room that cannot be read arms nothing and disarms nothing", async () => {
  const armed = { enabledAt: "2026-10-23T10:00:00Z" };
  const pulls = [pull(1), pull(2, { autoMergeRequest: armed })];
  for (const lane of [{ ...ROOM, unreadable: "in-flight:merge-queue-unreadable" }, { refusal: null }, null]) {
    const { writes } = await run(pulls, {}, {}, lane);
    assert.deepEqual(writes, [], JSON.stringify(lane));
  }
  const { github, writes } = world(pulls);
  const log = console.log;
  console.log = () => {};
  try {
    await main({
      env: ENV,
      github,
      verify: async ({ headRefOid: head }) => ({ refusal: null, head, ineligible: null, reviews: null }),
      room: async () => {
        throw new Error("lane-room exited 1");
      },
    });
  } finally {
    console.log = log;
  }
  assert.deepEqual(writes(), []);
});

test("an event run reads no room", async () => {
  let asked = 0;
  const { github } = world([pull(1)]);
  const log = console.log;
  console.log = () => {};
  try {
    await main({
      env: { ...ENV, EVENT_NAME: "pull_request_target" },
      github,
      room: async () => {
        asked += 1;
        return ROOM;
      },
    });
  } finally {
    console.log = log;
  }
  assert.equal(asked, 0);
});

test("readRoom takes only lane-room's shape", () => {
  assert.deepEqual(readRoom(ROOM), ROOM);
  for (const bad of [null, "x", { ...ROOM, cap: 0 }, { ...ROOM, count: -1 }, { ...ROOM, queued: ["3"] }, { ...ROOM, refusal: 1 }, { ...ROOM, unreadable: undefined }]) {
    assert.ok(readRoom(bad).unreadable, JSON.stringify(bad));
  }
});

test("pythonRoom passes the post-merge report, the rung cap as read, and the reader's token", async () => {
  const dir = mkdtempSync(join(tmpdir(), "enable-auto-merge-room-"));
  const script = join(dir, "room.py");
  writeFileSync(
    script,
    `import json, os, sys
print(json.dumps({"argv": sys.argv[1:], "token": os.environ.get("GH_TOKEN"), "budget": os.environ.get("API_BUDGET_TOKEN")}))
`,
  );
  const env = { PATH: process.env.PATH, GITHUB_REPOSITORY: REPO, VERIFY_EVIDENCE_SCRIPT: script, POSTMERGE_RESULT: "/tmp/post-merge.json", GH_TOKEN: "lane", BABYSIT_VERIFY_GH_TOKEN: "job" };
  // An empty cap is no cap, so it is passed; an unset one is not, which the gate reads as off.
  assert.deepEqual(await pythonRoom({ ...env, RUNG_CAP: "" })(), {
    argv: ["lane-room", "--repo", REPO, "--postmerge-result", "/tmp/post-merge.json", "--rung-cap", ""],
    token: "job",
    budget: "github-token",
  });
  assert.deepEqual((await pythonRoom(env)()).argv, ["lane-room", "--repo", REPO, "--postmerge-result", "/tmp/post-merge.json"]);
});

// The gate holds on the security lane's open CRITICAL findings
// (babysit_risk LANES, security-finding) and on a review not bound to the
// head, whether or not the lane applied its hold label.
test("a review-lane hold the gate reads arms nothing and disarms an armed pull request", async () => {
  const armed = { enabledAt: "2026-10-23T10:00:00Z" };
  const held = { refusal: null, head: HEAD, ineligible: null, reviews: "security-finding: 1 open" };
  const { writes, lines } = await run([
    pull(1, { verdict: held }),
    pull(2, { autoMergeRequest: armed, verdict: { ...held, reviews: "evidence-unbound:claude-security-review: marker-missing" } }),
    pull(3, { verdict: { refusal: null, head: HEAD, ineligible: null } }),
    pull(4),
  ]);
  assert.deepEqual(writes, [
    { mutation: "disarm", id: "PR_2" },
    { mutation: "arm", id: "PR_4", head: HEAD },
  ]);
  assert.ok(lines.some((line) => line.includes("#1 left: pr-merge's gate holds it on its review lanes (security-finding: 1 open)")));
  assert.ok(lines.some((line) => line.includes("#3 left: its review lanes could not be read")));
});
