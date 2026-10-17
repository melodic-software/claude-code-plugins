import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";

import { apply, main, validateRun } from "./apply-dependency-verdict.mjs";

const HEAD = "a".repeat(40);
const FIX = "f".repeat(40);
const APP = 337595936;

const output = (overrides = {}) => ({
  verdict: "merge",
  reasons: ["The major bump drops Node 18; this repository pins Node 24."],
  evidence: [".node-version:1"],
  ...overrides,
});
const runOf = (overrides = {}) => ({ version: 1, pr: 7, head_sha: HEAD, security: false, config_unreadable: false, output: output(), ...overrides });

function fakeApi({ head = HEAD, state = "open", labels = [], body = "", compare = { status: "ahead", commits: [], files: [] }, comments = [], issues = [], failClose = false } = {}) {
  // State persists across calls, so a second apply() is a re-run.
  const calls = { comments: [], closed: [], issues: [] };
  const pull = { number: 7, state, head: { sha: head }, labels: labels.map((name) => ({ name })), body, title: "bump x from 1.0.0 to 2.0.0" };
  const api = {
    calls,
    pull,
    failClose,
    getPull: async () => ({ ...pull }),
    listIssueComments: async () => comments,
    compare: async () => compare,
    createIssueComment: async (pr, text) => {
      calls.comments.push(text);
      comments.push({ user: { id: APP }, body: text });
    },
    listIssues: async () => issues,
    closePull: async (pr) => {
      if (api.failClose) throw new Error("close failed");
      calls.closed.push(pr);
      pull.state = "closed";
    },
    createIssue: async (fields) => {
      calls.issues.push(fields);
      const issue = { number: 99, user: { id: APP }, body: fields.body };
      issues.push(issue);
      return issue;
    },
  };
  return api;
}

const go = (api, run, extra = {}) => apply({ api, pr: 7, appId: APP, modelRun: "11-1", run, log: () => {}, ...extra });

test("validateRun accepts the runner's record and refuses anything off the template", () => {
  assert.deepEqual(validateRun(runOf(), 7).output.verdict, "merge");
  const bad = [
    runOf({ version: 2 }),
    runOf({ pr: 8 }),
    runOf({ head_sha: "nope" }),
    runOf({ output: null }),
    runOf({ output: output({ verdict: "ship-it" }) }),
    runOf({ output: output({ reasons: [] }) }),
    runOf({ output: output({ reasons: ["x".repeat(501)] }) }),
    runOf({ output: output({ reasons: ["ping @someone"] }) }),
    runOf({ output: output({ reasons: ["hide <!-- this -->"] }) }),
    runOf({ output: output({ reasons: ["fence ``` break"] }) }),
    runOf({ output: output({ reasons: ["bell \u0007"] }) }),
    runOf({ output: output({ evidence: Array(21).fill("a:1") }) }),
    runOf({ output: { ...output(), extra: 1 } }),
  ];
  for (const run of bad) {
    assert.throws(() => validateRun(run, 7), /invalid/i, JSON.stringify(run).slice(0, 120));
  }
});

test("merge posts the round marker the pr-merge lane reads, and nothing else", async () => {
  const api = fakeApi();
  const result = await go(api, runOf());
  assert.equal(result.escalationReason, "");
  assert.equal(api.calls.comments.length, 1);
  assert.match(api.calls.comments[0], /^<!-- pr-unblock:review-dependency-round head=a{40} verdict=merge run=11-1 -->\n/);
  assert.deepEqual(api.calls.closed, []);
});

test("a head that moved since the review is superseded for merge, close and escalate", async () => {
  for (const verdict of ["merge", "close", "escalate"]) {
    const api = fakeApi({ head: FIX });
    const result = await go(api, runOf({ output: output({ verdict }) }));
    assert.equal(result.skipReason, "superseded-sha", verdict);
    assert.equal(result.escalationReason, "", verdict);
    assert.deepEqual(api.calls.closed, []);
  }
});

test("fix needs the lanes App's commits on top of the reviewed head", async () => {
  const landed = fakeApi({ head: FIX, compare: { status: "ahead", commits: [{ author: { id: APP } }] } });
  assert.equal((await go(landed, runOf({ output: output({ verdict: "fix" }) }))).escalationReason, "");
  const notLanded = fakeApi();
  assert.equal((await go(notLanded, runOf({ output: output({ verdict: "fix" }) }))).escalationReason, "dependency-fix-not-landed");
  const rebased = fakeApi({ head: FIX, compare: { status: "diverged", commits: [{ author: { id: 49699333 } }] } });
  assert.equal((await go(rebased, runOf({ output: output({ verdict: "fix" }) }))).skipReason, "superseded-sha");
});

test("close files the ignore issue, then closes the pull request", async () => {
  const api = fakeApi();
  const result = await go(api, runOf({ output: output({ verdict: "close" }) }));
  assert.equal(result.escalationReason, "");
  assert.equal(api.calls.issues.length, 1);
  assert.match(api.calls.issues[0].body, /ignore:/);
  assert.match(api.calls.issues[0].body, /#7/);
  assert.deepEqual(api.calls.closed, [7]);
  assert.match(api.calls.comments.at(-1), /verdict=close/);
});

test("close resumes after a failed close without filing a second issue", async () => {
  const api = fakeApi({ failClose: true });
  const close = runOf({ output: output({ verdict: "close" }) });
  await assert.rejects(go(api, close), /close failed/);
  api.failClose = false;
  const result = await go(api, close);
  assert.equal(result.escalationReason, "");
  assert.equal(api.calls.issues.length, 1);
  assert.equal(api.calls.comments.length, 1);
  assert.deepEqual(api.calls.closed, [7]);
});

test("close resumes on a closed pull request whose issue is filed but whose marker is missing", async () => {
  const api = fakeApi({ state: "closed" });
  const close = runOf({ output: output({ verdict: "close" }) });
  assert.equal((await go(api, close)).skipReason, "not-applicable", "a PR someone else closed gets nothing");
  await api.createIssue({ body: `<!-- pr-unblock:dependency-ignore pr=7 head=${HEAD} -->\nbody` });
  const result = await go(api, close);
  assert.equal(result.skipReason, "");
  assert.equal(api.calls.issues.length, 1, "the existing issue is reused");
  assert.match(api.calls.comments.at(-1), /verdict=close/);
  assert.deepEqual(api.calls.closed, [], "a closed PR is not closed again");
});

test("an ignore issue for another head, or by another author, is not reused", async () => {
  const api = fakeApi({
    issues: [
      { number: 1, user: { id: APP }, body: `<!-- pr-unblock:dependency-ignore pr=7 head=${FIX} -->` },
      { number: 2, user: { id: 5 }, body: `<!-- pr-unblock:dependency-ignore pr=7 head=${HEAD} -->` },
    ],
  });
  await go(api, runOf({ output: output({ verdict: "close" }) }));
  assert.equal(api.calls.issues.length, 1);
});

test("a run with no model attempt posts its `none` marker once across re-runs", async () => {
  const api = fakeApi();
  await go(api, runOf(), { modelRun: null });
  await go(api, runOf(), { modelRun: null });
  assert.equal(api.calls.comments.length, 1);
  assert.match(api.calls.comments[0], /run=none -->/);
});

test("a fix that changed a path under .github/ is invalid", async () => {
  const api = fakeApi({
    head: FIX,
    compare: { status: "ahead", commits: [{ author: { id: APP } }], files: [{ filename: ".github/workflows/x.yml" }] },
  });
  assert.equal((await go(api, runOf({ output: output({ verdict: "fix" }) }))).escalationReason, "dependency-invalid");
});

test("a merge verdict on an unreadable Dependabot config escalates and posts no merge marker", async () => {
  const api = fakeApi();
  const result = await go(api, runOf({ config_unreadable: true }));
  assert.equal(result.escalationReason, "dependency-config-unreadable");
  assert.doesNotMatch(api.calls.comments.join("\n"), /verdict=merge/);
  assert.throws(() => validateRun(runOf({ config_unreadable: "no" }), 7), /invalid/i);
});

test("a security update is never closed: it escalates", async () => {
  for (const api of [fakeApi({ labels: ["security"] }), fakeApi({ body: "Fixes CVE-2026-12345" })]) {
    const result = await go(api, runOf({ output: output({ verdict: "close" }) }));
    assert.equal(result.escalationReason, "dependency-security-close");
    assert.deepEqual(api.calls.closed, []);
    assert.deepEqual(api.calls.issues, []);
  }
  const flagged = fakeApi();
  assert.equal((await go(flagged, runOf({ security: true, output: output({ verdict: "close" }) }))).escalationReason, "dependency-security-close");
});

test("escalate hands the pull request to a person", async () => {
  const api = fakeApi();
  assert.equal((await go(api, runOf({ output: output({ verdict: "escalate" }) }))).escalationReason, "dependency-escalate");
});

test("a pull request that is no longer open gets nothing", async () => {
  const api = fakeApi({ state: "closed" });
  const result = await go(api, runOf());
  assert.equal(result.skipReason, "not-applicable");
  assert.deepEqual(api.calls.comments, []);
});

test("a re-run that finds its own round marker posts nothing again", async () => {
  const api = fakeApi({ comments: [{ user: { id: APP }, body: `<!-- pr-unblock:review-dependency-round head=${HEAD} verdict=merge run=11-1 -->` }] });
  await go(api, runOf());
  assert.deepEqual(api.calls.comments, []);
});

test("main escalates dependency-invalid on a run.json whose SHA-256 does not match", async () => {
  const dir = mkdtempSync(join(tmpdir(), "apply-dependency-"));
  const text = `${JSON.stringify(runOf())}\n`;
  writeFileSync(join(dir, "run.json"), text);
  const env = {
    GH_TOKEN: "t",
    GITHUB_REPOSITORY: "o/r",
    PR_NUMBER: "7",
    HEAD_SHA: HEAD,
    GITHUB_RUN_ID: "11",
    DEPENDENCY_RUN_ATTEMPT: "1",
    APP_SENDER_ID: String(APP),
    DEPENDENCY_VERDICT_DIR: dir,
    DEPENDENCY_RUN_SHA256: "0".repeat(64),
    SKIP_REASON_FILE: join(dir, "skip"),
    ESCALATION_REASON_FILE: join(dir, "escalation"),
  };
  const api = fakeApi();
  await main(env, { api, log: () => {} });
  assert.equal(readFileSync(env.ESCALATION_REASON_FILE, "utf8"), "dependency-invalid\n");
  assert.match(api.calls.comments[0], /verdict=invalid/);
  const good = { ...env, DEPENDENCY_RUN_SHA256: createHash("sha256").update(text).digest("hex"), ESCALATION_REASON_FILE: join(dir, "e2") };
  await main(good, { api: fakeApi(), log: () => {} });
  assert.throws(() => readFileSync(good.ESCALATION_REASON_FILE));
});
