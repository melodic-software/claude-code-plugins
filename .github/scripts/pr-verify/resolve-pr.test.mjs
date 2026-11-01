// Expected values come from the verdict rules in
// docs/conventions/pr-pipeline/README.md ("Verifier verdict"): only a successful pr-require-checks pull_request run of this
// repository starts a verdict, for exactly one open same-repository PR into
// main whose head is the run's head SHA; the head is the run's, and the base
// SHA is the PR's; a head with a counted verdict from a completed run (a FAIL
// under any number the commit's pull requests carry) is not judged again, but a run still going or one that
// uploaded nothing does not stop a new judgment; with merge.verify-authors
// `lane` (the default) only a PR the lanes App (merge.agent-identity, a Bot
// account) opened is judged, `any` judges every author, and any other value
// judges none. Response shapes follow GET
// /actions/runs/{id}, /commits/{sha}/pulls, /actions/artifacts?name= (only
// artifacts with that name are returned) and the closingIssuesReferences
// GraphQL field.
import assert from "node:assert/strict";
import { readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import { test } from "node:test";

import { createRateLimitLatch } from "../../actions/log-api-budget/rate-guard.mjs";
import { CARRY_MAX, carryMain, CONTRACT_STEP, DO_NOT_MERGE_LINE, failureAnnotation, HOLD_STEP, main, packReads, resolvePull, takeReads, tooOld } from "./resolve-pr.mjs";

// Created 2026-07-25, too old from 2026-10-13 (TOO_OLD_DAYS 80), cleared by a
// fresh pass until 2026-10-21 (90-day FAIL retention less 2 days).
test("tooOld judges a head again only past the age with no pass made since", () => {
  const created = "2026-07-25T00:00:00Z";
  const now = Date.parse("2026-10-19T00:00:00Z");
  const OLD = "2026-10-01T00:00:00Z";
  const FRESH = "2026-10-14T00:00:00Z";
  assert.equal(tooOld([OLD], [OLD], created, now), true);
  // The newest-started run decides, as the gate's `_newest`.
  assert.equal(tooOld([OLD, FRESH], [OLD, FRESH], created, now), false);
  // A re-attempt of an old run starts later but keeps its creation time.
  assert.equal(tooOld([FRESH], [OLD], created, now), true);
  assert.equal(tooOld([FRESH, OLD], [OLD, FRESH], created, now), true);
  // A missing start time weighs every pass.
  assert.equal(tooOld([null, FRESH], [FRESH, OLD], created, now), true);
  assert.equal(tooOld([null, FRESH], [FRESH, FRESH], created, now), false);
  assert.equal(tooOld([OLD], [null], created, now), true);
  // Not yet too old, past the FAIL retention ceiling, or no creation time.
  assert.equal(tooOld([OLD], [OLD], created, Date.parse("2026-10-12T00:00:00Z")), false);
  assert.equal(tooOld([OLD], [OLD], created, Date.parse("2026-10-21T00:00:00Z")), false);
  assert.equal(tooOld([OLD], [OLD], undefined, now), false);
});
import { artifactName } from "./write-verdict.mjs";
import { bodyVersion, loadRules, REFINE_MARKER, splitItemsLine } from "../intake-triage/admit.mjs";
import { holds, labelHolds } from "../pr-merge/merge-holds.mjs";
import { tempDir } from "../../../lib/test-tmp.mjs";

const REPO = "example-org/example-repo";
const HEAD = "a".repeat(40);
const OWNER_ID = 153232337;
const BASE = "b".repeat(40);
const MAIN = "c".repeat(40);
const RUN = 5551;
const ISSUE = {
  number: 7,
  repository: { nameWithOwner: REPO },
  body: "the spec",
  lastEditedAt: null,
  author: { __typename: "User", login: "maintainer", databaseId: 100 },
  editor: null,
  comments: { totalCount: 0, nodes: [] },
};
const LINKED = {
  number: 7,
  author_login: "maintainer",
  author_id: 100,
  author_type: "User",
  last_edited_at: null,
  editor_login: null,
  editor_id: null,
  editor_type: null,
  spec_comments: [],
};
const HUMANS = new Set([100]);
const LANE = "melodic-automation-lanes[bot]";
// A verify run's start, after every edit the fixtures below make.
const JUDGED_AT = "2026-10-21T00:00:00Z";
// When the pull request was opened: after every fixture comment but those a test posts later.
const PR_OPENED = "2026-10-20T00:00:00Z";

const upstream = (overrides = {}) => ({
  id: RUN,
  path: ".github/workflows/pr-require-checks.yml",
  event: "pull_request",
  status: "completed",
  conclusion: "success",
  head_sha: HEAD,
  repository: { full_name: REPO },
  head_repository: { full_name: REPO },
  ...overrides,
});

// The first 16 hex digits of `printf %s <ref> | sha256sum`, for feat/x and feat/other.
const REF_DIGEST = "79b4cc554b80dca6";
const OTHER_DIGEST = "3b0035df584451e9";
const pull = (overrides = {}) => ({
  number: 41,
  state: "open",
  draft: false,
  user: { id: 337595936, login: LANE, type: "Bot" },
  head: { sha: HEAD, ref: "feat/x", repo: { full_name: REPO } },
  base: { ref: "main", sha: BASE },
  ...overrides,
});

const verifyRun = (id, overrides = {}) => ({
  id,
  path: ".github/workflows/pr-verify.yml",
  event: "workflow_run",
  status: "completed",
  conclusion: "success",
  head_branch: "main",
  head_sha: MAIN,
  repository: { full_name: REPO },
  head_repository: { full_name: REPO },
  created_at: JUDGED_AT,
  run_started_at: JUDGED_AT,
  ...overrides,
});

const artifact = (name, runId, expired = false) => ({ name, expired, workflow_run: { id: runId } });

function fake({ run = upstream(), pulls = [pull()], artifacts = [], runs = {}, onMain = [MAIN], issues = [ISSUE], edit = { lastEditedAt: null, editor: null }, restFails = false, associated = [], body: prBody = null, refs = {}, queries = [], renames = [], relink, jobs } = {}) {
  const github = async (method, apiPath, body) => {
    if (apiPath === `/repos/${REPO}/actions/runs/${RUN}`) return run;
    if (apiPath === `/repos/${REPO}/actions/runs/${RUN}/jobs?filter=latest&per_page=100` && jobs) return jobs;
    const listed = /\/commits\/([0-9a-f]+)\/pulls\?per_page=100&page=(\d+)$/.exec(apiPath);
    if (listed && restFails) throw new Error(`GET ${apiPath} failed with status 500`);
    if (listed && listed[1] === HEAD) return pulls.slice((Number(listed[2]) - 1) * 100, Number(listed[2]) * 100);
    if (apiPath === "/graphql" && body.query.includes("associatedPullRequests")) {
      assert.deepEqual(body.variables, { owner: "example-org", name: "example-repo", oid: HEAD });
      return { data: { repository: { object: { associatedPullRequests: { nodes: associated, pageInfo: { hasNextPage: false } } } } } };
    }
    if (apiPath === "/graphql" && body.query.includes("issueOrPullRequest")) {
      queries.push(body.variables.number);
      const n = body.variables.number;
      // GitHub's answer for a number that names nothing, as a live read of a
      // missing number returned it; refs[n] may also be a whole answer.
      if (!(n in refs)) {
        return { data: { repository: { issueOrPullRequest: null } }, errors: [{ type: "NOT_FOUND", path: ["repository", "issueOrPullRequest"], message: `Could not resolve to an issue or pull request with the number of ${n}.` }] };
      }
      return refs[n]?.answer ?? { data: { repository: { issueOrPullRequest: refs[n] } } };
    }
    // The pull request's RenamedTitleEvent timeline, oldest first; `renames`
    // may also be a whole answer.
    if (apiPath === "/graphql" && body.query.includes("RENAMED_TITLE_EVENT")) {
      assert.equal(body.variables.number, 41);
      if (!Array.isArray(renames)) return renames;
      const nodes = renames.map((actor) => ({ __typename: "RenamedTitleEvent", actor }));
      return { data: { repository: { pullRequest: { timelineItems: { nodes, pageInfo: { hasNextPage: false, endCursor: null } } } } } };
    }
    // The pull request's body edits and issue connect and disconnect events
    // (RELINK_QUERY); with none given the read fails, which keeps a FAIL.
    if (apiPath === "/graphql" && body.query.includes("userContentEdits")) {
      assert.deepEqual(body.variables, { o: "example-org", r: "example-repo", n: 41 });
      if (relink === undefined) throw new Error("POST /graphql failed with status 502");
      return relink;
    }
    if (apiPath === "/graphql") {
      return { data: { repository: { pullRequest: { createdAt: PR_OPENED, ...edit, body: prBody, closingIssuesReferences: { totalCount: issues.length, nodes: issues } } } } };
    }
    const named = /\/actions\/artifacts\?name=([^&]+)&per_page=100&page=(\d+)$/.exec(apiPath);
    if (named) {
      const matching = artifacts.filter((item) => item.name === decodeURIComponent(named[1]));
      return { total_count: matching.length, artifacts: matching.slice((Number(named[2]) - 1) * 100, Number(named[2]) * 100) };
    }
    const other = /\/actions\/runs\/(\d+)$/.exec(apiPath);
    if (other && runs[other[1]]) return runs[other[1]];
    const compare = /\/compare\/([0-9a-f]+)\.\.\.main$/.exec(apiPath);
    if (compare) return { status: onMain.includes(compare[1]) ? "ahead" : "diverged" };
    throw new Error(`unexpected ${method} ${apiPath}`);
  };
  return github;
}

const resolve = (setup, options = {}) =>
  resolvePull({ github: fake(setup), repository: REPO, upstreamRunId: String(RUN), humans: HUMANS, laneIdentity: LANE, ...options });
const reason = async (setup, options) => (await resolve(setup, options)).reason;
const HUMAN_PR = pull({ user: { id: 100, login: "maintainer", type: "User" } });

test("a passing same-repository run resolves its one PR at the run's head", async () => {
  assert.deepEqual(await resolve(), {
    proceed: true,
    reason: "ok",
    prNumber: 41,
    headSha: HEAD,
    baseSha: BASE,
    headRef: "feat/x",
    linkedIssues: [LINKED],
    specKind: "closes",
    specText: [{ number: 7, spec_kind: "closes", body: "the spec", comments: [] }],
    // The fixture's run names no head commit time, so a relink cannot be ruled out.
    relinkSinceHead: true,
  });
});

// pull()'s pull request as GraphQL's associatedPullRequests returns it: the
// App's login without "[bot]", the state in capitals.
const GRAPHQL_PULL = {
  number: 41,
  state: "OPEN",
  isDraft: false,
  headRefName: "feat/x",
  headRefOid: HEAD,
  baseRefName: "main",
  baseRefOid: BASE,
  headRepository: { nameWithOwner: REPO },
  author: { __typename: "Bot", login: "melodic-automation-lanes", databaseId: 337595936 },
  labels: { nodes: [], pageInfo: { hasNextPage: false } },
};

test("a commit pulls read that fails falls back to GraphQL and resolves the same PR", async () => {
  const fallback = await resolve({ restFails: true, associated: [GRAPHQL_PULL, { ...GRAPHQL_PULL, number: 12, state: "MERGED" }] });
  assert.deepEqual(fallback, await resolve());
});

test("a GraphQL fallback whose only PR is a draft skips as a draft", async () => {
  assert.equal(await reason({ restFails: true, associated: [{ ...GRAPHQL_PULL, isDraft: true }] }), "draft");
});

test("a linked issue in another repository is left out", async () => {
  const foreign = { ...ISSUE, number: 9, repository: { nameWithOwner: "someone/else" } };
  assert.deepEqual((await resolve({ issues: [foreign] })).linkedIssues, []);
});

// Owner decision 2026-10-23: a PR that closes no issue reads the one issue a
// plain `Refs: #<n>` line names as its spec, as babysit_merge_policy does.
const REFS_ISSUE = { __typename: "Issue", ...ISSUE };

test("a PR that closes no issue is judged against the one issue its Refs line names", async () => {
  const queries = [];
  const resolved = await resolve({ issues: [], body: "Refs: #7\n\nPart one.", refs: { 7: REFS_ISSUE }, queries });
  assert.deepEqual(resolved.linkedIssues, [LINKED]);
  assert.deepEqual(resolved.specText, [{ number: 7, spec_kind: "refs", body: "the spec", comments: [] }]);
  assert.equal(resolved.specKind, "refs");
  assert.deepEqual(queries, [7]);
});

test("a closing issue wins over a Refs line, which is then never read", async () => {
  const queries = [];
  const resolved = await resolve({ body: "Refs: #8", refs: { 8: { ...REFS_ISSUE, number: 8 } }, queries });
  assert.deepEqual(resolved.linkedIssues, [LINKED]);
  assert.deepEqual(queries, []);
});

test("a hidden, ambiguous or non-issue Refs line names no spec", async () => {
  // The kind each link gives the verifier: closes, refs, none, or the PR's own text.
  assert.equal((await resolve({ body: "Refs: #8" })).specKind, "closes");
  assert.equal((await resolve({ issues: [] })).specKind, "none");
  for (const [prBody, refs] of [
    ["<!-- Refs: #7 -->", { 7: REFS_ISSUE }],
    ["```\nRefs: #7\n```", { 7: REFS_ISSUE }],
    ["Refs: #7\nRefs: #8", { 7: REFS_ISSUE }],
    ["Refs: other/repo#7", { 7: REFS_ISSUE }],
    ["Refs: #7", { 7: { __typename: "PullRequest" } }],
    ["Refs: #7", { 7: { ...REFS_ISSUE, repository: { nameWithOwner: "someone/else" } } }],
  ]) {
    const resolved = await resolve({ issues: [], body: prBody, refs });
    assert.deepEqual([resolved.linkedIssues, resolved.specText, resolved.specKind], [[], [], "none"], prBody);
  }
});

test("a Refs number that names no issue or pull request names no spec, and any other error stops the run", async () => {
  const resolved = await resolve({ issues: [], body: "Refs: #99999" });
  assert.deepEqual([resolved.proceed, resolved.linkedIssues, resolved.specText, resolved.specKind], [true, [], [], "none"]);
  for (const errors of [
    [{ type: "RATE_LIMITED", path: ["repository", "issueOrPullRequest"] }],
    [{ type: "NOT_FOUND", path: ["repository"] }],
    [{ type: "NOT_FOUND", path: ["repository", "issueOrPullRequest"] }, { type: "INTERNAL" }],
  ]) {
    const answer = { data: { repository: { issueOrPullRequest: null } }, errors };
    await assert.rejects(resolve({ issues: [], body: "Refs: #7", refs: { 7: { answer } } }), /the Refs issue could not be read/, JSON.stringify(errors));
  }
  // No errors and no repository, or a null issue without NOT_FOUND, is no
  // answer, not "no issue".
  for (const answer of [{ data: {} }, { data: { repository: null } }, {}, { data: { repository: { issueOrPullRequest: null } } }]) {
    await assert.rejects(resolve({ issues: [], body: "Refs: #7", refs: { 7: { answer } } }), /the Refs issue could not be read/, JSON.stringify(answer));
  }
});

// The production helper throws on any GraphQL `errors` unless asked to keep
// them, so main must read the Refs issue with one that keeps them.
test("main with the real GitHub helper reads a Refs typo as no linked issue", async () => {
  const dir = tempDir("pr-verify-");
  const actors = path.join(dir, "trusted-actors.json");
  writeFileSync(actors, JSON.stringify({ version: 1, actors: [{ id: 100, login: "maintainer", kind: "human" }] }));
  const env = {
    GITHUB_TOKEN: "t",
    GITHUB_REPOSITORY: REPO,
    GITHUB_OUTPUT: path.join(dir, "out"),
    UPSTREAM_RUN_ID: String(RUN),
    SPEC_FILE: path.join(dir, "spec.json"),
    SPEC_TEXT_FILE: path.join(dir, "spec-text.json"),
    TRUSTED_ACTORS_PATH: actors,
    LANE_IDENTITY: LANE,
  };
  const github = fake({ issues: [], body: "Refs: #99999" });
  const fetchImpl = async (url, init) => {
    const body = init.body === undefined ? undefined : JSON.parse(init.body);
    const json = await github(init.method, new URL(url).pathname + new URL(url).search, body);
    return new Response(JSON.stringify(json), { status: 200, headers: { "Content-Type": "application/json" } });
  };
  await main(env, { fetchImpl });
  assert.match(readFileSync(env.GITHUB_OUTPUT, "utf8"), /^proceed=true\nreason=ok\n/);
  assert.deepEqual(JSON.parse(readFileSync(env.SPEC_FILE, "utf8")), []);
});

// retry-after latches the rate guard, so main gets a latch of its own.
test("a refused upstream-run read's annotation carries the status, the rate-limit headers and the body prefix", async () => {
  const dir = tempDir("pr-verify-");
  const actors = path.join(dir, "trusted-actors.json");
  writeFileSync(actors, JSON.stringify({ version: 1, actors: [{ id: 100, login: "maintainer", kind: "human" }] }));
  const env = {
    GITHUB_TOKEN: "bad-token",
    GITHUB_API_URL: "https://api.example.test",
    GITHUB_REPOSITORY: REPO,
    GITHUB_OUTPUT: path.join(dir, "out"),
    UPSTREAM_RUN_ID: String(RUN),
    SPEC_FILE: path.join(dir, "spec.json"),
    SPEC_TEXT_FILE: path.join(dir, "spec-text.json"),
    TRUSTED_ACTORS_PATH: actors,
    LANE_IDENTITY: LANE,
  };
  const body = JSON.stringify({ message: "Bad credentials", documentation_url: "https://docs.github.com/rest", pad: "x".repeat(300) });
  const headers = { "x-ratelimit-remaining": "4321", "x-ratelimit-reset": "1760767020", "x-ratelimit-resource": "core", "retry-after": "60" };
  const fetchImpl = async () => new Response(body, { status: 403, headers });
  const latch = createRateLimitLatch({ log: () => {}, fail: () => {}, stopFile: null, limits: () => ({}) });
  const error = await main(env, { fetchImpl, latch }).then(() => assert.fail("main resolved"), (thrown) => thrown);
  const annotation = failureAnnotation(error);
  assert.match(annotation, new RegExp(`^::error::pr-verify could not resolve the pull request: GET /repos/${REPO}/actions/runs/${RUN} failed with status 403 \\[`));
  for (const field of ["status=403", "x-ratelimit-remaining=4321", "x-ratelimit-reset=1760767020", "x-ratelimit-resource=core", "retry-after=60", `body=${JSON.stringify(body.slice(0, 200))}`]) {
    assert.ok(annotation.includes(field), `${field} in ${annotation}`);
  }
});

test("a run that is not a passing pr-require-checks pull_request run of this repository starts nothing", async () => {
  for (const overrides of [
    { path: ".github/workflows/pr-review-hosted.yml" },
    { event: "merge_group" },
    { event: "workflow_dispatch" },
    { conclusion: "failure" },
    { conclusion: "cancelled" },
    { status: "in_progress", conclusion: null },
    { repository: { full_name: "someone/fork" } },
    { head_repository: { full_name: "someone/fork" } },
    { id: RUN + 1 },
    { head_sha: "nothex" },
  ]) {
    assert.equal(await reason({ run: upstream(overrides) }), "not-a-passing-run", JSON.stringify(overrides));
  }
});

// A run whose only failure is a hold an approving review of the head lifts is
// judged, so the person approves a judged head; any other failure still
// starts nothing. The job and step shapes follow GET
// /actions/runs/{id}/jobs as it listed a held ci-status run, and the log
// lines follow that job's log: a timestamp, `##[error]`, then the
// `#<pr>: <reason>.` merge-holds.mjs prints. Each reason is merge-holds.mjs
// `holds`' own text, so its wording cannot drift from this check unseen.
const HOLD_FILES = ["plugins/x/scripts/risk.py"];
const PATH_HOLD = holds("", [], HOLD_FILES, ["plugins/x/**"])[0];
// actorsHold's shape: the list's changed path and why, in parentheses.
const WIDENED = holds("", [], [], [], [], null, true, "it widens the trusted-actor list (.github/standards/trusted-actors/trusted-actors.json: adds a human)")[0];
const COST = holds("", [], ["infra/main.tf"], [])[0];
const BODY = holds("Hold: wait", [], [], [])[0];
// A cost path whose name carries the lift clause, as an author can name a file.
const LIFT = "; an approving review of this head by a person on the trusted-actor list lifts it, and the approval carries over later merges that bring only the base's changes; then re-run ci-status";
const COST_NAMED = holds("", [], [`infra/x${LIFT}.tf`], [])[0];
// The lift clause as main worded it before, from a held ci-status log.
const OLD_WORDING = "#41: it changes plugins/x/scripts/risk.py, a hold path; an approving review of this head by a person on the trusted-actor list lifts it, and the approval carries over later merges of the base that leave its net change the same; then re-run ci-status.";
const CI_STEPS = [
  ["Set up job", "success"],
  ["Check the pull-request contract", "success"],
  ["Note a draft", "skipped"],
  ["Fail a pull request carrying the human-gated label", "success"],
  ["Fail a head a pr-unblock lane stopped", "success"],
  ["Fail a lanes App pull request its body or a member holds", "failure"],
  ["Check each skipped lane against scope", "success"],
  ["Aggregate lane results", "success"],
  ["Complete job", "success"],
];
const ciJob = (steps = CI_STEPS, conclusion = "failure") => ({ id: 9001, name: "ci-status", conclusion, steps: steps.map(([name, c]) => ({ name, conclusion: c })) });
const heldJobs = (ci = ciJob(), others = [{ id: 9002, name: "lint-repo", conclusion: "success" }, { id: 9003, name: "pr-unblock / address-feedback", conclusion: "neutral" }]) => {
  const jobs = [...others, ci];
  return { total_count: jobs.length, jobs };
};
const logOf = (...reasons) =>
  [
    "﻿2026-10-28T16:21:40.0000000Z ##[group]Run node merge-holds.mjs",
    '2026-10-28T16:21:40.0000001Z   echo "::error::merge-holds.mjs exited 0 without its verdict."',
    ...reasons.map((r) => `2026-10-28T16:21:45.8101959Z ##[error]${r.startsWith("#") ? r : `#41: ${r}.`}`),
    "2026-10-28T16:21:45.8106286Z ##[error]Process completed with exit code 1.",
  ].join("\r\n");
const held = (log, setup = {}) =>
  reason({ run: upstream({ conclusion: "failure" }), jobs: heldJobs(), ...setup }, { readLog: async (id) => (id === 9001 ? log : "") });

test("a run that failed only on a hold an approval of the head lifts is judged", async () => {
  assert.ok(PATH_HOLD.includes("it changes plugins/x/scripts/risk.py, a hold path"));
  assert.equal(await held(logOf(PATH_HOLD)), "ok");
  assert.equal(await held(logOf(WIDENED)), "ok");
  assert.equal(await held(logOf(PATH_HOLD, WIDENED)), "ok");
  assert.equal(await held(logOf(OLD_WORDING)), "ok");
});

test("a run that failed on anything but a hold an approval lifts starts nothing", async () => {
  const cases = {
    "a cost hold beside it": [logOf(PATH_HOLD, COST)],
    "a cost hold whose path carries the lift clause": [logOf(COST_NAMED)],
    "a hold path and a cost hold whose path carries the lift clause": [logOf(PATH_HOLD, COST_NAMED)],
    "a line with text after the lift clause": [logOf(`${PATH_HOLD} and more`)],
    "a body hold": [logOf(BODY)],
    "another pull request's hold": [logOf(`#42: ${PATH_HOLD}.`)],
    "no hold logged": [logOf()],
    "a second failed step's exit": [`${logOf(PATH_HOLD)}\n2026-10-28T16:21:46.0000000Z ##[error]Process completed with exit code 1.`],
    "an unreadable log": [null, { jobs: heldJobs() }, async () => { throw new Error("502"); }],
    "a pr-unblock stop too": [logOf(PATH_HOLD), { jobs: heldJobs(ciJob(CI_STEPS.map(([n, c]) => [n, n.includes("pr-unblock") ? "failure" : c]))) }],
    "a failed lane": [logOf(PATH_HOLD), { jobs: heldJobs(ciJob(), [{ id: 9002, name: "lint-repo", conclusion: "failure" }]) }],
    "a cancelled lane": [logOf(PATH_HOLD), { jobs: heldJobs(ciJob(), [{ id: 9002, name: "lint-repo", conclusion: "cancelled" }]) }],
    "a failed aggregate": [logOf(PATH_HOLD), { jobs: heldJobs(ciJob(CI_STEPS.map(([n, c]) => [n, n === "Aggregate lane results" ? "failure" : c]))) }],
    "a step list cut before the aggregate": [logOf(PATH_HOLD), { jobs: heldJobs(ciJob(CI_STEPS.slice(0, 6))) }],
    "no step list": [logOf(PATH_HOLD), { jobs: heldJobs(ciJob([])) }],
    "a job list cut short": [logOf(PATH_HOLD), { jobs: { ...heldJobs(), total_count: 4 } }],
    "no ci-status job": [logOf(PATH_HOLD), { jobs: heldJobs({ ...ciJob(), name: "other" }) }],
    "an unreadable job list": [logOf(PATH_HOLD), { jobs: undefined }],
  };
  for (const [name, [log, setup = {}, readLog]] of Object.entries(cases)) {
    const got = readLog
      ? await reason({ run: upstream({ conclusion: "failure" }), ...setup }, { readLog })
      : await held(log, setup);
    assert.equal(got, "not-a-passing-run", name);
  }
  // With no log reader a failed run is never judged.
  assert.equal(await reason({ run: upstream({ conclusion: "failure" }), jobs: heldJobs() }), "not-a-passing-run");
});

// A session holds a pull request with `do-not-merge`, which fails
// check-contract's step of ci-status. Its log lines follow that action's
// run.sh: the label's `::error::` line, then the step's exit.
const contractLog = (...lines) =>
  [
    '2026-10-28T16:21:30.0000000Z ##[group]Run bash "$GITHUB_ACTION_PATH/run.sh"',
    ...lines.map((line) => `2026-10-28T16:21:31.0000000Z ##[error]${line}`),
    "2026-10-28T16:21:31.0000001Z ##[error]Process completed with exit code 1.",
  ].join("\r\n");
const failing = (...names) => ({
  jobs: heldJobs(ciJob(CI_STEPS.map(([n, c]) => [n, names.includes(n) ? "failure" : n === HOLD_STEP ? "success" : c]))),
});

test("a run that failed only on do-not-merge, alone or beside a hold an approval lifts, is judged", async () => {
  assert.equal(await held(contractLog(DO_NOT_MERGE_LINE), failing(CONTRACT_STEP)), "ok");
  assert.equal(await held(`${contractLog(DO_NOT_MERGE_LINE)}\r\n${logOf(PATH_HOLD)}`, failing(CONTRACT_STEP, HOLD_STEP)), "ok");
});

test("a contract failure other than do-not-merge, or a label line its step does not account for, starts nothing", async () => {
  const TITLE = "pr-contract: the PR title does not follow Conventional Commits";
  const cases = {
    "a title failure beside the label": [contractLog(DO_NOT_MERGE_LINE, TITLE), failing(CONTRACT_STEP)],
    "a title failure alone": [contractLog(TITLE), failing(CONTRACT_STEP)],
    "no label line": [contractLog(), failing(CONTRACT_STEP)],
    "the label line twice": [contractLog(DO_NOT_MERGE_LINE, DO_NOT_MERGE_LINE), failing(CONTRACT_STEP)],
    "the label line with the label text changed": [contractLog(DO_NOT_MERGE_LINE.replace("do-not-merge", "hold")), failing(CONTRACT_STEP)],
    "the label line while the contract step passed": [`${contractLog(DO_NOT_MERGE_LINE)}\r\n${logOf(PATH_HOLD)}`.replace(/\r\n[^\r\n]*exit code 1\.(?=\r\n)/, ""), failing(HOLD_STEP)],
    "both steps failed with one exit": [`${contractLog(DO_NOT_MERGE_LINE)}\r\n${logOf(PATH_HOLD)}`.replace(/\r\n[^\r\n]*exit code 1\.(?=\r\n)/, ""), failing(CONTRACT_STEP, HOLD_STEP)],
    "the hold step failed with only the label": [`${contractLog(DO_NOT_MERGE_LINE)}\r\n${logOf()}`, failing(CONTRACT_STEP, HOLD_STEP)],
    "the contract step cancelled": [contractLog(DO_NOT_MERGE_LINE), { jobs: heldJobs(ciJob(CI_STEPS.map(([n, c]) => [n, n === CONTRACT_STEP ? "cancelled" : n === HOLD_STEP ? "success" : c]))) }],
  };
  for (const [name, [log, setup]] of Object.entries(cases)) {
    assert.equal(await held(log, setup), "not-a-passing-run", name);
  }
});

// Judging a held head loosens no hold: ci-status still fails on the label
// (check-contract, its default label name, no continue-on-error), and the
// merge queue's step still refuses a queued pull request that carries it.
test("do-not-merge still fails ci-status and the merge queue", () => {
  const workflow = readFileSync(new URL("../../workflows/pr-require-checks.yml", import.meta.url), "utf8");
  const step = (name) => new RegExp(`^ {6}- name: ${name}\\n((?: {8}.*\\n|\\n)*)`, "m").exec(workflow)?.[1] ?? "";
  const contract = step(CONTRACT_STEP);
  assert.match(contract, /^ {8}uses: melodic-software\/ci-workflows\/\.github\/actions\/pr-require-checks\/check-contract@[0-9a-f]{40} /m);
  assert.doesNotMatch(contract, /do-not-merge-label|continue-on-error|^ {8}if:/m);
  assert.match(step("Fail a queued pull request carrying a hold label"), /^ {8}if: github\.event_name == 'merge_group'$/m);
  assert.deepEqual(labelHolds([{ name: "do-not-merge" }], null, 41), [
    "#41 carries the 'do-not-merge' label; the merge queue removes it. Remove the label and re-queue to merge.",
  ]);
});

test("main reads the ci-status log through the redirect, without the token, and counts each API request but not the storage read", async () => {
  const dir = tempDir("resolve-pr-held-");
  const env = {
    GITHUB_TOKEN: "t0ken",
    GITHUB_REPOSITORY: REPO,
    GITHUB_OUTPUT: path.join(dir, "out"),
    UPSTREAM_RUN_ID: String(RUN),
    SPEC_FILE: path.join(dir, "spec.json"),
    SPEC_TEXT_FILE: path.join(dir, "spec-text.json"),
    TRUSTED_ACTORS_PATH: path.join(dir, "actors.json"),
    LANE_IDENTITY: LANE,
  };
  writeFileSync(env.TRUSTED_ACTORS_PATH, JSON.stringify({ version: 1, actors: [{ id: 100, login: "maintainer", kind: "human" }] }));
  writeFileSync(env.GITHUB_OUTPUT, "");
  const github = fake({ run: upstream({ conclusion: "failure" }), jobs: heldJobs() });
  const storage = [];
  let apiRequests = 0;
  const fetchImpl = async (url, init = {}) => {
    apiRequests += url.startsWith("https://api.github.com/") ? 1 : 0;
    if (url === `https://api.github.com/repos/${REPO}/actions/jobs/9001/logs`) {
      assert.equal(init.redirect, "manual");
      assert.equal(init.headers.Authorization, "Bearer t0ken");
      return new Response(null, { status: 302, headers: { Location: "https://storage.example/log?sig=1" } });
    }
    if (url === "https://storage.example/log?sig=1") {
      storage.push(init);
      return new Response(logOf(PATH_HOLD), { status: 200 });
    }
    const body = init.body === undefined ? undefined : JSON.parse(init.body);
    const json = await github(init.method, new URL(url).pathname + new URL(url).search, body);
    return new Response(JSON.stringify(json), { status: 200, headers: { "Content-Type": "application/json" } });
  };
  const saved = { RUNNER_TEMP: process.env.RUNNER_TEMP, API_BUDGET_TOKEN: process.env.API_BUDGET_TOKEN };
  Object.assign(process.env, { RUNNER_TEMP: dir, API_BUDGET_TOKEN: "github-token" });
  try {
    await main(env, { fetchImpl });
  } finally {
    for (const [key, value] of Object.entries(saved)) {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    }
  }
  assert.match(readFileSync(env.GITHUB_OUTPUT, "utf8"), /^proceed=true\nreason=ok\npr-number=41\n/);
  assert.deepEqual(storage, [{}]);
  // One reading per GitHub API request, the log's 302 among them; none for storage.
  const readings = readFileSync(path.join(dir, "api-budget", "github-token"), "utf8").trim().split("\n");
  assert.equal(readings.length, apiRequests);
  assert.equal(readings.filter((line) => line.startsWith("302 ")).length, 1);
});

test("anything but exactly one open same-repository PR into main at that head starts nothing", async () => {
  for (const pulls of [
    [],
    [pull(), pull({ number: 42 })],
    [pull({ state: "closed" })],
    [pull({ head: { sha: BASE, ref: "feat/x", repo: { full_name: REPO } } })],
    [pull({ head: { sha: HEAD, ref: "feat/x", repo: { full_name: "someone/fork" } } })],
    [pull({ base: { ref: "release", sha: BASE } })],
  ]) {
    assert.equal(await reason({ pulls }), "no-single-pr", JSON.stringify(pulls));
  }
});

test("a draft and a dependency manager's PR start nothing", async () => {
  assert.equal(await reason({ pulls: [pull({ draft: true })] }), "draft");
  for (const login of ["dependabot[bot]", "Renovate[bot]", "renovate-bot", "app/dependabot-preview"]) {
    assert.equal(await reason({ pulls: [pull({ user: { id: 1, login, type: "Bot" } })] }), "dependency-manager", login);
  }
});

test("a User account named like a dependency manager is not one", async () => {
  for (const login of ["dependabot", "renovate-bot"]) {
    const user = { id: 9, login, type: "User" };
    assert.equal(await reason({ pulls: [pull({ user })] }, { verifyAuthors: "any" }), "ok", login);
  }
});

test("a PR the lanes App did not open is not judged", async () => {
  assert.equal(await reason({ pulls: [HUMAN_PR] }), "author-not-lane");
  // A User account holding the App's login is not the App.
  assert.equal(await reason({ pulls: [pull({ user: { id: 5, login: LANE, type: "User" } })] }), "author-not-lane", "a User");
  // Another App is a Bot account too, so only the login tells it apart.
  assert.equal(await reason({ pulls: [pull({ user: { id: 6, login: "other-app[bot]", type: "Bot" } })] }), "author-not-lane", "another App");
  assert.equal(await reason({ pulls: [HUMAN_PR] }, { verifyAuthors: "lane" }), "author-not-lane", "lane named");
  // The workflow passes an unset identity as an empty string.
  assert.equal(await reason({ pulls: [pull()] }, { laneIdentity: "" }), "author-not-lane", "no identity");
});

test("a PR the lanes App opened is judged, matched across login spellings", async () => {
  assert.equal(await reason({ pulls: [pull()] }), "ok");
  const spelled = pull({ user: { id: 337595936, login: "Melodic-Automation-Lanes", type: "Bot" } });
  assert.equal(await reason({ pulls: [spelled] }), "ok");
});

test("verify-authors any judges a human's PR", async () => {
  assert.equal(await reason({ pulls: [HUMAN_PR] }, { verifyAuthors: "any" }), "ok");
});

test("verify-authors lane-or-owner judges the owner account's PRs and the lane's", async () => {
  const opts = { verifyAuthors: "lane-or-owner", ownerIds: [OWNER_ID] };
  assert.equal(await reason({ pulls: [pull()] }, opts), "ok", "lane");
  const owner = pull({ user: { id: OWNER_ID, login: "kyle-sexton", type: "User" } });
  assert.equal(await reason({ pulls: [owner] }, opts), "ok", "owner");
  // Matched by account id, never login.
  const spoof = pull({ user: { id: OWNER_ID + 1, login: "kyle-sexton", type: "User" } });
  assert.equal(await reason({ pulls: [spoof] }, opts), "author-not-lane-or-owner", "owner login, other id");
  // A listed App (the release App) is judged too (owner decision 2026-10-22).
  const app = pull({ user: { id: OWNER_ID, login: "melodic-plugin-release[bot]", type: "Bot" } });
  assert.equal(await reason({ pulls: [app] }, opts), "ok", "a listed Bot");
  const org = pull({ user: { id: OWNER_ID, login: "kyle-sexton", type: "Organization" } });
  assert.equal(await reason({ pulls: [org] }, opts), "author-not-lane-or-owner", "another account type");
  assert.equal(await reason({ pulls: [HUMAN_PR] }, opts), "author-not-lane-or-owner", "another human");
  // A draft stays unjudged.
  assert.equal(await reason({ pulls: [{ ...owner, draft: true }] }, opts), "draft", "owner draft");
});

test("lane-or-owner reads the owner ids it is given", async () => {
  const opts = { verifyAuthors: "lane-or-owner", ownerIds: [77] };
  const other = pull({ user: { id: 77, login: "other", type: "User" } });
  assert.equal(await reason({ pulls: [other] }, opts), "ok", "a listed id");
  const owner = pull({ user: { id: OWNER_ID, login: "kyle-sexton", type: "User" } });
  assert.equal(await reason({ pulls: [owner] }, opts), "author-not-lane-or-owner", "an unlisted id");
  assert.equal(await reason({ pulls: [owner] }, { ...opts, ownerIds: [] }), "author-not-lane-or-owner", "none");
  assert.equal(await reason({ pulls: [owner] }, { verifyAuthors: "lane-or-owner" }), "author-not-lane-or-owner", "not given");
});

// Owner decision 2026-10-22: with no closing issue here, a person's or a
// script-written App's title and body are the spec; a model-written App's
// (claude[bot]) or the lanes App's are not, since its run wrote them.
test("a trusted PR with no closing issue here is its own spec, unless a model wrote its body", async () => {
  const RELEASE = 337859524;
  const CLAUDE = 209825114;
  // cursoragent is a GitHub User the trusted list marks kind bot: a model
  // writes its bodies, so only a kind human id counts as a person.
  const CURSORAGENT = 199161495;
  const opts = {
    verifyAuthors: "lane-or-owner",
    humans: new Set([100, OWNER_ID]),
    ownerIds: [OWNER_ID, RELEASE, CLAUDE, CURSORAGENT],
    specFromBodyApps: [RELEASE],
  };
  const own = (user) => pull({ user, title: "chore: release", body: "Bumps the versions." });
  const spec = [{ number: 41, source: "pull-request", spec_kind: "pull-request", body: "chore: release\n\nBumps the versions.", comments: [] }];
  for (const [user, expected] of [
    [{ id: OWNER_ID, login: "kyle-sexton", type: "User" }, spec],
    [{ id: RELEASE, login: "melodic-plugin-release[bot]", type: "Bot" }, spec],
    [{ id: CLAUDE, login: "claude[bot]", type: "Bot" }, []],
    [{ id: CURSORAGENT, login: "cursoragent", type: "User" }, []],
    [{ id: 337595936, login: LANE, type: "Bot" }, []],
  ]) {
    const result = await resolve({ pulls: [own(user)], issues: [] }, opts);
    assert.deepEqual(result.specText, expected, user.login);
    assert.equal(result.specKind, expected.length ? "pull-request" : "none", user.login);
    assert.deepEqual(result.linkedIssues, [], user.login);
  }
  // S&C D: a body last edited by anyone but its author or a trusted person
  // is not the spec; edited by them, it still is.
  const owner = own({ id: OWNER_ID, login: "kyle-sexton", type: "User" });
  const releasePr = own({ id: RELEASE, login: "melodic-plugin-release[bot]", type: "Bot" });
  const by = (databaseId, __typename = "User") => ({ lastEditedAt: "2026-10-22T00:00:00Z", editor: { __typename, login: "x", databaseId } });
  for (const [pr, edit, expected] of [
    [owner, by(4242), []],
    [releasePr, by(CLAUDE, "Bot"), []],
    [owner, by(OWNER_ID), spec],
    [releasePr, by(RELEASE, "Bot"), spec],
    [releasePr, by(100), spec],
    [owner, { lastEditedAt: "2026-10-22T00:00:00Z", editor: null }, []],
  ]) {
    const result = await resolve({ pulls: [pr], issues: [], edit }, opts);
    assert.deepEqual(result.specText, expected, JSON.stringify(edit));
  }
  // A closing issue here keeps it the spec.
  const result = await resolve({ pulls: [own({ id: OWNER_ID, login: "kyle-sexton", type: "User" })] }, opts);
  assert.deepEqual(result.specText, [{ number: 7, spec_kind: "closes", body: "the spec", comments: [] }]);
});

// #9115: the title joins the spec, so a title someone else renamed last is
// not the author's intent either; only the latest rename counts, as only the
// body's latest edit does.
test("a PR whose title another actor renamed last is not its own spec", async () => {
  const RELEASE = 337859524;
  const opts = {
    verifyAuthors: "lane-or-owner",
    humans: new Set([100, OWNER_ID]),
    ownerIds: [OWNER_ID, RELEASE],
    specFromBodyApps: [RELEASE],
  };
  const own = (user) => pull({ user, title: "chore: release", body: "Bumps the versions." });
  const owner = own({ id: OWNER_ID, login: "kyle-sexton", type: "User" });
  const releasePr = own({ id: RELEASE, login: "melodic-plugin-release[bot]", type: "Bot" });
  const spec = [{ number: 41, source: "pull-request", spec_kind: "pull-request", body: "chore: release\n\nBumps the versions.", comments: [] }];
  const by = (databaseId, __typename = "User") => ({ __typename, databaseId });
  for (const [label, pr, renames, expected] of [
    ["never renamed", owner, [], spec],
    ["renamed by its author", owner, [by(OWNER_ID)], spec],
    ["renamed by the App that opened it", releasePr, [by(RELEASE, "Bot")], spec],
    ["renamed by another trusted person", releasePr, [by(100)], spec],
    ["renamed by someone else", owner, [by(4242)], []],
    ["renamed by a model's App", releasePr, [by(209825114, "Bot")], []],
    ["renamed by an actor GitHub cannot name", owner, [null], []],
    ["renamed by someone else, then by its author", owner, [by(4242), by(OWNER_ID)], spec],
    ["renamed by its author, then by someone else", owner, [by(OWNER_ID), by(4242)], []],
  ]) {
    const result = await resolve({ pulls: [pr], issues: [], renames }, opts);
    assert.deepEqual(result.specText, expected, label);
    assert.equal(result.specKind, expected.length ? "pull-request" : "none", label);
  }
  // A rename read with no timeline stops the run rather than trusting the title.
  await assert.rejects(resolve({ pulls: [owner], issues: [], renames: { data: { repository: { pullRequest: null } } } }, opts), /timelineItems could not be read/);
  // A PR with a closing issue, or one whose body is not its intent, never reads its renames.
  for (const setup of [{ pulls: [owner] }, { pulls: [pull({ title: "t", body: "b" })], issues: [] }]) {
    const result = await resolve({ ...setup, renames: { data: null } }, opts);
    assert.equal(result.proceed, true, JSON.stringify(setup.pulls[0].user));
  }
});

test("main judges every trusted-actors.json account under lane-or-owner, a Bot included", async (t) => {
  const dir = tempDir("pr-verify-");
  const output = path.join(dir, "out");
  const actors = path.join(dir, "trusted-actors.json");
  writeFileSync(
    actors,
    JSON.stringify({ version: 1, actors: [{ id: 100, login: "maintainer", kind: "human" }, { id: 77, login: "a-release[bot]", kind: "bot" }] }),
  );
  t.mock.method(console, "log", () => {});
  const env = {
    GITHUB_TOKEN: "t",
    GITHUB_REPOSITORY: REPO,
    GITHUB_OUTPUT: output,
    UPSTREAM_RUN_ID: String(RUN),
    SPEC_FILE: path.join(dir, "spec.json"),
    SPEC_TEXT_FILE: path.join(dir, "spec-text.json"),
    TRUSTED_ACTORS_PATH: actors,
    LANE_IDENTITY: LANE,
    VERIFY_AUTHORS: "lane-or-owner",
  };
  const release = pull({ user: { id: 77, login: "a-release[bot]", type: "Bot" } });
  await main(env, { github: fake({ pulls: [release] }) });
  assert.match(readFileSync(output, "utf8"), /^proceed=true\nreason=ok\n/);
  writeFileSync(output, "");
  const stranger = pull({ user: { id: 78, login: "stranger", type: "User" } });
  await main(env, { github: fake({ pulls: [stranger] }) });
  assert.match(readFileSync(output, "utf8"), /^proceed=false\nreason=author-not-lane-or-owner\n/);
});

test("an unknown verify-authors value judges nothing", async () => {
  for (const verifyAuthors of ["Lane", "all", "", "none"]) {
    assert.equal(await reason({ pulls: [pull()] }, { verifyAuthors }), "verify-authors-invalid", JSON.stringify(verifyAuthors));
  }
});

test("a counted verdict at the head from a completed run stops a new judgment", async () => {
  const cases = {
    "this PR's pass": [artifact(`pr-verify-41-${HEAD}-pass`, 77), verifyRun(77)],
    "this PR's fail": [artifact(`pr-verify-41-${HEAD}-fail`, 77), verifyRun(77)],
    "this PR's pass-notes": [artifact(`pr-verify-41-${HEAD}-pass-notes`, 77), verifyRun(77)],
    "another PR's fail": [artifact(`pr-verify-99-${HEAD}-fail`, 77), verifyRun(77)],
    "a fail from a run that failed later": [artifact(`pr-verify-41-${HEAD}-fail`, 77), verifyRun(77, { conclusion: "failure" })],
  };
  // The commit's pull requests name the other numbers a FAIL at the head can carry.
  const pulls = [pull(), pull({ number: 99, state: "closed" })];
  for (const [label, [item, record]] of Object.entries(cases)) {
    assert.equal(await reason({ pulls, artifacts: [item], runs: { 77: record } }), "already-judged", label);
  }
});

test("verdicts are looked up by exact name, never by listing every artifact", async () => {
  const paths = [];
  const other = { sha: HEAD, ref: "feat/other", repo: { full_name: REPO } };
  const github = fake({ pulls: [pull(), pull({ number: 99, state: "closed", head: other }), pull({ number: 99, state: "closed", head: other })] });
  const recording = async (method, apiPath, body) => {
    paths.push(apiPath);
    return github(method, apiPath, body);
  };
  await resolvePull({ github: recording, repository: REPO, upstreamRunId: String(RUN), humans: HUMANS, laneIdentity: LANE });
  const lookups = paths.filter((apiPath) => apiPath.includes("/actions/artifacts"));
  assert.deepEqual(lookups.sort(), [
    `/repos/${REPO}/actions/artifacts?name=pr-verify-41-${HEAD}-fail&per_page=100&page=1`,
    `/repos/${REPO}/actions/artifacts?name=pr-verify-41-${HEAD}-fail-i7&per_page=100&page=1`,
    `/repos/${REPO}/actions/artifacts?name=pr-verify-41-${HEAD}-pass&per_page=100&page=1`,
    `/repos/${REPO}/actions/artifacts?name=pr-verify-41-${HEAD}-pass-notes&per_page=100&page=1`,
    `/repos/${REPO}/actions/artifacts?name=pr-verify-99-${HEAD}-fail&per_page=100&page=1`,
  ]);
});

test("the resolver looks up exactly the names write-verdict writes", async () => {
  // Every verdict that can stand at this head, named by the writer itself: this
  // PR's pass and pass-notes, its FAIL with and without the issue it closes,
  // and PR 99's FAIL, whose issues this run never reads. A writer that moves
  // to new names (a head-ref digest) fails here until the resolver looks them up.
  const other = { sha: HEAD, ref: "feat/other", repo: { full_name: REPO } };
  const pulls = [pull(), pull({ number: 99, state: "closed", head: other })];
  const written = [
    { pr: 41, head_sha: HEAD, head_ref: "feat/x", verdict: "pass", linked_issues: [{ number: 7 }] },
    { pr: 41, head_sha: HEAD, head_ref: "feat/x", verdict: "pass-notes", linked_issues: [{ number: 7 }] },
    { pr: 41, head_sha: HEAD, head_ref: "feat/x", verdict: "fail", linked_issues: [{ number: 7 }] },
    { pr: 41, head_sha: HEAD, head_ref: "feat/x", verdict: "fail", linked_issues: [] },
    { pr: 99, head_sha: HEAD, head_ref: "feat/other", verdict: "fail", linked_issues: [] },
  ].map(artifactName);
  const paths = [];
  const github = fake({ pulls });
  const recording = async (method, apiPath, body) => {
    paths.push(apiPath);
    return github(method, apiPath, body);
  };
  await resolvePull({ github: recording, repository: REPO, upstreamRunId: String(RUN), humans: HUMANS, laneIdentity: LANE });
  const looked = paths
    .filter((apiPath) => apiPath.includes("/actions/artifacts"))
    .map((apiPath) => new URL(apiPath, "https://api.github.com").searchParams.get("name"));
  assert.deepEqual(looked.sort(), [...new Set(written)].sort());
  // Each written name, once at the head, stops a new judgment.
  for (const name of written) {
    assert.equal(await reason({ pulls, artifacts: [artifact(name, 77)], runs: { 77: verifyRun(77) } }), "already-judged", name);
  }
});

test("a FAIL named with this pull request's issues stops a new judgment", async () => {
  // The fake pull request closes one issue, so write-verdict.mjs named its
  // FAIL with that number after -i.
  const pulls = [pull()];
  for (const name of [`pr-verify-41-${HEAD}-fail-i7`]) {
    assert.equal(await reason({ pulls, artifacts: [artifact(name, 77)], runs: { 77: verifyRun(77) } }), "already-judged", name);
  }
  // A suffix naming other issues is another judgment.
  for (const name of [`pr-verify-41-${HEAD}-fail-i8`, `pr-verify-41-${HEAD}-fail-i7.8`]) {
    assert.equal(await reason({ pulls, artifacts: [artifact(name, 77)], runs: { 77: verifyRun(77) } }), "ok", name);
  }
});

// The reason, and how many times the linked-issues query ran.
async function specReads(setup) {
  const github = fake(setup);
  let reads = 0;
  const counting = async (method, apiPath, body) => {
    if (apiPath === "/graphql" && body.query.includes("closingIssuesReferences")) reads += 1;
    return github(method, apiPath, body);
  };
  const { reason } = await resolvePull({ github: counting, repository: REPO, upstreamRunId: String(RUN), humans: HUMANS, laneIdentity: LANE });
  return [reason, reads];
}

test("a FAIL named without issues, and a pass, each skip after one linked-issues read", async () => {
  // A pass is weighed against the spec's last change, which that read gives;
  // a FAIL named without issues against whether the PR now links issues.
  for (const [verdict, reads] of [["fail", 1], ["pass", 1]]) {
    const name = `pr-verify-41-${HEAD}-${verdict}`;
    assert.deepEqual(await specReads({ artifacts: [artifact(name, 77)], runs: { 77: verifyRun(77) } }), ["already-judged", reads], name);
  }
});

test("a head whose only verdict is a FAIL named with issues skips after one linked-issues read", async () => {
  const artifacts = [artifact(`pr-verify-41-${HEAD}-fail-i7`, 77)];
  assert.deepEqual(await specReads({ artifacts, runs: { 77: verifyRun(77) } }), ["already-judged", 1]);
});

// A relink: the PR's FAIL at the head was named without issues (it linked
// none), and the PR now closes ISSUE. The FAIL's run was created at
// FAILED_AT; the edit shapes follow a live userContentEdits read of an edited
// pull request (newest first, the original text last, stamped when the pull
// request opened, by its author), with identifying details changed.
const FAILED_AT = "2026-10-20T06:00:00Z";
const PERSON = { __typename: "User", login: "maintainer", databaseId: 100 };
const LANES_APP = { __typename: "Bot", login: "melodic-automation-lanes", databaseId: 337595936 };
// The original text's entry, stamped before the FAIL, by the App that opened the PR.
const ORIGINAL = { editedAt: "2026-10-19T00:00:00Z", editor: LANES_APP };
const relinkAnswer = ({ edits = [], events = [], editsTotal = edits.length + 1, eventsFiltered = events.length } = {}) => ({
  data: {
    repository: {
      pullRequest: {
        userContentEdits: { totalCount: editsTotal, nodes: [...edits, ORIGINAL] },
        timelineItems: { filteredCount: eventsFiltered, nodes: events },
      },
    },
  },
});
const relinked = (relink, overrides = {}) => ({
  artifacts: [artifact(`pr-verify-41-${HEAD}-fail`, 77)],
  runs: { 77: verifyRun(77, { created_at: FAILED_AT }) },
  relink,
  ...overrides,
});

test("a FAIL named without issues is judged again after only trusted people linked an issue", async () => {
  const relink = relinkAnswer({
    edits: [{ editedAt: "2026-10-20T07:00:00Z", editor: PERSON }],
    events: [{ createdAt: "2026-10-20T08:00:00Z", actor: PERSON }],
  });
  const resolved = await resolve(relinked(relink));
  assert.equal(resolved.proceed, true);
  assert.equal(resolved.reason, "relinked");
  assert.deepEqual(resolved.linkedIssues, [LINKED]);
});

test("a lanes App or unnamed actor's edit or link since the FAIL keeps it", async () => {
  for (const [label, edit, event] of [
    ["the App's body edit", LANES_APP, PERSON],
    ["the App's connect event", PERSON, LANES_APP],
    ["a ghost's edit", null, PERSON],
    ["another person's link", PERSON, { __typename: "User", login: "outsider", databaseId: 999 }],
  ]) {
    const relink = relinkAnswer({ edits: [{ editedAt: "2026-10-20T07:00:00Z", editor: edit }], events: [{ createdAt: "2026-10-20T08:00:00Z", actor: event }] });
    assert.equal(await reason(relinked(relink)), "already-judged", label);
  }
});

test("a relink that cannot be read whole keeps the FAIL", async () => {
  const cut = relinkAnswer({ events: [{ createdAt: "2026-10-20T08:00:00Z", actor: PERSON }], editsTotal: 101 });
  const filtered = relinkAnswer({ events: [{ createdAt: "2026-10-20T08:00:00Z", actor: PERSON }], eventsFiltered: 2 });
  const timeless = relinkAnswer({ events: [{ createdAt: null, actor: PERSON }] });
  for (const [label, setup] of [
    ["a failed read", relinked(undefined)],
    ["a GraphQL answer with no pull request", relinked({ data: { repository: { pullRequest: null } } })],
    ["edits cut short", relinked(cut)],
    ["events cut short", relinked(filtered)],
    ["an event with no time", relinked(timeless)],
    // Only the original text, before the FAIL: no visible cause for the link.
    ["nothing since the FAIL", relinked(relinkAnswer())],
    ["a FAIL run with no creation time", relinked(relinkAnswer(), { runs: { 77: verifyRun(77, { created_at: null }) } })],
  ]) {
    assert.equal(await reason(setup), "already-judged", label);
  }
});

test("a FAIL named without issues stands while the PR links no issue a FAIL name carries", async () => {
  // None, or more than a name carries: the set the FAIL recorded may be this one.
  const eleven = Array.from({ length: 11 }, (_, i) => ({ ...ISSUE, number: i + 1 }));
  for (const issues of [[], eleven]) {
    const queries = [];
    const github = fake(relinked(relinkAnswer(), { issues }));
    const recording = async (method, apiPath, body) => {
      if (apiPath === "/graphql" && body.query.includes("userContentEdits")) queries.push(apiPath);
      return github(method, apiPath, body);
    };
    const { reason: got } = await resolvePull({ github: recording, repository: REPO, upstreamRunId: String(RUN), humans: HUMANS, laneIdentity: LANE });
    assert.equal(got, "already-judged", String(issues.length));
    assert.deepEqual(queries, [], "no relink read");
  }
});

// The head commit, after ORIGINAL and before FAILED_AT.
const COMMITTED_AT = "2026-10-19T12:00:00Z";
const committed = (overrides = {}) => ({ run: upstream({ head_commit: { id: HEAD, timestamp: COMMITTED_AT } }), ...overrides });

test("a judgment after an edit or link change since the head commit reports a relink, so its pass keeps a FAIL's retention", async () => {
  // This PR's FAIL at the head, named with an issue it no longer links, so
  // the head is judged again with reason ok, and the gate may find its pass
  // superseding the FAIL (babysit_verify_evidence `_superseded`).
  const fail = { artifacts: [artifact(`pr-verify-41-${HEAD}-fail-i5`, 77)], runs: { 77: verifyRun(77, { created_at: FAILED_AT }) } };
  const linked = await resolve(committed({ ...fail, relink: relinkAnswer({ events: [{ createdAt: "2026-10-20T08:00:00Z", actor: PERSON }] }) }));
  assert.equal(linked.reason, "ok");
  assert.equal(linked.relinkSinceHead, true);
  for (const [label, setup] of [
    ["a failed read", committed(fail)],
    ["no head commit time", { ...fail, relink: relinkAnswer() }],
    ["edits cut short", committed({ ...fail, relink: relinkAnswer({ editsTotal: 101 }) })],
  ]) {
    assert.equal((await resolve(setup)).relinkSinceHead, true, label);
  }
});

test("a judgment with no edit or link change since the head commit reports none", async () => {
  // Only the original text, stamped before the head commit.
  const resolved = await resolve(committed({ relink: relinkAnswer() }));
  assert.equal(resolved.proceed, true);
  assert.equal(resolved.relinkSinceHead, false);
});

test("a relinked judgment reports a relink", async () => {
  const relink = relinkAnswer({ events: [{ createdAt: "2026-10-20T08:00:00Z", actor: PERSON }] });
  const resolved = await resolve(relinked(relink));
  assert.equal(resolved.reason, "relinked");
  assert.equal(resolved.relinkSinceHead, true);
});

test("after a trusted relink, another PR's FAIL or one named with the new issues still stops the judgment", async () => {
  const relink = relinkAnswer({ events: [{ createdAt: "2026-10-20T08:00:00Z", actor: PERSON }] });
  for (const name of [`pr-verify-99-${HEAD}-fail`, `pr-verify-41-${HEAD}-fail-i7`]) {
    const setup = relinked(relink, { pulls: [pull(), pull({ number: 99, state: "closed" })] });
    setup.artifacts.push(artifact(name, 78));
    setup.runs[78] = verifyRun(78);
    assert.equal(await reason(setup), "already-judged", name);
  }
});

test("an unjudged head reads its linked issues once", async () => {
  assert.deepEqual(await specReads({}), ["ok", 1]);
});

test("a pull request closing more issues than a FAIL's name carries is still judged", async () => {
  // No FAIL is named with eleven issues or an 11-digit one, so none is looked up.
  for (const numbers of [Array.from({ length: 11 }, (_, i) => i + 1), [10000000000]]) {
    const issues = numbers.map((number) => ({ ...ISSUE, number }));
    assert.equal(await reason({ issues }), "ok", JSON.stringify(numbers));
  }
});

test("a verdict named with a head-ref digest is not looked up, since write-verdict writes none", async () => {
  // write-verdict.mjs artifactName writes no digest, so no such name can stand
  // at a head; the change that moves the writer to digests adds the lookups.
  const pulls = [pull(), pull({ number: 99, state: "closed", head: { sha: HEAD, ref: "feat/other", repo: { full_name: REPO } } })];
  for (const name of [
    `pr-verify-41-${HEAD}-pass-${REF_DIGEST}`,
    `pr-verify-41-${HEAD}-fail-${REF_DIGEST}`,
    `pr-verify-41-${HEAD}-fail-${REF_DIGEST}-i7`,
    `pr-verify-99-${HEAD}-fail-${OTHER_DIGEST}`,
  ]) {
    const paths = [];
    const github = fake({ pulls, artifacts: [artifact(name, 77)], runs: { 77: verifyRun(77) } });
    const recording = async (method, apiPath, body) => {
      paths.push(apiPath);
      return github(method, apiPath, body);
    };
    const { reason: got } = await resolvePull({ github: recording, repository: REPO, upstreamRunId: String(RUN), humans: HUMANS, laneIdentity: LANE });
    assert.equal(got, "ok", name);
    assert.ok(!paths.some((apiPath) => apiPath.includes(encodeURIComponent(name))), name);
  }
});

test("a name with more than one page of artifacts is read to the end", async () => {
  const name = `pr-verify-41-${HEAD}-pass`;
  const artifacts = [...Array.from({ length: 100 }, () => artifact(name, 77, true)), artifact(name, 78)];
  assert.equal(await reason({ artifacts, runs: { 78: verifyRun(78) } }), "already-judged");
});

test("a FAIL under a PR listed only on the second page of the commit's pull requests is found", async () => {
  const filler = Array.from({ length: 100 }, (_, index) => pull({ number: 1000 + index, state: "closed" }));
  const pulls = [pull(), ...filler.slice(1), pull({ number: 99, state: "closed" })];
  const artifacts = [artifact(`pr-verify-99-${HEAD}-fail`, 77)];
  assert.equal(await reason({ pulls, artifacts, runs: { 77: verifyRun(77) } }), "already-judged");
});

test("a commit with more pull-request pages than the cap throws", async () => {
  const pulls = Array.from({ length: 100 * 100 + 1 }, (_, index) => pull({ number: 1000 + index, state: "closed" }));
  await assert.rejects(resolve({ pulls }), /more than \d+ pages/);
});

test("a failed artifact lookup throws instead of judging again", async () => {
  const github = fake();
  const failing = async (method, apiPath, body) => {
    if (apiPath.includes("/actions/artifacts")) throw new Error("403 rate limit");
    return github(method, apiPath, body);
  };
  await assert.rejects(
    resolvePull({ github: failing, repository: REPO, upstreamRunId: String(RUN), humans: HUMANS, laneIdentity: LANE }),
    /rate limit/,
  );
});

test("a run still going, or a run that uploaded nothing, does not stop a new judgment", async () => {
  const going = verifyRun(77, { status: "in_progress", conclusion: null });
  assert.equal(await reason({ artifacts: [artifact(`pr-verify-41-${HEAD}-fail`, 77)], runs: { 77: going } }), "ok");
  // A failed run with no artifact leaves nothing in the listing.
  assert.equal(await reason({ artifacts: [], runs: { 77: verifyRun(77, { conclusion: "failure" }) } }), "ok");
});

test("a head whose only verdict can no longer be read is judged again", async () => {
  // An expired artifact cannot be downloaded, so the gate cannot read it either.
  for (const verdict of ["pass", "fail"]) {
    const item = artifact(`pr-verify-41-${HEAD}-${verdict}`, 77, true);
    assert.equal(await reason({ artifacts: [item], runs: { 77: verifyRun(77) } }), "ok", verdict);
  }
});

test("a verdict that would not count does not stop a new judgment", async () => {
  const name = `pr-verify-41-${HEAD}-pass`;
  const forgeries = {
    path: { path: ".github/workflows/pr-require-checks.yml" },
    event: { event: "pull_request" },
    head_branch: { head_branch: "feat/x" },
    repository: { repository: { full_name: "someone/fork" } },
    head_repository: { head_repository: { full_name: "someone/fork" } },
    status: { status: "queued" },
    conclusion: { conclusion: "cancelled" },
    id: { id: 78 },
    "head off main": { head_sha: "d".repeat(40) },
  };
  for (const [field, overrides] of Object.entries(forgeries)) {
    const runs = { 77: verifyRun(77, overrides) };
    assert.equal(await reason({ artifacts: [artifact(name, 77)], runs }), "ok", field);
  }
  assert.equal(await reason({ artifacts: [artifact(name, 77, true)], runs: { 77: verifyRun(77) } }), "ok", "expired");
  assert.equal(await reason({ artifacts: [artifact(name, 77)], runs: {} }), "ok", "unreadable run");
  const otherPass = `pr-verify-99-${HEAD}-pass`;
  assert.equal(await reason({ artifacts: [artifact(otherPass, 77)], runs: { 77: verifyRun(77) } }), "ok", "another PR's pass");
});

test("a malformed run id throws", async () => {
  await assert.rejects(resolvePull({ github: fake(), repository: REPO, upstreamRunId: "1;x" }));
});

test("the spec text keeps only what trusted humans wrote and last edited", async () => {
  const human = { __typename: "User", login: "maintainer", databaseId: 100 };
  const lanes = { __typename: "Bot", login: "melodic-automation-lanes", databaseId: 337595936 };
  const stranger = { __typename: "User", login: "stranger", databaseId: 999 };
  let next = 0;
  const comment = (body, author, extra = {}) => {
    next += 1;
    return { databaseId: next, updatedAt: `2026-10-1${next}T00:00:00Z`, body, author, lastEditedAt: null, editor: null, ...extra };
  };
  const issue = {
    ...ISSUE,
    comments: {
      totalCount: 6,
      nodes: [
        comment("kept", human),
        comment("by a bot with a listed human's id", { ...human, __typename: "Bot" }),
        comment("by the lanes App", lanes),
        comment("by a stranger", stranger),
        comment("edited by the lanes App", human, { lastEditedAt: "2026-10-14T00:00:00Z", editor: lanes }),
        comment("edited by the human", human, { lastEditedAt: "2026-10-14T00:00:00Z", editor: human }),
      ],
    },
  };
  assert.deepEqual((await resolve({ issues: [issue] })).specText, [
    { number: 7, spec_kind: "closes", body: "the spec", comments: ["kept", "edited by the human"] },
  ]);
  // The gate re-reads the same comments with the same filter, by id and update time.
  assert.deepEqual((await resolve({ issues: [issue] })).linkedIssues[0].spec_comments, [
    { id: 1, updated_at: "2026-10-11T00:00:00Z" },
    { id: 6, updated_at: "2026-10-16T00:00:00Z" },
  ]);
  const byMaintainer = { issues: [issue], pulls: [pull({ user: { id: 100, login: "Maintainer", type: "User" } })] };
  const byAuthorRecord = (await resolve(byMaintainer, { verifyAuthors: "any" })).linkedIssues[0];
  assert.deepEqual(
    byAuthorRecord.spec_comments,
    [
      { id: 1, updated_at: "2026-10-11T00:00:00Z" },
      { id: 6, updated_at: "2026-10-16T00:00:00Z" },
    ],
    "a trusted PR author's comments",
  );
  const editedBody = { ...issue, lastEditedAt: "2026-10-14T00:00:00Z", editor: lanes };
  assert.equal((await resolve({ issues: [editedBody] })).specText[0].body, null, "a body the lanes App last edited");
  const byAuthor = (await resolve(byMaintainer, { verifyAuthors: "any" })).specText[0];
  assert.deepEqual(byAuthor, { number: 7, spec_kind: "closes", body: "the spec", comments: ["kept", "edited by the human"] }, "a trusted PR author's own text");
  const lanesIssue = { ...issue, author: lanes };
  assert.equal((await resolve({ issues: [lanesIssue] })).specText[0].body, null, "an issue the lanes App wrote");
  const strangerIssue = { ...issue, author: stranger, comments: { totalCount: 1, nodes: [comment("by the stranger", stranger)] } };
  const byStranger = { issues: [strangerIssue], pulls: [pull({ user: { id: 999, login: "stranger", type: "User" } })] };
  assert.deepEqual(
    (await resolve(byStranger, { verifyAuthors: "any" })).specText[0],
    { number: 7, spec_kind: "closes", body: null, comments: [] },
    "an untrusted PR author's own text",
  );
});

test("on an issue a listed human wrote, intake's newest unedited refinement comment by the lanes App is spec", async () => {
  const human = { __typename: "User", login: "maintainer", databaseId: 100 };
  const lanes = { __typename: "Bot", login: "melodic-automation-lanes", databaseId: 337595936 };
  const actions = { __typename: "Bot", login: "github-actions", databaseId: 41898282 };
  const impostor = { __typename: "Bot", login: "melodic-automation-lanes", databaseId: 4242 };
  const MARKER = "<!-- intake-triage refinement -->";
  let next = 0;
  const comment = (body, author, extra = {}) => {
    next += 1;
    const at = `2026-10-1${next}T00:00:00Z`;
    return { databaseId: next, createdAt: at, updatedAt: at, body, author, lastEditedAt: null, editor: null, ...extra };
  };
  const on = (nodes, overrides = {}) => ({ ...ISSUE, ...overrides, comments: { totalCount: nodes.length, nodes } });
  const comments = async (issue) => (await resolve({ issues: [issue] }, { laneAppId: 337595936 })).specText[0].comments;

  const refinement = comment(`${MARKER}\n- [ ] Line 3 says nineteen.`, lanes);
  const kept = comment("kept", human);
  const issue = on([kept, refinement]);
  assert.deepEqual(await comments(issue), ["kept", refinement.body]);
  // The gate's filter is human-only, so the record it compares holds no App comment.
  assert.deepEqual((await resolve({ issues: [issue] }, { laneAppId: 337595936 })).linkedIssues[0].spec_comments, [
    { id: kept.databaseId, updated_at: kept.updatedAt },
  ]);
  // Without the lanes App's id nothing the App wrote counts.
  assert.deepEqual((await resolve({ issues: [issue] })).specText[0].comments, ["kept"]);

  const edited = comment(`${MARKER}\nedited`, lanes, { lastEditedAt: "2026-10-20T00:00:00Z", editor: lanes });
  assert.deepEqual(await comments(on([edited])), [], "an edited refinement");

  const older = comment(`${MARKER}\nolder`, lanes);
  const newer = comment(`${MARKER}\nnewer`, lanes);
  assert.deepEqual(await comments(on([older, kept, newer])), ["kept", newer.body], "the newest supersedes an older one");
  assert.deepEqual(await comments(on([older, edited])), [], "an edited newest one leaves no older one in its place");

  assert.deepEqual(await comments(on([refinement], { author: lanes })), [], "an issue the lanes App filed");
  const otherEdit = { lastEditedAt: "2026-10-14T00:00:00Z", editor: lanes };
  assert.deepEqual(await comments(on([refinement], otherEdit)), [], "a body the lanes App last edited");

  for (const body of [`${MARKER.toUpperCase()}\nx`, ` ${MARKER}\nx`, `<!-- intake-triage refinements -->\nx`, `note\n${MARKER}`, "<!-- intake-triage admission -->\nx"]) {
    assert.deepEqual(await comments(on([comment(body, lanes)])), [], `marker mismatch: ${JSON.stringify(body)}`);
  }
  // pr-verify counts only a refinement posted before the pull request opened.
  const late = comment(`${MARKER}\nposted after the pull request opened`, lanes, { createdAt: "2026-10-20T00:00:01Z", updatedAt: "2026-10-20T00:00:01Z" });
  assert.deepEqual(await comments(on([refinement, late])), [], "a refinement posted after the pull request opened");
  assert.deepEqual(await comments(on([late])), [], "the only refinement, posted after the pull request opened");
  const early = comment(`${MARKER}\nposted just before`, lanes, { createdAt: "2026-10-19T23:59:59Z", updatedAt: "2026-10-19T23:59:59Z" });
  assert.deepEqual(await comments(on([early])), [early.body], "a refinement posted before the pull request opened");
  const undated = comment(`${MARKER}\nno creation time`, lanes, { createdAt: undefined });
  assert.deepEqual(await comments(on([undated])), [], "a refinement with no readable creation time");
  const opened = (createdAt) => resolve({ issues: [on([early])], edit: { lastEditedAt: null, editor: null, createdAt } }, { laneAppId: 337595936 });
  assert.deepEqual((await opened(undefined)).specText[0].comments, [], "a pull request with no readable creation time");

  for (const [who, author] of [["github-actions", actions], ["a Bot with the App's login and another id", impostor], ["the App as a User", { ...lanes, __typename: "User" }]]) {
    assert.deepEqual(await comments(on([comment(`${MARKER}\nx`, author)])), [], who);
  }
});

// #9372: intake's split leaves the human's body untouched, so it stays
// trusted; the split refinement alone names the item a person runs.
test("the done-when items intake's split refinement lists as checks a person runs reach the verifier beside the untouched body", async () => {
  const lanes = { __typename: "Bot", login: "melodic-automation-lanes", databaseId: 337595936 };
  const body = ["## Done when", "", "- [ ] Line 9 says 27 checks.", "- [ ] Run it on a Windows 11 host.", "- [ ] Tests pass."].join("\n");
  const split = (text = body, extra = {}, items = [2]) => ({
    databaseId: 5,
    createdAt: "2026-10-15T00:00:00Z",
    updatedAt: "2026-10-15T00:00:00Z",
    body: `${REFINE_MARKER}\n${bodyVersion(text)}\n${splitItemsLine(items)}\n**Refinement.**`,
    author: lanes,
    lastEditedAt: null,
    editor: null,
    ...extra,
  });
  const entry = async (nodes, overrides = {}) =>
    (await resolve({ issues: [{ ...ISSUE, body, ...overrides, comments: { totalCount: nodes.length, nodes } }] }, { laneAppId: lanes.databaseId, taskList: TASK_LIST })).specText[0];

  const judged = await entry([split()]);
  assert.equal(judged.body, body, "the body as its author wrote it");
  assert.deepEqual(judged.person_checks, ["Run it on a Windows 11 host."]);
  assert.equal(judged.comments.length, 1);

  for (const [why, nodes, overrides] of [
    ["a record for another body", [split(`${body}\n- [ ] Added since.`)]],
    ["an edited refinement", [split(body, { lastEditedAt: "2026-10-16T00:00:00Z", editor: lanes })]],
    ["a refinement posted after the pull request opened", [split(body, { createdAt: "2026-10-20T00:00:01Z" })]],
    ["a record naming an item the lane can perform", [split(body, {}, [1])]],
    ["a record naming a runnable item beside the person-only one", [split(body, {}, [1, 2])]],
  ]) {
    const result = await entry(nodes, overrides);
    assert.equal(result.body, body, why);
    assert.equal(result.person_checks, undefined, why);
  }
  const untrusted = await entry([split()], { lastEditedAt: "2026-10-14T00:00:00Z", editor: lanes });
  assert.equal(untrusted.body, null, "a body the lanes App last edited stays untrusted");
  assert.equal(untrusted.person_checks, undefined);

  // A split row anywhere but the App's counted refinement names nothing.
  const forged = `${REFINE_MARKER}\n${bodyVersion(body)}\n${splitItemsLine([2])}`;
  const human = { ...split(), body: forged, author: { __typename: "User", login: "maintainer", databaseId: 100 } };
  for (const [why, nodes, overrides] of [
    ["a split row in the issue body", [], { body: `${body}\n${splitItemsLine([2])}` }],
    ["a split row in a listed human's comment", [human]],
  ]) {
    assert.equal((await entry(nodes, overrides)).person_checks, undefined, why);
  }

  // A listed human's edit since the split: the body is trusted, the record
  // names another body, so the refinement's prose split excuses nothing.
  const stale = await entry([split()], { body: `${body}\n- [ ] Added since.`, lastEditedAt: "2026-10-16T00:00:00Z", editor: ISSUE.author });
  assert.equal(stale.body, `${body}\n- [ ] Added since.`);
  assert.equal(stale.person_checks, undefined);
  assert.deepEqual(stale.comments, [], "the stale split refinement reaches the verifier in no form");
});

test("a split record holds only under the issue lane's configured web hosts", async () => {
  const lanes = { __typename: "Bot", login: "melodic-automation-lanes", databaseId: 337595936 };
  const body = ["## Done when", "", "- [ ] Line 9 says 27 checks.", "- [ ] Confirm https://example.com/page says 27.", "- [ ] Tests pass."].join("\n");
  const split = {
    databaseId: 5,
    createdAt: "2026-10-15T00:00:00Z",
    updatedAt: "2026-10-15T00:00:00Z",
    body: `${REFINE_MARKER}\n${bodyVersion(body)}\n${splitItemsLine([2])}\n**Split.** Done-when item 2 of the issue body needs a person.`,
    author: lanes,
    lastEditedAt: null,
    editor: null,
  };
  const entry = async (webHosts) =>
    (await resolve({ issues: [{ ...ISSUE, body, comments: { totalCount: 1, nodes: [split] } }] }, { laneAppId: lanes.databaseId, taskList: TASK_LIST, webHosts })).specText[0];
  assert.deepEqual((await entry([])).person_checks, ["Confirm https://example.com/page says 27."], "a host outside the list");
  for (const hosts of [["example.com"], "any"]) {
    const result = await entry(hosts);
    assert.equal(result.person_checks, undefined, `hosts ${hosts}`);
    assert.deepEqual(result.comments, [], `hosts ${hosts}: the refinement's split prose is left out`);
  }
});

test("main identifies the lanes App by merge.agent-identity's id on the trusted list", async () => {
  const dir = tempDir("pr-verify-");
  const actors = path.join(dir, "trusted-actors.json");
  writeFileSync(
    actors,
    JSON.stringify({ version: 1, actors: [{ id: 100, login: "maintainer", kind: "human" }, { id: 337595936, login: "melodic-automation-lanes[bot]", kind: "bot" }] }),
  );
  const lanes = { __typename: "Bot", login: "melodic-automation-lanes", databaseId: 337595936 };
  const body = "<!-- intake-triage refinement -->\n- [ ] Line 3 says nineteen.";
  const issue = { ...ISSUE, comments: { totalCount: 1, nodes: [{ databaseId: 1, createdAt: "2026-10-11T00:00:00Z", updatedAt: "2026-10-11T00:00:00Z", body, author: lanes, lastEditedAt: null, editor: null }] } };
  const run = async (identity) => {
    const files = { out: path.join(dir, `out-${identity}`), spec: path.join(dir, "spec.json"), text: path.join(dir, `text-${identity}.json`) };
    const env = { GITHUB_TOKEN: "t", GITHUB_REPOSITORY: REPO, GITHUB_OUTPUT: files.out, UPSTREAM_RUN_ID: String(RUN), SPEC_FILE: files.spec, SPEC_TEXT_FILE: files.text, TRUSTED_ACTORS_PATH: actors, LANE_IDENTITY: identity };
    const log = console.log;
    console.log = () => {};
    try {
      await main(env, { github: fake({ issues: [issue] }) });
    } finally {
      console.log = log;
    }
    return JSON.parse(readFileSync(files.text, "utf8"))[0].comments;
  };
  // loginKey strips a trailing [bot], so both spellings of the identity resolve.
  assert.deepEqual(await run(LANE), [body]);
  assert.deepEqual(await run("melodic-automation-lanes"), [body]);
});

test("a pass judged before the spec last changed is judged again at the same head", async () => {
  const name = `pr-verify-41-${HEAD}-pass`;
  const passed = (start) => ({ artifacts: [artifact(name, 77)], runs: { 77: verifyRun(77, { run_started_at: start }) } });
  const human = { __typename: "User", login: "maintainer", databaseId: 100 };
  const edited = { ...ISSUE, lastEditedAt: "2026-10-21T00:00:00Z", editor: human };
  const commented = {
    ...ISSUE,
    comments: { totalCount: 1, nodes: [{ databaseId: 3, body: "one more criterion", updatedAt: "2026-10-21T00:00:00Z", author: human, lastEditedAt: null, editor: null }] },
  };
  for (const [label, issue] of [["a body edit", edited], ["a new spec comment", commented]]) {
    assert.equal(await reason({ ...passed("2026-10-20T23:59:59Z"), issues: [issue] }), "spec-changed", `${label} after the pass`);
    assert.equal(await reason({ ...passed("2026-10-21T00:00:01Z"), issues: [issue] }), "already-judged", `${label} before the pass`);
  }
  // A comment the spec leaves out changes nothing.
  const bot = { ...commented.comments.nodes[0], author: { __typename: "Bot", login: "github-actions", databaseId: 41898282 } };
  assert.equal(await reason({ ...passed("2026-10-20T23:59:59Z"), issues: [{ ...ISSUE, comments: { totalCount: 1, nodes: [bot] } }] }), "already-judged");
  // A pass whose start cannot be read is judged again.
  assert.equal(await reason(passed(undefined)), "spec-changed");
  // One pass after the change is enough; a FAIL at the head still stops it.
  const both = {
    issues: [edited],
    artifacts: [artifact(name, 77), artifact(name, 78)],
    runs: { 77: verifyRun(77, { run_started_at: "2026-10-20T00:00:00Z" }), 78: verifyRun(78, { run_started_at: "2026-10-22T00:00:00Z" }) },
  };
  assert.equal(await reason(both), "already-judged");
  const failed = { ...passed("2026-10-20T00:00:00Z"), issues: [edited] };
  failed.artifacts.push(artifact(`pr-verify-41-${HEAD}-fail`, 79));
  failed.runs[79] = verifyRun(79);
  assert.equal(await reason(failed), "already-judged");
});

test("a pull request that is its own spec is judged again after a body edit", async () => {
  const name = `pr-verify-41-${HEAD}-pass`;
  const setup = (lastEditedAt) => ({
    issues: [],
    pulls: [HUMAN_PR],
    edit: { lastEditedAt, editor: lastEditedAt ? { __typename: "User", login: "maintainer", databaseId: 100 } : null },
    artifacts: [artifact(name, 77)],
    runs: { 77: verifyRun(77) },
  });
  assert.equal(await reason(setup("2026-10-22T00:00:00Z"), { verifyAuthors: "any" }), "spec-changed");
  assert.equal(await reason(setup("2026-10-19T00:00:00Z"), { verifyAuthors: "any" }), "already-judged");
});

test("the linked issues record each body's last editor", async () => {
  const lanes = { __typename: "Bot", login: "melodic-automation-lanes", databaseId: 337595936 };
  const edited = { ...ISSUE, lastEditedAt: "2026-10-14T00:00:00Z", editor: lanes };
  assert.deepEqual((await resolve({ issues: [edited] })).linkedIssues, [
    { ...LINKED, last_edited_at: "2026-10-14T00:00:00Z", editor_login: "melodic-automation-lanes", editor_id: 337595936, editor_type: "Bot" },
  ]);
});

test("an issue whose comments are cut off fails the read", async () => {
  const cut = { ...ISSUE, comments: { totalCount: 101, nodes: [] } };
  await assert.rejects(resolve({ issues: [cut] }), { message: "#7: the issue's comments could not be read" });
});

test("main writes the outputs, the linked issues and the spec text the workflow reads", async () => {
  const dir = tempDir("pr-verify-");
  const output = path.join(dir, "out");
  const spec = path.join(dir, "spec.json");
  const specText = path.join(dir, "spec-text.json");
  const actors = path.join(dir, "trusted-actors.json");
  writeFileSync(actors, JSON.stringify({ version: 1, actors: [{ id: 100, login: "maintainer", kind: "human" }] }));
  await main(
    {
      GITHUB_TOKEN: "t",
      GITHUB_REPOSITORY: REPO,
      GITHUB_OUTPUT: output,
      UPSTREAM_RUN_ID: String(RUN),
      SPEC_FILE: spec,
      SPEC_TEXT_FILE: specText,
      TRUSTED_ACTORS_PATH: actors,
      LANE_IDENTITY: LANE,
    },
    { github: fake() },
  );
  assert.equal(
    readFileSync(output, "utf8"),
    `proceed=true\nreason=ok\npr-number=41\nhead-sha=${HEAD}\nbase-sha=${BASE}\nhead-ref=feat/x\nrelink-since-head=true\n`,
  );
  assert.deepEqual(JSON.parse(readFileSync(spec, "utf8")), [LINKED]);
  assert.deepEqual(JSON.parse(readFileSync(specText, "utf8")), [{ number: 7, spec_kind: "closes", body: "the spec", comments: [] }]);
});

test("main reports a human's PR as skipped in the log and the step summary", async (t) => {
  const dir = tempDir("pr-verify-");
  const output = path.join(dir, "out");
  const summary = path.join(dir, "summary");
  const actors = path.join(dir, "trusted-actors.json");
  writeFileSync(actors, JSON.stringify({ version: 1, actors: [{ id: 100, login: "maintainer", kind: "human" }] }));
  const log = t.mock.method(console, "log", () => {});
  await main(
    {
      GITHUB_TOKEN: "t",
      GITHUB_REPOSITORY: REPO,
      GITHUB_OUTPUT: output,
      GITHUB_STEP_SUMMARY: summary,
      UPSTREAM_RUN_ID: String(RUN),
      SPEC_FILE: path.join(dir, "spec.json"),
      SPEC_TEXT_FILE: path.join(dir, "spec-text.json"),
      TRUSTED_ACTORS_PATH: actors,
      LANE_IDENTITY: LANE,
    },
    { github: fake({ pulls: [HUMAN_PR] }) },
  );
  assert.match(readFileSync(output, "utf8"), /^proceed=false\nreason=author-not-lane\n/);
  assert.deepEqual(log.mock.calls.map((call) => call.arguments[0]), ["resolve-pr: proceed=false reason=author-not-lane"]);
  assert.equal(readFileSync(summary, "utf8"), "skipped: author not the lanes App\n");
});

test("main reports an invalid verify-authors value in the step summary", async (t) => {
  const dir = tempDir("pr-verify-");
  const summary = path.join(dir, "summary");
  const actors = path.join(dir, "trusted-actors.json");
  writeFileSync(actors, JSON.stringify({ version: 1, actors: [{ id: 100, login: "maintainer", kind: "human" }] }));
  t.mock.method(console, "log", () => {});
  await main(
    {
      GITHUB_TOKEN: "t",
      GITHUB_REPOSITORY: REPO,
      GITHUB_OUTPUT: path.join(dir, "out"),
      GITHUB_STEP_SUMMARY: summary,
      UPSTREAM_RUN_ID: String(RUN),
      SPEC_FILE: path.join(dir, "spec.json"),
      SPEC_TEXT_FILE: path.join(dir, "spec-text.json"),
      TRUSTED_ACTORS_PATH: actors,
      LANE_IDENTITY: LANE,
      VERIFY_AUTHORS: "all",
    },
    { github: fake() },
  );
  assert.equal(readFileSync(summary, "utf8"), "skipped: verify-authors value is invalid\n");
});

// Owner Q93 with the coordinator's Q9 extension: the unedited body of a
// sub-issue the lanes App filed in a size split, holding only lines of its
// native parent a listed human filed, is spec text; any other App body is not.
// The cases are shared with admit.test.mjs (split-child.vectors.json).
const VECTORS = JSON.parse(readFileSync(new URL("../intake-triage/split-child.vectors.json", import.meta.url), "utf8"));
const actorOf = (actor) => (actor ? { __typename: actor.type, login: actor.type === "Bot" ? "some-app" : "someone", databaseId: actor.id } : null);
const commentOf = (c) => ({ databaseId: c.id, createdAt: c.created_at, updatedAt: c.updated_at, body: c.body, lastEditedAt: c.last_edited_at, author: actorOf(c.author), editor: actorOf(c.editor) });
const childNode = ({ child }) => ({
  ...ISSUE,
  number: 8,
  body: child.body,
  lastEditedAt: child.last_edited_at,
  author: actorOf(child.author),
  editor: actorOf(child.editor),
});
const parentNode = ({ child, parent }) =>
  child.parent === null
    ? null
    : { ...ISSUE, number: child.parent.number, repository: { nameWithOwner: child.parent.repo ?? REPO }, body: VECTORS.parents[parent].body, author: actorOf(VECTORS.parents[parent].author), comments: { totalCount: VECTORS.parents[parent].comments.length, nodes: VECTORS.parents[parent].comments.map(commentOf) } };
const withParent = (setup, parent) => {
  const github = fake(setup);
  return async (method, apiPath, body) =>
    apiPath === "/graphql" && body.query.includes("parent {") ? { data: { repository: { issue: { parent } } } } : github(method, apiPath, body);
};
const TASK_LIST = loadRules(new URL("../../actions/resolve-config/admission-rules.json", import.meta.url).pathname)["task-list"];
const resolveChild = (child, parent, options = { laneAppId: VECTORS.app_id }) =>
  resolvePull({ github: withParent({ issues: [child] }, parent), repository: REPO, upstreamRunId: String(RUN), humans: new Set(VECTORS.humans), laneIdentity: LANE, taskList: TASK_LIST, ...options });
const specBody = async (...args) => (await resolveChild(...args)).specText.map(({ number, body }) => [number, body]);

for (const vector of VECTORS.cases) {
  test(`split-child vector: ${vector.name}`, async () => {
    const appId = "app_id" in vector ? vector.app_id : VECTORS.app_id;
    const body = await specBody(childNode(vector), parentNode(vector), appId === null ? {} : { laneAppId: appId });
    assert.deepEqual(body, [[8, vector.expect.trusted ? vector.child.body : null]], vector.expect.reason);
  });
}

// A trusted target-subset part carries its Scope line's targets as `scope`,
// which narrows its criteria; any other entry carries none.
test("a trusted target-subset child's spec entry carries its scope", async () => {
  const scoped = VECTORS.cases.find((item) => item.name === "a target-subset child with one Scope line of verbatim targets");
  const plain = VECTORS.cases.find((item) => item.name === "the trusted child");
  const scopeOf = async (vector) => (await resolveChild(childNode(vector), parentNode(vector))).specText.map(({ scope }) => scope);
  assert.deepEqual(await scopeOf(scoped), [["nineteen", "Line 4"]]);
  assert.deepEqual(await scopeOf(plain), [undefined]);
});

// A parent read short of its comments, or not read at all, stops the run:
// judging without the child's criteria leaves a pass the gate would count
// once the parent reads whole again (an outsider deleting padding comments).
test("a split child whose parent cannot be read whole stops the run", async () => {
  const vector = VECTORS.cases.find((item) => item.name === "the trusted child");
  const cut = { ...parentNode(vector), comments: { totalCount: 101, nodes: [] } };
  await assert.rejects(resolveChild(childNode(vector), cut), { message: "#8: the split parent's comments could not be read" });
  const github = fake({ issues: [childNode(vector)] });
  const unread = async (method, apiPath, body) => (apiPath === "/graphql" && body.query.includes("parent {") ? { data: null } : github(method, apiPath, body));
  await assert.rejects(
    resolvePull({ github: unread, repository: REPO, upstreamRunId: String(RUN), humans: new Set(VECTORS.humans), laneIdentity: LANE, taskList: TASK_LIST, laneAppId: VECTORS.app_id }),
    { message: "#8: the split parent could not be read" },
  );
});

test("with no task-list marker, even the trusted split child is not spec", async () => {
  const vector = VECTORS.cases.find((item) => item.name === "the trusted child");
  for (const taskList of [undefined, ""]) {
    assert.deepEqual(await specBody(childNode(vector), parentNode(vector), { laneAppId: VECTORS.app_id, taskList }), [[8, null]], JSON.stringify(taskList));
  }
});

// Every API call resolvePull makes, for the call-count pins below. The counts
// follow the lookup order: FAIL names first, since a counted FAIL alone
// decides already-judged, then this PR's passes; a pass whose spec is
// unchanged decides already-judged before the issue-named FAIL lookups.
async function calls(setup) {
  const github = fake(setup);
  const paths = [];
  const recording = async (method, apiPath, body) => {
    paths.push(apiPath === "/graphql" ? `graphql ${body.query.includes("closingIssuesReferences") ? "spec" : "other"}` : apiPath);
    return github(method, apiPath, body);
  };
  const { reason } = await resolvePull({ github: recording, repository: REPO, upstreamRunId: String(RUN), humans: HUMANS, laneIdentity: LANE });
  return { reason, paths };
}

test("each path through the resolver makes a pinned number of API calls", async () => {
  const counted = (name, start = JUDGED_AT) => ({ artifacts: [artifact(name, 77)], runs: { 77: verifyRun(77, { run_started_at: start }) } });
  const cases = [
    // run, commit pulls, three names without issues, the spec, the FAIL name with issues.
    ["an unjudged head", {}, "ok", 7],
    // run, commit pulls, the FAIL name, its run and compare, the spec, the relink read.
    ["a FAIL named without issues", counted(`pr-verify-41-${HEAD}-fail`), "already-judged", 7],
    // As above, but the PR links no issue now, so the relink is never read.
    ["a FAIL named without issues, no issue linked", { ...counted(`pr-verify-41-${HEAD}-fail`), issues: [] }, "already-judged", 6],
    // run, commit pulls, three names, the spec, the -i7 name, the FAIL's run and compare.
    ["a FAIL named with the PR's issues", counted(`pr-verify-41-${HEAD}-fail-i7`), "already-judged", 9],
    // run, commit pulls, three names, the pass's run and compare, the spec.
    ["a pass with the spec unchanged", counted(`pr-verify-41-${HEAD}-pass`), "already-judged", 8],
    // As above, then the FAIL name with issues.
    ["a pass the spec changed after", counted(`pr-verify-41-${HEAD}-pass`, "2026-10-19T00:00:00Z"), "spec-changed", 9],
  ];
  const edited = { ...ISSUE, lastEditedAt: "2026-10-20T00:00:00Z", editor: { __typename: "User", login: "maintainer", databaseId: 100 } };
  for (const [label, setup, expected, count] of cases) {
    const { reason: got, paths } = await calls({ issues: [edited], ...setup });
    assert.equal(got, expected, label);
    assert.equal(paths.length, count, `${label}:\n${paths.join("\n")}`);
  }
});

test("FAIL names first and a pass decided before the issue-named lookups give the same reasons as the old order", async () => {
  // The old order looked up this PR's passes, then the FAILs, and always the
  // issue-named FAILs before weighing a pass; each combination resolves the same.
  const fail = (name, id) => [artifact(name, id), verifyRun(id)];
  const pass = (id, start) => [artifact(`pr-verify-41-${HEAD}-pass`, id), verifyRun(id, { run_started_at: start })];
  const verdicts = {
    plainFail: fail(`pr-verify-41-${HEAD}-fail`, 80),
    otherFail: fail(`pr-verify-99-${HEAD}-fail`, 81),
    issueFail: fail(`pr-verify-41-${HEAD}-fail-i7`, 82),
    stalePass: pass(83, "2026-10-19T00:00:00Z"),
    freshPass: pass(84, JUDGED_AT),
  };
  const edited = { ...ISSUE, lastEditedAt: "2026-10-20T00:00:00Z", editor: { __typename: "User", login: "maintainer", databaseId: 100 } };
  const keys = Object.keys(verdicts);
  for (let mask = 0; mask < 1 << keys.length; mask += 1) {
    const chosen = keys.filter((_, i) => mask & (1 << i));
    const setup = {
      issues: [edited],
      pulls: [pull(), pull({ number: 99, state: "closed" })],
      artifacts: chosen.map((key) => verdicts[key][0]),
      runs: Object.fromEntries(chosen.map((key) => [verdicts[key][1].id, verdicts[key][1]])),
    };
    const anyFail = chosen.some((key) => key.endsWith("Fail"));
    const expected = anyFail || chosen.includes("freshPass") ? "already-judged" : chosen.includes("stalePass") ? "spec-changed" : "ok";
    assert.equal(await reason(setup), expected, chosen.join("+") || "none");
  }
});

// pr-verify.yml's check-intent hands its reads to check-intent-subscription
// (resolve-pr.mjs packReads, takeReads), so a handoff does not repeat them.
const CARRY = {
  attempt: "1",
  prNumber: 41,
  headSha: HEAD,
  baseSha: "b".repeat(40),
  headRef: "feat/41-carry",
  relinkSinceHead: "false",
  linkedIssues: [{ number: 7 }],
  specText: [{ number: 7, body: "spec" }],
  context: { pr: { number: 41 }, items: [], dropped: {} },
};
// A client that fails the test on any read.
const noReads = () => async (method, apiPath) => assert.fail(`no read on the carried path: ${method} ${apiPath}`);

test("the carried reads round-trip for the same run attempt and nothing else", () => {
  const packed = packReads(CARRY);
  assert.ok(packed.length > 0 && packed.length <= CARRY_MAX);
  const { attempt, ...rest } = CARRY;
  assert.deepEqual(takeReads(packed, "1"), rest);
  // relink-since-head survives as written, both ways.
  assert.equal(takeReads(packReads({ ...CARRY, relinkSinceHead: "true" }), "1").relinkSinceHead, "true");
  // A re-run of the subscription job alone is a new attempt: it reads again.
  assert.equal(takeReads(packed, "2"), null);
  assert.equal(takeReads(packed, ""), null);
  for (const broken of [
    { headSha: "x" },
    { baseSha: "" },
    { headRef: "a b" },
    { prNumber: 0 },
    { linkedIssues: null },
    { specText: {} },
    { context: [] },
    { relinkSinceHead: "" },
    { relinkSinceHead: "yes" },
    { relinkSinceHead: undefined },
  ]) {
    assert.equal(takeReads(packReads({ ...CARRY, ...broken }), "1"), null, JSON.stringify(broken));
  }
  assert.equal(takeReads("not base64 json", "1"), null);
  assert.equal(takeReads("", "1"), null);
  // Too large to hand on: empty, so the subscription job reads again.
  assert.equal(packReads({ ...CARRY, context: { pad: "x".repeat(CARRY_MAX) } }), "");
  // The taker caps size too, whoever wrote the bundle.
  assert.equal(takeReads("A".repeat(CARRY_MAX + 1), "1"), null);
});

test("carry hands on the base-side files, and nothing when one is missing", (t) => {
  t.mock.method(console, "log", () => {});
  const dir = tempDir("pr-verify-");
  const env = {
    GITHUB_RUN_ATTEMPT: "1",
    GITHUB_OUTPUT: path.join(dir, "out"),
    PR_NUMBER: "41",
    HEAD_SHA: CARRY.headSha,
    BASE_SHA: CARRY.baseSha,
    HEAD_REF: CARRY.headRef,
    RELINK_SINCE_HEAD: CARRY.relinkSinceHead,
    SPEC_FILE: path.join(dir, "spec.json"),
    SPEC_TEXT_FILE: path.join(dir, "spec-text.json"),
    CONTEXT_FILE: path.join(dir, "context.json"),
  };
  writeFileSync(env.SPEC_FILE, JSON.stringify(CARRY.linkedIssues));
  writeFileSync(env.SPEC_TEXT_FILE, JSON.stringify(CARRY.specText));
  carryMain(env);
  assert.match(readFileSync(env.GITHUB_OUTPUT, "utf8"), /^reads=\n$/, "no context file");
  writeFileSync(env.CONTEXT_FILE, JSON.stringify(CARRY.context));
  writeFileSync(env.GITHUB_OUTPUT, "");
  carryMain(env);
  const reads = /^reads=(.+)$/m.exec(readFileSync(env.GITHUB_OUTPUT, "utf8"))[1];
  assert.equal(takeReads(reads, "1").context.pr.number, 41);
  // With no relink-since-head output, nothing is handed on.
  writeFileSync(env.GITHUB_OUTPUT, "");
  carryMain({ ...env, RELINK_SINCE_HEAD: "" });
  assert.match(readFileSync(env.GITHUB_OUTPUT, "utf8"), /^reads=\n$/, "no relink-since-head");
});

test("main takes the carried reads with no API read, and reads again when they do not hold", async (t) => {
  t.mock.method(console, "log", () => {});
  const dir = tempDir("pr-verify-");
  const actors = path.join(dir, "trusted-actors.json");
  writeFileSync(actors, JSON.stringify({ version: 1, actors: [{ id: 100, login: "maintainer", kind: "human" }] }));
  const env = {
    GITHUB_TOKEN: "t",
    GITHUB_REPOSITORY: REPO,
    GITHUB_RUN_ATTEMPT: "1",
    GITHUB_OUTPUT: path.join(dir, "out"),
    UPSTREAM_RUN_ID: String(RUN),
    SPEC_FILE: path.join(dir, "spec.json"),
    SPEC_TEXT_FILE: path.join(dir, "spec-text.json"),
    CONTEXT_FILE: path.join(dir, "context.json"),
    TRUSTED_ACTORS_PATH: actors,
    LANE_IDENTITY: LANE,
    CARRIED: packReads(CARRY),
  };
  await main(env, { github: noReads() });
  assert.equal(
    readFileSync(env.GITHUB_OUTPUT, "utf8"),
    `proceed=true\nreason=carried\npr-number=41\nhead-sha=${HEAD}\nbase-sha=${CARRY.baseSha}\nhead-ref=feat/41-carry\nrelink-since-head=false\ncarried=true\n`,
  );
  assert.deepEqual(JSON.parse(readFileSync(env.SPEC_FILE, "utf8")), CARRY.linkedIssues);
  assert.deepEqual(JSON.parse(readFileSync(env.SPEC_TEXT_FILE, "utf8")), CARRY.specText);
  assert.deepEqual(JSON.parse(readFileSync(env.CONTEXT_FILE, "utf8")), CARRY.context);
  // Another attempt's reads, or none: the full resolver runs on its reads.
  for (const carried of [packReads({ ...CARRY, attempt: "2" }), "garbage"]) {
    writeFileSync(env.GITHUB_OUTPUT, "");
    await main({ ...env, CARRIED: carried }, { github: fake() });
    const out = readFileSync(env.GITHUB_OUTPUT, "utf8");
    assert.match(out, /^proceed=true\nreason=ok\npr-number=41\n/, carried);
    assert.doesNotMatch(out, /carried=true/);
  }
});
