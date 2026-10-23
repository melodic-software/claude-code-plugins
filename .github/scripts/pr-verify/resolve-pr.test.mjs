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
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { test } from "node:test";

import { main, resolvePull } from "./resolve-pr.mjs";

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
  ...overrides,
});

const artifact = (name, runId, expired = false) => ({ name, expired, workflow_run: { id: runId } });

function fake({ run = upstream(), pulls = [pull()], artifacts = [], runs = {}, onMain = [MAIN], issues = [ISSUE], edit = { lastEditedAt: null, editor: null }, restFails = false, associated = [], body: prBody = null, refs = {}, queries = [] } = {}) {
  const github = async (method, apiPath, body) => {
    if (apiPath === `/repos/${REPO}/actions/runs/${RUN}`) return run;
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
    if (apiPath === "/graphql") {
      return { data: { repository: { pullRequest: { ...edit, body: prBody, closingIssuesReferences: { totalCount: issues.length, nodes: issues } } } } };
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
  // No errors and no repository is no answer, not "no issue".
  for (const answer of [{ data: {} }, { data: { repository: null } }, {}]) {
    await assert.rejects(resolve({ issues: [], body: "Refs: #7", refs: { 7: { answer } } }), /the Refs issue could not be read/, JSON.stringify(answer));
  }
});

// The production helper throws on any GraphQL `errors` unless asked to keep
// them, so main must read the Refs issue with one that keeps them.
test("main with the real GitHub helper reads a Refs typo as no linked issue", async () => {
  const dir = mkdtempSync(path.join(tmpdir(), "pr-verify-"));
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

test("a run that is not a passing pr-require-checks pull_request run of this repository starts nothing", async () => {
  for (const overrides of [
    { path: ".github/workflows/pr-review-hosted.yml" },
    { event: "merge_group" },
    { event: "workflow_dispatch" },
    { conclusion: "failure" },
    { status: "in_progress", conclusion: null },
    { repository: { full_name: "someone/fork" } },
    { head_repository: { full_name: "someone/fork" } },
    { id: RUN + 1 },
    { head_sha: "nothex" },
  ]) {
    assert.equal(await reason({ run: upstream(overrides) }), "not-a-passing-run", JSON.stringify(overrides));
  }
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

test("main judges every trusted-actors.json account under lane-or-owner, a Bot included", async (t) => {
  const dir = mkdtempSync(path.join(tmpdir(), "pr-verify-"));
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
    `/repos/${REPO}/actions/artifacts?name=pr-verify-41-${HEAD}-fail-${REF_DIGEST}&per_page=100&page=1`,
    `/repos/${REPO}/actions/artifacts?name=pr-verify-41-${HEAD}-fail-${REF_DIGEST}-i7&per_page=100&page=1`,
    `/repos/${REPO}/actions/artifacts?name=pr-verify-41-${HEAD}-fail-i7&per_page=100&page=1`,
    `/repos/${REPO}/actions/artifacts?name=pr-verify-41-${HEAD}-pass&per_page=100&page=1`,
    `/repos/${REPO}/actions/artifacts?name=pr-verify-41-${HEAD}-pass-${REF_DIGEST}&per_page=100&page=1`,
    `/repos/${REPO}/actions/artifacts?name=pr-verify-41-${HEAD}-pass-notes&per_page=100&page=1`,
    `/repos/${REPO}/actions/artifacts?name=pr-verify-41-${HEAD}-pass-notes-${REF_DIGEST}&per_page=100&page=1`,
    `/repos/${REPO}/actions/artifacts?name=pr-verify-99-${HEAD}-fail&per_page=100&page=1`,
    `/repos/${REPO}/actions/artifacts?name=pr-verify-99-${HEAD}-fail-${OTHER_DIGEST}&per_page=100&page=1`,
  ]);
});

test("a FAIL named with this pull request's issues stops a new judgment", async () => {
  // The fake pull request closes one issue, so write-verdict.mjs named its
  // FAIL with that number after -i.
  const pulls = [pull()];
  for (const name of [`pr-verify-41-${HEAD}-fail-i7`, `pr-verify-41-${HEAD}-fail-${REF_DIGEST}-i7`]) {
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

test("a head with a verdict named without issues skips before the linked issues are read", async () => {
  for (const name of [`pr-verify-41-${HEAD}-pass`, `pr-verify-41-${HEAD}-fail`]) {
    assert.deepEqual(await specReads({ artifacts: [artifact(name, 77)], runs: { 77: verifyRun(77) } }), ["already-judged", 0], name);
  }
});

test("a head whose only verdict is a FAIL named with issues skips after one linked-issues read", async () => {
  const artifacts = [artifact(`pr-verify-41-${HEAD}-fail-i7`, 77)];
  assert.deepEqual(await specReads({ artifacts, runs: { 77: verifyRun(77) } }), ["already-judged", 1]);
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

test("a verdict named with its head-ref digest stops a new judgment like one without", async () => {
  const pulls = [pull(), pull({ number: 99, state: "closed", head: { sha: HEAD, ref: "feat/other", repo: { full_name: REPO } } })];
  for (const name of [`pr-verify-41-${HEAD}-pass-${REF_DIGEST}`, `pr-verify-99-${HEAD}-fail-${OTHER_DIGEST}`]) {
    assert.equal(await reason({ pulls, artifacts: [artifact(name, 77)], runs: { 77: verifyRun(77) } }), "already-judged", name);
  }
  // Any branch name is looked up by its digest, whatever characters it holds:
  // the first 16 hex digits of `printf %s <ref> | sha256sum`.
  for (const [ref, digest] of [["feat/a+b", "a27da2afd9962004"], ["fix/\u00e9", "8c8a071ad0e51f5e"]]) {
    const head = { sha: HEAD, ref, repo: { full_name: REPO } };
    const odd = [pull({ head }), pull({ number: 99, state: "closed", head })];
    for (const name of [`pr-verify-41-${HEAD}-pass-${digest}`, `pr-verify-99-${HEAD}-fail-${digest}`]) {
      assert.equal(await reason({ pulls: odd, artifacts: [artifact(name, 77)], runs: { 77: verifyRun(77) } }), "already-judged", name);
    }
  }
  // A digest of another branch is not this pull request's verdict.
  const foreign = artifact(`pr-verify-41-${HEAD}-pass-${OTHER_DIGEST}`, 77);
  assert.equal(await reason({ pulls, artifacts: [foreign], runs: { 77: verifyRun(77) } }), "ok");
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
  const dir = mkdtempSync(path.join(tmpdir(), "pr-verify-"));
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
    `proceed=true\nreason=ok\npr-number=41\nhead-sha=${HEAD}\nbase-sha=${BASE}\nhead-ref=feat/x\n`,
  );
  assert.deepEqual(JSON.parse(readFileSync(spec, "utf8")), [LINKED]);
  assert.deepEqual(JSON.parse(readFileSync(specText, "utf8")), [{ number: 7, spec_kind: "closes", body: "the spec", comments: [] }]);
});

test("main reports a human's PR as skipped in the log and the step summary", async (t) => {
  const dir = mkdtempSync(path.join(tmpdir(), "pr-verify-"));
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
  const dir = mkdtempSync(path.join(tmpdir(), "pr-verify-"));
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
