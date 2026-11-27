import assert from "node:assert/strict";
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { test } from "node:test";

import { ARM_MUTATION, PULLS_QUERY, WAKE_OUTPUT, decideTrusted, main, pythonLaneSource, pythonVerify } from "./enable-auto-merge.mjs";
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

async function run(pulls, { env = {}, verdicts = {} } = {}) {
  const calls = [];
  const verified = [];
  const github = async (method, path, body) => {
    calls.push({ method, path, query: body?.query });
    if (method === "POST" && path === "/graphql" && body.query === PULLS_QUERY) {
      return { data: { repository: { pullRequests: { pageInfo: { hasNextPage: false, endCursor: null }, nodes: pulls } } } };
    }
    if (method === "POST" && path === "/graphql" && body.query === ARM_MUTATION) {
      return { data: { enablePullRequestAutoMerge: { pullRequest: { autoMergeRequest: { enabledAt: "2026-11-27T15:00:00Z" } } } } };
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

test("the arm sends the head pr-verify passed as expectedHeadOid", async () => {
  const pull = clean();
  const sent = [];
  const github = async (method, path, body) => {
    if (body?.query === ARM_MUTATION) {
      sent.push(body.variables);
      return { data: {} };
    }
    if (body?.query === PULLS_QUERY) {
      return { data: { repository: { pullRequests: { pageInfo: { hasNextPage: false }, nodes: [pull] } } } };
    }
    if (method === "GET" && path.includes("/files?")) {
      return pull.files.map((filename) => ({ filename }));
    }
    throw new Error(`unexpected call ${method} ${path}`);
  };
  const trustedVerify = async (read) => pass(read.headRefOid);
  trustedVerify.costs = [];
  const log = console.log;
  console.log = () => {};
  try {
    await main({ env: { ...ENV }, github, trustedVerify, room: async () => null, whole: { recover: () => [] }, sleep: async () => {}, now: () => 0 });
  } finally {
    console.log = log;
  }
  assert.deepEqual(sent, [{ id: "PR_500", head: CLEAN_HEAD }]);
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

test("a trusted bot's Hold: line holds too, though no person wrote the body", async () => {
  const list = join(tempDir("trusted-arm-"), "actors.json");
  writeFileSync(list, JSON.stringify({ version: 1, actors: [{ id: 209825114, login: "claude[bot]", kind: "bot" }] }));
  const bot = { __typename: "Bot", login: "claude", databaseId: 209825114 };
  const held = await run([clean({ author: bot, body: RECORDED["19361"].body_hold_lines[0] })], { env: { TRUSTED_ACTORS: list } });
  assert.equal(armedHeads(held), 0);
  assert.match(leftLine(held, 500), /left: its body holds it/);
  const open = await run([clean({ author: bot })], { env: { TRUSTED_ACTORS: list } });
  assert.equal(armedHeads(open), 1);
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
  const facts = { files: { paths: CLEAN_FILES, capped: false }, laneSources: [], verify: pass(CLEAN_HEAD) };
  assert.equal(decideTrusted(clean(), "needs-human", facts).action, "arm");
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
