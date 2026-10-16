// Starts pr-unblock's address-feedback activity on a lanes App PR once both
// review lanes have reviewed its current head and left an unresolved thread.
// Run by .github/workflows/pr-feedback-dispatch.yml on workflow_run, after the
// kill switch. The only event field it takes is the upstream run id; every
// other fact is read back from the API, so nothing in the event payload
// reaches a decision or a shell.
//
// It dispatches pr-unblock.yml on main, with activity address-feedback, only
// when all of these hold, and otherwise logs why not and dispatches nothing:
// - the upstream run is a completed pull_request run of a review workflow,
//   by exact path, in this repository and on a head of this repository;
// - exactly one open, non-draft PR into main has that run's head SHA as its
//   current head, and the lanes App opened it;
// - it carries no do-not-merge or needs-human label;
// - both review lanes' newest reviewed-head markers, written by
//   github-actions[bot], name that head;
// - an unresolved review thread exists whose every comment is the reviewer
//   bot's;
// - that head has no pr-unblock / address-feedback check run yet, and no
//   pr-unblock.yml address-feedback run for the PR is still queued or going;
// - the base config's pr-unblock lane is enabled, holds enabled
//   address-feedback and publish-feedback slots, and address-feedback applies
//   to that PR at that head, resolved by resolve-config for that one slot.
// The gate and the broker re-check the upstream run and the head; this script
// only decides whether to spend a run.

import { appendFileSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

export const DEFAULTS = Object.freeze({
  base: "main",
  workflow: "pr-unblock.yml",
  lane: "pr-unblock",
  activity: "address-feedback",
  replyActivity: "publish-feedback",
  checkName: "pr-unblock / address-feedback",
  reviewWorkflows: Object.freeze([
    ".github/workflows/pr-review-hosted.yml",
    ".github/workflows/pr-review-security-hosted.yml",
  ]),
  // The lanes each review workflow names in its reviewed-head marker
  // (melodic-software/ci-workflows pr-review.yml and pr-review-security.yml).
  markerLanes: Object.freeze(["claude-review", "claude-security-review"]),
  holdLabels: Object.freeze(["do-not-merge", "needs-human"]),
  // claude[bot], the reviewer (.github/standards/trusted-actors/trusted-actors.json).
  reviewerId: 209825114,
  // github-actions[bot], which writes the reviewed-head markers.
  markerAuthorId: 41898282,
  // The GitHub Actions app: only a check run it created counts.
  appId: 15368,
});

const SHA = /^[0-9a-f]{40}$/;
const RUN_ID = /^[1-9][0-9]{0,14}$/;

// The SHA the newest marker of `lane` written by the marker author names, or "".
export function markedHead(comments, lane, markerAuthorId = DEFAULTS.markerAuthorId) {
  const prefix = `<!-- claude-lane-reviewed-head lane=${lane} sha=`;
  const marker = comments
    .filter((comment) => comment.user?.id === markerAuthorId && comment.body?.startsWith(prefix))
    .at(-1);
  const sha = marker?.body.slice(prefix.length, prefix.length + 40) ?? "";
  return SHA.test(sha) ? sha : "";
}

// An unresolved thread whose every comment is the reviewer bot's.
export function hasBotThread(threads, reviewerId = DEFAULTS.reviewerId) {
  return threads.some(
    (thread) =>
      thread.isResolved === false &&
      thread.comments.nodes.length > 0 &&
      thread.comments.pageInfo?.hasNextPage !== true &&
      thread.comments.nodes.every((comment) => comment.author?.databaseId === reviewerId),
  );
}

// pr-unblock.yml's run-name, which names the activity and the PR.
export const runTitle = (activity, number) => `pr-unblock ${activity} #${number}`;

// A check run handles the head unless it is the gate's completed neutral skip
// for an untrusted trigger.
function handles(run) {
  return !(
    run.status === "completed" &&
    run.conclusion === "neutral" &&
    String(run.output?.title ?? "").startsWith("Skipped: untrusted-trigger")
  );
}

export async function dispatchFeedback({
  api,
  repository,
  runId,
  upstreamRunId,
  appSenderId,
  resolveSlot,
  log,
  settings = DEFAULTS,
}) {
  const skip = (why) => {
    log(`skip: ${why}`);
    return null;
  };
  if (!RUN_ID.test(String(upstreamRunId)) || !RUN_ID.test(String(runId))) {
    throw new Error("the upstream or own run id is not a run id");
  }
  if (!Number.isSafeInteger(appSenderId) || appSenderId < 1) {
    throw new Error("the lanes App sender id is not a positive integer");
  }
  const upstream = await api.getRun(upstreamRunId);
  if (
    String(upstream?.id) !== String(upstreamRunId) ||
    !settings.reviewWorkflows.includes(upstream.path) ||
    upstream.event !== "pull_request" ||
    upstream.status !== "completed" ||
    upstream.repository?.full_name !== repository ||
    upstream.head_repository?.full_name !== repository ||
    !SHA.test(upstream.head_sha ?? "")
  ) {
    return skip(`run ${upstreamRunId} is not a completed same-repository review run`);
  }
  const head = upstream.head_sha;
  const pulls = (await api.pullsForCommit(head)).filter(
    (pull) =>
      pull.state === "open" &&
      pull.head?.sha === head &&
      pull.head?.repo?.full_name === repository &&
      pull.base?.ref === settings.base,
  );
  if (pulls.length !== 1) {
    return skip(`head ${head} is the current head of ${pulls.length} open PRs into ${settings.base}`);
  }
  const [pull] = pulls;
  const number = pull.number;
  if (pull.draft !== false) {
    return skip(`#${number} is a draft`);
  }
  if (pull.user?.id !== appSenderId) {
    return skip(`#${number} was not opened by the lanes App`);
  }
  const held = (pull.labels ?? []).map((label) => label.name).filter((name) => settings.holdLabels.includes(name));
  if (held.length > 0) {
    return skip(`#${number} is labeled ${held.join(", ")}`);
  }
  const comments = await api.listIssueComments(number);
  const unreviewed = settings.markerLanes.filter((lane) => markedHead(comments, lane, settings.markerAuthorId) !== head);
  if (unreviewed.length > 0) {
    return skip(`#${number}: ${unreviewed.join(", ")} has not marked head ${head} reviewed`);
  }
  if (!hasBotThread(await api.listReviewThreads(number), settings.reviewerId)) {
    return skip(`#${number} has no unresolved thread left only by the reviewer bot`);
  }
  const existing = await api.listCheckRuns({ sha: head, checkName: settings.checkName, appId: settings.appId });
  if (existing.some(handles)) {
    return skip(`#${number}: head ${head} already has a ${settings.checkName} check run`);
  }
  // Both review lanes finish on one head, and their dispatchers queue in one
  // concurrency group. The first one's run posts no check until it ends, so
  // the second skips while a run of this activity for this PR, created after
  // this review started, is not done. An older run (the round whose push made
  // this head) does not hold the dispatch, or the next round would never start.
  const title = runTitle(settings.activity, number);
  const reviewStarted = Date.parse(upstream.run_started_at ?? "");
  const active = (await api.listWorkflowRuns(settings.workflow)).filter(
    (run) =>
      run.status !== "completed" &&
      run.display_title === title &&
      !(Date.parse(run.created_at ?? "") < reviewStarted),
  );
  if (active.length > 0) {
    return skip(`#${number}: ${settings.workflow} run ${active[0].id} for ${settings.activity} is not done yet`);
  }
  const resolved = await resolveSlot({ number, head });
  const enabled = (name) => resolved.lane.slots.some((slot) => slot.name === name && slot.enabled === true);
  if (resolved.lane.enabled !== true || !enabled(settings.activity) || !enabled(settings.replyActivity)) {
    return skip(`the ${settings.lane} lane has no enabled ${settings.activity} and ${settings.replyActivity} slots`);
  }
  if (resolved.selected?.applies !== true) {
    return skip(`#${number}: ${settings.activity} does not apply (${resolved.selected?.["skip-reason"] ?? "unknown"})`);
  }
  const { workflowRunId } = await api.dispatchWorkflow({
    workflow: settings.workflow,
    ref: `refs/heads/${settings.base}`,
    inputs: {
      "pr-number": String(number),
      activity: settings.activity,
      "dispatcher-run-id": String(runId),
    },
  });
  const id = String(workflowRunId);
  if (!RUN_ID.test(id)) {
    throw new Error(`#${number}: dispatch returned no valid workflow_run_id`);
  }
  log(`dispatched #${number} head ${head} upstream run ${upstreamRunId} workflow_run_id=${id}`);
  return { number, workflowRunId: id };
}

const THREADS_QUERY = `query($owner: String!, $name: String!, $number: Int!, $after: String) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) {
      reviewThreads(first: 100, after: $after) {
        nodes {
          isResolved
          comments(first: 100) {
            nodes { author { ... on Bot { databaseId } ... on User { databaseId } } }
            pageInfo { hasNextPage }
          }
        }
        pageInfo { hasNextPage endCursor }
      }
    }
  }
}`;

export function createGitHubApi({ token, repository, apiUrl, graphqlUrl, fetch = globalThis.fetch }) {
  const [owner, name] = repository.split("/");
  const repo = `${apiUrl}/repos/${owner}/${name}`;
  const headers = {
    Accept: "application/vnd.github+json",
    Authorization: `Bearer ${token}`,
    "X-GitHub-Api-Version": "2022-11-28",
  };

  async function request(url, method = "GET", body) {
    const response = await fetch(url, {
      method,
      headers: body === undefined ? headers : { ...headers, "Content-Type": "application/json" },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    if (!response.ok) {
      throw new Error(`${method} ${url} returned ${response.status}`);
    }
    return response.status === 204 ? {} : response.json();
  }

  async function graphql(query, variables) {
    const result = await request(graphqlUrl, "POST", { query, variables });
    if (result.errors?.length) {
      throw new Error(`GraphQL: ${result.errors.map((error) => error.message).join("; ")}`);
    }
    return result.data;
  }

  return {
    getRun: (id) => request(`${repo}/actions/runs/${id}`),
    pullsForCommit: (sha) => request(`${repo}/commits/${sha}/pulls`),
    async listIssueComments(number) {
      const comments = [];
      for (let page = 1; page <= 50; page += 1) {
        const batch = await request(`${repo}/issues/${number}/comments?per_page=100&page=${page}`);
        comments.push(...batch);
        if (batch.length < 100) {
          return comments;
        }
      }
      throw new Error(`#${number} has more than 5000 comments`);
    },
    async listReviewThreads(number) {
      const threads = [];
      let after = null;
      for (;;) {
        const data = await graphql(THREADS_QUERY, { owner, name, number, after });
        const page = data.repository.pullRequest.reviewThreads;
        threads.push(...page.nodes);
        if (!page.pageInfo.hasNextPage) {
          return threads;
        }
        after = page.pageInfo.endCursor;
      }
    },
    async listCheckRuns({ sha, checkName, appId }) {
      const query = new URLSearchParams({
        check_name: checkName,
        app_id: String(appId),
        filter: "all",
        per_page: "100",
      });
      return (await request(`${repo}/commits/${sha}/check-runs?${query}`)).check_runs;
    },
    // The newest workflow_dispatch runs: a run still queued or going is
    // among them, since a dispatcher waits at most minutes behind it.
    async listWorkflowRuns(workflow) {
      return (await request(`${repo}/actions/workflows/${workflow}/runs?event=workflow_dispatch&per_page=100`)).workflow_runs ?? [];
    },
    async dispatchWorkflow({ workflow, ref, inputs }) {
      const result = await request(`${repo}/actions/workflows/${workflow}/dispatches`, "POST", {
        ref,
        inputs,
        return_run_details: true,
      });
      return { workflowRunId: result.workflow_run_id };
    },
  };
}

// The pr-unblock lane as the dispatched run resolves it: resolve-config from
// the base checkout, deciding only the address-feedback slot, for this PR and
// head, on a workflow_dispatch event. Naming the activity keeps another slot's
// predicate (resolve-conflicts' mergeable) from needing facts this run lacks.
// The workflow installs resolve-config's dependencies before this runs.
export async function resolveFeedbackSlot({ number, head, env, github, settings = DEFAULTS }) {
  const { main: resolveConfig } = await import(
    new URL("../../actions/resolve-config/resolve-config.mjs", import.meta.url).href
  );
  const dir = mkdtempSync(join(env.RUNNER_TEMP || tmpdir(), "feedback-slot-"));
  try {
    const eventPath = join(dir, "event.json");
    const outputPath = join(dir, "resolved.json");
    writeFileSync(eventPath, "{}");
    const code = await resolveConfig({
      env: {
        LANE: settings.lane,
        ACTIVITY: settings.activity,
        BASE_PATH: env.BASE_PATH || ".base",
        OUTPUT_PATH: outputPath,
        EVENT_NAME: "workflow_dispatch",
        EVENT_PATH: eventPath,
        PR_NUMBER: String(number),
        HEAD_SHA: head,
        // Only reading: the dispatched write runner performs the prepare step.
        PREPARE_SUPPORTED: "true",
        GITHUB_OUTPUT: join(dir, "outputs"),
        GITHUB_TOKEN: env.GITHUB_TOKEN,
        GITHUB_API_URL: env.GITHUB_API_URL,
        REPOSITORY: env.GITHUB_REPOSITORY,
      },
      github,
    });
    if (code !== 0) {
      throw new Error(`resolve-config could not resolve the ${settings.lane} lane's ${settings.activity} slot`);
    }
    return JSON.parse(readFileSync(outputPath, "utf8"));
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

// Writes run-id, the dispatched run, as a step output; the workflow records
// it with the upstream run id as an artifact on this run.
export async function main(env, { api, github, resolveSlot, log = (line) => console.log(line) } = {}) {
  for (const key of ["GITHUB_TOKEN", "GITHUB_REPOSITORY", "GITHUB_RUN_ID", "GITHUB_OUTPUT", "UPSTREAM_RUN_ID", "APP_SENDER_ID"]) {
    if (!env[key]) {
      throw new Error(`${key} is not set`);
    }
  }
  const dispatched = await dispatchFeedback({
    api:
      api ??
      createGitHubApi({
        token: env.GITHUB_TOKEN,
        repository: env.GITHUB_REPOSITORY,
        apiUrl: env.GITHUB_API_URL ?? "https://api.github.com",
        graphqlUrl: env.GITHUB_GRAPHQL_URL ?? "https://api.github.com/graphql",
      }),
    repository: env.GITHUB_REPOSITORY,
    runId: env.GITHUB_RUN_ID,
    upstreamRunId: env.UPSTREAM_RUN_ID,
    appSenderId: Number(env.APP_SENDER_ID),
    resolveSlot: resolveSlot ?? (({ number, head }) => resolveFeedbackSlot({ number, head, env, github })),
    log,
  });
  if (dispatched !== null) {
    appendFileSync(env.GITHUB_OUTPUT, `run-id=${dispatched.workflowRunId}\n`);
  }
  return 0;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main(process.env).then(
    (code) => {
      process.exitCode = code;
    },
    (error) => {
      console.log(`::error::pr-feedback dispatch failed: ${error.message}`);
      process.exitCode = 1;
    },
  );
}
