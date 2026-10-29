import assert from "node:assert/strict";
import { readFileSync, rmSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";

import { commitMessage, loadRules, rowFor } from "../apply-patch/apply-patch.mjs";
import { addedLines, countFixRounds, logExcerpt, main, select, WEAKEN_BRIEF } from "./fix-ci-context.mjs";
import { tempDir } from "../../../lib/test-tmp.mjs";

// The lanes App bot's id (.github/standards/trusted-actors/trusted-actors.json).
const APP = 337595936;
// claude[bot] and github-actions[bot], the reviewer bot and the marker author.
const REVIEWER = 209825114;
const ACTIONS = 41898282;
const HUMAN = 153232337;
const TRUSTED_ACTORS = join(import.meta.dirname, "../../standards/trusted-actors/trusted-actors.json");
const STRANGER = 4242;
const HEAD = "a".repeat(40);
const TRAILER = "Lane-Activity: pr-unblock/fix-ci";

const fixCommit = (author = APP, trailer = TRAILER) => ({
  sha: "c".repeat(40),
  author: { id: author },
  commit: { message: `Fix failing CI checks\n\n${trailer}\n` },
});

const run = (id, name, conclusion, extra = {}) => ({
  id,
  name,
  status: "completed",
  conclusion,
  app: { slug: "github-actions" },
  started_at: `2026-10-18T00:00:${String(id % 60).padStart(2, "0")}Z`,
  ...extra,
});

function fakeApi(overrides = {}) {
  const jobs = overrides.jobs ?? {
    11: { id: 11, run_id: 900, head_sha: HEAD },
    12: { id: 12, run_id: 900, head_sha: HEAD },
  };
  return {
    getPull: async () => overrides.pull ?? { state: "open", head: { sha: HEAD } },
    listPullCommits: async () => overrides.commits ?? [],
    listCommitCheckRuns: async () => {
      if (overrides.checkRunsError) {
        throw overrides.checkRunsError;
      }
      return Object.assign([...(overrides.checkRuns ?? [run(11, "lint-shell", "failure"), run(13, "ci-status", "failure")])], { complete: overrides.complete ?? true });
    },
    // The head's pr-unblock / apply-patch checks: a lane stop runs the retry a rung up.
    listCheckRuns: async (sha, name) => (name === "pr-unblock / fix-ci" ? (overrides.fixCiRuns ?? []) : (overrides.stopRuns ?? [])),
    // The head's statuses: report-escalation.sh status names a fail-routed stop's reason.
    listCommitStatuses: async () => overrides.statuses ?? [],
    listAnnotations: async (id) =>
      overrides.annotations?.[id] ?? [
        { path: "scripts/x.sh", start_line: 12, annotation_level: "failure", message: "SC2034: foo appears unused" },
      ],
    getJob: async (id) => {
      if (!jobs[id]) {
        const error = new Error(`GET jobs/${id} returned 404`);
        error.status = 404;
        throw error;
      }
      return jobs[id];
    },
    getRun: async () => overrides.run ?? { path: ".github/workflows/pr-require-checks.yml" },
    getJobLog: async () => overrides.log ?? "2026-10-18T00:00:01.0000000Z lint-shell: SC2034\n",
    listIssueComments: async () => overrides.issueComments ?? [],
    listReviews: async () => overrides.reviews ?? [],
    listReviewComments: async () => overrides.reviewComments ?? [],
    listThreads: async () => overrides.threads ?? [],
    getCommit: async (sha) => overrides.commitFiles?.[sha] ?? { files: [] },
    // resolve-pr.mjs linkedIssues' specText: what trusted people wrote on the linked issues.
    readSpec: async () => overrides.spec ?? [],
  };
}

const selectWith = (api, maxRounds = 3) => select({ api, pr: 42, appId: APP, reviewerId: REVIEWER, maxRounds });

// One unresolved thread on HEAD, opened by `author` in review 500, which the
// reviewed-head marker confirms, with `replies` after it.
const FINDING =
  "Adding `get-field-options` to `ADAPTER_VERBS` makes the generator require it; the `BASE_SPEC` fixture in generate-adapter.test.sh lacks it, so the suite fails.";
function reviewed({ author = REVIEWER, resolved = false, replies = [], body = FINDING } = {}) {
  const rows = [
    { id: 1, user: { id: author }, body, path: "plugins/p/generate-adapter.sh", line: 56, pull_request_review_id: 500, created_at: "2026-10-22T16:18:46Z" },
    ...replies.map((reply, i) => ({ id: 2 + i, pull_request_review_id: 501, created_at: "2026-10-22T17:00:00Z", ...reply })),
  ];
  return {
    issueComments: [{ user: { id: ACTIONS }, body: `<!-- claude-lane-reviewed-head lane=claude-review sha=${HEAD} -->` }],
    reviews: [{ id: 500, user: { id: author }, commit_id: HEAD }],
    reviewComments: rows,
    threads: [{ id: "T1", isResolved: resolved, comments: { totalCount: rows.length, nodes: rows.map((row) => ({ databaseId: row.id })) } }],
  };
}

test("a failing workflow job becomes one context entry with its workflow, annotations and log", async () => {
  const result = await selectWith(fakeApi());
  assert.equal(result.decision, "proceed");
  assert.deepEqual(result.file, {
    pr: 42,
    head_sha: HEAD,
    review_findings: [],
    spec: [],
    feedback_lines: [],
    checks: [
      {
        name: "lint-shell",
        workflow: ".github/workflows/pr-require-checks.yml",
        annotations: [{ path: "scripts/x.sh", line: 12, level: "failure", message: "SC2034: foo appears unused" }],
        log_excerpt: "lint-shell: SC2034",
      },
    ],
  });
});

test("an unresolved reviewer-bot finding goes into the context beside the failing checks", async () => {
  const result = await selectWith(fakeApi(reviewed()));
  assert.equal(result.decision, "proceed");
  assert.deepEqual(result.file.review_findings, [{ path: "plugins/p/generate-adapter.sh", line: 56, body: FINDING }]);
});

test("a resolved thread, a person's thread and one a person replied to stay out of the context", async () => {
  for (const shape of [{ resolved: true }, { author: HUMAN }, { replies: [{ user: { id: HUMAN }, body: "I disagree" }] }]) {
    const result = await selectWith(fakeApi(reviewed(shape)));
    assert.deepEqual(result.file.review_findings, [], JSON.stringify(shape));
  }
});

test("a review-findings read that fails leaves no findings and still proceeds with the checks", async () => {
  const api = fakeApi(reviewed());
  api.listThreads = async () => {
    throw new Error("POST graphql returned 502");
  };
  const lines = [];
  const result = await select({ api, pr: 42, appId: APP, reviewerId: REVIEWER, maxRounds: 3, log: (line) => lines.push(line) });
  assert.equal(result.decision, "proceed");
  assert.deepEqual(result.file.review_findings, []);
  assert.deepEqual(result.file.checks.map((check) => check.name), ["lint-shell"]);
  assert.deepEqual(lines, ["::warning::the review findings could not be read (POST graphql returned 502); the context holds none"]);
});

test("a finding's body and the number of findings are capped", async () => {
  const one = reviewed({ body: "b".repeat(5000) });
  const threads = Array.from({ length: 15 }, (_, i) => ({ ...one.threads[0], id: `T${i}` }));
  const result = await selectWith(fakeApi({ ...one, threads }));
  assert.equal(result.file.review_findings.length, 10);
  assert.equal(result.file.review_findings[0].body.length, 2000);
});

// #10919: fix-ci cut the SKILL.md line that met a criterion to get under the
// line cap, so the context carries the linked issue's spec text and the lines
// the last address-feedback round added.
const CRITERION = "- [ ] `SKILL.md` names the new check where it lists what `run-validity.py` judges";
const SPEC = [{ number: 10504, spec_kind: "closes", body: `## Done when\n\n${CRITERION}\n`, comments: ["**Decision recorded.** Keep the check in SKILL.md."] }];
const FEEDBACK = "Lane-Activity: pr-unblock/address-feedback";
const feedbackCommit = (sha, author = APP) => ({ sha, author: { id: author }, commit: { message: `Address review feedback on feature\n\n${FEEDBACK}\nLane-Thread: PRRT_a\n` } });

test("main writes the linked issue's spec text into the context file", async () => {
  const dir = tempDir("fix-ci-context-");
  try {
    const env = { GITHUB_TOKEN: "t", GITHUB_REPOSITORY: "o/r", GITHUB_OUTPUT: join(dir, "out"), PR_NUMBER: "42", APP_SENDER_ID: String(APP), CONTEXT_FILE: join(dir, "context.json"), FIX_CI_ROUNDS: "3", TRUSTED_ACTORS };
    const asked = [];
    const api = fakeApi({ spec: SPEC });
    const readSpec = api.readSpec;
    api.readSpec = async (pr) => {
      asked.push(pr);
      return readSpec(pr);
    };
    await main(env, { api, log: () => {} });
    assert.deepEqual(asked, [42]);
    assert.deepEqual(JSON.parse(readFileSync(env.CONTEXT_FILE, "utf8")).spec, SPEC);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("the spec text is capped: three issues, each one's newest ten comments, each text cut", async () => {
  const issue = (number) => ({ number, spec_kind: "closes", body: "b".repeat(20000), comments: Array.from({ length: 15 }, (_, i) => `c${i}`) });
  const result = await selectWith(fakeApi({ spec: [1, 2, 3, 4].map(issue) }));
  assert.deepEqual(result.file.spec.map((row) => row.number), [1, 2, 3]);
  assert.equal(result.file.spec[0].body.length, 10000);
  assert.deepEqual(result.file.spec[0].comments, Array.from({ length: 10 }, (_, i) => `c${i + 5}`));
  const none = await selectWith(fakeApi({ spec: [{ number: 7, spec_kind: "refs", body: null, comments: [] }] }));
  assert.equal(none.file.spec[0].body, null);
});

test("a spec read that fails leaves the spec field out and still proceeds with the checks", async () => {
  const api = fakeApi();
  api.readSpec = async () => {
    throw new Error("#42: the closing issues could not be read");
  };
  const lines = [];
  const result = await select({ api, pr: 42, appId: APP, reviewerId: REVIEWER, maxRounds: 3, log: (line) => lines.push(line) });
  assert.equal(result.decision, "proceed");
  assert.equal(Object.hasOwn(result.file, "spec"), false);
  assert.deepEqual(lines, ["::warning::the linked issues' spec text could not be read (#42: the closing issues could not be read); the context holds none"]);
});

test("the lines the lanes App's last address-feedback commit added go into the context", async () => {
  const patch = `@@ -10,2 +10,4 @@\n Context line.\n+${CRITERION.slice(6)}\n+\n-Old line.\n+Second added line.`;
  const commits = [feedbackCommit("1".repeat(40)), fixCommit(), feedbackCommit("2".repeat(40)), feedbackCommit("3".repeat(40), STRANGER), fixCommit()];
  const commitFiles = {
    ["1".repeat(40)]: { files: [{ filename: "old.md", patch: "@@ -1 +1 @@\n+earlier round" }] },
    ["2".repeat(40)]: { files: [{ filename: "plugins/p/skills/s/SKILL.md", patch }, { filename: "image.png" }] },
  };
  const result = await selectWith(fakeApi({ commits, commitFiles }));
  assert.deepEqual(result.file.feedback_lines, [{ path: "plugins/p/skills/s/SKILL.md", lines: [CRITERION.slice(6), "Second added line."] }]);
  const none = await selectWith(fakeApi({ commits: [fixCommit()] }));
  assert.deepEqual(none.file.feedback_lines, []);
});

test("a feedback commit read that fails leaves no lines and still proceeds", async () => {
  const api = fakeApi({ commits: [feedbackCommit("2".repeat(40))] });
  api.getCommit = async () => {
    throw new Error("GET commits returned 502");
  };
  const lines = [];
  const result = await select({ api, pr: 42, appId: APP, reviewerId: REVIEWER, maxRounds: 3, log: (line) => lines.push(line) });
  assert.equal(result.decision, "proceed");
  assert.deepEqual(result.file.feedback_lines, []);
  assert.deepEqual(lines, ["::warning::the last address-feedback commit could not be read (GET commits returned 502); the context holds none of its lines"]);
});

test("added lines are capped at 200 in all, each cut at 500 characters", () => {
  const patch = (n) => Array.from({ length: n }, (_, i) => `+${String(i).padEnd(900, "x")}`).join("\n");
  const added = addedLines([
    { filename: "a.md", patch: patch(150) },
    { filename: "b.md", patch: patch(150) },
    { filename: "c.md", patch: patch(5) },
  ]);
  assert.deepEqual(added.map((file) => [file.path, file.lines.length]), [["a.md", 150], ["b.md", 50]]);
  assert.equal(added[0].lines[0].length, 500);
});

test("ci-status, passing checks and a check whose later run passed are left out", async () => {
  const api = fakeApi({
    checkRuns: [
      run(11, "lint-shell", "failure"),
      run(14, "lint-shell", "success"),
      run(12, "test-node", "success"),
      run(13, "ci-status", "failure"),
    ],
  });
  const result = await selectWith(api);
  assert.equal(result.decision, "skip");
  assert.equal(result.skipReason, "not-applicable");
});

test("a failure a later skipped or neutral run of the same check hides is still failing", async () => {
  const api = fakeApi({
    checkRuns: [
      run(11, "lint-shell", "failure"),
      run(12, "test-node", "failure"),
      run(15, "lint-shell", "skipped"),
      run(16, "test-node", "neutral"),
      run(17, "ci-status", "failure"),
    ],
  });
  const result = await selectWith(api);
  assert.equal(result.decision, "proceed");
  assert.deepEqual(
    result.file.checks.map((check) => check.name),
    ["lint-shell", "test-node"],
  );
});

test("a later success still outranks an earlier failure when a skip follows it", async () => {
  const api = fakeApi({
    checkRuns: [run(11, "lint-shell", "failure"), run(14, "lint-shell", "success"), run(16, "lint-shell", "skipped")],
  });
  const result = await selectWith(api);
  assert.equal(result.decision, "skip");
});

test("a check with only skipped runs is not failing", async () => {
  const api = fakeApi({ checkRuns: [run(11, "lint-shell", "skipped"), run(15, "lint-shell", "skipped")] });
  const result = await selectWith(api);
  assert.equal(result.decision, "skip");
});

test("a github-actions check run that is no workflow job (a lane's own check) is left out", async () => {
  const api = fakeApi({ checkRuns: [run(11, "lint-shell", "failure"), run(77, "pr-unblock / address-feedback", "failure")] });
  const result = await selectWith(api);
  assert.deepEqual(
    result.file.checks.map((check) => check.name),
    ["lint-shell"],
  );
});

test("another app's failing check is kept with no workflow and no log", async () => {
  const api = fakeApi({ checkRuns: [run(50, "codecov/patch", "failure", { app: { slug: "codecov" } })] });
  const result = await selectWith(api);
  assert.equal(result.file.checks[0].workflow, null);
  assert.equal(result.file.checks[0].log_excerpt, "");
});

test("a run path outside .github/workflows is reported as no workflow", async () => {
  const result = await selectWith(fakeApi({ run: { path: "dynamic/codeql" } }));
  assert.equal(result.file.checks[0].workflow, null);
});

test("timed_out and startup_failure count as failing", async () => {
  const api = fakeApi({ checkRuns: [run(11, "lint-shell", "timed_out"), run(12, "test-node", "startup_failure")] });
  const result = await selectWith(api);
  assert.deepEqual(
    result.file.checks.map((check) => check.name),
    ["lint-shell", "test-node"],
  );
});

// #9828's head c1184e03: test-bash (3) ended cancelled past its 9-minute
// limit, beside the failed ci-status aggregate. Its recorded annotations
// carry the time limit, so it is fixable and the model reads the cause; a
// fail-fast sibling cancelled with only the cancel note is not.
const TIME_LIMITED = JSON.parse(readFileSync(new URL("../maintenance-reconcile-lost-runs/fixtures/annotations-120950643531.json", import.meta.url), "utf8"));
const CANCEL_ONLY = TIME_LIMITED.filter((a) => a.message === "The operation was canceled.");

test("a check cancelled past its time limit counts as failing, with the time-limit note in its context", async () => {
  const reads = [];
  const api = fakeApi({
    checkRuns: [run(11, "test-bash (3)", "cancelled"), run(12, "test-bash (1)", "cancelled"), run(13, "ci-status", "failure")],
    annotations: { 11: TIME_LIMITED, 12: CANCEL_ONLY },
  });
  const listAnnotations = api.listAnnotations;
  api.listAnnotations = async (id) => {
    reads.push(id);
    return listAnnotations(id);
  };
  const result = await selectWith(api);
  assert.equal(result.decision, "proceed");
  assert.deepEqual(
    result.file.checks.map((check) => check.name),
    ["test-bash (3)"],
  );
  assert.match(result.file.checks[0].annotations[0].message, /^The job has exceeded the maximum execution time of 9m0s$/);
  // Each cancelled check's annotations are read once.
  assert.deepEqual(reads, [11, 12]);
});

test("a head whose only cancelled checks carry no time-limit note stays not-applicable", async () => {
  const api = fakeApi({ checkRuns: [run(12, "test-bash (1)", "cancelled"), run(13, "ci-status", "failure")], annotations: { 12: CANCEL_ONLY } });
  const result = await selectWith(api);
  assert.equal(result.decision, "skip");
  assert.equal(result.skipReason, "not-applicable");
});

test("the round cap escalates before any context is written", async () => {
  const commits = [fixCommit(), fixCommit(), fixCommit()];
  const result = await selectWith(fakeApi({ commits }));
  assert.equal(result.decision, "escalate");
  assert.equal(result.escalationReason, "ci-fix-round-cap");
  assert.equal(result.rounds, 3);
  assert.equal(result.file, undefined);
});

test("one round under the cap proceeds", async () => {
  const result = await selectWith(fakeApi({ commits: [fixCommit(), fixCommit()] }));
  assert.equal(result.decision, "proceed");
  assert.equal(result.rounds, 2);
});

// apply-patch pushes a fix with no escalation and leaves the new head to its
// own CI; this is the bound on that: a red head that is the lane's own fix
// commit counts its round, and the cap's run hands the PR to a person.
test("a red head the lane's fix commit made counts that round, and escalates once the rounds are spent", async () => {
  const own = { sha: HEAD, author: { id: APP }, commit: { message: `Fix failing CI checks on work/x\n\n${TRAILER}\n` } };
  const api = () => fakeApi({ commits: [{ sha: "b".repeat(40), author: { id: APP }, commit: { message: "Address review feedback" } }, own] });
  const spent = await selectWith(api(), 1);
  assert.equal(spent.decision, "escalate");
  assert.equal(spent.escalationReason, "ci-fix-round-cap");
  assert.equal(spent.rounds, 1);
  const left = await selectWith(api(), 3);
  assert.equal(left.decision, "proceed");
  assert.equal(left.rounds, 1);
});

test("only the lanes App's commits carrying the fix-ci trailer count as rounds", () => {
  assert.equal(
    countFixRounds(
      [fixCommit(), fixCommit(STRANGER), fixCommit(APP, "Lane-Activity: pr-unblock/resolve-conflicts"), { sha: "d", author: null, commit: { message: TRAILER } }],
      APP,
    ),
    1,
  );
});

// The round cap is fix-ci's only stop, so the trailer it counts must be the one apply-patch writes.
test("a commit apply-patch writes for fix-ci counts as a round", () => {
  const row = rowFor(loadRules(join(import.meta.dirname, "../../..")), { prepare: "ci-context" });
  const message = commitMessage(row, { ref: "feature", base: "main", lane: "pr-unblock", activity: "fix-ci", issue: "1" });
  assert.equal(countFixRounds([{ sha: "e".repeat(40), author: { id: APP }, commit: { message } }], APP), 1);
});

// Review finding on #10252: a failing pr-unblock/fix-ci status must come off
// a head whose CI went green with no new commit (fixed by hand, or a flaky
// lane re-run green), including after the round cap; only a whole, settled
// check listing with nothing failing says so.
test("a head with no failing check resolves the fix-ci stop, at the round cap too", async () => {
  const green = [run(11, "lint-shell", "failure"), run(14, "lint-shell", "success"), run(13, "ci-status", "failure")];
  for (const commits of [[], [fixCommit(), fixCommit(), fixCommit()]]) {
    const result = await selectWith(fakeApi({ checkRuns: green, commits }));
    assert.deepEqual([result.decision, result.skipReason, result.resolved, result.headSha], ["skip", "not-applicable", true, HEAD]);
  }
});

test("a failing, cancelled or unsettled check, a cut-short listing, a hold or a closed PR resolves nothing", async () => {
  const cases = {
    failing: fakeApi(),
    "failing at the round cap": fakeApi({ commits: [fixCommit(), fixCommit(), fixCommit()] }),
    "cancelled with no time-limit note": fakeApi({ checkRuns: [run(12, "test-bash (1)", "cancelled")], annotations: { 12: CANCEL_ONLY } }),
    "a re-run still in progress": fakeApi({ checkRuns: [run(11, "lint-shell", null, { status: "in_progress" })] }),
    "a cut-short listing": fakeApi({ checkRuns: [run(14, "lint-shell", "success")], complete: false }),
    closed: fakeApi({ pull: { state: "closed", head: { sha: HEAD } }, checkRuns: [] }),
    held: gatedApi({ login: "kyle-sexton", id: HUMAN, type: "User" }, "feedback-disputed"),
  };
  for (const [name, api] of Object.entries(cases)) {
    const result = await selectWith(api);
    assert.notEqual(result.resolved, true, name);
  }
});

test("a check listing that fails to read throws, so main writes no outputs and resolves nothing", async () => {
  const dir = tempDir("fix-ci-context-");
  try {
    const env = { GITHUB_TOKEN: "t", GITHUB_REPOSITORY: "o/r", PR_NUMBER: "42", APP_SENDER_ID: String(APP), CONTEXT_FILE: join(dir, "context.json"), FIX_CI_ROUNDS: "3", TRUSTED_ACTORS, GITHUB_OUTPUT: join(dir, "out") };
    await assert.rejects(main(env, { api: fakeApi({ checkRunsError: new Error("GET check-runs returned 502") }), log: () => {} }), /502/);
    assert.throws(() => readFileSync(env.GITHUB_OUTPUT, "utf8"));
    await main({ ...env, GITHUB_OUTPUT: join(dir, "green") }, { api: fakeApi({ checkRuns: [run(14, "lint-shell", "success")] }), log: () => {} });
    assert.match(readFileSync(join(dir, "green"), "utf8"), /^stop-resolved=true$/m);
    await main({ ...env, GITHUB_OUTPUT: join(dir, "red") }, { api: fakeApi(), log: () => {} });
    assert.match(readFileSync(join(dir, "red"), "utf8"), /^stop-resolved=false$/m);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("a closed pull request is skipped", async () => {
  const result = await selectWith(fakeApi({ pull: { state: "closed", head: { sha: HEAD } } }));
  assert.equal(result.decision, "skip");
});

// The human-gated label holds fix-ci unless another lane's escalation put it
// on (report-escalation.sh's label then comment, its Reason line).
const APP_USER = { login: "melodic-automation-lanes[bot]", id: APP, type: "Bot" };
const gatedApi = (actor, reason) => {
  const api = fakeApi({
    pull: { state: "open", head: { sha: HEAD }, labels: [{ name: "needs-human" }] },
    issueComments: [
      {
        user: APP_USER,
        created_at: "2026-10-22T10:00:05Z",
        body: `<!-- work-items:escalation lane=pr-unblock kind=escalated -->\n<!-- pr-unblock resume-key=${"b".repeat(40)} -->\nStopped.\n\n- Reason: \`${reason}\``,
      },
    ],
  });
  const comments = api.listIssueComments;
  api.listTimeline = async (pr) => [
    ...(await comments(pr)).map((comment) => ({ event: "commented", ...comment })),
    { event: "labeled", actor, label: { name: "needs-human" }, created_at: "2026-10-22T10:00:00Z" },
  ];
  return api;
};

test("needs-human from another lane's escalation proceeds and says so; fix-ci's own or a person's skips awaiting-human", async () => {
  const other = await selectWith(gatedApi(APP_USER, "feedback-disputed"));
  assert.equal(other.decision, "proceed");
  assert.equal(other.laneEscalated, true);
  const own = await selectWith(gatedApi(APP_USER, "ci-fix-escalated"));
  assert.deepEqual([own.decision, own.skipReason, own.headSha], ["skip", "awaiting-human", HEAD]);
  const person = await selectWith(gatedApi({ login: "kyle-sexton", id: HUMAN, type: "User" }, "feedback-disputed"));
  assert.deepEqual([person.decision, person.skipReason], ["skip", "awaiting-human"]);
  const plain = await selectWith(fakeApi());
  assert.equal(plain.laneEscalated, false);
});

test("a person's inline review-thread reply since another lane's escalation skips awaiting-human", async () => {
  // GitHub's timeline has no event for a reply inside an existing review thread.
  const api = gatedApi(APP_USER, "feedback-disputed");
  api.listReviewComments = async () => [
    { id: 2, in_reply_to_id: 1, user: { login: "kyle-sexton", id: HUMAN, type: "User" }, body: "Wait.", created_at: "2026-10-22T11:00:00Z", updated_at: "2026-10-22T11:00:00Z" },
  ];
  const result = await selectWith(api);
  assert.deepEqual([result.decision, result.skipReason], ["skip", "awaiting-human"]);
});

test("main writes the hold's skip reason and lane-escalated", async () => {
  const dir = tempDir("fix-ci-context-");
  try {
    const env = { GITHUB_TOKEN: "t", GITHUB_REPOSITORY: "o/r", PR_NUMBER: "42", APP_SENDER_ID: String(APP), CONTEXT_FILE: join(dir, "context.json"), FIX_CI_ROUNDS: "3", TRUSTED_ACTORS };
    await main({ ...env, GITHUB_OUTPUT: join(dir, "held") }, { api: gatedApi(APP_USER, "ci-fix-escalated"), log: () => {} });
    const held = readFileSync(join(dir, "held"), "utf8");
    assert.match(held, /^proceed=false$/m);
    assert.match(held, /^skip-reason=awaiting-human$/m);
    assert.match(held, /^lane-escalated=false$/m);
    await main({ ...env, GITHUB_OUTPUT: join(dir, "other") }, { api: gatedApi(APP_USER, "feedback-disputed"), log: () => {} });
    const other = readFileSync(join(dir, "other"), "utf8");
    assert.match(other, /^proceed=true$/m);
    assert.match(other, /^skip-reason=$/m);
    assert.match(other, /^lane-escalated=true$/m);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("a log excerpt keeps the last lines, drops timestamps and color codes, and is capped", () => {
  assert.equal(logExcerpt("2026-10-18T00:00:01.1234567Z \u001b[31mred\u001b[0m\nplain\n"), "red\nplain");
  const long = Array.from({ length: 500 }, (_, i) => `line ${i} ${"x".repeat(40)}`).join("\n");
  const excerpt = logExcerpt(long);
  assert.ok(excerpt.length <= 3000);
  assert.ok(excerpt.endsWith(`line 499 ${"x".repeat(40)}`));
});

test("an annotation message and the number of annotations are capped", async () => {
  const many = Array.from({ length: 40 }, (_, i) => ({ path: "a", start_line: i, annotation_level: "failure", message: "m".repeat(900) }));
  const result = await selectWith(fakeApi({ annotations: { 11: many } }));
  assert.equal(result.file.checks[0].annotations.length, 20);
  assert.equal(result.file.checks[0].annotations[0].message.length, 500);
});

test("a log that cannot be read leaves an empty excerpt rather than failing", async () => {
  const api = fakeApi();
  api.getJobLog = async () => {
    throw new Error("GET logs returned 410");
  };
  const result = await selectWith(api);
  assert.equal(result.file.checks[0].log_excerpt, "");
});

test("main writes the context file and the step outputs", async () => {
  const dir = tempDir("fix-ci-context-");
  try {
    const env = {
      GITHUB_TOKEN: "t",
      GITHUB_REPOSITORY: "o/r",
      GITHUB_OUTPUT: join(dir, "out"),
      PR_NUMBER: "42",
      APP_SENDER_ID: String(APP),
      CONTEXT_FILE: join(dir, "context.json"),
      FIX_CI_ROUNDS: "3",
      TRUSTED_ACTORS,
    };
    await main(env, { api: fakeApi(), log: () => {} });
    const outputs = readFileSync(env.GITHUB_OUTPUT, "utf8");
    assert.match(outputs, /^proceed=true$/m);
    assert.match(outputs, new RegExp(`^head-sha=${HEAD}$`, "m"));
    assert.match(outputs, /^escalation-reason=$/m);
    assert.match(outputs, /^context-sha256=[0-9a-f]{64}$/m);
    assert.equal(JSON.parse(readFileSync(env.CONTEXT_FILE, "utf8")).checks[0].name, "lint-shell");
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("main escalates the round cap with no context file", async () => {
  const dir = tempDir("fix-ci-context-");
  try {
    const env = {
      GITHUB_TOKEN: "t",
      GITHUB_REPOSITORY: "o/r",
      GITHUB_OUTPUT: join(dir, "out"),
      PR_NUMBER: "42",
      APP_SENDER_ID: String(APP),
      CONTEXT_FILE: join(dir, "context.json"),
      FIX_CI_ROUNDS: "1",
      TRUSTED_ACTORS,
    };
    await main(env, { api: fakeApi({ commits: [fixCommit()] }), log: () => {} });
    const outputs = readFileSync(env.GITHUB_OUTPUT, "utf8");
    assert.match(outputs, /^proceed=false$/m);
    assert.match(outputs, /^escalation-reason=ci-fix-round-cap$/m);
    assert.match(outputs, /^context-sha256=$/m);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("main refuses a malformed round cap", async () => {
  const env = { GITHUB_TOKEN: "t", GITHUB_REPOSITORY: "o/r", GITHUB_OUTPUT: "/dev/null", PR_NUMBER: "42", APP_SENDER_ID: String(APP), CONTEXT_FILE: "/dev/null", TRUSTED_ACTORS };
  await assert.rejects(main({ ...env, FIX_CI_ROUNDS: "0" }, { api: fakeApi() }), /FIX_CI_ROUNDS/);
});

// A retry after the push job stopped on this head runs one model rung up, so
// apply-patch takes no second in-run rung-up.
test("a head whose push job stopped proceeds at model rung 1; any other at its own", async () => {
  const stop = { status: "completed", conclusion: "neutral", output: { title: "Skipped: lane-stopped" }, app: { id: 15368 } };
  assert.equal((await selectWith(fakeApi({ stopRuns: [stop] }))).modelRung, "1");
  assert.equal((await selectWith(fakeApi())).modelRung, "");
  assert.equal((await selectWith(fakeApi({ stopRuns: [{ ...stop, app: { id: 2 } }] }))).modelRung, "");
});

// The first weaken-required stop on a head takes one fresh fixer round:
// apply-patch gets weakenRetry only while the head has no lane stop, and the
// round after a weaken retry stop carries the runner's brief and the pull
// request's stated change. A lane stop for another reason, or a status by
// another creator or on another context, carries no brief.
const LANE_STOP = { status: "completed", conclusion: "neutral", output: { title: "Skipped: lane-stopped" }, app: { id: 15368 } };
const weakenStatus = (extra = {}) => ({
  context: "pr-unblock/fix-ci",
  state: "failure",
  description: "Lane stopped: ci-fix-weaken-retry; checked again on a new head",
  creator: { login: "github-actions[bot]" },
  ...extra,
});

test("a head with no lane stop gives a weaken-required stop its fresh round, with no brief yet", async () => {
  let read = false;
  const api = {
    ...fakeApi(),
    listCommitStatuses: async () => {
      read = true;
      return [weakenStatus()];
    },
  };
  const result = await selectWith(api);
  assert.equal(result.weakenRetry, true);
  assert.equal(result.modelRung, "");
  assert.equal(result.file.retry, undefined);
  assert.equal(read, false, "no statuses read without a lane stop");
});

test("the round after a weaken retry stop carries the brief, no PR text, and has no retry left", async () => {
  const pull = { state: "open", head: { sha: HEAD }, title: "feat: print the new banner", body: "x".repeat(5000) };
  const result = await selectWith(fakeApi({ pull, stopRuns: [LANE_STOP], statuses: [weakenStatus({ state: "success", description: "The lane ran again on this head and did not stop" }), weakenStatus()] }));
  assert.equal(result.weakenRetry, false);
  assert.equal(result.modelRung, "1");
  assert.deepEqual(result.file.retry, { after: "ci-fix-weaken-retry", brief: WEAKEN_BRIEF });
  assert.match(result.file.retry.brief, /keeps every test's assertions and expected values unchanged/);
  assert.doesNotMatch(result.file.retry.brief, /pr_title|pr_body/);
  assert.equal(result.file.pr_title, undefined);
  assert.equal(result.file.pr_body, undefined);
});

test("an earlier finished fix-ci attempt on the head leaves no weaken retry, another app's check does not count", async () => {
  const earlier = { name: "pr-unblock / fix-ci", status: "completed", conclusion: "failure", app: { id: 15368 } };
  assert.equal((await selectWith(fakeApi({ fixCiRuns: [earlier] }))).weakenRetry, false);
  assert.equal((await selectWith(fakeApi({ fixCiRuns: [{ ...earlier, app: { id: 2 } }] }))).weakenRetry, true);
  assert.equal((await selectWith(fakeApi({ fixCiRuns: [{ ...earlier, status: "in_progress" }] }))).weakenRetry, true);
});

for (const [why, statuses] of [
  ["another fail-routed stop", [weakenStatus({ description: "Lane stopped: ci-fix-escalated; checked again on a new head" })]],
  ["another creator", [weakenStatus({ creator: { login: "someone" } })]],
  ["another context", [weakenStatus({ context: "pr-unblock/conflict" })]],
  ["no status", []],
]) {
  test(`a lane stop with ${why} carries no brief and leaves no weaken retry`, async () => {
    const result = await selectWith(fakeApi({ stopRuns: [LANE_STOP], statuses }));
    assert.equal(result.weakenRetry, false);
    assert.equal(result.file.retry, undefined);
    assert.equal(result.file.pr_title, undefined);
  });
}

test("main writes weaken-retry true on a head with no lane stop, false after one", async () => {
  const dir = tempDir("fix-ci-context-");
  try {
    const env = {
      GITHUB_TOKEN: "t",
      GITHUB_REPOSITORY: "o/r",
      GITHUB_OUTPUT: join(dir, "out"),
      PR_NUMBER: "42",
      APP_SENDER_ID: String(APP),
      CONTEXT_FILE: join(dir, "context.json"),
      FIX_CI_ROUNDS: "3",
      TRUSTED_ACTORS,
    };
    await main(env, { api: fakeApi(), log: () => {} });
    assert.match(readFileSync(env.GITHUB_OUTPUT, "utf8"), /^weaken-retry=true$/m);
    await main({ ...env, GITHUB_OUTPUT: join(dir, "out2") }, { api: fakeApi({ stopRuns: [LANE_STOP], statuses: [weakenStatus()] }), log: () => {} });
    assert.match(readFileSync(join(dir, "out2"), "utf8"), /^weaken-retry=false$/m);
    assert.equal(JSON.parse(readFileSync(env.CONTEXT_FILE, "utf8")).retry.brief, WEAKEN_BRIEF);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
