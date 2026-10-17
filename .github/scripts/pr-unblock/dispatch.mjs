// Starts the pr-unblock lane for each open pull request GitHub reports as
// conflicting, because no pull_request event fires on a conflicting PR.
// Run by .github/workflows/pr-unblock-dispatch.yml on a push to main, after
// the kill switch and, where needed, the trusted-trigger gate; this script
// does no sender check of its own.
//
// It lists open PRs into main, keeps the non-draft, same-repository ones
// whose mergeable state is CONFLICTING (re-querying UNKNOWN a bounded number
// of times), skips a PR whose current head already carries a pr-unblock check
// run, and dispatches pr-unblock.yml on main for at most maxDispatch of them,
// lowest PR number first. Labels and authors are left to the lane's own
// config and gate. Logs carry PR numbers, SHAs and run ids only. The run ids
// it dispatched become the step output run-ids, which the workflow records.
// The same run then starts review-dependency for review-tier Dependabot PRs
// (dependency-dispatch.mjs), and its run ids join the same record.

import { appendFileSync } from "node:fs";
import { pathToFileURL } from "node:url";

import { POLICY_PATH } from "./dependency-classify.mjs";
import { dispatchDependencyReviews } from "./dependency-dispatch.mjs";
import { readConfig, readPolicy } from "./review-dependency.mjs";

export const DEFAULTS = Object.freeze({
  base: "main",
  workflow: "pr-unblock.yml",
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

// A check run handles the head unless it is the gate's completed neutral skip
// for an untrusted trigger: a trusted dispatch may still resolve that head.
function handles(run) {
  return !(
    run.status === "completed" &&
    run.conclusion === "neutral" &&
    String(run.output?.title ?? "").startsWith("Skipped: untrusted-trigger")
  );
}

async function listAll(api, base) {
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
  checkName = DEFAULTS.checkName,
  appId = DEFAULTS.appId,
  maxDispatch = DEFAULTS.maxDispatch,
  unknownRetries = DEFAULTS.unknownRetries,
  unknownDelayMs = DEFAULTS.unknownDelayMs,
}) {
  const listed = await listAll(api, base);
  const candidates = listed.filter((node) => isCandidate(node, base));
  let pending = listed.filter((node) => isPending(node, base)).map((node) => node.number);

  for (let attempt = 1; pending.length > 0 && attempt <= unknownRetries; attempt += 1) {
    await sleep(unknownDelayMs);
    const nodes = await api.getPulls(pending);
    candidates.push(...nodes.filter((node) => isCandidate(node, base)));
    pending = nodes.filter((node) => isPending(node, base)).map((node) => node.number);
  }
  for (const number of pending) {
    log(
      `skip #${number}: mergeable still UNKNOWN after ${unknownRetries} re-queries; a later run retries`,
    );
  }

  candidates.sort((a, b) => a.number - b.number);
  const dispatched = [];
  let failed = 0;
  // Every dispatch call counts against the cap: one that failed or returned no
  // usable id may still have started a run.
  let sent = 0;
  for (const node of candidates) {
    if (sent >= maxDispatch) {
      log(`defer #${node.number}: ${maxDispatch} dispatches this run; left for a later run`);
      continue;
    }
    let existing;
    try {
      existing = await api.listCheckRuns({ sha: node.headRefOid, checkName, appId });
    } catch (error) {
      failed += 1;
      log(
        `::error::#${node.number}: could not read check runs for ${node.headRefOid}: ${error.message}`,
      );
      continue;
    }
    if (existing.some(handles)) {
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
  "number isDraft isCrossRepository mergeable baseRefName headRefOid headRefName state title body author { login } labels(first: 100) { nodes { name } } changedFiles";

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

// Writes the dispatched run ids, lowest PR first, as the step output run-ids,
// which the workflow records as an artifact on this run.
export async function main(
  env,
  {
    api,
    sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
    log = (line) => console.log(line),
  } = {},
) {
  for (const key of ["GITHUB_TOKEN", "GITHUB_REPOSITORY", "GITHUB_RUN_ID", "GITHUB_OUTPUT"]) {
    if (!env[key]) {
      throw new Error(`${key} is not set`);
    }
  }
  const client =
    api ??
    createGitHubApi({
      token: env.GITHUB_TOKEN,
      repository: env.GITHUB_REPOSITORY,
      apiUrl: env.GITHUB_API_URL ?? "https://api.github.com",
      graphqlUrl: env.GITHUB_GRAPHQL_URL ?? "https://api.github.com/graphql",
    });
  const conflicts = await dispatchConflicting({ api: client, runId: env.GITHUB_RUN_ID, sleep, log });
  const reviews = await dispatchDependencyReviews({
    api: client,
    runId: env.GITHUB_RUN_ID,
    log,
    config: readConfig(env.DEPENDABOT_CONFIG ?? ".base/.github/dependabot.yml", log),
    policy: readPolicy(env.DEPENDABOT_POLICY ?? `.base/${POLICY_PATH}`, log),
    repository: env.GITHUB_REPOSITORY,
  });
  const dispatched = [...conflicts.dispatched, ...reviews.dispatched];
  const failed = conflicts.failed + reviews.failed;
  if (dispatched.length > 0) {
    const ids = dispatched.map((run) => run.workflowRunId).join(" ");
    appendFileSync(env.GITHUB_OUTPUT, `run-ids=${ids}\n`);
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
