// Expected values come from fix-docs's applies-when in
// docs/conventions/pr-pipeline.yaml (paths **/*.md, labels-absent do-not-merge
// and needs-human, draft false), the check name `pr-refine / fix-docs` the
// read runner posts as `<lane> / <activity>` (and `pr-unblock / fix-docs`, the
// lane fix-docs ran in before), the owner's call to tidy every PR but
// Dependabot's, the release App's and the standards-sync App's, and once per
// PR, as pr-refine.yml's old trigger ran it when a PR opened or turned ready.
// work-resolve-issue's PRs, the lanes App's on a lane branch
// (work-resolve-issue/issue-<n>-<run>-<attempt>), are skipped when tidied in
// their own run (within the tidy cutoffs: README, Activities, `tidy`), and
// dispatched over them (#13717 issuecomment-6692723687).
import assert from "node:assert/strict";
import { test } from "node:test";

import { emptyRecord, isHandled, markHandled, parseRecord, serializeRecord } from "./dispatch-record.mjs";
import { createGitHubApi, PULL_QUERY } from "./dispatch.mjs";
import { dispatchDocsFixes, docsRunState, heldHandoff, heldHead, HISTORY_COMMITS, HISTORY_QUERY } from "./fix-docs-dispatch.mjs";

const ACTIONS = 15368;
const CHECK = "pr-refine / fix-docs";
const EARLIER_CHECK = "pr-unblock / fix-docs";
// GET /users/<login> ids, which GraphQL's Bot.databaseId returns too.
const DEPENDABOT = 49699333;
const RELEASE_APP = 337859524;
const STANDARDS_SYNC_APP = 300666570;
const LANES_APP = 337595936;

const checkRun = (name, app = ACTIONS) => ({ __typename: "CheckRun", name, checkSuite: { app: { databaseId: app } } });

// A ready PR a person opened that changes a Markdown file, with no fix-docs run.
function pr(number, { paths = ["docs/guide.md"], more = false, checks = [], ...overrides } = {}) {
  const head = String(number).padStart(40, "d");
  return {
    number,
    isDraft: false,
    isCrossRepository: false,
    baseRefName: "main",
    headRefOid: head,
    author: { __typename: "User", login: "someone", databaseId: 4242 },
    labels: { nodes: [] },
    files: { nodes: paths.map((path) => ({ path })), pageInfo: { hasNextPage: more } },
    commits: { nodes: [{ commit: { oid: head, statusCheckRollup: { contexts: { nodes: checks, pageInfo: { hasNextPage: false } } } } }] },
    ...overrides,
  };
}

// Per PR number, the check-run counts on each of its last commits; absent is
// none. `earlier` gives the counts under the earlier check name.
const history = (counts = [], earlier = counts.map(() => 0)) => ({
  commits: {
    nodes: counts.map((count, index) => ({
      commit: {
        checkSuites: { nodes: [{ checkRuns: { totalCount: count }, earlierRuns: { totalCount: earlier[index] } }], pageInfo: { hasNextPage: false } },
      },
    })),
  },
});

function fakeApi({ pages = [[]], histories = {}, workflowRuns = [], failHistory = new Set(), comments = new Map(), labelEvents = new Map(), reviewComments = new Map(), runJobs = new Map() } = {}) {
  const calls = { history: [], dispatch: [], jobs: [] };
  return {
    calls,
    // Per run id, its status and latest jobs, null when it is gone, or the
    // error the read throws.
    async readRunJobs(runId) {
      calls.jobs.push(runId);
      const read = runJobs.get(runId);
      if (read instanceof Error) {
        throw read;
      }
      return read ?? null;
    },
    // The REST issue timeline: its comments, then its label events.
    async listTimeline(number) {
      return [...(comments.get(number) ?? []).map((comment) => ({ event: "commented", ...comment })), ...(labelEvents.get(number) ?? [])];
    },
    // The REST review comments and reviews, with an inline reply's in_reply_to_id.
    async listReviewComments(number) {
      return reviewComments.get(number) ?? [];
    },
    async listReviews() {
      return [];
    },
    async listDocsFixCandidates({ after }) {
      const index = after === undefined ? 0 : Number(after);
      return {
        rateLimit: { cost: 3, remaining: 4990 },
        pullRequests: { nodes: pages[index], pageInfo: { hasNextPage: index + 1 < pages.length, endCursor: String(index + 1) } },
      };
    },
    async readDocsFixHistory({ number, appId, checkName, earlierCheckName }) {
      calls.history.push({ number, appId, checkName, earlierCheckName });
      if (failHistory.has(number)) {
        throw new Error("history read failed");
      }
      return { rateLimit: { cost: 1, remaining: 4989 }, pullRequest: histories[number] ?? history([0]) };
    },
    async listWorkflowRuns() {
      if (workflowRuns instanceof Error) {
        throw workflowRuns;
      }
      return workflowRuns;
    },
    async dispatchWorkflow({ workflow, ref, inputs }) {
      calls.dispatch.push({ workflow, ref, inputs });
      return { workflowRunId: 8000 + Number(inputs["pr-number"]) };
    },
  };
}

async function run(apiOptions, options = {}) {
  const api = fakeApi(apiOptions);
  const lines = [];
  const record = options.record ?? emptyRecord();
  const result = await dispatchDocsFixes({ api, runId: "4242", log: (line) => lines.push(line), maxDispatch: 2, record, ...options });
  return { api, lines, result, record };
}

const numbers = (api) => api.calls.dispatch.map((call) => call.inputs["pr-number"]);

test("a ready PR a person opened that changes Markdown is dispatched pr-refine.yml fix-docs on main with the dispatcher's run id", async () => {
  const { api, result, lines } = await run({ pages: [[pr(5)]] });
  assert.deepEqual(api.calls.dispatch, [
    { workflow: "pr-refine.yml", ref: "refs/heads/main", inputs: { "pr-number": "5", activity: "fix-docs", "dispatcher-run-id": "4242" } },
  ]);
  assert.deepEqual(result, { dispatched: [{ number: 5, workflowRunId: "8005" }], failed: 0 });
  assert.deepEqual(api.calls.history, [{ number: 5, appId: ACTIONS, checkName: CHECK, earlierCheckName: EARLIER_CHECK }]);
  assert.ok(lines.includes("fix-docs listing page 1: rateLimit.cost=3 remaining=4990"), "the listing's cost is logged");
});

test("maxDispatch 0 turns fix-docs off: one log line, nothing sent, no GitHub call", async () => {
  const touched = [];
  const api = new Proxy({}, { get: (_, name) => touched.push(name) && (() => assert.fail(`${String(name)} called`)) });
  const lines = [];
  const result = await dispatchDocsFixes({ api, runId: "4242", log: (line) => lines.push(line), maxDispatch: 0, record: emptyRecord() });
  assert.deepEqual(result, { dispatched: [], failed: 0 });
  assert.deepEqual(lines, ["fix-docs is off (fix-docs-per-run: 0)"]);
  assert.deepEqual(touched, []);
  const on = await run({ pages: [[pr(5), pr(6)]] }, { maxDispatch: 1 });
  assert.deepEqual(numbers(on.api), ["5"], "1 still sends one");
});

test("a run listing that cannot be read, rate-limited or not, defers with a warning and fails nothing", async () => {
  const limited = Object.assign(new Error("GET runs returned 403"), { rateLimited: true });
  const deferred = await run({ pages: [[pr(5)]], workflowRuns: limited });
  assert.deepEqual(deferred.result, { dispatched: [], failed: 0 });
  assert.ok(deferred.lines.some((line) => line.startsWith("::warning::") && line.includes("rate limited")));
  const broken = await run({ pages: [[pr(5)]], workflowRuns: new Error("GET runs returned 404") });
  assert.deepEqual(broken.result, { dispatched: [], failed: 0 });
  assert.ok(broken.lines.some((line) => line.startsWith("::warning::") && line.includes("could not be read") && line.includes("404")));
});

test("a PR that changes no Markdown file is not dispatched; a file list cut off at 100 leaves it to the lane", async () => {
  assert.deepEqual(numbers((await run({ pages: [[pr(6, { paths: ["src/a.js", "README.txt", "notes.mdx"] })]] })).api), []);
  assert.deepEqual(numbers((await run({ pages: [[pr(7, { paths: ["src/a.js"], more: true })]] })).api), ["7"]);
  assert.deepEqual(numbers((await run({ pages: [[pr(8, { paths: ["a/b/c.md"] })]] })).api), ["8"]);
});

test("a draft, a fork, a PR into another base, or a held PR is not dispatched", async () => {
  const pulls = [
    pr(10, { isDraft: true }),
    pr(11, { isCrossRepository: true }),
    pr(12, { baseRefName: "release" }),
    pr(13, { labels: { nodes: [{ name: "do-not-merge" }] } }),
    pr(14, { labels: { nodes: [{ name: "needs-human" }] } }),
  ];
  const { api } = await run({ pages: [pulls] });
  assert.deepEqual(numbers(api), []);
  assert.deepEqual(api.calls.history, [], "no history read for a PR the listing drops");
});

// report-escalation.sh's comment and label, by the lanes App, or the label by a person.
const APP_USER = { login: "melodic-automation-lanes[bot]", id: LANES_APP, type: "Bot" };
const labeledBy = (actor) => [{ event: "labeled", actor, label: { name: "needs-human" }, created_at: "2026-10-22T10:00:00Z" }];
const escalation = [
  {
    user: APP_USER,
    created_at: "2026-10-22T10:00:05Z",
    body: `<!-- work-items:escalation lane=pr-unblock kind=escalated -->\n<!-- pr-unblock resume-key=${"b".repeat(40)} -->\nStopped.\n\n- Reason: \`ci-fix-escalated\``,
  },
];

test("needs-human from a lane escalation does not hold fix-docs, which never escalates; a person's does", async () => {
  const gated = { labels: { nodes: [{ name: "needs-human" }] } };
  const { api, record } = await run(
    {
      pages: [[pr(15, gated), pr(16, gated)]],
      comments: new Map([[15, escalation]]),
      labelEvents: new Map([
        [15, labeledBy(APP_USER)],
        [16, labeledBy({ login: "kyle-sexton", id: 153232337, type: "User" })],
      ]),
    },
    { gateLabel: "needs-human", appSenderId: LANES_APP },
  );
  assert.deepEqual(numbers(api), ["15"]);
  assert.equal(isHandled(record, CHECK, pr(16).headRefOid), false, "a held PR is not done");
});

test("a person's inline review-thread reply since a lane escalation holds fix-docs; a bot's does not", async () => {
  // GitHub's timeline has no event for a reply inside an existing review thread.
  const reply = (user) => [{ id: 2, in_reply_to_id: 1, user, body: "Wait.", created_at: "2026-10-22T11:00:00Z", updated_at: "2026-10-22T11:00:00Z" }];
  const gated = { labels: { nodes: [{ name: "needs-human" }] } };
  const { api, lines } = await run(
    {
      pages: [[pr(17, gated), pr(18, gated)]],
      comments: new Map([
        [17, escalation],
        [18, escalation],
      ]),
      labelEvents: new Map([
        [17, labeledBy(APP_USER)],
        [18, labeledBy(APP_USER)],
      ]),
      reviewComments: new Map([
        [17, reply({ login: "kyle-sexton", id: 153232337, type: "User" })],
        [18, reply(APP_USER)],
      ]),
    },
    { gateLabel: "needs-human", appSenderId: LANES_APP },
  );
  assert.deepEqual(numbers(api), ["18"]);
  assert.ok(lines.includes("skip fix-docs #17: held by needs-human: a person commented or reviewed since needs-human went on"), lines.join("\n"));
});

test("PRs the lanes App or another bot opened are dispatched; Dependabot's, the release App's and the standards-sync App's are not", async () => {
  const pulls = [
    pr(20, { author: { __typename: "Bot", login: "melodic-automation-lanes", databaseId: LANES_APP } }),
    pr(21, { author: { __typename: "Bot", login: "dependabot", databaseId: DEPENDABOT } }),
    pr(22, { author: { __typename: "Bot", login: "melodic-release", databaseId: RELEASE_APP } }),
    pr(23, { author: { __typename: "Bot", login: "melodic-standards-sync", databaseId: STANDARDS_SYNC_APP } }),
    pr(24, { author: { __typename: "Bot", login: "claude", databaseId: 209825114 } }),
    pr(25),
  ];
  assert.deepEqual(numbers((await run({ pages: [pulls] })).api), ["20", "24"]);
});

const LANES_BOT = { __typename: "Bot", login: "melodic-automation-lanes", databaseId: LANES_APP };
// Small cutoffs in resolve-issue's tidy.cutoffs shape (pr-pipeline.yaml), so
// each bound sits a step from its value; areas as the README's tidy entry
// defines them.
const CUTOFFS = { "max-files": 2, "max-lines": 10, "max-areas": 1, "shared-paths": [".github/", "AGENTS.md"] };
// The lane run's one commit as PULL_QUERY lists it, in the shape GraphQL
// returned for a work-resolve-issue PR's API commit: a valid signature, the
// App's bot user as author, and GitHub's noreply@github.com as committer.
const laneCommitNode = (head, overrides = {}) => ({
  oid: head,
  signature: { isValid: true },
  author: { user: { login: "melodic-automation-lanes[bot]" } },
  committer: { email: "noreply@github.com" },
  statusCheckRollup: { contexts: { nodes: [], pageInfo: { hasNextPage: false } } },
  ...overrides,
});
// A lane PR exactly at the cutoffs: 2 files, 6 + 4 lines, one area
// (plugins/x with its .changes/x fragment), and one lane commit at its head.
const lanePr = (number, { paths = ["plugins/x/a.md", ".changes/x/f.md"], commit = {}, commitCount = 1, ...overrides } = {}) =>
  pr(number, {
    author: LANES_BOT,
    headRefName: "work-resolve-issue/issue-12-345-1",
    paths,
    changedFiles: paths.length,
    additions: 6,
    deletions: 4,
    commits: { totalCount: commitCount, nodes: [{ commit: laneCommitNode(pr(number).headRefOid, commit) }] },
    ...overrides,
  });
const lane = { appSenderId: LANES_APP, tidyCutoffs: CUTOFFS, maxDispatch: 20 };

test("a work-resolve-issue PR (the lanes App's, on a lane branch) within the tidy cutoffs is skipped; the App's other PRs and a person's lane-named branch are not", async () => {
  const pulls = [lanePr(30), lanePr(31, { headRefName: "chore/x" }), lanePr(32, { author: pr(32).author }), lanePr(33, { headRefName: "work-resolve-issue/issue-1-x" })];
  const { api, record } = await run({ pages: [pulls] }, lane);
  assert.deepEqual(numbers(api), ["31", "32", "33"]);
  assert.equal(isHandled(record, CHECK, pr(30).headRefOid), false, "a skipped lane PR is not recorded as handled");
});

test("a work-resolve-issue PR over any tidy cutoff was not tidied in its run and is dispatched", async () => {
  const pulls = [
    lanePr(40, { paths: ["plugins/x/a.md"], changedFiles: 3 }),
    lanePr(41, { additions: 7 }),
    lanePr(42, { paths: [".github/x.md"] }),
    lanePr(43, { paths: ["AGENTS.md"] }),
    lanePr(44, { paths: ["plugins/x/a.md", "plugins/y/b.md"] }),
    lanePr(45, { paths: ["docs/a/x.md", "docs/b/y.md"] }),
    lanePr(46, { more: true }),
    // Within: a shared file's name elsewhere, and two files of one docs dir.
    lanePr(47, { paths: ["plugins/x/AGENTS.md"] }),
    lanePr(48, { paths: ["docs/a/x.md", "docs/a/y.md"] }),
  ];
  assert.deepEqual(numbers((await run({ pages: [pulls] }, lane)).api), ["40", "41", "42", "43", "44", "45", "46"]);
});

test("a work-resolve-issue PR whose head is not the lane run's one API commit had a push its tidy never saw and is dispatched", async () => {
  const pulls = [
    lanePr(50, { commitCount: 2 }),
    lanePr(52, { commit: { signature: { isValid: false } } }),
    lanePr(53, { commit: { author: { user: { login: "someone" } } } }),
    lanePr(54, { commit: { committer: { email: "someone@example.com" } } }),
    lanePr(55),
  ];
  assert.deepEqual(numbers((await run({ pages: [pulls] }, lane)).api), ["50", "52", "53", "54"]);
});

test("without a valid lanes App id or tidy cutoffs no PR is skipped as a work-resolve-issue PR", async () => {
  for (const options of [{ appSenderId: undefined }, { appSenderId: Number.NaN }, { appSenderId: "337595936" }, { tidyCutoffs: null }]) {
    assert.deepEqual(numbers((await run({ pages: [[lanePr(34)]] }, { ...lane, ...options })).api), ["34"], JSON.stringify(options));
  }
});

test("an excluded account is matched by id, not login, and a PR whose author has no id is not dispatched", async () => {
  const pulls = [
    pr(26, { author: { __typename: "Bot", login: "renamed-dependabot", databaseId: DEPENDABOT } }),
    pr(27, { author: { __typename: "User", login: "dependabot" } }),
    pr(28, { author: null }),
    pr(29, { author: { __typename: "Bot", login: "x", databaseId: "49699333" } }),
  ];
  assert.deepEqual(numbers((await run({ pages: [pulls] })).api), []);
});

test("a head or an earlier commit with a pr-unblock / fix-docs run, from before the lane moved, is not dispatched again", async () => {
  const record = emptyRecord();
  markHandled(record, EARLIER_CHECK, pr(38).headRefOid);
  const { api } = await run({
    pages: [[pr(36, { checks: [checkRun(EARLIER_CHECK)] }), pr(37), pr(38), pr(39)]],
    histories: { 37: history([0, 0], [0, 1]) },
  }, { record });
  assert.deepEqual(numbers(api), ["39"]);
  assert.deepEqual(api.calls.history.map((call) => call.number), [37, 39], "a head recorded under the earlier name skips its read");
  assert.ok(isHandled(record, CHECK, pr(36).headRefOid), "a head handled under the earlier name is recorded under the current one");
  assert.ok(isHandled(record, CHECK, pr(37).headRefOid));
});

test("once per PR: a head with a fix-docs run, or any earlier commit with one, is not dispatched again", async () => {
  const { api, record } = await run({
    pages: [[pr(30, { checks: [checkRun(CHECK)] }), pr(31), pr(32)]],
    histories: { 31: history([0, 1, 0]) },
  });
  assert.deepEqual(numbers(api), ["32"]);
  assert.ok(isHandled(record, CHECK, pr(30).headRefOid), "the head's own run is recorded");
  assert.ok(isHandled(record, CHECK, pr(31).headRefOid), "an earlier commit's run is recorded");
  assert.ok(!isHandled(record, CHECK, pr(32).headRefOid), "a dispatch is not recorded as handled");
});

test("a run another app posted under the name does not count", async () => {
  assert.deepEqual(numbers((await run({ pages: [[pr(33, { checks: [checkRun(CHECK, 999)] })]] })).api), ["33"]);
});

test("a commit whose check suites were not listed whole counts as having a run", async () => {
  const cut = { commits: { nodes: [{ commit: { checkSuites: { nodes: [], pageInfo: { hasNextPage: true } } } }] } };
  assert.deepEqual(numbers((await run({ pages: [[pr(34)]], histories: { 34: cut } })).api), []);
});

test("a recorded head is skipped without a history read", async () => {
  const record = emptyRecord();
  markHandled(record, CHECK, pr(35).headRefOid);
  const { api } = await run({ pages: [[pr(35)]] }, { record });
  assert.deepEqual(numbers(api), []);
  assert.deepEqual(api.calls.history, []);
});

test("at most maxDispatch per run, lowest PR number first; a PR with history does not use a slot", async () => {
  const { api, lines } = await run({ pages: [[pr(44), pr(41), pr(43), pr(42)]], histories: { 41: history([1]) } });
  assert.deepEqual(numbers(api), ["42", "43"]);
  assert.ok(lines.some((line) => line.startsWith("defer fix-docs #44")));
});

test("a fix-docs run still queued or going for the PR holds the dispatch", async () => {
  const { api } = await run({
    pages: [[pr(50), pr(51)]],
    workflowRuns: [
      { id: 1, status: "in_progress", display_title: "pr-refine fix-docs #50" },
      { id: 2, status: "completed", conclusion: "cancelled", display_title: "pr-refine fix-docs #51" },
      { id: 3, status: "queued", display_title: "pr-unblock fix-docs #51" },
    ],
  });
  assert.deepEqual(numbers(api), ["51"]);
});

const ran = (id, number, conclusion) => ({ id, status: "completed", conclusion, display_title: `pr-refine fix-docs #${number}` });

test("a PR whose fix-docs run completed without a check run is not dispatched again, and its head is recorded without a history read", async () => {
  // success: the run job stopped at its trigger gate or emitted an empty head.
  for (const conclusion of ["success", "skipped"]) {
    const record = emptyRecord();
    record.docsRuns.set(pr(54).headRefOid, ["9"]);
    const { api, lines } = await run({ pages: [[pr(54)]], workflowRuns: [ran(9, 54, conclusion)] }, { record });
    assert.deepEqual(numbers(api), [], conclusion);
    assert.deepEqual(api.calls.history, [], conclusion);
    assert.ok(isHandled(record, CHECK, pr(54).headRefOid), conclusion);
    assert.equal(record.docsRuns.has(pr(54).headRefOid), false, conclusion);
    assert.ok(lines.includes("skip fix-docs #54: a pr-refine.yml run for it already ended"), lines.join("\n"));
  }
});

test("a PR whose only fix-docs run was lost without a check run is dispatched once more, and not after a second lost run", async () => {
  for (const conclusion of ["cancelled", "timed_out", "startup_failure"]) {
    const once = await run({ pages: [[pr(55)]], workflowRuns: [ran(10, 55, conclusion)] });
    assert.deepEqual(numbers(once.api), ["55"], conclusion);
    assert.equal(isHandled(once.record, CHECK, pr(55).headRefOid), false, conclusion);
    const twice = await run({ pages: [[pr(55)]], workflowRuns: [ran(11, 55, "timed_out"), ran(10, 55, conclusion)] });
    assert.deepEqual(numbers(twice.api), [], conclusion);
    assert.ok(isHandled(twice.record, CHECK, pr(55).headRefOid), conclusion);
  }
  const mixed = await run({ pages: [[pr(56)]], workflowRuns: [ran(12, 56, "success"), ran(13, 56, "cancelled")] });
  assert.deepEqual(numbers(mixed.api), [], "a lost run after one that ended is not retried");
  const going = await run({ pages: [[pr(56)]], workflowRuns: [{ id: 15, status: "in_progress", display_title: "pr-refine fix-docs #56" }, ran(13, 56, "cancelled")] });
  assert.deepEqual(numbers(going.api), [], "the retry already going holds the dispatch");
  assert.equal(isHandled(going.record, CHECK, pr(56).headRefOid), false);
});

// A fix-docs run's status and latest jobs as the REST listings name them:
// pr-refine.yml's fix-docs call's jobs are `Fix Docs / <job>`
// (pr-run-activity-read.yml's Broker Check, Broker Allowed, Run and Report).
const job = (name, conclusion, status = "completed") => ({ name, status, conclusion });
const ended = (...jobs) => ({ status: "completed", jobs });
// fix-docs-head found a person's hold: the call never started.
const HELD = ended(job("Fix Docs Head", "success"), job("Fix Docs", "skipped"));

// Outage posture element 3: the PR's next event is the probe. A red run names no
// cause (a read that failed, or a broker that refused, both end red), so at most
// limits.limit-stops-per-head (3, README's limits table) go again before it ends
// the PR, which bounds a refusal; a red run that posted its check is ended by
// that check, not by its conclusion.
test("a red fix-docs run with no check run does not end the PR: the next run dispatches it, until three red runs do", async () => {
  const reds = (...ids) => ids.map((id) => ran(id, 54, "failure"));
  for (const runs of [reds(9), reds(10, 9)]) {
    const { api, record, result } = await run({ pages: [[pr(54)]], workflowRuns: runs });
    assert.deepEqual(numbers(api), ["54"], `${runs.length} red`);
    assert.equal(isHandled(record, CHECK, pr(54).headRefOid), false, `${runs.length} red`);
    assert.equal(result.failed, 0);
    assert.equal(api.calls.history.length, 1, "a red run may have posted its check on an earlier commit");
  }
  const done = await run({ pages: [[pr(54)]], workflowRuns: reds(11, 10, 9) });
  assert.deepEqual(numbers(done.api), []);
  assert.ok(isHandled(done.record, CHECK, pr(54).headRefOid));
  const lower = await run({ pages: [[pr(54)]], workflowRuns: reds(10, 9) }, { maxRunsPerHead: 2 });
  assert.deepEqual(numbers(lower.api), [], "maxRunsPerHead sets the bound");
});

test("a red fix-docs run does not outlive a run that ended, or the check run it posted", async () => {
  const settled = await run({ pages: [[pr(54)]], workflowRuns: [ran(10, 54, "skipped"), ran(9, 54, "failure")] });
  assert.deepEqual(numbers(settled.api), []);
  assert.ok(isHandled(settled.record, CHECK, pr(54).headRefOid));
  const checked = await run({ pages: [[pr(54)]], workflowRuns: [ran(9, 54, "failure")], histories: { 54: history([1]) } });
  assert.deepEqual(numbers(checked.api), []);
  assert.ok(isHandled(checked.record, CHECK, pr(54).headRefOid));
});

// handoff-evidence.sh's hold ends the run green with no check. Job conclusions
// tell it from a decline: the leg's handoff job succeeded, yet the next leg never
// started, which pr-refine.yml starts on a handoff that read settled. The run
// job's handed-off output alone skips a scan job (head code can forge it, #8890),
// so a skipped scan with no handoff job read is no hold.
const leg = (name, scan) => [job(`${name} / Broker Allowed`, "success"), job(`${name} / Run`, "success"), job(`${name} / Scan`, scan)];
const read = (name) => job(`${name} Handoff`, "success");
const HANDED_OFF = ended(job("Fix Docs Head", "success"), ...leg("Fix Docs", "skipped"), read("Fix Docs"), job("Fix Docs Subscription", "skipped"));

test("heldHandoff: a leg that handed off, whose handoff job succeeded, with no next leg held; anything else did not", () => {
  assert.equal(heldHandoff(HANDED_OFF), true);
  assert.equal(heldHandoff(ended(...leg("Fix Docs", "skipped"), read("Fix Docs"), job("Fix Docs Subscription / Run", "skipped"))), true, "a next leg all skipped never ran");
  assert.equal(heldHandoff(ended(job("Fix Docs / Broker Allowed", "success"), job("Fix Docs / Run", "success"), read("Fix Docs"))), true, "a handoff's scan job may be unlisted");
  const second = [...leg("Fix Docs", "skipped"), read("Fix Docs"), ...leg("Fix Docs Subscription", "skipped")];
  assert.equal(heldHandoff(ended(...second, read("Fix Docs Subscription"), job("Fix Docs Fallback", "skipped"))), true, "the second leg's read held");
  assert.equal(heldHandoff(ended(...second, job("Fix Docs Subscription Handoff", "skipped"), job("Fix Docs Fallback", "skipped"))), false, "no fallback token: no read ran, so a skipped scan is a forged handoff");
  assert.equal(heldHandoff(ended(...leg("Fix Docs", "skipped"), job("Fix Docs Handoff", "failure"), job("Fix Docs Subscription", "skipped"))), false, "a handoff job that went red is the red run's count");
  assert.equal(heldHandoff(ended(...leg("Fix Docs", "success"), read("Fix Docs"), job("Fix Docs Subscription", "skipped"))), false, "a decline or a supersede scans");
  assert.equal(heldHandoff(ended(...leg("Fix Docs", "skipped"), read("Fix Docs"), ...leg("Fix Docs Subscription", "success"))), false, "the next leg ran and scanned");
  assert.equal(heldHandoff(ended(...second, read("Fix Docs Subscription"), ...leg("Fix Docs Fallback", "success"))), false, "the third leg ran");
  assert.equal(heldHandoff(ended(...second, read("Fix Docs Subscription"), ...leg("Fix Docs Fallback", "skipped"), read("Fix Docs Fallback"))), false, "the last leg has no next one to hold back");
  assert.equal(heldHandoff(ended(job("Fix Docs / Broker Allowed", "skipped"), job("Fix Docs / Run", "success"), read("Fix Docs"))), false, "no broker allow");
  assert.equal(heldHandoff(ended(job("Fix Docs / Broker Allowed", "success"), job("Fix Docs / Run", "failure"), read("Fix Docs"))), false, "a run job that failed");
  assert.equal(heldHandoff(HELD), false, "a person's hold never started the call");
  assert.equal(heldHandoff(null), false, "a run that is gone");
});

test("a green fix-docs run that held on a failed handoff read is dispatched again, until three such runs end the PR", async () => {
  const green = (...ids) => ids.map((id) => ran(id, 54, "success"));
  const runJobs = new Map([9, 10, 11].map((id) => [id, HANDED_OFF]));
  const again = await run({ pages: [[pr(54)]], workflowRuns: green(10, 9), runJobs });
  assert.deepEqual(numbers(again.api), ["54"]);
  assert.equal(isHandled(again.record, CHECK, pr(54).headRefOid), false);
  const done = await run({ pages: [[pr(54)]], workflowRuns: green(11, 10, 9), runJobs });
  assert.deepEqual(numbers(done.api), []);
  assert.ok(isHandled(done.record, CHECK, pr(54).headRefOid));
  const mixed = await run({ pages: [[pr(54)]], workflowRuns: [ran(10, 54, "failure"), ...green(9)], runJobs }, { maxRunsPerHead: 2 });
  assert.deepEqual(numbers(mixed.api), [], "a red run and a held one count together");
});

// fix-docs-head's hold on an unread PR head (outage posture element 2) ends the
// run green with fix-docs skipped, as a person's hold does; only pr-refine.yml's
// fix-docs-head-held job, which runs on the unread output alone, tells them apart.
const UNREAD = ended(job("Fix Docs Head", "success"), job("Fix Docs Head Held", "success"), job("Fix Docs", "skipped"));

test("heldHead: only a fix-docs-head-held job that succeeded shows an unread head", () => {
  assert.equal(heldHead(UNREAD), true);
  assert.equal(heldHead(HELD), false, "a person's hold");
  assert.equal(heldHead(ended(job("Fix Docs Head", "success"), job("Fix Docs Head Held", "skipped"))), false);
  assert.equal(heldHead(ended(job("Fix Docs Head", "success"), job("Fix Docs Head Held", "failure"))), false);
  assert.equal(heldHead(HANDED_OFF), false);
  assert.equal(heldHead(null), false, "a run that is gone");
});

test("a green fix-docs run held on an unread PR head is dispatched again, until three held runs end the PR; a person's hold ends it", async () => {
  const green = (...ids) => ids.map((id) => ran(id, 54, "success"));
  const runJobs = new Map([9, 10, 11].map((id) => [id, UNREAD]));
  const again = await run({ pages: [[pr(54)]], workflowRuns: green(10, 9), runJobs });
  assert.deepEqual(numbers(again.api), ["54"]);
  assert.equal(isHandled(again.record, CHECK, pr(54).headRefOid), false);
  const done = await run({ pages: [[pr(54)]], workflowRuns: green(11, 10, 9), runJobs });
  assert.deepEqual(numbers(done.api), []);
  assert.ok(isHandled(done.record, CHECK, pr(54).headRefOid));
  const mixed = await run({ pages: [[pr(54)]], workflowRuns: [ran(11, 54, "failure"), ...green(10, 9)], runJobs: new Map([[10, UNREAD], [9, HANDED_OFF]]) });
  assert.deepEqual(numbers(mixed.api), [], "a red run, a handoff hold and an unread head count together");
  const person = await run({ pages: [[pr(54)]], workflowRuns: green(9), runJobs: new Map([[9, HELD]]) });
  assert.deepEqual(numbers(person.api), []);
  assert.ok(isHandled(person.record, CHECK, pr(54).headRefOid));
});

test("a green fix-docs run that scanned ends the PR, and a run that did not go green costs no job read", async () => {
  const runJobs = new Map([[9, ended(...leg("Fix Docs", "success"))], [10, HANDED_OFF]]);
  const scanned = await run({ pages: [[pr(54)]], workflowRuns: [ran(10, 54, "success"), ran(9, 54, "success")], runJobs });
  assert.deepEqual(numbers(scanned.api), [], "a held run after one that scanned changes nothing");
  assert.ok(isHandled(scanned.record, CHECK, pr(54).headRefOid));
  const skipped = await run({ pages: [[pr(54)]], workflowRuns: [ran(9, 54, "skipped")], runJobs });
  assert.deepEqual(skipped.api.calls.jobs, []);
});

test("a run whose jobs cannot be read holds the PR with a warning: not dispatched, not recorded, nothing fails", async () => {
  for (const [error, why] of [[Object.assign(new Error("502"), { rateLimited: false }), "could not be read"], [Object.assign(new Error("limited"), { rateLimited: true }), "are rate limited"]]) {
    const { api, lines, record, result } = await run({ pages: [[pr(54), pr(55)]], workflowRuns: [ran(9, 54, "success")], runJobs: new Map([[9, error]]) });
    assert.deepEqual(numbers(api), ["55"], why);
    assert.equal(isHandled(record, CHECK, pr(54).headRefOid), false, why);
    assert.equal(result.failed, 0, why);
    assert.ok(lines.includes(`::warning::#54: a pr-refine.yml run's jobs ${why} (${error.message}); no fix-docs dispatched, a later run retries`), lines.join("\n"));
  }
});

test("a same-repository PR whose fix-docs dispatch stopped at the trigger gate does not take a dispatch slot on later runs", async () => {
  // Lowest number first: #57 would take the first of the two slots each run.
  const { api, lines } = await run({ pages: [[pr(57), pr(58), pr(59)]], workflowRuns: [ran(14, 57, "success")] });
  assert.deepEqual(numbers(api), ["58", "59"]);
  assert.ok(!lines.some((line) => line.startsWith("defer fix-docs")), lines.join("\n"));
});

test("a fix-docs run an outage lost before its check gets a fresh dispatch from this dispatcher, never a re-run", async () => {
  const { api } = await run({
    pages: [[pr(52)]],
    workflowRuns: [{ id: 4, status: "completed", conclusion: "cancelled", display_title: "pr-refine fix-docs #52" }],
  });
  assert.deepEqual(api.calls.dispatch, [
    { workflow: "pr-refine.yml", ref: "refs/heads/main", inputs: { "pr-number": "52", activity: "fix-docs", "dispatcher-run-id": "4242" } },
  ]);
});

test("a fix-docs run that pushed its lanes App commit is left alone: its check is on the commit before the push", async () => {
  // pr-refine.yml's push job runs after the report job posted the check on
  // fix-docs-head, so a pushed run's check sits one commit below the new head.
  const { api, record } = await run({ pages: [[pr(53)]], histories: { 53: history([0, 1]) } });
  assert.deepEqual(numbers(api), []);
  assert.ok(isHandled(record, CHECK, pr(53).headRefOid));
});

test("a failed history read skips that PR with a warning, fails nothing, and the others still go", async () => {
  const { api, lines, result } = await run({ pages: [[pr(60), pr(61)]], failHistory: new Set([60]) });
  assert.deepEqual(numbers(api), ["61"]);
  assert.equal(result.failed, 0);
  assert.ok(lines.includes("::warning::#60: could not read fix-docs history or holds: history read failed; skipped, a later run retries"), lines.join("\n"));
});

test("every listing page is read", async () => {
  assert.deepEqual(numbers((await run({ pages: [[pr(70)], [pr(71)]] })).api), ["70", "71"]);
});

// The broker allowed it and its run job emitted an empty head: no check posted.
const EMPTY_HEAD = ended(
  job("Fix Docs Head", "success"),
  job("Fix Docs / Broker Check", "success"),
  job("Fix Docs / Broker Allowed", "success"),
  job("Fix Docs / Run", "success"),
  job("Fix Docs / Report", "success"),
  job("Fix Docs Handoff", "success"),
);
// The broker refused it: broker-allowed and the run job skipped.
const REFUSED = ended(
  job("Fix Docs Head", "success"),
  job("Fix Docs / Broker Check", "failure"),
  job("Fix Docs / Broker Allowed", "skipped"),
  job("Fix Docs / Run", "skipped"),
  job("Fix Docs / Report", "success"),
  job("Fix Docs Handoff", "success"),
);
const GOING = { status: "in_progress", jobs: [job("Fix Docs Head", "success"), job("Fix Docs / Broker Check", null, "in_progress")] };

test("docsRunState: only a succeeded broker-allowed job counts; a run that ended without one, or is gone, is done; any other is going", () => {
  assert.equal(docsRunState(EMPTY_HEAD), "allowed");
  assert.equal(docsRunState(REFUSED), "done");
  assert.equal(docsRunState(HELD), "done");
  assert.equal(docsRunState(GOING), "going");
  assert.equal(docsRunState({ status: "queued", jobs: [] }), "going", "a run with no job listed yet");
  assert.equal(docsRunState(ended()), "done", "a run that ended with no job, as a startup failure does");
  assert.equal(docsRunState(null), "done", "a run that is gone");
  assert.equal(docsRunState(ended(job("Fix Docs / Run", "success"))), "done", "a run job's success is not the broker's allow");
});

// A run started before the rename lists its jobs by their ids.
test("heldHandoff, heldHead and docsRunState read a run whose jobs are named by their ids", () => {
  const byIds = (...jobs) => ended(job("fix-docs-head", "success"), ...jobs);
  const handedOff = byIds(
    job("fix-docs / broker-allowed", "success"),
    job("fix-docs / run", "success"),
    job("fix-docs / scan", "skipped"),
    job("fix-docs-handoff", "success"),
    job("fix-docs-subscription", "skipped"),
  );
  assert.equal(heldHandoff(handedOff), true);
  assert.equal(
    heldHandoff(byIds(job("fix-docs / broker-allowed", "success"), job("fix-docs / run", "success"), job("fix-docs-handoff", "success"), job("fix-docs-subscription / run", "success"))),
    false,
    "the next leg ran",
  );
  assert.equal(heldHead(byIds(job("fix-docs-head-held", "success"))), true);
  assert.equal(heldHead(byIds(job("fix-docs-head-held", "skipped"))), false);
  assert.equal(docsRunState(byIds(job("fix-docs / broker-allowed", "success"))), "allowed");
  assert.equal(docsRunState(byIds(job("fix-docs / broker-allowed", "skipped"))), "done");
});

// Run ids the dispatch record keeps for a head.
const kept = (record, number, ids) => record.docsRuns.set(pr(number).headRefOid, ids);

test("a head whose fix-docs runs reach the per-head cap with no check run is not dispatched, recorded, and warned about once; a head below it is dispatched", async () => {
  const record = emptyRecord();
  kept(record, 80, ["101", "102", "103"]);
  kept(record, 81, ["111", "112"]);
  const runJobs = new Map(["101", "102", "103"].map((id) => [id, EMPTY_HEAD]));
  const { api, lines, result } = await run({ pages: [[pr(80), pr(81)]], runJobs }, { record });
  assert.deepEqual(numbers(api), ["81"]);
  assert.deepEqual(result, { dispatched: [{ number: 81, workflowRunId: "8081" }], failed: 0 });
  assert.deepEqual(lines.filter((line) => line.startsWith("::warning::")), [
    `::warning::#80: head ${pr(80).headRefOid}'s fix-docs ran 3 time(s) with no ${CHECK} check run, the most one head gets; no fix-docs until a new push`,
  ]);
  assert.ok(isHandled(record, CHECK, pr(80).headRefOid), "the capped head goes into the dispatch record");
  assert.equal(record.docsRuns.has(pr(80).headRefOid), false);
  assert.deepEqual(api.calls.jobs, ["101", "102", "103"], "a head below the cap reads no runs");
  assert.deepEqual(record.docsRuns.get(pr(81).headRefOid), ["111", "112", "8081"], "the dispatch joins its head's runs");

  const next = await run({ pages: [[pr(80)]], runJobs }, { record: parseRecord(serializeRecord(record)) });
  assert.deepEqual(numbers(next.api), []);
  assert.deepEqual([next.api.calls.history, next.api.calls.jobs], [[], []], "the recorded head is skipped before any read");
  assert.deepEqual(next.lines.filter((line) => line.startsWith("::warning::")), []);
});

test("broker-refused, held and gone runs do not count toward the cap and leave the list; a run still going stays", async () => {
  const record = emptyRecord();
  kept(record, 82, ["201", "202", "203", "204", "205"]);
  const runJobs = new Map([["201", EMPTY_HEAD], ["202", REFUSED], ["203", HELD], ["204", GOING], ["205", null]]);
  const { api } = await run({ pages: [[pr(82)]], runJobs }, { record });
  assert.deepEqual(numbers(api), ["82"]);
  assert.deepEqual(record.docsRuns.get(pr(82).headRefOid), ["201", "204", "8082"]);
  assert.equal(isHandled(record, CHECK, pr(82).headRefOid), false);
});

test("maxRunsPerHead sets the cap", async () => {
  const record = emptyRecord();
  kept(record, 83, ["301"]);
  const { api } = await run({ pages: [[pr(83)]], runJobs: new Map([["301", EMPTY_HEAD]]) }, { record, maxRunsPerHead: 1 });
  assert.deepEqual(numbers(api), []);
  assert.ok(isHandled(record, CHECK, pr(83).headRefOid));
});

test("a head whose runs cannot be read is not dispatched: a rate limit, a server error or any other answer warns and fails nothing", async () => {
  const errors = [
    Object.assign(new Error("GET jobs returned 403"), { rateLimited: true }),
    Object.assign(new Error("GET jobs returned 502"), { status: 502 }),
    Object.assign(new Error("GET jobs returned 401"), { status: 401 }),
  ];
  for (const error of errors) {
    const record = emptyRecord();
    kept(record, 84, ["401", "402", "403"]);
    const runJobs = new Map([["401", EMPTY_HEAD], ["402", error], ["403", EMPTY_HEAD]]);
    const { api, lines, result } = await run({ pages: [[pr(84)]], runJobs }, { record });
    assert.deepEqual(numbers(api), [], error.message);
    assert.equal(result.failed, 0, error.message);
    assert.ok(lines.some((line) => line.startsWith("::warning::#84:") && line.includes(error.message)), error.message);
    assert.equal(isHandled(record, CHECK, pr(84).headRefOid), false, error.message);
    assert.deepEqual(record.docsRuns.get(pr(84).headRefOid), ["401", "402", "403"], error.message);
  }
});

test("the GitHub API reads a run's status and its latest jobs as one complete page; a gone run reads null", async () => {
  const urls = [];
  const responses = [
    { ok: true, status: 200, body: { id: 38779200001, status: "completed" } },
    { ok: true, status: 200, body: { total_count: 1, jobs: [job("Fix Docs / Broker Allowed", "success")] } },
    { ok: false, status: 404, body: {} },
    { ok: true, status: 200, body: { id: 38779200003, status: "completed" } },
    { ok: true, status: 200, body: { total_count: 101, jobs: [] } },
  ];
  const api = createGitHubApi({
    token: "t",
    repository: "octo/repo",
    apiUrl: "https://api.example",
    graphqlUrl: "https://api.example/graphql",
    fetch: async (url) => {
      urls.push(url);
      const { ok, status, body } = responses.shift();
      return { ok, status, json: async () => body };
    },
  });
  assert.deepEqual(await api.readRunJobs("38779200001"), { status: "completed", jobs: [job("Fix Docs / Broker Allowed", "success")] });
  assert.deepEqual(urls, [
    "https://api.example/repos/octo/repo/actions/runs/38779200001",
    "https://api.example/repos/octo/repo/actions/runs/38779200001/jobs?filter=latest&per_page=100",
  ]);
  assert.equal(await api.readRunJobs("38779200002"), null);
  await assert.rejects(api.readRunJobs("38779200003"), /not one complete page/);
  await assert.rejects(api.readRunJobs("../1"), /not a run id/);
});

test("the GitHub API sends the one-PR and history queries with their variables", async () => {
  const bodies = [];
  const fetch = async (url, init) => {
    const body = JSON.parse(init.body);
    bodies.push(body);
    const data = body.query === PULL_QUERY
      ? { rateLimit: { cost: 1, remaining: 1 }, repository: { pullRequest: { number: 9, state: "OPEN" } } }
      : { rateLimit: { cost: 1, remaining: 1 }, repository: { pullRequest: history([0]) } };
    return { ok: true, status: 200, json: async () => ({ data }) };
  };
  const api = createGitHubApi({ token: "t", repository: "octo/repo", apiUrl: "https://api.example", graphqlUrl: "https://api.example/graphql", fetch });
  await api.readDocsFixCandidate(9);
  const read = await api.readDocsFixHistory({ number: 9, appId: ACTIONS, checkName: CHECK, earlierCheckName: EARLIER_CHECK });
  assert.equal(bodies[0].query, PULL_QUERY);
  assert.deepEqual(bodies[0].variables, { owner: "octo", name: "repo", number: 9 });
  assert.deepEqual(bodies[1].variables, { owner: "octo", name: "repo", number: 9, appId: ACTIONS, checkName: CHECK, earlierCheckName: EARLIER_CHECK });
  assert.match(PULL_QUERY, /\.\.\. on Bot \{ databaseId \}/);
  assert.match(PULL_QUERY, /\.\.\. on User \{ databaseId \}/);
  assert.equal(bodies[1].query, HISTORY_QUERY);
  assert.match(HISTORY_QUERY, new RegExp(`commits\\(last: ${HISTORY_COMMITS}\\)`));
  assert.deepEqual(read.pullRequest, history([0]));
});
