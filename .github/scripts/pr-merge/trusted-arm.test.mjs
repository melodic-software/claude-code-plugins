// test-scope: plugins/source-control/.claude-plugin/plugin.json
import assert from "node:assert/strict";
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { test } from "node:test";

import { ARM_MUTATION, AUTO_MERGE_STATE_QUERY, DETAIL_QUERY, DISARM_MUTATION, PULLS_QUERY, SKIP_STATE_PREFIX, WAKE_OUTPUT, decideTrusted, main, pinBody, pinMoved, pinned, pythonLaneSource, pythonVerify, unpinBody } from "./enable-auto-merge.mjs";
import { COMMENT_EDITED_QUERY, LANES_APP_LOGIN, PULL_OPENED_QUERY, pinHold } from "./merge-holds.mjs";
import { GitHubError } from "../lib/github-client.mjs";
import { tempDir } from "../../../lib/test-tmp.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const RECORDED = JSON.parse(readFileSync(join(HERE, "fixtures/trusted-arm-pulls.json"), "utf8"));
const RECORDED_DETAIL = JSON.parse(readFileSync(join(HERE, "fixtures/trusted-arm-detail.json"), "utf8"));
const DETAIL_PULL = RECORDED_DETAIL.answer.data.repository.pullRequest;
const RECORDED_PIN = DETAIL_PULL.comments.nodes.find((node) => node.body.startsWith("<!-- babysit-merge-pin "));
const REPO = "melodic-software/claude-code-plugins";
const VERIFY_EVIDENCE_SCRIPT = join(HERE, "../../../plugins/source-control/skills/babysit-prs/scripts/babysit_verify_evidence.py");
const ENV = {
  EVENT_NAME: "schedule",
  GITHUB_REPOSITORY: REPO,
  KILL_SWITCH: "proceed",
  REPORT_ONLY: "false",
  LANES_BOT_LOGIN: "melodic-automation-lanes[bot]",
  TRACKER_CONFIG: "/nonexistent/work-items.yaml",
  RESOLVED_CONFIG: join(HERE, "fixtures/enable-auto-merge-resolved.json"),
  TRUSTED_ACTORS: join(HERE, "fixtures/trusted-actors.json"),
  VERIFY_EVIDENCE_SCRIPT,
};
const LANES_APP = { __typename: "Bot", login: "melodic-automation-lanes", databaseId: 337595936 };
const CLEAN_HEAD = "c".repeat(40);
const CLEAN_FILES = ["plugins/work-items/README.md", ".changes/work-items/fix-a1b2c3d4.md"];

function recorded(number, overrides = {}) {
  const rec = RECORDED[number];
  return {
    id: `PR_${number}`,
    number: rec.number,
    isDraft: rec.draft,
    isCrossRepository: rec.head.repo !== REPO,
    isInMergeQueue: false,
    headRefOid: rec.head.sha,
    baseRefOid: "d".repeat(40),
    body: [...rec.body_first_lines, "", "## Summary", "", ...rec.body_hold_lines].join("\n"),
    author: { __typename: rec.user.type, login: rec.user.login, databaseId: rec.user.id },
    labels: { totalCount: rec.labels.length, nodes: rec.labels.map((name) => ({ name })) },
    autoMergeRequest: rec.auto_merge,
    stack: null,
    files: rec.files_page_1 ?? CLEAN_FILES,
    ...overrides,
  };
}

const clean = (overrides = {}) =>
  recorded("19361", { number: 500, id: "PR_500", headRefOid: CLEAN_HEAD, body: "Closes #499\n\n## Summary\n\nDone.", files: CLEAN_FILES, ...overrides });

const COST_LINK = `https://github.com/${REPO}/issues/500#issuecomment-7`;
const COST_COMMENT = {
  issue_url: `https://api.github.com/repos/${REPO}/issues/500`,
  user: { login: "kyle-sexton", id: 153232337, type: "User" },
  performed_via_github_app: null,
  body: '**Decision recorded.** Cost: approve it for #500.\nRow: https://github.com/melodic-software/architecture/blob/main/docs/owner-decisions.md#L10\nOwner, verbatim: "Approve it."',
  node_id: "IC_7",
  created_at: "2026-11-27T12:00:00Z",
};
const BASE_TIP = "3".repeat(40);
const costReads = (method, path, body) => {
  if (method === "POST" && path === "/graphql" && body.query === PULL_OPENED_QUERY) {
    return { data: { repository: { pullRequest: { createdAt: "2026-11-27T10:00:00Z", baseRefName: "main", headRefName: "fix/cost", closingIssuesReferences: { totalCount: 1, nodes: [{ number: 499, repository: { nameWithOwner: REPO } }] } } } } };
  }
  if (method === "POST" && path === "/graphql" && body.query === COMMENT_EDITED_QUERY) {
    return { data: { node: { lastEditedAt: null } } };
  }
  const answers = {
    [`/repos/${REPO}/issues/comments/7`]: COST_COMMENT,
    [`/repos/${REPO}/git/ref/heads/main`]: { ref: "refs/heads/main", object: { type: "commit", sha: BASE_TIP } },
    [`/repos/${REPO}/compare/${BASE_TIP}...${CLEAN_HEAD}`]: { files: [{ filename: "infra/main.tf" }] },
    [`/repos/${REPO}/activity?ref=refs%2Fheads%2Ffix%2Fcost&direction=desc&per_page=100`]: [{ after: CLEAN_HEAD, timestamp: "2026-11-27T10:45:00Z", activity_type: "push", ref: "refs/heads/fix/cost" }],
    [`/repos/${REPO}/actions/runs/9/jobs?filter=all&per_page=100&page=1`]: { jobs: [{ id: 90, name: "PR Review / review-status", completed_at: "2026-11-27T11:00:00Z" }] },
    [`/repos/${REPO}/check-runs/90/annotations?per_page=100&page=1`]: [{ annotation_level: "notice", message: `claude-lane-hold lane=claude-review sha=${CLEAN_HEAD} criteria=cost label=needs-human` }],
  };
  if (method === "GET" && path in answers) {
    return answers[path];
  }
  const runs = /^\/repos\/melodic-software\/claude-code-plugins\/actions\/workflows\/([a-z-]+)\.yml\/runs\?event=pull_request&branch=fix%2Fcost&per_page=100&page=1$/.exec(path);
  if (method === "GET" && runs) {
    return { workflow_runs: runs[1] === "pr-review-hosted" ? [{ id: 9, head_sha: CLEAN_HEAD, head_repository: { full_name: REPO }, created_at: "2026-11-27T10:50:00Z" }] : [] };
  }
  return undefined;
};

const pass = (head) => ({ refusal: null, needsHuman: false, head, atHead: ["pass"], earlierFails: [], ignored: 0, detail: null, supersededAtHead: false });
const refused = (head, refusal) => ({ ...pass(head), refusal, atHead: refusal === "verify:fail" ? ["fail"] : [] });

const ROOM = { refusal: null, unreadable: null, count: 0, cap: 5, queued: [], rung: "C2" };

async function run(pulls, { env = {}, verdicts = {}, laneSource, fail = {}, room = ROOM, now = Date.parse("2026-11-27T15:00:00Z"), mainInputs } = {}) {
  const calls = [];
  const verified = [];
  const disarmed = new Set();
  const github = async (method, path, body) => {
    calls.push({ method, path, query: body?.query, variables: body?.variables, body: body?.body });
    if (method === "POST" && path === "/graphql" && body.query === PULLS_QUERY) {
      return { data: { repository: { pullRequests: { pageInfo: { hasNextPage: false, endCursor: null }, nodes: pulls } } } };
    }
    if (method === "POST" && path === "/graphql" && body.query === ARM_MUTATION) {
      if (fail.firstArm && calls.filter(({ query }) => query === ARM_MUTATION).length === 1) {
        throw new GitHubError(422, "POST /graphql");
      }
      if (fail.arm) {
        throw new Error("POST /graphql failed with status 502");
      }
      return { data: { enablePullRequestAutoMerge: { pullRequest: { autoMergeRequest: { enabledAt: "2026-11-27T15:00:00Z" } } } } };
    }
    if (method === "POST" && path === "/graphql" && body.query === DISARM_MUTATION) {
      disarmed.add(body.variables.id);
      return { data: { disablePullRequestAutoMerge: { clientMutationId: null } } };
    }
    if (method === "POST" && path === "/graphql" && body.query === AUTO_MERGE_STATE_QUERY) {
      const found = pulls.find((candidate) => candidate.id === body.variables.id);
      if (found.reread === "error") {
        throw new Error("POST /graphql failed with status 502");
      }
      const live = { state: "OPEN", headRefOid: found.headRefOid, isInMergeQueue: found.isInMergeQueue, autoMergeRequest: disarmed.has(found.id) ? null : found.autoMergeRequest };
      return { data: { node: { ...live, ...found.reread } } };
    }
    if (method === "POST" && path === "/graphql" && body.query === DETAIL_QUERY) {
      const found = pulls.find((candidate) => candidate.number === body.variables.number);
      if (found.commentsError) {
        throw new Error("POST /graphql failed with status 502");
      }
      const comments = found.comments ?? [];
      const totalCount = found.commentsTotal ?? comments.length;
      const files = Array.isArray(found.files) ? { totalCount: found.files.length, nodes: found.files.slice(0, 100).map((path) => ({ path, changeType: "MODIFIED" })) } : { totalCount: 1, nodes: [] };
      return { data: { repository: { pullRequest: { ...DETAIL_PULL, comments: { ...DETAIL_PULL.comments, totalCount, nodes: comments }, files } } } };
    }
    if (method === "POST" && path === "/graphql" && String(body.query).startsWith(SKIP_STATE_PREFIX)) {
      const asked = [...body.query.matchAll(/p([0-9]+): pullRequest/g)].map((match) => Number(match[1]));
      const state = (found) => {
        const comments = found.comments ?? [];
        return { number: found.number, headRefOid: found.headRefOid, updatedAt: found.updatedAt, comments: { totalCount: found.commentsTotal ?? comments.length, nodes: comments.slice(-50).map((c) => ({ databaseId: c.databaseId, updatedAt: c.updatedAt })) } };
      };
      return { data: { repository: Object.fromEntries(asked.map((number) => [`p${number}`, state(pulls.find((candidate) => candidate.number === number))])) } };
    }
    if (method === "POST" && /^\/repos\/melodic-software\/claude-code-plugins\/issues\/[0-9]+\/comments$/.test(path)) {
      if ((fail.pin && body.body.startsWith("<!-- babysit-merge-pin ")) || (fail.unpin && body.body.startsWith("<!-- babysit-merge-unpin "))) {
        throw new Error(`POST ${path} failed with status 502`);
      }
      return {};
    }
    const files = /^\/repos\/melodic-software\/claude-code-plugins\/pulls\/([0-9]+)\/files\?per_page=100&page=([0-9]+)$/.exec(path);
    if (method === "GET" && files) {
      const found = pulls.find((candidate) => candidate.number === Number(files[1]));
      return found.files.slice((Number(files[2]) - 1) * 100, Number(files[2]) * 100).map((filename) => ({ filename }));
    }
    const labelPage = /^\/repos\/melodic-software\/claude-code-plugins\/issues\/([0-9]+)\/labels\?per_page=100&page=([0-9]+)$/.exec(path);
    if (method === "GET" && labelPage) {
      const found = pulls.find((candidate) => candidate.number === Number(labelPage[1]));
      if (!Array.isArray(found.labelPages)) {
        throw new Error(`GET ${path} failed with status 502`);
      }
      return found.labelPages[Number(labelPage[2]) - 1] ?? [];
    }
    const cost = costReads(method, path, body);
    if (cost !== undefined) {
      return cost;
    }
    throw new Error(`unexpected call ${method} ${path}`);
  };
  const trustedVerify = async (pull) => {
    verified.push(pull.number);
    return pull.number in verdicts ? verdicts[pull.number] : pass(pull.headRefOid);
  };
  trustedVerify.costs = [];
  const laneVerify = async () => {
    throw new Error("the lanes verifier was called for a pull request the lanes path does not verify");
  };
  const whole = { recover: () => [], request: () => null, toggle: () => null };
  const output = join(tempDir("trusted-arm-"), "output");
  writeFileSync(output, "");
  const lines = [];
  const log = console.log;
  console.log = (line) => lines.push(String(line));
  try {
    const code = await main({
      env: { ...ENV, GITHUB_OUTPUT: output, ...env },
      github,
      verify: laneVerify,
      trustedVerify,
      laneSource,
      room: async () => room,
      whole,
      sleep: async () => {},
      now: () => now,
      mainInputs,
    });
    const arms = calls.filter(({ query }) => query === ARM_MUTATION);
    const outcome = readFileSync(output, "utf8").split("\n").find((text) => text.startsWith(`${WAKE_OUTPUT}=`))?.slice(WAKE_OUTPUT.length + 1);
    return { code, calls, arms, lines, verified, outcome };
  } finally {
    console.log = log;
  }
}

const armedHeads = (result) => result.calls.filter(({ query }) => query === ARM_MUTATION).length;
const leftLine = (result, number) => result.lines.findLast((line) => line.startsWith(`enable-auto-merge: #${number} `)) ?? "";

test("a clean trusted-author pull request with a pr-verify PASS at its head is armed pinned to that head", async () => {
  const result = await run([clean()]);
  assert.equal(result.code, 0);
  assert.equal(armedHeads(result), 1, result.lines.join("\n"));
  assert.deepEqual(result.verified, [500]);
  assert.match(leftLine(result, 500), new RegExp(`armed at ${CLEAN_HEAD}`));
});

const six = () => Array.from({ length: 6 }, (_, i) => clean({ number: 501 + i, id: `PR_${501 + i}` }));

test("the trusted arm counts against merge.max-in-flight: none at 5 of 5 in flight, two at 3 of 5, each arm counted as it is sent", async () => {
  const full = await run(six(), { room: { ...ROOM, count: 5, cap: 5 } });
  assert.equal(armedHeads(full), 0, full.lines.join("\n"));
  assert.equal(full.calls.filter(({ body }) => String(body).startsWith("<!-- babysit-merge-pin ")).length, 0, "a refused arm posts no pin");
  assert.match(leftLine(full, 501), /trusted author: left: merge\.max-in-flight is 5 and 5 merges are in flight$/);
  const room = await run(six(), { room: { ...ROOM, count: 3, cap: 5 } });
  assert.equal(armedHeads(room), 2, room.lines.join("\n"));
  assert.equal(room.lines.filter((line) => / trusted author: left: merge\.max-in-flight is 5 and 5 merges are in flight$/.test(line)).length, 4, "the four after the cap are refused with its reason");
});

test("a trusted pull request armed in an earlier sweep and not yet queued holds its slot: at 4 of 5 it fills the fifth, and no clean one arms", async () => {
  const earlier = clean({ number: 510, id: "PR_510", autoMergeRequest: { enabledAt: "2026-11-27T14:00:00Z" }, isInMergeQueue: false });
  const result = await run([earlier, ...six().slice(0, 2)], { room: { ...ROOM, count: 4, cap: 5 } });
  assert.equal(armedHeads(result), 0, result.lines.join("\n"));
  for (const number of [501, 502]) {
    assert.match(leftLine(result, number), /trusted author: left: merge\.max-in-flight is 5 and 5 merges are in flight$/, `#${number} is refused at the cap`);
  }
});

test("an arm GitHub refuses on its first send gives its slot back: at 4 of 5 the second clean trusted pull request still arms", async () => {
  const result = await run(six().slice(0, 2), { room: { ...ROOM, count: 4, cap: 5 }, fail: { firstArm: true } });
  assert.equal(armedHeads(result), 2, result.lines.join("\n"));
  assert.equal(result.lines.filter((line) => /trusted author: arm not made, skipped this run: /.test(line)).length, 1, "the refused arm is skipped with a warning");
  assert.equal(result.lines.filter((line) => /trusted author: armed at /.test(line)).length, 1, "the other one arms in the freed slot");
});

test("a rung or post-merge refusal, or a room that does not read, arms no trusted pull request", async () => {
  for (const [label, answer, why] of [
    ["rung off", { ...ROOM, refusal: "rung-off:merge.rung" }, /left: pr-merge's gate holds its lane off \(rung-off:merge\.rung\)$/],
    ["unreadable", { ...ROOM, unreadable: "config: boom" }, /left: the lane's room could not be read \(config: boom\)$/],
  ]) {
    const result = await run([clean()], { room: answer });
    assert.equal(armedHeads(result), 0, label);
    assert.match(leftLine(result, 500), why, label);
  }
});

test("a trusted pull request changing infra/main.tf is refused without a recorded cost decision, and armed once its body links one", async () => {
  const unrecorded = await run([clean({ files: ["infra/main.tf"] })]);
  assert.equal(armedHeads(unrecorded), 0, unrecorded.lines.join("\n"));
  assert.match(leftLine(unrecorded, 500), /left: it changes infra\/main\.tf, a cost path$/);
  const recordedDecision = await run([clean({ files: ["infra/main.tf"], body: `Closes #499\n\nCost decision: ${COST_LINK}` })]);
  assert.equal(armedHeads(recordedDecision), 1, recordedDecision.lines.join("\n"));
  assert.match(leftLine(recordedDecision, 500), new RegExp(`armed at ${CLEAN_HEAD}`));
});

test("a member's 'Please do not merge this yet.' after the PASS refuses the trusted arm", async () => {
  const veto = { author: { __typename: "User", login: "kyle-sexton" }, authorAssociation: "MEMBER", body: "Please do not merge this yet.", createdAt: "2026-11-27T14:30:00Z", lastEditedAt: null };
  const result = await run([clean({ comments: [veto] })]);
  assert.equal(armedHeads(result), 0, result.lines.join("\n"));
  assert.equal(pinPosts(result).length, 0, "no pin posts for a vetoed pull request");
  assert.match(leftLine(result, 500), /left: kyle-sexton asked not to merge it$/);
});

const OLD_HEAD = "a".repeat(40);
const lanesComment = (body, at = "2026-11-27T14:00:00Z", lastEditedAt = null) => ({ ...RECORDED_PIN, body, createdAt: at, updatedAt: lastEditedAt ?? at, lastEditedAt });
const pinPosts = (result) => result.calls.filter(({ method, path, body }) => method === "POST" && path.endsWith("/issues/500/comments") && String(body).startsWith("<!-- babysit-merge-pin "));
const disarms = (result) => result.calls.filter(({ query }) => query === DISARM_MUTATION);

test("the arm posts the lanes App pin at the head pr-verify passed, then sends that head as expectedHeadOid", async () => {
  const result = await run([clean()]);
  assert.deepEqual(
    pinPosts(result).map(({ body }) => body.split("\n")[0]),
    [`<!-- babysit-merge-pin sha=${CLEAN_HEAD} -->`],
  );
  assert.deepEqual(result.calls.filter(({ query }) => query === ARM_MUTATION).map(({ variables }) => variables), [{ id: "PR_500", head: CLEAN_HEAD }]);
  const order = result.calls.map(({ path, query, body }) => (query === ARM_MUTATION ? "arm" : String(body).startsWith("<!-- babysit-merge-pin ") ? "pin" : path));
  assert.ok(order.indexOf("pin") < order.indexOf("arm"), order.join(" "));
});

test("#19412's recorded discussion, its lanes App pin at its own head, reads whole: the trusted arm pins that head without the lanes rung and arms it", async () => {
  const head = /sha=([0-9a-f]{40})/.exec(RECORDED_PIN.body)[1];
  const result = await run([clean({ headRefOid: head, comments: DETAIL_PULL.comments.nodes })], { verdicts: { 500: pass(head) } });
  assert.deepEqual(pinPosts(result).map(({ body }) => body.split("\n")[0]), [`<!-- babysit-merge-pin sha=${head} -->`], "a rung=C2 pin is the lanes path's, so the trusted arm posts its own");
  assert.equal(armedHeads(result), 1, result.lines.join("\n"));
});

test("a recorded discussion whose comment count runs past the nodes it returned, and whose next page fails, is refused unarmed", async () => {
  const result = await run([clean({ comments: DETAIL_PULL.comments.nodes, commentsTotal: DETAIL_PULL.comments.totalCount + 100 })]);
  assert.equal(armedHeads(result), 0, result.lines.join("\n"));
  assert.equal(pinPosts(result).length, 0);
  assert.match(leftLine(result, 500), /trusted author: left: its comments could not be read/);
});

test("a pin already at the head is not posted again", async () => {
  const result = await run([clean({ comments: [lanesComment(pinBody(CLEAN_HEAD))] })]);
  assert.equal(pinPosts(result).length, 0);
  assert.equal(armedHeads(result), 1);
});

test("comments that do not read leave a trusted pull request unarmed and unpinned", async () => {
  const result = await run([clean({ commentsError: true })]);
  assert.equal(pinPosts(result).length, 0);
  assert.equal(armedHeads(result), 0);
  assert.match(leftLine(result, 500), /left: its comments could not be read/);
});

test("a trusted pull request armed at X and pushed to Y is disarmed", async () => {
  const armed = { enabledAt: "2026-11-27T14:00:00Z" };
  const result = await run([clean({ autoMergeRequest: armed, comments: [lanesComment(pinBody(OLD_HEAD))] })]);
  assert.deepEqual(disarms(result).map(({ variables }) => variables), [{ id: "PR_500" }]);
  assert.equal(armedHeads(result), 0);
  assert.match(leftLine(result, 500), new RegExp(`disarmed: its head moved from ${OLD_HEAD}, the head its arm judged, to ${CLEAN_HEAD}`));
});

test("an edited pin disarms; a pin at the head, or no lanes pin, leaves the arm on", async () => {
  const armed = { enabledAt: "2026-11-27T14:00:00Z" };
  const edited = await run([clean({ autoMergeRequest: armed, comments: [lanesComment(pinBody(CLEAN_HEAD), undefined, "2026-11-27T14:30:00Z")] })]);
  assert.equal(disarms(edited).length, 1);
  const current = await run([clean({ autoMergeRequest: armed, comments: [lanesComment(pinBody(CLEAN_HEAD))] })]);
  const session = await run([clean({ autoMergeRequest: armed, comments: [] })]);
  for (const result of [current, session]) {
    assert.equal(disarms(result).length, 0);
    assert.match(leftLine(result, 500), /left: already armed$/);
  }
});

const unpinPosts = (result) => result.calls.filter(({ method, path, body }) => method === "POST" && path.endsWith("/issues/500/comments") && String(body).startsWith("<!-- babysit-merge-unpin "));
const LANE_SOURCE_FILES = [".github/workflows/pr-merge.yml"];

test("armed and pinned at A, pushed to a lane-source B: the sweep disarms and unpins, and a person's later arm at B is left alone", async () => {
  const armed = { enabledAt: "2026-11-27T14:00:00Z" };
  const pinA = lanesComment(pinBody(OLD_HEAD));
  const swept = await run([clean({ autoMergeRequest: armed, files: LANE_SOURCE_FILES, comments: [pinA] })]);
  assert.equal(disarms(swept).length, 1);
  assert.deepEqual(
    unpinPosts(swept).map(({ body }) => body.split("\n")[0]),
    [`<!-- babysit-merge-unpin sha=${CLEAN_HEAD} -->`],
  );
  const order = swept.calls.map(({ query, body }) => (query === DISARM_MUTATION ? "disarm" : String(body).startsWith("<!-- babysit-merge-unpin ") ? "unpin" : "other"));
  assert.ok(order.indexOf("disarm") < order.indexOf("unpin"), order.join(" "));
  const unpinB = lanesComment(unpinPosts(swept)[0].body, "2026-11-27T14:30:00Z");
  const unarmed = await run([clean({ files: LANE_SOURCE_FILES, comments: [pinA, unpinB] })]);
  assert.equal(armedHeads(unarmed), 0);
  assert.match(leftLine(unarmed, 500), /left: .*lane source/);
  const session = await run([clean({ autoMergeRequest: armed, files: LANE_SOURCE_FILES, comments: [pinA, unpinB] })]);
  assert.equal(disarms(session).length, 0);
  assert.equal(unpinPosts(session).length, 0);
  assert.match(leftLine(session, 500), /left: already armed$/);
});

test("an unpin a person wrote is ignored, and an edited lanes App unpin disarms", async () => {
  const armed = { enabledAt: "2026-11-27T14:00:00Z" };
  const forged = { ...lanesComment(`<!-- babysit-merge-unpin sha=${CLEAN_HEAD} -->`, "2026-11-27T14:30:00Z"), author: { __typename: "User", login: "melodic-automation-lanes" } };
  const result = await run([clean({ autoMergeRequest: armed, comments: [lanesComment(pinBody(OLD_HEAD)), forged] })]);
  assert.equal(disarms(result).length, 1);
  assert.match(leftLine(result, 500), new RegExp(`its head moved from ${OLD_HEAD}`));
  const edited = await run([clean({ autoMergeRequest: armed, comments: [lanesComment(pinBody(OLD_HEAD)), lanesComment(`<!-- babysit-merge-unpin sha=${CLEAN_HEAD} -->`, "2026-11-27T14:30:00Z", "2026-11-27T14:40:00Z")] })]);
  assert.equal(disarms(edited).length, 1);
  assert.match(leftLine(edited, 500), /its newest unpin comment was edited/);
});

test("on the lanes App's own pull request a lanes App unpin is no record: the older pin still names the head its arm judged", () => {
  const bot = "melodic-automation-lanes";
  const records = [lanesComment(pinBody(OLD_HEAD)), lanesComment(`<!-- babysit-merge-unpin sha=${CLEAN_HEAD} -->`, "2026-11-27T14:30:00Z")];
  assert.equal(pinMoved(records, bot, CLEAN_HEAD), `its head moved from ${OLD_HEAD}, the head its arm judged, to ${CLEAN_HEAD}`, "the lanes path disarms the moved head");
  assert.equal(pinMoved(records, bot, CLEAN_HEAD, true), null, "the trusted path reads the unpin as no pin");
  const atHead = [lanesComment(pinBody(CLEAN_HEAD)), lanesComment(`<!-- babysit-merge-unpin sha=${CLEAN_HEAD} -->`, "2026-11-27T14:30:00Z")];
  assert.equal(pinned(atHead, bot, CLEAN_HEAD), true, "the lanes path keeps its pin at the head and posts none");
  assert.equal(pinned(atHead, bot, CLEAN_HEAD, undefined, true), false, "the trusted path pins the head again over its unpin");
});

test("an unpin that does not post after the disarm fails the run, and the disarm stands", async () => {
  const result = await run([clean({ autoMergeRequest: { enabledAt: "2026-11-27T14:00:00Z" }, comments: [lanesComment(pinBody(OLD_HEAD))] })], { fail: { unpin: true } });
  assert.equal(disarms(result).length, 1);
  assert.notEqual(result.code, 0);
  assert.ok(result.lines.some((line) => line.startsWith("::error title=enable-auto-merge::#500 trusted author: unpin")), result.lines.join("\n"));
});

test("an armed trusted pull request in the merge queue, or of unread queue state, keeps its moved pin: no disarm, no unpin, and the queue's pin hold refuses the moved head", async () => {
  const armed = { enabledAt: "2026-11-27T14:00:00Z" };
  const pinA = lanesComment(pinBody(OLD_HEAD));
  for (const isInMergeQueue of [true, undefined]) {
    const result = await run([clean({ autoMergeRequest: armed, isInMergeQueue, comments: [pinA] })]);
    assert.equal(disarms(result).length, 0, `isInMergeQueue ${isInMergeQueue}: no disarm`);
    assert.equal(unpinPosts(result).length, 0, `isInMergeQueue ${isInMergeQueue}: no unpin`);
    assert.match(leftLine(result, 500), /left: already armed; .*its pin stands/);
  }
  const kept = { login: LANES_APP_LOGIN, at: pinA.createdAt, body: pinA.body, lastEditedAt: null };
  assert.match(pinHold([kept], CLEAN_HEAD) ?? "", new RegExp(`its head is not ${OLD_HEAD}`), "the kept pin still holds the moved head in the merge group");
});

const UNVERIFIED = { 500: { ...pass(CLEAN_HEAD), atHead: [] } };

test("unarmed and unqueued, its newest lanes pin at A and its head at B: the sweep posts one unpin at B, and a second sweep posts nothing more", async () => {
  const pinA = lanesComment(pinBody(OLD_HEAD));
  const first = await run([clean({ comments: [pinA] })], { verdicts: UNVERIFIED });
  assert.deepEqual(
    unpinPosts(first).map(({ body }) => body.split("\n")[0]),
    [`<!-- babysit-merge-unpin sha=${CLEAN_HEAD} -->`],
  );
  assert.equal(armedHeads(first), 0);
  assert.equal(disarms(first).length, 0);
  assert.match(leftLine(first, 500), new RegExp(`unpinned at ${CLEAN_HEAD}`));
  const posted = lanesComment(unpinPosts(first)[0].body, "2026-11-27T14:30:00Z");
  const second = await run([clean({ comments: [pinA, posted] })], { verdicts: UNVERIFIED });
  assert.equal(unpinPosts(second).length, 0, "the newest record is already an unpin");
  assert.match(leftLine(second, 500), /left: pr-verify has no PASS or PASS-NOTES at its head$/);
});

test("an unarmed stale pin stays while queued or of unread queue state, or when a person wrote it; an arm at the new head pins it instead of unpinning", async () => {
  const pinA = lanesComment(pinBody(OLD_HEAD));
  const forged = { ...pinA, author: { __typename: "User", login: "melodic-automation-lanes" } };
  for (const [label, pull] of [
    ["queued", clean({ isInMergeQueue: true, comments: [pinA] })],
    ["unread queue state", clean({ isInMergeQueue: undefined, comments: [pinA] })],
    ["a person's pin", clean({ comments: [forged] })],
  ]) {
    const result = await run([pull], { verdicts: UNVERIFIED });
    assert.equal(unpinPosts(result).length, 0, `${label}: no unpin`);
    assert.equal(armedHeads(result), 0, `${label}: no arm`);
  }
  const armedNow = await run([clean({ comments: [pinA] })]);
  assert.equal(unpinPosts(armedNow).length, 0);
  assert.deepEqual(
    pinPosts(armedNow).map(({ body }) => body.split("\n")[0]),
    [`<!-- babysit-merge-pin sha=${CLEAN_HEAD} -->`],
  );
  assert.equal(armedHeads(armedNow), 1);
});

test("report-only names the disarm it would send and sends none", async () => {
  const result = await run([clean({ autoMergeRequest: { enabledAt: "2026-11-27T14:00:00Z" }, comments: [lanesComment(pinBody(OLD_HEAD))] })], { env: { REPORT_ONLY: "true" } });
  assert.equal(disarms(result).length, 0);
  assert.match(leftLine(result, 500), /would disarm \(report-only\)/);
});

test("#19128's shape is not armed: it changes a .claude lane source and no reader settles pr-review-main's findings", async () => {
  const pull = recorded("19128", { labels: { totalCount: 0, nodes: [] } });
  const result = await run([pull]);
  assert.equal(armedHeads(result), 0);
  assert.deepEqual(result.verified, [], "the verdict is not read once a lane source refuses");
  assert.match(leftLine(result, 19128), /left: .*\.claude\/skills\/control-claude-code-plugins\/features\/docs-hygiene\/README\.md.*lane source/);
});

test("#19361's shape is not armed: its body carries a Hold: line", async () => {
  const result = await run([recorded("19361")]);
  assert.equal(armedHeads(result), 0);
  assert.deepEqual(result.verified, []);
  assert.match(leftLine(result, 19361), /left: its body holds it/);
});

test("only a User whose id is kind human is a trusted person: a trusted bot, a bot id typed User and a person id typed Bot keep the lanes' skip", async () => {
  const list = join(tempDir("trusted-arm-"), "actors.json");
  writeFileSync(
    list,
    JSON.stringify({
      version: 1,
      actors: [
        { id: 153232337, login: "kyle-sexton", kind: "human" },
        { id: 209825114, login: "claude[bot]", kind: "bot" },
      ],
    }),
  );
  for (const author of [
    { __typename: "Bot", login: "claude", databaseId: 209825114 },
    { __typename: "User", login: "claude", databaseId: 209825114 },
    { __typename: "Bot", login: "kyle-sexton", databaseId: 153232337 },
  ]) {
    const result = await run([clean({ author })], { env: { TRUSTED_ACTORS: list } });
    assert.equal(armedHeads(result), 0, JSON.stringify(author));
    assert.deepEqual(result.verified, [], JSON.stringify(author));
    assert.equal(leftLine(result, 500), "", JSON.stringify(author));
  }
  const person = await run([clean()], { env: { TRUSTED_ACTORS: list } });
  assert.equal(armedHeads(person), 1, "the same list's kind human User is armed");
});

test("a trusted person's needs-human label holds even where the tracker's human-gated label is another", async () => {
  const tracker = join(HERE, "fixtures/enable-auto-merge-tracker.json");
  for (const name of ["needs-human", "human-gated"]) {
    const result = await run([clean({ labels: { totalCount: 1, nodes: [{ name }] } })], { env: { TRACKER_CONFIG: tracker } });
    assert.equal(armedHeads(result), 0, name);
    assert.match(leftLine(result, 500), new RegExp(`left: it carries ${name}`), name);
  }
});

test("a verdict with no PASS or PASS-NOTES at the head, or verify:missing, refuses; PASS-NOTES alone arms", async () => {
  const none = await run([clean()], { verdicts: { 500: { ...pass(CLEAN_HEAD), atHead: [] } } });
  assert.equal(armedHeads(none), 0);
  assert.match(leftLine(none, 500), /left: pr-verify has no PASS or PASS-NOTES at its head$/);
  const missing = await run([clean()], { verdicts: { 500: refused(CLEAN_HEAD, "verify:missing") } });
  assert.equal(armedHeads(missing), 0);
  assert.match(leftLine(missing, 500), /left: .*verify:missing/);
  const notes = await run([clean()], { verdicts: { 500: { ...pass(CLEAN_HEAD), atHead: ["pass-notes"] } } });
  assert.equal(armedHeads(notes), 1);
});

test("a lane-source check that fails refuses before the verdict is read", async () => {
  const result = await run([clean()], {
    laneSource: () => {
      throw new Error("babysit_review_evidence.lane_source exited 1: boom");
    },
  });
  assert.equal(armedHeads(result), 0);
  assert.deepEqual(result.verified, []);
  assert.match(leftLine(result, 500), /left: its lane-source paths could not be checked$/);
});

test("a pin that does not post arms nothing, and the run fails", async () => {
  const result = await run([clean()], { fail: { pin: true } });
  assert.equal(armedHeads(result), 0);
  assert.notEqual(result.code, 0);
  assert.ok(result.lines.some((line) => line.startsWith("::error title=enable-auto-merge::#500 trusted author: pin, so not armed")), result.lines.join("\n"));
});

test("an arm mutation that fails leaves the pull request refused, and the run fails", async () => {
  const result = await run([clean()], { env: { EVENT_NAME: "workflow_dispatch", EVENT_PR: "500" }, fail: { arm: true } });
  assert.equal(armedHeads(result), 1, "the arm was sent once");
  assert.notEqual(result.code, 0);
  assert.equal(result.outcome, "refused: its arm failed");
  assert.ok(result.lines.some((line) => line.startsWith("::error title=enable-auto-merge::#500 trusted author: arm:")), result.lines.join("\n"));
});

test("a merge queue state that did not read refuses", async () => {
  const result = await run([clean({ isInMergeQueue: undefined })]);
  assert.equal(armedHeads(result), 0);
  assert.match(leftLine(result, 500), /left: its merge queue state did not read$/);
});

test("a trusted author's draft is not armed", async () => {
  const result = await run([clean({ isDraft: true })]);
  assert.equal(armedHeads(result), 0);
  assert.match(leftLine(result, 500), /left: it is a draft/);
});

test("a trusted author's pull request with do-not-merge is not armed", async () => {
  const result = await run([clean({ labels: { totalCount: 1, nodes: [{ name: "do-not-merge" }] } })]);
  assert.equal(armedHeads(result), 0);
  assert.match(leftLine(result, 500), /left: it carries do-not-merge/);
});

test("needs-human, pr-verify-failed and security: outside-actor each hold a trusted author's pull request", async () => {
  for (const name of ["needs-human", "pr-verify-failed", "security: outside-actor"]) {
    const result = await run([clean({ labels: { totalCount: 1, nodes: [{ name }] } })]);
    assert.equal(armedHeads(result), 0, name);
    assert.match(leftLine(result, 500), new RegExp(`left: it carries ${name}`), name);
  }
});

test("a trusted author's pull request whose head pr-verify FAILed is not armed", async () => {
  const result = await run([clean()], { verdicts: { 500: refused(CLEAN_HEAD, "verify:fail") } });
  assert.equal(armedHeads(result), 0);
  assert.match(leftLine(result, 500), /verify:fail/);
});

test("a verdict read at another head, or one that does not read, refuses", async () => {
  for (const verdict of [pass("e".repeat(40)), null, { head: CLEAN_HEAD }]) {
    const result = await run([clean()], { verdicts: { 500: verdict } });
    assert.equal(armedHeads(result), 0, JSON.stringify(verdict));
  }
});

test("an armed or queued trusted pull request with no hold standing is left as it is", async () => {
  const armedAt = { enabledAt: "2026-11-27T14:00:00Z" };
  for (const comments of [[], [lanesComment(pinBody(CLEAN_HEAD))]]) {
    const armed = await run([clean({ autoMergeRequest: armedAt, comments })]);
    assert.equal(armedHeads(armed), 0);
    assert.equal(disarms(armed).length, 0, `${comments.length} pins: no disarm`);
    assert.equal(unpinPosts(armed).length, 0, `${comments.length} pins: no unpin`);
    assert.match(leftLine(armed, 500), /left: already armed$/);
  }
  const queued = await run([clean({ isInMergeQueue: true })]);
  assert.equal(armedHeads(queued), 0);
  assert.match(leftLine(queued, 500), /left: it is in the merge queue/);
});

const VETO = { author: { __typename: "User", login: "kyle-sexton" }, authorAssociation: "MEMBER", body: "Please do not merge this yet.", createdAt: "2026-11-27T14:30:00Z", lastEditedAt: null };
const lanesArmed = (overrides = {}) => clean({ autoMergeRequest: { enabledAt: "2026-11-27T14:00:00Z" }, comments: [lanesComment(pinBody(CLEAN_HEAD))], ...overrides });
const disarmedAndUnpinned = (result, why) => {
  assert.deepEqual(disarms(result).map(({ variables }) => variables), [{ id: "PR_500" }], result.lines.join("\n"));
  assert.deepEqual(
    unpinPosts(result).map(({ body }) => body.split("\n")[0]),
    [`<!-- babysit-merge-unpin sha=${CLEAN_HEAD} -->`],
  );
  assert.match(leftLine(result, 500), new RegExp(`disarmed: ${why}; unpinned at ${CLEAN_HEAD}`));
};

test("a lanes App arm at the head is disarmed and unpinned once a member vetoes it", async () => {
  disarmedAndUnpinned(await run([lanesArmed({ comments: [lanesComment(pinBody(CLEAN_HEAD)), VETO] })]), "kyle-sexton asked not to merge it");
});

test("a lanes App arm at the head is disarmed and unpinned once a hold label goes on", async () => {
  const tracker = join(HERE, "fixtures/enable-auto-merge-tracker.json");
  for (const name of ["do-not-merge", "needs-human", "security: outside-actor", "human-gated"]) {
    disarmedAndUnpinned(await run([lanesArmed({ labels: { totalCount: 1, nodes: [{ name }] } })], { env: { TRACKER_CONFIG: tracker } }), `it carries ${name}`);
  }
});

test("a lanes App arm at the head is disarmed and unpinned once its body gains a Hold: line", async () => {
  disarmedAndUnpinned(await run([lanesArmed({ body: "Closes #499\n\nHold: the owner reads this first." })]), "its body holds it");
});

test("a lanes App arm at the head is disarmed and unpinned once pr-verify no longer passes it", async () => {
  disarmedAndUnpinned(await run([lanesArmed()], { verdicts: { 500: { ...pass(CLEAN_HEAD), atHead: [] } } }), "pr-verify has no PASS or PASS-NOTES at its head");
  disarmedAndUnpinned(await run([lanesArmed()], { verdicts: { 500: refused(CLEAN_HEAD, "verify:fail") } }), ".*\\(verify:fail\\)");
});

test("a session's arm with no lanes App pin is left armed under a hold label, and its verdict is not read", async () => {
  const result = await run([clean({ autoMergeRequest: { enabledAt: "2026-11-27T14:00:00Z" }, labels: { totalCount: 1, nodes: [{ name: "needs-human" }] } })]);
  assert.equal(disarms(result).length, 0);
  assert.deepEqual(result.verified, []);
  assert.match(leftLine(result, 500), /left: already armed$/);
});

test("an unpin is not posted when the pull request read again just before it is queued, armed or at another head", async () => {
  const pinA = lanesComment(pinBody(OLD_HEAD));
  for (const [label, reread] of [
    ["queued", { isInMergeQueue: true }],
    ["armed", { autoMergeRequest: { enabledAt: "2026-11-27T14:50:00Z" } }],
    ["another head", { headRefOid: "e".repeat(40) }],
    ["unread", "error"],
  ]) {
    const unarmed = await run([clean({ comments: [pinA], reread })], { verdicts: UNVERIFIED });
    assert.equal(unpinPosts(unarmed).length, 0, `unarmed, re-read ${label}: no unpin`);
    assert.equal(unarmed.calls.filter(({ query }) => query === AUTO_MERGE_STATE_QUERY).length, 1, `unarmed, re-read ${label}: one re-read`);
    assert.match(leftLine(unarmed, 500), /unpin not posted: /, `unarmed, re-read ${label}`);
    const disarmed = await run([clean({ autoMergeRequest: { enabledAt: "2026-11-27T14:00:00Z" }, comments: [pinA], reread })]);
    assert.equal(disarms(disarmed).length, 1, `disarm, re-read ${label}: the disarm is sent`);
    assert.equal(unpinPosts(disarmed).length, 0, `disarm, re-read ${label}: no unpin`);
    assert.match(leftLine(disarmed, 500), /unpin not posted: /, `disarm, re-read ${label}`);
  }
});

test("an author outside the trusted list, and Dependabot on it, keep the lanes' skip", async () => {
  const outsider = await run([clean({ author: { __typename: "User", login: "someone", databaseId: 42 } })]);
  const dependabot = await run([clean({ author: { __typename: "Bot", login: "dependabot", databaseId: 49699333 } })]);
  for (const result of [outsider, dependabot]) {
    assert.equal(armedHeads(result), 0);
    assert.deepEqual(result.verified, []);
    assert.equal(leftLine(result, 500), "");
  }
});

test("a trusted-actor list that does not read arms no trusted author's pull request", async () => {
  const result = await run([clean()], { env: { TRUSTED_ACTORS: "/nonexistent/trusted-actors.json" } });
  assert.equal(armedHeads(result), 0);
  assert.deepEqual(result.verified, []);
  assert.ok(result.lines.some((line) => line.includes("the trusted-actor list did not read")), result.lines.join("\n"));
});

test("changed files that do not read refuse", async () => {
  const pull = clean({ files: null });
  const result = await run([pull]);
  assert.equal(armedHeads(result), 0);
  assert.match(leftLine(result, 500), /left: .*changed files/);
});

test("report-only names the arm it would send and sends none", async () => {
  const result = await run([clean()], { env: { REPORT_ONLY: "true" } });
  assert.equal(armedHeads(result), 0);
  assert.match(leftLine(result, 500), /would arm \(report-only\)/);
});

test("a PR-scoped wake reports the trusted arm as its outcome", async () => {
  const result = await run([clean()], { env: { EVENT_NAME: "workflow_dispatch", EVENT_PR: "500" } });
  assert.equal(armedHeads(result), 1);
  assert.equal(result.outcome, "armed");
});

test("a lanes App pull request on the trusted list takes the lanes path, its decision unchanged", async () => {
  const lanesPull = clean({ number: 600, id: "PR_600", author: LANES_APP, labels: { totalCount: 1, nodes: [{ name: "pr-verify-failed" }] } });
  const listed = await run([lanesPull]);
  const unlisted = await run([lanesPull], { env: { TRUSTED_ACTORS: "/nonexistent/trusted-actors.json" } });
  assert.equal(leftLine(listed, 600), "enable-auto-merge: #600 left: it carries pr-verify-failed");
  assert.equal(leftLine(unlisted, 600), leftLine(listed, 600));
  assert.deepEqual(listed.verified, []);
  assert.equal(armedHeads(listed), 0);
});

test("decideTrusted refuses a stacked pull request and arms only past every check", () => {
  const none = { totalCount: 0, nodes: [] };
  const facts = { files: { paths: CLEAN_FILES, capped: false }, laneSources: [], verify: pass(CLEAN_HEAD), comments: [], discussion: { comments: none, reviews: none, reviewThreads: none } };
  const bot = "melodic-automation-lanes";
  assert.deepEqual(decideTrusted(clean(), "needs-human", facts, bot), { action: "arm", reason: "pr-verify passed its head and no hold stands", pin: true });
  assert.equal(decideTrusted(clean(), "needs-human", { ...facts, comments: [lanesComment(pinBody(CLEAN_HEAD))] }, bot).pin, false);
  assert.equal(decideTrusted(clean(), "needs-human", { ...facts, comments: [lanesComment(pinBody(OLD_HEAD))] }, bot).pin, true);
  assert.equal(decideTrusted(clean(), "needs-human", { files: facts.files, laneSources: [], verify: facts.verify }, bot).action, "comments");
  assert.equal(decideTrusted(clean({ stack: { baseRefName: "main", entries: { totalCount: 0, nodes: [] } } }), "needs-human", facts).action, "none");
  assert.equal(decideTrusted(clean(), "needs-human", { ...facts, files: { paths: null, capped: true } }).action, "none");
  assert.equal(decideTrusted(clean(), "needs-human", { files: facts.files }).action, "lane-source");
  assert.equal(decideTrusted(clean(), "needs-human", { files: facts.files, laneSources: [] }).action, "verify");
  assert.equal(decideTrusted(clean({ isCrossRepository: true }), "needs-human", facts).action, "none");
});

test("the lane-source reader is babysit_review_evidence.lane_source: #19128's .claude path is one, a plugin README is not", () => {
  const read = pythonLaneSource({ VERIFY_EVIDENCE_SCRIPT });
  assert.deepEqual(read(RECORDED["19128"].files_page_1), [".claude/skills/control-claude-code-plugins/features/docs-hygiene/README.md"]);
  assert.deepEqual(read(["plugins/docs-hygiene/README.md", "docs/catalog.md"]), []);
  assert.deepEqual(read([".github/workflows/pr-merge.yml", "AGENTS.md"]), [".github/workflows/pr-merge.yml", "AGENTS.md"]);
});

test("the trusted verdict read asks evidence for the verdict alone, with no lane flags", async () => {
  let sent;
  const spawn = (cmd, args) => {
    sent = [cmd, ...args];
    return { status: 0, stdout: `${JSON.stringify(pass(CLEAN_HEAD))}\n`, stderr: "" };
  };
  const read = pythonVerify({ GITHUB_REPOSITORY: REPO }, { spawn, clock: () => 0, lane: false });
  const log = console.log;
  console.log = () => {};
  try {
    await read({ number: 500, headRefOid: CLEAN_HEAD, baseRefOid: "d".repeat(40) }, "C2");
  } finally {
    console.log = log;
  }
  assert.deepEqual(sent, [
    "python3",
    ".base/plugins/source-control/skills/babysit-prs/scripts/babysit_verify_evidence.py",
    "evidence",
    "--shared-listing",
    "--repo",
    REPO,
    "--base-sha",
    "d".repeat(40),
    "500",
    CLEAN_HEAD,
  ]);
});

test("an unpin that fails after a hold disarm at the pinned head is posted by the next sweep, which still refuses the arm for the hold", async () => {
  const pinAtHead = lanesComment(pinBody(CLEAN_HEAD));
  const doNotMerge = { labels: { totalCount: 1, nodes: [{ name: "do-not-merge" }] } };
  const failed = await run([lanesArmed(doNotMerge)], { fail: { unpin: true } });
  assert.equal(disarms(failed).length, 1, "the first sweep disarms for the hold label");
  assert.notEqual(failed.code, 0, "the failed unpin fails the run");
  for (const [label, pull, why] of [
    ["hold label", clean({ ...doNotMerge, comments: [pinAtHead] }), "it carries do-not-merge"],
    ["body hold", clean({ body: "Closes #499\n\nHold: the owner reads this first.", comments: [pinAtHead] }), "its body holds it"],
    ["draft", clean({ isDraft: true, comments: [pinAtHead] }), "it is a draft"],
    ["veto", clean({ comments: [pinAtHead, VETO] }), "kyle-sexton asked not to merge it"],
  ]) {
    const next = await run([pull]);
    assert.deepEqual(
      unpinPosts(next).map(({ body }) => body.split("\n")[0]),
      [`<!-- babysit-merge-unpin sha=${CLEAN_HEAD} -->`],
      `${label}: the next sweep posts the unpin it missed`,
    );
    assert.equal(armedHeads(next), 0, `${label}: still not armed`);
    assert.equal(pinPosts(next).length, 0, `${label}: no new pin`);
    assert.match(leftLine(next, 500), new RegExp(`left: ${why}; .*unpinned at ${CLEAN_HEAD}$`), label);
  }
  const lostPass = await run([clean({ comments: [pinAtHead] })], { verdicts: UNVERIFIED });
  assert.equal(unpinPosts(lostPass).length, 1, "a lost PASS at the pinned head also posts the missed unpin");
  const settled = await run([clean({ ...doNotMerge, comments: [pinAtHead, lanesComment(unpinBody(CLEAN_HEAD), "2026-11-27T14:30:00Z")] })]);
  assert.equal(unpinPosts(settled).length, 0, "once the newest record is an unpin, nothing more posts");
  assert.match(leftLine(settled, 500), /left: it carries do-not-merge$/);
});

const PLAIN_LABELS = Array.from({ length: 100 }, (_, i) => ({ name: `area-${i}` }));

test("a label list cut at 100 is read again whole before the trusted arm: a hold label on the second page refuses, none arms, and a re-read that fails refuses unarmed", async () => {
  const truncated = { labels: { totalCount: 101, nodes: PLAIN_LABELS } };
  const held = await run([clean({ ...truncated, labelPages: [PLAIN_LABELS, [{ name: "do-not-merge" }]] })]);
  assert.equal(armedHeads(held), 0, held.lines.join("\n"));
  assert.match(leftLine(held, 500), /left: it carries do-not-merge$/);
  const unheld = await run([clean({ ...truncated, labelPages: [PLAIN_LABELS, [{ name: "area-100" }]] })]);
  assert.equal(armedHeads(unheld), 1, unheld.lines.join("\n"));
  const unread = await run([clean(truncated)]);
  assert.equal(armedHeads(unread), 0, unread.lines.join("\n"));
  assert.equal(pinPosts(unread).length, 0);
  assert.match(leftLine(unread, 500), /left: its labels could not all be read$/);
});

const SWEPT_AT = Date.parse("2026-11-27T15:00:00Z");
const graphqlReads = (result, query) => result.calls.filter((call) => call.method === "POST" && call.path === "/graphql" && (typeof query === "string" ? call.query === query : String(call.query).startsWith(SKIP_STATE_PREFIX))).length;
const restCalls = (result) => result.calls.filter((call) => call.path !== "/graphql").length;
async function sweep(pulls, { from, minutes = 0, verdicts = UNVERIFIED, env = {}, main = "main-1" } = {}) {
  const dir = tempDir("trusted-arm-skip-");
  const out = join(dir, "eam-skip.json");
  const result = await run(pulls, { env: { EAM_SKIP_IN: from ?? join(dir, "none.json"), EAM_SKIP_OUT: out, ...env }, verdicts, now: SWEPT_AT + minutes * 60_000, mainInputs: () => main });
  const kept = JSON.parse(readFileSync(out, "utf8"));
  return { ...result, from: out, kept, details: graphqlReads(result, DETAIL_QUERY), stateReads: graphqlReads(result), graphql: result.calls.filter((call) => call.path === "/graphql").length, rest: restCalls(result) };
}
const remark = (id, at = "2026-11-27T13:00:00Z") => ({ databaseId: id, author: { __typename: "User", login: "kyle-sexton" }, authorAssociation: "MEMBER", body: "Looks fine to me.", createdAt: at, updatedAt: at, lastEditedAt: null });
const DO_NOT_MERGE = { labels: { totalCount: 1, nodes: [{ name: "do-not-merge" }] } };
const refusedTrusted = (number, overrides = {}) => clean({ number, id: `PR_${number}`, updatedAt: "2026-11-27T14:00:00Z", comments: [remark(number * 10)], ...overrides });

test("refused unarmed trusted pull requests unchanged since the last sweep read no discussion: three refused cost three detail reads, then one batched state read", async () => {
  const pulls = [refusedTrusted(500), refusedTrusted(501), refusedTrusted(502, DO_NOT_MERGE)];
  const verdicts = { 500: UNVERIFIED[500], 501: { ...pass(CLEAN_HEAD), atHead: [] } };
  const first = await sweep(pulls, { verdicts });
  assert.equal(first.details, 3, first.lines.join("\n"));
  assert.equal(first.stateReads, 0, "no record yet, so no state read");
  assert.deepEqual(Object.keys(first.kept.entries).sort(), ["500", "501", "502"]);
  const second = await sweep(pulls, { from: first.from, minutes: 15, verdicts });
  assert.equal(second.details, 0, second.lines.join("\n"));
  assert.equal(second.stateReads, 1);
  assert.deepEqual(second.verified.sort(), [500, 501], "the verdict is still read every sweep");
  assert.equal(armedHeads(second), 0);
  assert.equal(unpinPosts(second).length, 0);
  assert.match(leftLine(second, 500), /left: pr-verify has no PASS or PASS-NOTES at its head$/);
  assert.match(leftLine(second, 502), /left: it carries do-not-merge$/);
  assert.deepEqual(Object.values(second.kept.entries).map(({ skips }) => skips), [1, 1, 1]);
  assert.deepEqual([first.graphql, first.rest], [4, 2], "first sweep: the listing and three detail reads, files by REST for the two past the label hold");
  assert.deepEqual([second.graphql, second.rest], [2, 2], "second sweep: the listing and one state read, files by REST for the two past the label hold");
});

test("a changed head, update time, label set, new comment or edited comment reads the discussion again", async () => {
  const first = await sweep([refusedTrusted(500)]);
  assert.equal((await sweep([refusedTrusted(500)], { from: first.from, minutes: 15 })).details, 0);
  const cases = {
    head: refusedTrusted(500, { headRefOid: "e".repeat(40) }),
    updatedAt: refusedTrusted(500, { updatedAt: "2026-11-27T14:10:00Z" }),
    labels: refusedTrusted(500, { labels: { totalCount: 1, nodes: [{ name: "area-docs" }] } }),
    comment: refusedTrusted(500, { comments: [remark(5000), remark(5001, "2026-11-27T14:05:00Z")] }),
    edited: refusedTrusted(500, { comments: [{ ...remark(5000), updatedAt: "2026-11-27T14:05:00Z", lastEditedAt: "2026-11-27T14:05:00Z" }] }),
  };
  for (const [name, pull] of Object.entries(cases)) {
    const head = pull.headRefOid;
    const again = await sweep([pull], { from: first.from, minutes: 15, verdicts: { 500: { ...pass(head), atHead: [] } } });
    assert.equal(again.details, 1, name);
  }
});

test("a lanes pin that appears after the record, with the head moved or with the same head and update time, is read and unpinned on that first sweep", async () => {
  const first = await sweep([refusedTrusted(500)]);
  const pinA = { ...lanesComment(pinBody(OLD_HEAD), "2026-11-27T14:20:00Z"), databaseId: 9001 };
  for (const [name, pull] of Object.entries({
    moved: refusedTrusted(500, { headRefOid: "e".repeat(40), comments: [remark(5000), pinA] }),
    same: refusedTrusted(500, { comments: [remark(5000), pinA] }),
  })) {
    const head = pull.headRefOid;
    const next = await sweep([pull], { from: first.from, minutes: 15, verdicts: { 500: { ...pass(head), atHead: [] } } });
    assert.equal(next.details, 1, name);
    assert.deepEqual(unpinPosts(next).map(({ body }) => body.split("\n")[0]), [`<!-- babysit-merge-unpin sha=${head} -->`], name);
    assert.deepEqual(next.kept.entries, {}, `${name}: an unpin keeps no record`);
  }
});

test("a PASS landing on an unchanged refused trusted pull request arms it on the next sweep", async () => {
  const first = await sweep([refusedTrusted(500)]);
  assert.equal(first.kept.entries["500"]?.skips, 0);
  const passed = await sweep([refusedTrusted(500)], { from: first.from, minutes: 15, verdicts: {} });
  assert.equal(armedHeads(passed), 1, passed.lines.join("\n"));
  assert.equal(pinPosts(passed).length, 1);
  assert.equal(passed.details, 1, "the arm reads the discussion for vetoes and the pin");
  assert.match(leftLine(passed, 500), new RegExp(`armed at ${CLEAN_HEAD}`));
});

test("a record past max-skips, or a run with skips off, reads the discussion again", async () => {
  let from = (await sweep([refusedTrusted(500)])).from;
  for (const minutes of [10, 20, 30]) {
    const skipped = await sweep([refusedTrusted(500)], { from, minutes });
    assert.equal(skipped.details, 0, `skip at ${minutes}`);
    from = skipped.from;
  }
  assert.equal((await sweep([refusedTrusted(500)], { from, minutes: 40 })).details, 1);
  const first = await sweep([refusedTrusted(500)]);
  assert.equal((await sweep([refusedTrusted(500)], { from: first.from, minutes: 15, env: { REPORT_ONLY: "true" } })).details, 1);
  assert.equal((await sweep([refusedTrusted(500)], { from: first.from, minutes: 15, main: "main-2" })).details, 1);
});

test("a trusted pull request with more comments than the state read returns keeps no record; one with exactly 50 keeps one", async () => {
  const comments = (length) => Array.from({ length }, (_, i) => remark(7000 + i));
  assert.deepEqual((await sweep([refusedTrusted(500, { comments: comments(51) })])).kept.entries, {});
  assert.equal((await sweep([refusedTrusted(500, { comments: comments(50) })])).kept.entries["500"]?.reason, "trusted author: its comments held no stale lanes App pin");
});

test("a member's veto posted while the lane-source or verdict check runs refuses the trusted arm", async () => {
  const during = clean({ comments: [] });
  const vetoed = await run([during], { laneSource: () => { during.comments = [VETO]; return []; } });
  assert.equal(armedHeads(vetoed), 0, vetoed.lines.join("\n"));
  assert.match(leftLine(vetoed, 500), /left: kyle-sexton asked not to merge it/);
  const late = clean({ comments: [] });
  const verdicts = { get 500() { late.comments = [VETO]; return pass(CLEAN_HEAD); } };
  const verified = await run([late], { verdicts });
  assert.equal(armedHeads(verified), 0, verified.lines.join("\n"));
  assert.match(leftLine(verified, 500), /left: kyle-sexton asked not to merge it/);
});
