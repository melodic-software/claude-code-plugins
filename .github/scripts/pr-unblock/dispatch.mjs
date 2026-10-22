// Starts the pr-unblock lane for each open pull request GitHub reports as
// conflicting, because no pull_request event fires on a conflicting PR.
// Run by .github/workflows/pr-unblock-dispatch.yml on a push to main, after
// the kill switch and, where needed, the trusted-trigger gate; this script
// does no sender check of its own.
//
// It lists open PRs into main, keeps the non-draft, same-repository ones
// whose mergeable state is CONFLICTING (re-querying UNKNOWN a bounded number
// of times), skips a PR whose resolve-conflicts run is still queued or going,
// or whose current head already carries a pr-unblock check run (one the usage
// limit stopped stops counting once its limit resets, see limit-stop.mjs),
// and dispatches pr-unblock.yml on main for at most maxDispatch of them,
// lowest PR number first. Labels and authors are left to the lane's own
// config and gate. Logs carry PR numbers, SHAs and run ids only. The run ids
// it dispatched become the step output run-ids, which the workflow records.
// The same run then starts review-dependency for review-tier Dependabot PRs
// (dependency-dispatch.mjs), fix-ci for lanes App PRs whose ci-status
// failed (fix-ci-dispatch.mjs) and fix-docs once per ready PR that changes
// Markdown (fix-docs-dispatch.mjs), and their run ids join the same record.
// resolve-conflicts and review-dependency read the one open-PR listing. A head whose check runs handle it for
// good is kept in DISPATCH_RECORD (dispatch-record.mjs), which the workflow
// carries to the next run through the Actions cache; the next run skips that
// head's check-run read, and its UNKNOWN re-queries.

import { appendFileSync } from "node:fs";
import { pathToFileURL } from "node:url";

import { testedRun } from "../maintenance-reconcile-lost-runs/infra-failure.mjs";
import { POLICY_PATH } from "./dependency-classify.mjs";
import { dispatchDependencyReviews } from "./dependency-dispatch.mjs";
import { emptyRecord, isHandled, markHandled, pruneRecord, readRecord, writeRecord } from "./dispatch-record.mjs";
import { runTitle } from "./feedback-dispatch.mjs";
import { dispatchCiFixes, LIST_QUERY as CI_FIX_QUERY } from "./fix-ci-dispatch.mjs";
import { dispatchDocsFixes, HISTORY_QUERY as DOCS_FIX_HISTORY_QUERY, LIST_QUERY as DOCS_FIX_QUERY } from "./fix-docs-dispatch.mjs";
import { anyHandles, permanentlyHandles } from "./limit-stop.mjs";
import { budgetedFetch } from "./request-budget.mjs";
import { readConfig, readPolicy } from "./review-dependency.mjs";

export const DEFAULTS = Object.freeze({
  base: "main",
  workflow: "pr-unblock.yml",
  activity: "resolve-conflicts",
  checkName: "pr-unblock / resolve-conflicts",
  // The GitHub Actions app: only a check run it created counts, so another
  // app cannot suppress a dispatch by posting a run under the same name.
  appId: 15368,
  // Judgment until the lane's measured per-run cost sets it.
  maxDispatch: 3,
  // GitHub gives no timing for computing mergeability; this bounds the wait
  // at about a minute (judgment).
  unknownRetries: 5,
  unknownDelayMs: 10_000,
});

// The run id form the record's readers accept.
const RUN_ID = /^[1-9][0-9]{0,14}$/;

function isCandidate(node, base) {
  return (
    node.isDraft === false &&
    node.isCrossRepository === false &&
    node.baseRefName === base &&
    node.mergeable === "CONFLICTING"
  );
}

function isPending(node, base) {
  return (
    node.isDraft === false &&
    node.isCrossRepository === false &&
    node.baseRefName === base &&
    node.mergeable === "UNKNOWN"
  );
}

export async function listAll(api, base) {
  const nodes = [];
  let after;
  for (;;) {
    const page = await api.listOpenPulls({ base, after });
    nodes.push(...page.nodes);
    if (!page.pageInfo.hasNextPage) {
      return nodes;
    }
    after = page.pageInfo.endCursor;
  }
}

export async function dispatchConflicting({
  api,
  runId,
  sleep,
  log,
  base = DEFAULTS.base,
  workflow = DEFAULTS.workflow,
  activity = DEFAULTS.activity,
  checkName = DEFAULTS.checkName,
  appId = DEFAULTS.appId,
  maxDispatch = DEFAULTS.maxDispatch,
  unknownRetries = DEFAULTS.unknownRetries,
  unknownDelayMs = DEFAULTS.unknownDelayMs,
  now = Date.now(),
  limits,
  listed,
  record = emptyRecord(),
}) {
  const nodes = listed ?? (await listAll(api, base));
  // A recorded head is skipped whatever its mergeable state, so it is neither
  // read nor re-queried.
  const recorded = (node) => {
    if (!isHandled(record, checkName, node.headRefOid)) {
      return false;
    }
    log(`skip #${node.number}: head ${node.headRefOid} already has a ${checkName} check run (recorded)`);
    return true;
  };
  const candidates = nodes.filter((node) => isCandidate(node, base) && !recorded(node));
  let pending = nodes.filter((node) => isPending(node, base) && !recorded(node)).map((node) => node.number);

  for (let attempt = 1; pending.length > 0 && attempt <= unknownRetries; attempt += 1) {
    await sleep(unknownDelayMs);
    const reread = await api.getPulls(pending);
    candidates.push(...reread.filter((node) => isCandidate(node, base) && !recorded(node)));
    pending = reread.filter((node) => isPending(node, base) && !recorded(node)).map((node) => node.number);
  }
  for (const number of pending) {
    log(
      `skip #${number}: mergeable still UNKNOWN after ${unknownRetries} re-queries; a later run retries`,
    );
  }

  candidates.sort((a, b) => a.number - b.number);
  const dispatched = [];
  let failed = 0;
  // A dispatched run posts its check run only when it ends, so two main
  // pushes seconds apart would each dispatch one. A run of this activity for
  // the PR that is not done yet holds the dispatch.
  let active = [];
  if (candidates.length > 0) {
    try {
      active = (await api.listWorkflowRuns(workflow)).filter((run) => run.status !== "completed");
    } catch (error) {
      log(`::error::could not list ${workflow} runs: ${error.message}`);
      return { dispatched, failed: failed + 1 };
    }
  }
  // Every dispatch call counts against the cap: one that failed or returned no
  // usable id may still have started a run.
  let sent = 0;
  for (const node of candidates) {
    if (sent >= maxDispatch) {
      log(`defer #${node.number}: ${maxDispatch} dispatches this run; left for a later run`);
      continue;
    }
    const inFlight = active.find((run) => run.display_title === runTitle(activity, node.number));
    if (inFlight) {
      log(`skip #${node.number}: ${workflow} run ${inFlight.id} for ${activity} is not done yet`);
      continue;
    }
    let handled;
    try {
      const existing = await api.listCheckRuns({ sha: node.headRefOid, checkName, appId });
      handled = anyHandles(existing, { now, limits });
      if (permanentlyHandles(existing)) {
        markHandled(record, checkName, node.headRefOid);
      }
    } catch (error) {
      failed += 1;
      log(
        `::error::#${node.number}: could not read check runs for ${node.headRefOid}: ${error.message}`,
      );
      continue;
    }
    if (handled) {
      log(`skip #${node.number}: head ${node.headRefOid} already has a ${checkName} check run`);
      continue;
    }
    sent += 1;
    try {
      const { workflowRunId } = await api.dispatchWorkflow({
        workflow,
        ref: `refs/heads/${base}`,
        inputs: { "pr-number": String(node.number), "dispatcher-run-id": String(runId) },
      });
      // The dispatched run's gate and the broker refuse a run this run did not
      // record, so a dispatch with no usable id counts as failed.
      const id = String(workflowRunId);
      if (!RUN_ID.test(id)) {
        failed += 1;
        log(`::error::#${node.number}: dispatch returned no valid workflow_run_id`);
        continue;
      }
      dispatched.push({ number: node.number, workflowRunId: id });
      log(`dispatched #${node.number} head ${node.headRefOid} workflow_run_id=${id}`);
    } catch (error) {
      failed += 1;
      log(`::error::#${node.number}: dispatch failed: ${error.message}`);
    }
  }
  return { dispatched, failed };
}

// The Dependabot fields feed dependency-dispatch.mjs's classification.
const PULL_FIELDS =
  "number isDraft isCrossRepository mergeable baseRefName headRefOid headRefName state title body author { login ... on Bot { databaseId } } labels(first: 100) { nodes { name } } changedFiles commits { totalCount }";

const LIST_QUERY = `query($owner: String!, $name: String!, $base: String!, $after: String) {
  repository(owner: $owner, name: $name) {
    pullRequests(states: OPEN, baseRefName: $base, first: 100, after: $after) {
      nodes { ${PULL_FIELDS} }
      pageInfo { hasNextPage endCursor }
    }
  }
}`;

export function createGitHubApi({
  token,
  repository,
  apiUrl,
  graphqlUrl,
  fetch = globalThis.fetch,
}) {
  const [owner, name] = repository.split("/");
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

  async function paginate(path) {
    const rows = [];
    let url = `${apiUrl}/repos/${owner}/${name}/${path}?per_page=100`;
    while (url) {
      const response = await fetch(url, { headers });
      if (!response.ok) {
        throw new Error(`GET ${url} returned ${response.status}`);
      }
      rows.push(...(await response.json()));
      url = /<([^>]+)>;\s*rel="next"/.exec(response.headers.get("link") ?? "")?.[1] ?? "";
    }
    return rows;
  }

  async function graphql(query, variables) {
    const result = await request(graphqlUrl, "POST", { query, variables });
    if (result.errors?.length) {
      throw new Error(`GraphQL: ${result.errors.map((error) => error.message).join("; ")}`);
    }
    return result.data;
  }

  return {
    async listOpenPulls({ base, after }) {
      const data = await graphql(LIST_QUERY, { owner, name, base, after: after ?? null });
      return data.repository.pullRequests;
    },
    // fix-ci-dispatch.mjs's listing: one query per page, with its cost.
    async listCiFixCandidates({ base, after }) {
      const data = await graphql(CI_FIX_QUERY, { owner, name, base, after: after ?? null });
      return { rateLimit: data.rateLimit, pullRequests: data.repository.pullRequests };
    },
    // fix-docs-dispatch.mjs's listing and its per-PR check-run history.
    async listDocsFixCandidates({ base, after }) {
      const data = await graphql(DOCS_FIX_QUERY, { owner, name, base, after: after ?? null });
      return { rateLimit: data.rateLimit, pullRequests: data.repository.pullRequests };
    },
    async readDocsFixHistory({ number, appId, checkName }) {
      const data = await graphql(DOCS_FIX_HISTORY_QUERY, { owner, name, number, appId, checkName });
      return { rateLimit: data.rateLimit, pullRequest: data.repository.pullRequest };
    },
    async getPulls(numbers) {
      const fields = numbers
        .map((number) => {
          if (!Number.isSafeInteger(number) || number < 1) {
            throw new Error(`not a PR number: ${number}`);
          }
          return `pr${number}: pullRequest(number: ${number}) { ${PULL_FIELDS} }`;
        })
        .join("\n");
      const data = await graphql(
        `query($owner: String!, $name: String!) { repository(owner: $owner, name: $name) { ${fields} } }`,
        { owner, name },
      );
      return Object.values(data.repository).filter((node) => node?.state === "OPEN");
    },
    // The REST reads the Dependabot classifier takes: the files listing with
    // patches, the commits, and one commit's files.
    listPullFiles: (number) => paginate(`pulls/${Number(number)}/files`),
    listPullCommits: (number) => paginate(`pulls/${Number(number)}/commits`),
    async getCommit(sha) {
      return request(`${apiUrl}/repos/${owner}/${name}/commits/${encodeURIComponent(sha)}`);
    },
    async listCheckRuns({ sha, checkName, appId }) {
      const query = new URLSearchParams({
        check_name: checkName,
        app_id: String(appId),
        filter: "all",
        per_page: "100",
      });
      const result = await request(
        `${apiUrl}/repos/${owner}/${name}/commits/${sha}/check-runs?${query}`,
      );
      return result.check_runs;
    },
    // fix-ci-dispatch.mjs's infra check: the attempt and latest jobs of the
    // newest pr-require-checks pull_request run on the head that tested it
    // (infra-failure.mjs testedRun); attempt 0 and no jobs when there is none.
    async readRequiredRun(sha) {
      if (!/^[0-9a-f]{40}$/.test(sha)) {
        throw new Error("not a commit SHA");
      }
      const listing = await request(`${apiUrl}/repos/${owner}/${name}/actions/runs?head_sha=${sha}&event=pull_request&per_page=100`);
      const runs = (listing.workflow_runs ?? [])
        .filter((run) => run.path === ".github/workflows/pr-require-checks.yml")
        .sort((a, b) => Date.parse(b.created_at) - Date.parse(a.created_at) || b.id - a.id);
      const tested = await testedRun(runs, async (run) => {
        const jobs = await request(`${apiUrl}/repos/${owner}/${name}/actions/runs/${run.id}/jobs?filter=latest&per_page=100`);
        if (!Array.isArray(jobs.jobs) || jobs.total_count > jobs.jobs.length) {
          throw new Error(`run ${run.id}'s job listing is not one complete page`);
        }
        return jobs.jobs;
      });
      return { attempt: tested?.run?.run_attempt ?? 0, jobs: tested?.jobs ?? [] };
    },
    // The newest workflow_dispatch runs: a run still queued or going is
    // among them, since a dispatcher waits at most minutes behind it.
    async listWorkflowRuns(workflow) {
      const result = await request(
        `${apiUrl}/repos/${owner}/${name}/actions/workflows/${workflow}/runs?event=workflow_dispatch&per_page=100`,
      );
      return result.workflow_runs ?? [];
    },
    async dispatchWorkflow({ workflow, ref, inputs }) {
      const result = await request(
        `${apiUrl}/repos/${owner}/${name}/actions/workflows/${workflow}/dispatches`,
        "POST",
        {
          ref,
          inputs,
          return_run_details: true,
        },
      );
      return { workflowRunId: result.workflow_run_id };
    },
  };
}

// The base config's resolved limits, through the base checkout's
// resolve-config; the workflow installs its dependencies before this runs. A
// config the resolver refuses throws, so nothing is dispatched.
export async function loadBaseLimits(env) {
  const { limitsFromBase } = await import(
    new URL("../../actions/resolve-config/resolve-config.mjs", import.meta.url).href
  );
  return limitsFromBase({ BASE_PATH: env.BASE_PATH || ".base" });
}

// Each run id is also appended to RUN_IDS_FILE as soon as its dispatch
// returns, so a run cancelled mid-step still records what it sent.
function wrapRunIds(base, env) {
  return {
    ...base,
    async dispatchWorkflow(request) {
      const result = await base.dispatchWorkflow(request);
      if (env.RUN_IDS_FILE && RUN_ID.test(String(result.workflowRunId))) {
        appendFileSync(env.RUN_IDS_FILE, `${result.workflowRunId}\n`);
      }
      return result;
    },
  };
}

// Writes the dispatched run ids, lowest PR first, as the step output run-ids,
// which the workflow records as an artifact on this run.
export async function main(
  env,
  {
    api,
    sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
    log = (line) => console.log(line),
    loadLimits = loadBaseLimits,
    now,
  } = {},
) {
  for (const key of ["GITHUB_TOKEN", "GITHUB_REPOSITORY", "GITHUB_RUN_ID", "GITHUB_OUTPUT"]) {
    if (!env[key]) {
      throw new Error(`${key} is not set`);
    }
  }
  const budget = api ? null : budgetedFetch({ log });
  const base =
    api ??
    createGitHubApi({
      token: env.GITHUB_TOKEN,
      repository: env.GITHUB_REPOSITORY,
      apiUrl: env.GITHUB_API_URL ?? "https://api.github.com",
      graphqlUrl: env.GITHUB_GRAPHQL_URL ?? "https://api.github.com/graphql",
      fetch: budget.fetch,
    });
  try {
    return await dispatchAll(env, { client: wrapRunIds(base, env), sleep, log, loadLimits, now });
  } finally {
    if (budget) {
      log(budget.summary());
    }
  }
}

async function dispatchAll(env, { client, sleep, log, loadLimits, now }) {
  const limits = await loadLimits(env);
  const listed = await listAll(client, DEFAULTS.base);
  const { record, text } = readRecord(env.DISPATCH_RECORD);
  pruneRecord(record, new Set(listed.map((node) => node.headRefOid)));
  const conflicts = await dispatchConflicting({ api: client, runId: env.GITHUB_RUN_ID, sleep, log, limits, now, listed, record });
  const reviews = await dispatchDependencyReviews({
    api: client,
    runId: env.GITHUB_RUN_ID,
    log,
    listed,
    record,
    config: readConfig(env.DEPENDABOT_CONFIG ?? ".base/.github/dependabot.yml", log),
    policy: readPolicy(env.DEPENDABOT_POLICY ?? `.base/${POLICY_PATH}`, log),
    repository: env.GITHUB_REPOSITORY,
  });
  // A missing lanes App id stops fix-ci alone, as a failure.
  let fixes = { dispatched: [], failed: 1 };
  if (/^[1-9][0-9]*$/.test(env.APP_SENDER_ID ?? "")) {
    fixes = await dispatchCiFixes({
      api: client,
      runId: env.GITHUB_RUN_ID,
      log,
      appSenderId: Number(env.APP_SENDER_ID),
      maxDispatch: limits["fix-ci-per-run"] ?? 2,
      restarts: limits["fix-ci-restarts"] ?? 1,
    });
  } else {
    log("::error::APP_SENDER_ID is not the lanes App's user id; no fix-ci dispatched");
  }
  const docs = await dispatchDocsFixes({
    api: client,
    runId: env.GITHUB_RUN_ID,
    log,
    record,
    maxDispatch: limits["fix-docs-per-run"] ?? 2,
  });
  const dispatched = [...conflicts.dispatched, ...reviews.dispatched, ...fixes.dispatched, ...docs.dispatched];
  const failed = conflicts.failed + reviews.failed + fixes.failed + docs.failed;
  if (dispatched.length > 0) {
    const ids = dispatched.map((run) => run.workflowRunId).join(" ");
    appendFileSync(env.GITHUB_OUTPUT, `run-ids=${ids}\n`);
  }
  if (writeRecord(env.DISPATCH_RECORD, record, text)) {
    appendFileSync(env.GITHUB_OUTPUT, "record-changed=true\n");
  }
  log(`dispatched ${dispatched.length} run(s), ${failed} failure(s)`);
  return failed === 0 ? 0 : 1;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main(process.env).then(
    (code) => {
      process.exitCode = code;
    },
    (error) => {
      console.log(`::error::pr-unblock dispatch failed: ${error.message}`);
      process.exitCode = 1;
    },
  );
}
