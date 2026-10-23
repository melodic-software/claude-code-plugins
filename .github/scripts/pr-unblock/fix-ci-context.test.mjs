import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";

import { countFixRounds, logExcerpt, main, select } from "./fix-ci-context.mjs";

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
    listCommitCheckRuns: async () => overrides.checkRuns ?? [run(11, "lint-shell", "failure"), run(13, "ci-status", "failure")],
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

test("a finding's body and the number of findings are capped", async () => {
  const one = reviewed({ body: "b".repeat(5000) });
  const threads = Array.from({ length: 15 }, (_, i) => ({ ...one.threads[0], id: `T${i}` }));
  const result = await selectWith(fakeApi({ ...one, threads }));
  assert.equal(result.file.review_findings.length, 10);
  assert.equal(result.file.review_findings[0].body.length, 2000);
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

test("only the lanes App's commits carrying the fix-ci trailer count as rounds", () => {
  assert.equal(
    countFixRounds(
      [fixCommit(), fixCommit(STRANGER), fixCommit(APP, "Lane-Activity: pr-unblock/resolve-conflicts"), { sha: "d", author: null, commit: { message: TRAILER } }],
      APP,
    ),
    1,
  );
});

test("a closed pull request is skipped", async () => {
  const result = await selectWith(fakeApi({ pull: { state: "closed", head: { sha: HEAD } } }));
  assert.equal(result.decision, "skip");
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
  const dir = mkdtempSync(join(tmpdir(), "fix-ci-context-"));
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
  const dir = mkdtempSync(join(tmpdir(), "fix-ci-context-"));
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
