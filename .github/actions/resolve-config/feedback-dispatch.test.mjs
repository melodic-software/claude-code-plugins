// pr-feedback-dispatch.yml's slot read through the real resolver: the
// dispatcher script resolves only the address-feedback slot of a pr-unblock
// lane whose resolve-conflicts slot has a mergeable predicate (runs
// 38838718857 and 38838482787 failed reading that lane with no activity), and
// dispatches nothing when the slot is disabled. Lives here because it needs
// resolve-config's dependencies.
import assert from "node:assert/strict";
import { cpSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

import { main } from "../../scripts/pr-unblock/feedback-dispatch.mjs";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "../../..");
const REPOSITORY = "melodic-software/claude-code-plugins";
const HEAD = "1111111111111111111111111111111111111111";
const APP_ID = 337595936;
const CLAUDE = { databaseId: 209825114 };
const ACTIONS_BOT = { id: 41898282 };

const config = (addressFeedbackSlot) => `version: 2
activities:
  resolve-conflicts:
    skill: source-control:resolve-conflicts
    args: ci
    prepare: merge-base
    effect: mutate-branch
    gating: advisory
    reads-untrusted: true
    inputs: [pr, base-sha, head-sha]
    applies-when:
      mergeable: [conflicting]
      labels-absent: [do-not-merge, needs-human]
      draft: [false]
  address-feedback:
    skill: source-control:pull-request
    args: comments --ci
    prepare: review-threads
    effect: mutate-branch
    gating: advisory
    reads-untrusted: true
    inputs: [pr, head-sha]
    applies-when:
      labels-absent: [do-not-merge, needs-human]
      draft: [false]
  publish-feedback:
    script: .github/scripts/pr-unblock/publish-feedback.mjs
    effect: publish-artifact
    gating: advisory
    reads-untrusted: true
    inputs: [pr, head-sha]
lanes:
  pr-unblock:
    stage: unblock
    slots:
      - activity: resolve-conflicts
${addressFeedbackSlot}
      - activity: publish-feedback
        needs: [address-feedback]
`;

function baseWith(text) {
  const base = mkdtempSync(join(tmpdir(), "feedback-dispatch-base-"));
  for (const file of [
    "docs/conventions/pr-pipeline/pr-pipeline.schema.json",
    ".github/standards/github-actions-conventions/vocabulary.json",
  ]) {
    mkdirSync(dirname(join(base, file)), { recursive: true });
    cpSync(join(ROOT, file), join(base, file));
  }
  writeFileSync(join(base, "docs/conventions/pr-pipeline.yaml"), text);
  return base;
}

const pull = {
  number: 42,
  state: "open",
  draft: false,
  user: { id: APP_ID },
  labels: [],
  head: { sha: HEAD, repo: { full_name: REPOSITORY } },
  base: { ref: "main" },
  mergeable: null,
};

function fakes() {
  const dispatched = [];
  const reads = [];
  const api = {
    getRun: async (id) => ({
      id: Number(id),
      path: ".github/workflows/pr-review-hosted.yml",
      event: "pull_request",
      status: "completed",
      head_sha: HEAD,
      repository: { full_name: REPOSITORY },
      head_repository: { full_name: REPOSITORY },
    }),
    pullsForCommit: async () => [pull],
    listIssueComments: async () =>
      ["claude-review", "claude-security-review"].map((lane) => ({
        user: ACTIONS_BOT,
        body: `<!-- claude-lane-reviewed-head lane=${lane} sha=${HEAD} -->`,
      })),
    listReviewThreads: async () => [
      { isResolved: false, comments: { nodes: [{ author: CLAUDE }], pageInfo: { hasNextPage: false } } },
    ],
    listCheckRuns: async () => [],
    listWorkflowRuns: async () => [],
    dispatchWorkflow: async (request) => {
      dispatched.push(request);
      return { workflowRunId: 38779200001 };
    },
  };
  // resolve-config's PR reads.
  const github = async (method, path) => {
    reads.push(`${method} ${path}`);
    return pull;
  };
  return { api, github, dispatched, reads };
}

async function run(slot, text = config(slot)) {
  const base = baseWith(text);
  const { api, github, dispatched, reads } = fakes();
  const lines = [];
  try {
    await main(
      {
        GITHUB_TOKEN: "t",
        GITHUB_REPOSITORY: REPOSITORY,
        GITHUB_RUN_ID: "38779143370",
        GITHUB_OUTPUT: join(base, "output"),
        RUNNER_TEMP: base,
        BASE_PATH: base,
        UPSTREAM_RUN_ID: "38779135732",
        APP_SENDER_ID: String(APP_ID),
      },
      { api, github, log: (line) => lines.push(line) },
    );
  } finally {
    rmSync(base, { recursive: true, force: true });
  }
  return { dispatched, reads, lines };
}

test("a lane whose resolve-conflicts slot has a mergeable predicate dispatches once address-feedback applies at the PR", async () => {
  const { dispatched, reads } = await run("      - activity: address-feedback");
  assert.equal(dispatched.length, 1);
  assert.equal(dispatched[0].inputs.activity, "address-feedback");
  // address-feedback's labels-absent and draft were decided from a fresh PR
  // read; resolve-conflicts' mergeable was not.
  assert.deepEqual(reads, [`GET /repos/${REPOSITORY}/pulls/42`]);
});

test("a lane with no address-feedback slot skips without failing the run", async () => {
  const { dispatched, lines } = await run(null, config("").replace("        needs: [address-feedback]\n", ""));
  assert.deepEqual(dispatched, []);
  assert.match(lines.at(-1), /no enabled address-feedback and publish-feedback slots/);
});

test("a config the resolver refuses fails the run even when the lane has no address-feedback slot", async () => {
  // The lane names an activity the config never defines, and has no
  // address-feedback slot: the refusal is not an absent slot.
  const text = config("      - activity: ghost").replace("        needs: [address-feedback]\n", "");
  await assert.rejects(run(null, text), (error) => error.name === "Rejection" && error.code === "undefined-activity");
});

// The round is enabled in this repository (#7032 Phase 4), so a lanes App PR
// with an open reviewer-bot thread on a reviewed head is dispatched.
test("this repository's own config dispatches address-feedback", async () => {
  const { dispatched, lines } = await run(null, readFileSync(join(ROOT, "docs/conventions/pr-pipeline.yaml"), "utf8"));
  assert.equal(dispatched.length, 1);
  assert.equal(dispatched[0].inputs.activity, "address-feedback");
  assert.match(lines.at(-1), /^dispatched #42 /);
});

test("a disabled address-feedback slot dispatches nothing", async () => {
  const { dispatched, lines } = await run("      - activity: address-feedback\n        enabled: false");
  assert.deepEqual(dispatched, []);
  assert.match(lines.at(-1), /no enabled address-feedback and publish-feedback slots/);
});
