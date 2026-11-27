import assert from "node:assert/strict";
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { test } from "node:test";

import { ARM_MUTATION, DETAIL_QUERY, DISARM_MUTATION, PULLS_QUERY, WAKE_OUTPUT, decideTrusted, main, pinBody, pythonLaneSource, pythonVerify } from "./enable-auto-merge.mjs";
import { tempDir } from "../../../lib/test-tmp.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const RECORDED = JSON.parse(readFileSync(join(HERE, "fixtures/trusted-arm-pulls.json"), "utf8"));
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

const pass = (head) => ({ refusal: null, needsHuman: false, head, atHead: ["pass"], earlierFails: [], ignored: 0, detail: null, supersededAtHead: false });
const refused = (head, refusal) => ({ ...pass(head), refusal, atHead: refusal === "verify:fail" ? ["fail"] : [] });

async function run(pulls, { env = {}, verdicts = {}, laneSource, fail = {} } = {}) {
  const calls = [];
  const verified = [];
  const github = async (method, path, body) => {
    calls.push({ method, path, query: body?.query, variables: body?.variables, body: body?.body });
    if (method === "POST" && path === "/graphql" && body.query === PULLS_QUERY) {
      return { data: { repository: { pullRequests: { pageInfo: { hasNextPage: false, endCursor: null }, nodes: pulls } } } };
    }
    if (method === "POST" && path === "/graphql" && body.query === ARM_MUTATION) {
      if (fail.arm) {
        throw new Error("POST /graphql failed with status 502");
      }
      return { data: { enablePullRequestAutoMerge: { pullRequest: { autoMergeRequest: { enabledAt: "2026-11-27T15:00:00Z" } } } } };
    }
    if (method === "POST" && path === "/graphql" && body.query === DISARM_MUTATION) {
      return { data: { disablePullRequestAutoMerge: { clientMutationId: null } } };
    }
    if (method === "POST" && path === "/graphql" && body.query === DETAIL_QUERY) {
      const found = pulls.find((candidate) => candidate.number === body.variables.number);
      if (found.commentsError) {
        throw new Error("POST /graphql failed with status 502");
      }
      const none = { totalCount: 0, nodes: [] };
      const comments = found.comments ?? [];
      return { data: { repository: { pullRequest: { comments: { totalCount: comments.length, nodes: comments }, reviews: none, reviewThreads: none, timelineItems: { nodes: [] }, files: none } } } };
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
      room: async () => ({ refusal: null, unreadable: null, count: 0, cap: 5, queued: [], rung: "C2" }),
      whole,
      sleep: async () => {},
      now: () => Date.parse("2026-11-27T15:00:00Z"),
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

const OLD_HEAD = "a".repeat(40);
const lanesComment = (body, at = "2026-11-27T14:00:00Z", lastEditedAt = null) => ({ author: { __typename: "Bot", login: "melodic-automation-lanes" }, body, createdAt: at, lastEditedAt });
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

test("an unpin that does not post after the disarm fails the run, and the disarm stands", async () => {
  const result = await run([clean({ autoMergeRequest: { enabledAt: "2026-11-27T14:00:00Z" }, comments: [lanesComment(pinBody(OLD_HEAD))] })], { fail: { unpin: true } });
  assert.equal(disarms(result).length, 1);
  assert.notEqual(result.code, 0);
  assert.ok(result.lines.some((line) => line.startsWith("::error title=enable-auto-merge::#500 trusted author: unpin")), result.lines.join("\n"));
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

test("an armed or queued trusted pull request is left as it is", async () => {
  const armed = await run([clean({ autoMergeRequest: { enabledAt: "2026-11-27T14:00:00Z" } })]);
  assert.equal(armedHeads(armed), 0);
  assert.match(leftLine(armed, 500), /left: already armed/);
  const queued = await run([clean({ isInMergeQueue: true })]);
  assert.equal(armedHeads(queued), 0);
  assert.match(leftLine(queued, 500), /left: it is in the merge queue/);
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
  const facts = { files: { paths: CLEAN_FILES, capped: false }, laneSources: [], verify: pass(CLEAN_HEAD), comments: [] };
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
