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
// When the model job's select step ran, before any model turn.
const RUN_STARTED = "2026-10-17T10:00:00Z";
// The base dependabot.yml's [ecosystem, directory] pairs: a fixture.
const PAIRS = [["github-actions", "/"], ["npm", "/"], ["npm", "/plugins/miro/server"], ["pip", "/plugins/speech"]];
const runOf = (overrides = {}) => ({
  version: 1,
  pr: 7,
  head_sha: HEAD,
  security: false,
  config_unreadable: false,
  files_truncated: false,
  started_at: RUN_STARTED,
  controls: [],
  config: PAIRS,
  output: output(),
  ...overrides,
});

// A commit GitHub signed for the lanes App after the model job started.
const laneCommit = (overrides = {}) => ({
  sha: FIX,
  author: { id: APP },
  committer: { id: 19864447 },
  commit: { committer: { date: "2026-10-17T10:05:00Z" }, verification: { verified: true, reason: "valid" } },
  ...overrides,
});
const landed = (overrides = {}) => ({ status: "ahead", total_commits: 1, commits: [laneCommit()], files: [{ filename: "package.json" }], ...overrides });

function fakeApi({ head = HEAD, state = "open", labels = [], body = "", compare = { status: "ahead", total_commits: 0, commits: [], files: [] }, comments = [], issues = [], failClose = false, files = [{ filename: "package.json" }, { filename: "package-lock.json" }] } = {}) {
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
    listPullFiles: async () => files,
    // The lane token holds no actions permission.
    getRun: async () => {
      throw new Error("403 Resource not accessible by integration");
    },
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
    runOf({ started_at: undefined }),
    runOf({ started_at: 1760695200 }),
    runOf({ started_at: "not a date" }),
    runOf({ started_at: "2026-10-17" }),
    runOf({ started_at: "2026-13-45T99:99:99Z" }),
    runOf({ config: undefined }),
    runOf({ config: "npm:/" }),
    runOf({ config: [["npm"]] }),
    runOf({ config: [["npm", 1]] }),
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

const fix = (overrides = {}) => runOf({ output: output({ verdict: "fix" }), ...overrides });

test("fix needs the lanes App's commits on top of the reviewed head", async () => {
  const ok = fakeApi({ head: FIX, compare: landed() });
  assert.deepEqual(await go(ok, fix()), { escalationReason: "", skipReason: "" });
  assert.match(ok.calls.comments[0], /verdict=fix/);
  const notLanded = fakeApi();
  assert.equal((await go(notLanded, fix())).escalationReason, "dependency-fix-not-landed");
  const rebased = fakeApi({ head: FIX, compare: landed({ status: "diverged", commits: [laneCommit({ author: { id: 49699333 } })] }) });
  assert.equal((await go(rebased, fix())).skipReason, "superseded-sha");
});

test("a fix commit is the lanes App's only when GitHub signed it for the App during this run", async () => {
  const forged = {
    "another author": laneCommit({ author: { id: 5 } }),
    "no author account": laneCommit({ author: null }),
    "a committer other than web-flow": laneCommit({ committer: { id: APP } }),
    "an unverified signature": laneCommit({ commit: { committer: { date: "2026-10-17T10:05:00Z" }, verification: { verified: false, reason: "unsigned" } } }),
    "a verified signature whose reason is not valid": laneCommit({ commit: { committer: { date: "2026-10-17T10:05:00Z" }, verification: { verified: true, reason: "unknown_key" } } }),
    "a commit made before this run": laneCommit({ commit: { committer: { date: "2026-10-17T09:59:59Z" }, verification: { verified: true, reason: "valid" } } }),
    "no commit date": laneCommit({ commit: { verification: { verified: true, reason: "valid" } } }),
  };
  for (const [why, commit] of Object.entries(forged)) {
    const api = fakeApi({ head: FIX, compare: landed({ commits: [commit] }) });
    assert.deepEqual(await go(api, fix()), { escalationReason: "", skipReason: "superseded-sha" }, why);
    assert.deepEqual(api.calls.comments, [], `${why}: no fix marker`);
  }
});

test("a fix whose comparison is not listed whole is invalid", async () => {
  const many = (n, name = (i) => `f${i}.js`) => Array.from({ length: n }, (_, i) => ({ filename: name(i) }));
  const cases = {
    "no files key": landed({ files: undefined }),
    "a files value that is not a list": landed({ files: { filename: "x" } }),
    "no commits key": landed({ commits: undefined }),
    "300 files, the listing's limit": landed({ files: many(300) }),
    "250 commits, the listing's limit": landed({ total_commits: 250, commits: Array.from({ length: 250 }, () => laneCommit()) }),
    "fewer commits listed than the total": landed({ total_commits: 2 }),
    "no total": landed({ total_commits: undefined }),
  };
  for (const [why, compare] of Object.entries(cases)) {
    const api = fakeApi({ head: FIX, compare });
    assert.equal((await go(api, fix())).escalationReason, "dependency-invalid", why);
    assert.match(api.calls.comments[0], /verdict=invalid/, why);
  }
  const under = fakeApi({ head: FIX, compare: landed({ files: many(299, () => "package.json") }) });
  assert.equal((await go(under, fix())).escalationReason, "", "299 files is a whole listing");
});

test("a .github/ path in the 300th file of a capped listing is still invalid", async () => {
  const files = Array.from({ length: 300 }, (_, i) => ({ filename: i === 299 ? ".github/workflows/x.yml" : `f${i}.js` }));
  assert.equal((await go(fakeApi({ head: FIX, compare: landed({ files }) }), fix())).escalationReason, "dependency-invalid");
});

test("a fix commit's date is bounded by the run.json start time, with no Actions API read", async () => {
  const at = (date) => laneCommit({ commit: { committer: { date }, verification: { verified: true, reason: "valid" } } });
  const onTheSecond = fakeApi({ head: FIX, compare: landed({ commits: [at(RUN_STARTED)] }) });
  assert.deepEqual(await go(onTheSecond, fix()), { escalationReason: "", skipReason: "" });
  const later = fakeApi({ head: FIX, compare: landed({ commits: [at("2026-10-17T10:05:00Z")] }) });
  assert.deepEqual(await go(later, fix({ started_at: "2026-10-17T10:05:01Z" })), { escalationReason: "", skipReason: "superseded-sha" });
});

test("a merge verdict from a model that read a truncated files listing escalates and posts no merge marker", async () => {
  const api = fakeApi();
  const result = await go(api, runOf({ files_truncated: true }));
  assert.equal(result.escalationReason, "dependency-files-truncated");
  assert.doesNotMatch(api.calls.comments.join("\n"), /verdict=merge/);
  assert.match(api.calls.comments[0], /verdict=escalate/);
  assert.throws(() => validateRun(runOf({ files_truncated: "no" }), 7), /invalid/i);
  const older = runOf();
  delete older.files_truncated;
  assert.throws(() => validateRun(older, 7), /invalid/i, "a run.json without the flag is not the runner's");
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

test("a fix that landed a path other than an npm or pip manifest or lock file outside .github/ is invalid", async () => {
  for (const file of [
    { filename: ".github/workflows/x.yml" },
    { filename: "x.yml", previous_filename: ".github/x.yml" },
    { filename: "src/index.js" },
    { filename: "package.json", previous_filename: "src/index.js" },
    { filename: ".github/actions/resolve-config/package.json" },
    { filename: "setup.py" },
    { filename: "plugins/unlisted/package.json" },
  ]) {
    const api = fakeApi({ head: FIX, compare: landed({ files: [file] }) });
    assert.equal((await go(api, fix())).escalationReason, "dependency-invalid", JSON.stringify(file));
  }
});

test("a fix that landed only manifests and lock files is recorded", async () => {
  const files = [{ filename: "plugins/miro/server/package.json" }, { filename: "plugins/miro/server/package-lock.json" }, { filename: "plugins/speech/requirements.txt" }];
  assert.deepEqual(await go(fakeApi({ head: FIX, compare: landed({ files }) }), fix()), { escalationReason: "", skipReason: "" });
  const unreadable = fakeApi({ head: FIX, compare: landed({ files }) });
  assert.equal((await go(unreadable, fix({ config: [] }))).escalationReason, "dependency-invalid", "no config pairs admit no fix");
});

test("a merge verdict on a pull request that changes a workflow or action file escalates and posts no merge marker", async () => {
  for (const file of [
    { filename: ".github/workflows/ci.yml" },
    { filename: ".github/actions/check-wip-cap/action.yml" },
    { filename: "x.yml", previous_filename: ".github/workflows/old.yml" },
  ]) {
    const api = fakeApi({ files: [{ filename: "package.json" }, file] });
    const result = await go(api, runOf());
    assert.equal(result.escalationReason, "dependency-workflow-held", JSON.stringify(file));
    assert.doesNotMatch(api.calls.comments.join("\n"), /verdict=merge/);
    assert.match(api.calls.comments[0], /verdict=escalate/);
  }
  // A manifest under .github/ is not a workflow file.
  assert.equal((await go(fakeApi({ files: [{ filename: ".github/actions/resolve-config/package.json" }] }), runOf())).escalationReason, "");
});

test("a merge verdict whose files listing reads at its limit escalates as truncated", async () => {
  const files = Array.from({ length: 3000 }, (_, i) => ({ filename: `p${i}/package.json` }));
  assert.equal((await go(fakeApi({ files }), runOf())).escalationReason, "dependency-files-truncated");
});

test("a merge verdict on an unreadable Dependabot config escalates and posts no merge marker", async () => {
  const api = fakeApi();
  const result = await go(api, runOf({ config_unreadable: true }));
  assert.equal(result.escalationReason, "dependency-config-unreadable");
  assert.doesNotMatch(api.calls.comments.join("\n"), /verdict=merge/);
  assert.throws(() => validateRun(runOf({ config_unreadable: "no" }), 7), /invalid/i);
});

const CONTROL = "docs/conventions/pr-pipeline/README.md#review-only-dependencies";

test("a merge verdict on a review-only dependency must quote each matched control verbatim", async () => {
  const cited = output({ evidence: [`${CONTROL}: provenance unchanged from 2.5.13`, ".node-version:1"] });
  const merged = fakeApi();
  assert.equal((await go(merged, runOf({ controls: [CONTROL], output: cited }))).escalationReason, "");
  assert.match(merged.calls.comments.join("\n"), /verdict=merge/);
  for (const evidence of [[".node-version:1"], ["docs/conventions/pr-pipeline/README.md"], [CONTROL.toUpperCase()]]) {
    const api = fakeApi();
    const result = await go(api, runOf({ controls: [CONTROL], output: output({ evidence }) }));
    assert.equal(result.escalationReason, "dependency-control-uncited", JSON.stringify(evidence));
    assert.doesNotMatch(api.calls.comments.join("\n"), /verdict=merge/);
    assert.match(api.calls.comments.join("\n"), /verdict=escalate/);
  }
  // Every control, not just one.
  const two = fakeApi();
  assert.equal((await go(two, runOf({ controls: [CONTROL, "docs/y.md#z"], output: cited }))).escalationReason, "dependency-control-uncited");
  // No control to cite: a merge stands, and a non-merge verdict is not checked.
  assert.equal((await go(fakeApi(), runOf())).escalationReason, "");
  assert.equal((await go(fakeApi(), runOf({ controls: [CONTROL], output: output({ verdict: "escalate" }) }))).escalationReason, "dependency-escalate");
});

test("validateRun refuses a run.json without a list of controls", () => {
  for (const controls of [undefined, "x", [1], [""], Array(21).fill("c")]) {
    const run = runOf({ controls });
    if (controls === undefined) delete run.controls;
    assert.throws(() => validateRun(run, 7), /invalid/i, JSON.stringify(controls));
  }
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
