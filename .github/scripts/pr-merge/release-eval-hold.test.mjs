// Expected values come from the owner's decision Q-EVAL-HOLD (a), 2026-11-06:
// a listed human's `<!-- eval-pair verdict=no-loss validity=VALID head=<sha> -->`
// line for the pull request's current head releases a `do-not-merge` hold
// whose recorded reason is `eval`, and nothing else does: not a wrong head, an
// unlisted author, an App-posted comment, a quoted or fenced line, another
// hold reason, or a pull request without the label.
import assert from "node:assert/strict";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, test } from "node:test";

import { decide, LABEL, main, ownLines, RELEASES_PER_RUN } from "./release-eval-hold.mjs";

const REPO = "melodic-software/claude-code-plugins";
const PERSON = { login: "kyle-sexton", id: 153232337, type: "User" };
const STRANGER = { login: "someone", id: 42, type: "User" };
const APP = { login: "melodic-automation-lanes[bot]", id: 337595936, type: "Bot" };
const HEAD = "b".repeat(40);
const OLD = "c".repeat(40);
const LABELED_AT = "2026-11-06T10:00:00Z";
const HUMANS = new Set([PERSON.id]);

const holdLine = (reason) => `<!-- pr-hold reason=${reason} -->`;
const recordLine = (head) => `<!-- eval-pair verdict=no-loss validity=VALID head=${head} -->`;

let nextId = 100;
const comment = (body, { user = PERSON, at = "2026-11-06T11:00:00Z", app = null } = {}) => ({
  id: nextId++,
  html_url: `https://github.com/${REPO}/pull/7#issuecomment-${nextId}`,
  user,
  author_association: user === PERSON ? "OWNER" : "NONE",
  performed_via_github_app: app,
  created_at: at,
  body,
});

const pull = ({ labels = [LABEL], head = HEAD, body = "Closes #1" } = {}) => ({
  number: 7,
  state: "open",
  head: { sha: head },
  body,
  labels: labels.map((name) => ({ name })),
});

const events = [{ event: "labeled", label: { name: LABEL }, created_at: LABELED_AT }];
const holdComment = () => comment(`Held for eval.\n${holdLine("eval")}`, { at: "2026-11-06T10:01:00Z" });
const recordComment = (head = HEAD, options = {}) => comment(`Paired eval: no loss.\n\n${recordLine(head)}\n`, options);

const run = (overrides = {}) =>
  decide({ pull: pull(), comments: [holdComment(), recordComment()], reviews: [], events, humans: HUMANS, ...overrides });

test("a listed human's VALID no-loss record at the current head releases an eval hold", () => {
  const result = run();
  assert.equal(result.release, true);
  assert.equal(result.head, HEAD);
});

test("a record for another head keeps the hold", () => {
  assert.deepEqual(run({ comments: [holdComment(), recordComment(OLD)] }), { release: false, reason: "record-head-mismatch" });
});

test("the newest record decides: a later record for an older head keeps the hold", () => {
  const comments = [holdComment(), recordComment(HEAD, { at: "2026-11-06T11:00:00Z" }), recordComment(OLD, { at: "2026-11-06T12:00:00Z" })];
  assert.equal(run({ comments }).reason, "record-head-mismatch");
});

test("a record from an account not on the list releases nothing", () => {
  assert.equal(run({ comments: [holdComment(), recordComment(HEAD, { user: STRANGER })] }).reason, "no-record");
});

test("a record posted through an App releases nothing", () => {
  assert.equal(run({ comments: [holdComment(), recordComment(HEAD, { app: { id: 1, slug: "some-app" } })] }).reason, "no-record");
});

test("a quoted or fenced record line releases nothing", () => {
  const quoted = comment(`> ${recordLine(HEAD)}`);
  const fenced = comment(`\`\`\`\n${recordLine(HEAD)}\n\`\`\``);
  const tilde = comment(`~~~md\n${recordLine(HEAD)}\n~~~`);
  for (const record of [quoted, fenced, tilde]) {
    assert.equal(run({ comments: [holdComment(), record] }).reason, "no-record");
  }
});

test("a record line with text around it on the same line releases nothing", () => {
  assert.equal(run({ comments: [holdComment(), comment(`see ${recordLine(HEAD)}`)] }).reason, "no-record");
});

test("a hold whose recorded reason is not eval is kept", () => {
  const superseded = comment(holdLine("superseded"), { at: "2026-11-06T10:01:00Z" });
  assert.equal(run({ comments: [superseded, recordComment()] }).reason, "hold-reason-superseded");
});

test("an eval reason beside any other reason since the label keeps the hold", () => {
  const other = comment(holdLine("r17-replacement"), { at: "2026-11-06T10:02:00Z" });
  assert.equal(run({ comments: [holdComment(), other, recordComment()] }).reason, "hold-reason-r17-replacement");
});

test("a hold line in any other shape keeps the hold", () => {
  const extra = comment("<!-- pr-hold reason=superseded by=#13440 -->", { at: "2026-11-06T10:02:00Z" });
  assert.equal(run({ comments: [holdComment(), extra, recordComment()] }).reason, "hold-reason-unknown");
});

test("a hold line any account posted counts: an App's other reason keeps the hold", () => {
  const app = comment(holdLine("superseded"), { user: APP, at: "2026-11-06T10:02:00Z", app: { id: 1, slug: "lanes" } });
  assert.equal(run({ comments: [holdComment(), app, recordComment()] }).reason, "hold-reason-superseded");
  const strangerEval = comment(holdLine("eval"), { user: STRANGER, at: "2026-11-06T10:02:00Z" });
  assert.equal(run({ comments: [strangerEval, recordComment()] }).reason, "hold-reason-unlisted-author");
});

test("a hold with no recorded reason is kept", () => {
  assert.equal(run({ comments: [recordComment()] }).reason, "no-hold-reason");
});

test("only reasons and records since the newest label event count", () => {
  const relabeled = [...events, { event: "labeled", label: { name: LABEL }, created_at: "2026-11-06T12:00:00Z" }];
  // The eval hold and its record came before the label went on again.
  assert.equal(run({ events: relabeled }).reason, "no-hold-reason");
  const newHold = comment(holdLine("eval"), { at: "2026-11-06T12:01:00Z" });
  assert.equal(run({ events: relabeled, comments: [holdComment(), recordComment(), newHold] }).reason, "no-record");
});

test("a pull request without the label is left alone", () => {
  assert.deepEqual(run({ pull: pull({ labels: [] }) }), { release: false, reason: "no-label" });
});

test("a body hold or a member veto keeps the hold", () => {
  assert.equal(run({ pull: pull({ body: "Closes #1\n\nHold: waiting on the desk" }) }).reason, "body-hold");
  const veto = comment(`Paired eval: no loss, but do not merge yet.\n${recordLine(HEAD)}`);
  assert.match(run({ comments: [holdComment(), veto] }).reason, /^member-veto-/);
});

test("ownLines drops fenced and quoted lines and keeps the rest", () => {
  assert.deepEqual([...ownLines("a\n```\nb\n```\n> c\nd")], ["a", "d"]);
});

// main: the comment names the record and the head, then the label comes off;
// a pull request that does not qualify gets neither.
const TRUSTED_DIR = mkdtempSync(join(tmpdir(), "release-eval-hold-"));
after(() => rmSync(TRUSTED_DIR, { recursive: true, force: true }));
const TRUSTED = join(TRUSTED_DIR, "trusted-actors.json");
writeFileSync(
  TRUSTED,
  JSON.stringify({
    version: 1,
    actors: [
      { id: PERSON.id, login: PERSON.login, kind: "human" },
      { id: APP.id, login: APP.login, kind: "bot" },
    ],
  }),
);

function fakeGitHub(pulls) {
  const calls = [];
  const github = async (method, path, body) => {
    calls.push({ method, path, body });
    const page = /[?&]page=([0-9]+)/.exec(path);
    if (page && page[1] !== "1") {
      return [];
    }
    if (method === "GET" && path.startsWith(`/repos/${REPO}/issues?state=open&labels=${LABEL}`)) {
      return Object.keys(pulls).map((n) => ({ number: Number(n), pull_request: {}, labels: [{ name: LABEL }] }));
    }
    const match = /^\/repos\/[^/]+\/[^/]+\/(pulls|issues)\/([0-9]+)(\/[a-z]+)?/.exec(path);
    const entry = pulls[match?.[2]];
    if (method === "GET" && match[1] === "pulls" && !match[3]) return entry.pull;
    if (method === "GET" && match[3] === "/comments") return entry.comments;
    if (method === "GET" && match[3] === "/events") return events;
    if (method === "GET" && match[3] === "/reviews") return [];
    if (method === "POST" || method === "DELETE") return null;
    throw new Error(`unexpected ${method} ${path}`);
  };
  return { github, calls };
}

test("main comments with the record's URL and head, then removes the label, and logs the outcome", async () => {
  const record = recordComment();
  const { github, calls } = fakeGitHub({
    7: { pull: pull(), comments: [holdComment(), record] },
    8: { pull: pull(), comments: [comment(holdLine("superseded"), { at: "2026-11-06T10:01:00Z" }), recordComment()] },
  });
  const lines = [];
  const log = console.log;
  console.log = (line) => lines.push(line);
  try {
    const code = await main({ env: { GITHUB_REPOSITORY: REPO, KILL_SWITCH: "proceed", TRUSTED_ACTORS_PATH: TRUSTED }, github, now: () => Date.parse("2026-11-06T11:30:00Z") });
    assert.equal(code, 0);
  } finally {
    console.log = log;
  }
  const writes = calls.filter((call) => call.method !== "GET");
  assert.deepEqual(
    writes.map((call) => `${call.method} ${call.path}`),
    [`POST /repos/${REPO}/issues/7/comments`, `DELETE /repos/${REPO}/issues/7/labels/${LABEL}`],
  );
  assert.ok(writes[0].body.body.includes(record.html_url));
  assert.ok(writes[0].body.body.includes(HEAD));
  assert.ok(lines.includes(`release-eval-hold: #7 released head=${HEAD} record=${record.html_url} wait-minutes=30`));
  assert.ok(lines.includes("release-eval-hold: #8 kept: no-eval-hold"));
  // #8 cost one read: its comments hold no eval hold.
  assert.deepEqual(
    calls.filter((call) => /\/(?:issues|pulls)\/8\b/.test(call.path)).map((call) => call.path.replace(/\?.*/, "")),
    [`/repos/${REPO}/issues/8/comments`],
  );
  assert.ok(lines.includes("release-eval-hold: held=2 released=1 kept=1 failed=0"));
});

test("main stops on the kill switch before any read", async () => {
  const { github, calls } = fakeGitHub({});
  assert.equal(await main({ env: { GITHUB_REPOSITORY: REPO, KILL_SWITCH: "", TRUSTED_ACTORS_PATH: TRUSTED }, github }), 0);
  assert.equal(calls.length, 0);
});

test("main releases at most RELEASES_PER_RUN a run", async () => {
  const pulls = Object.fromEntries(Array.from({ length: RELEASES_PER_RUN + 1 }, (_, i) => [String(10 + i), { pull: pull(), comments: [holdComment(), recordComment()] }]));
  const { github, calls } = fakeGitHub(pulls);
  const log = console.log;
  console.log = () => {};
  try {
    await main({ env: { GITHUB_REPOSITORY: REPO, KILL_SWITCH: "proceed", TRUSTED_ACTORS_PATH: TRUSTED }, github });
  } finally {
    console.log = log;
  }
  assert.equal(calls.filter((call) => call.method === "DELETE").length, RELEASES_PER_RUN);
});
