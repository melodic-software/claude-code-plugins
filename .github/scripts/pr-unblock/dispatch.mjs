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
// config and gate. Logs carry PR numbers, SHAs and run ids only.

import { pathToFileURL } from "node:url";

export const DEFAULTS = Object.freeze({
  base: "main",
  workflow: "pr-unblock.yml",
  checkName: "pr-unblock / resolve-conflicts",
  // Judgment until the lane's measured per-run cost sets it.
  maxDispatch: 3,
  // GitHub gives no timing for computing mergeability; this bounds the wait
  // at about a minute (judgment).
  unknownRetries: 5,
  unknownDelayMs: 10_000,
});

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
  for (const node of candidates) {
    if (dispatched.length >= maxDispatch) {
      log(`defer #${node.number}: ${maxDispatch} dispatches this run; left for a later run`);
      continue;
    }
    let existing;
    try {
      existing = await api.listCheckRuns({ sha: node.headRefOid, checkName });
    } catch (error) {
      failed += 1;
      log(
        `::error::#${node.number}: could not read check runs for ${node.headRefOid}: ${error.message}`,
      );
      continue;
    }
    if (existing > 0) {
      log(`skip #${node.number}: head ${node.headRefOid} already has a ${checkName} check run`);
      continue;
    }
    try {
      const { workflowRunId } = await api.dispatchWorkflow({
        workflow,
        ref: base,
        inputs: { "pr-number": String(node.number), "dispatcher-run-id": String(runId) },
      });
      dispatched.push({ number: node.number, workflowRunId });
      log(
        `dispatched #${node.number} head ${node.headRefOid} workflow_run_id=${workflowRunId ?? "unreported"}`,
      );
    } catch (error) {
      failed += 1;
      log(`::error::#${node.number}: dispatch failed: ${error.message}`);
    }
  }
  return { dispatched, failed };
}

const PULL_FIELDS = "number isDraft isCrossRepository mergeable baseRefName headRefOid state";

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
    async listCheckRuns({ sha, checkName }) {
      const query = new URLSearchParams({ check_name: checkName, filter: "all" });
      const result = await request(
        `${apiUrl}/repos/${owner}/${name}/commits/${sha}/check-runs?${query}`,
      );
      return result.total_count;
    },
    async dispatchWorkflow({ workflow, ref, inputs }) {
      const result = await request(
        `${apiUrl}/repos/${owner}/${name}/actions/workflows/${workflow}/dispatches`,
        "POST",
        {
          ref,
          inputs,
        },
      );
      return { workflowRunId: result.workflow_run_id };
    },
  };
}

async function main(env) {
  for (const key of ["GITHUB_TOKEN", "GITHUB_REPOSITORY", "GITHUB_RUN_ID"]) {
    if (!env[key]) {
      throw new Error(`${key} is not set`);
    }
  }
  const api = createGitHubApi({
    token: env.GITHUB_TOKEN,
    repository: env.GITHUB_REPOSITORY,
    apiUrl: env.GITHUB_API_URL ?? "https://api.github.com",
    graphqlUrl: env.GITHUB_GRAPHQL_URL ?? "https://api.github.com/graphql",
  });
  const { dispatched, failed } = await dispatchConflicting({
    api,
    runId: env.GITHUB_RUN_ID,
    sleep: (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
    log: (line) => console.log(line),
  });
  console.log(`dispatched ${dispatched.length} run(s), ${failed} failure(s)`);
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
