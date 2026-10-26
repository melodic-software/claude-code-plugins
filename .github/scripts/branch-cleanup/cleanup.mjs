// maintenance-delete-stale-branches.yml's two jobs, by STAGE.
//
// plan: sorts every branch of this repository into delete, keep or report by
// the branch-cleanup rule (docs/conventions/pr-pipeline/README.md, "Branch
// cleanup"), prints how many it will delete, and writes at most
// `max-deletes-per-run` candidates to CANDIDATES_PATH. Its client refuses
// every request but GET, and its job's token writes nothing.
//
// delete: reads only that candidate list, never issue or pull request text.
// Before each delete it re-reads the branch tip and its open pull requests,
// skips the branch when either changed, and appends the ledger line. The
// delete is one GraphQL updateRefs per branch with beforeOid set to the
// listed tip, so GitHub refuses it when the tip moved after the re-read. In
// dry-run its client refuses every request but GET.
//
// REST and one GraphQL mutation per delete, paced, within a call budget, of
// which the delete stage's share is reserved before any branch is evaluated.
// No model.
//
// Environment: STAGE (`plan` or `delete`), GITHUB_TOKEN, REPOSITORY, DRY_RUN
// (`true` or `false`), BASE_PATH (main's checkout), CANDIDATES_PATH (JSON),
// LEDGER_PATH (JSON Lines file, delete), CALL_BUDGET, GITHUB_API_URL,
// GITHUB_STEP_SUMMARY, GITHUB_OUTPUT (plan), GITHUB_RUN_NUMBER.
import { appendFileSync, readFileSync, writeFileSync } from "node:fs";
import process from "node:process";
import { setTimeout as delay } from "node:timers/promises";
import { pathToFileURL } from "node:url";

import { excluded, laneIssue, lastPull, linkedIssues, resolveBranchCleanup } from "./rules.mjs";
import { rateLimitLatch } from "../../actions/log-api-budget/rate-guard.mjs";

// Every GitHub call goes through the rate guard (rate-guard.mjs); the fetch
// is read at call time, so a test's stub is guarded too.
const guardedFetch = (url, init) => rateLimitLatch.guard(globalThis.fetch)(url, init);

export class BudgetSpent extends Error {}

export function client(env, { pace = () => delay(200), dryRun = true, budget = Number(env.CALL_BUDGET ?? 600) } = {}) {
  let used = 0;
  const call = async (method, path, body) => {
    if (dryRun && method !== "GET") throw new Error(`dry-run refuses ${method} ${path}`);
    if (used >= budget) throw new BudgetSpent(`call budget of ${budget} spent`);
    used += 1;
    await pace();
    const headers = {
      accept: "application/vnd.github+json",
      authorization: `Bearer ${env.GITHUB_TOKEN}`,
      "x-github-api-version": "2022-11-28",
    };
    if (body !== undefined) headers["content-type"] = "application/json";
    const response = await guardedFetch(`${env.GITHUB_API_URL ?? "https://api.github.com"}${path}`, {
      method,
      headers,
      ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    });
    if (response.status === 404 && method === "GET") return null;
    if (!response.ok) throw new Error(`${method} ${path.split("?")[0]}: HTTP ${response.status}`);
    if (response.status === 204) return null;
    const json = await response.json();
    // GraphQL answers a refused mutation with HTTP 200 and an errors list.
    if (path === "/graphql" && (json?.errors?.length || !json?.data)) {
      throw new Error(`POST /graphql: ${json?.errors?.map((e) => e.message).join("; ") || "no data"}`);
    }
    return json;
  };
  call.remaining = () => budget - used;
  return call;
}

async function pages(call, path, max = 20) {
  const items = [];
  for (let page = 1; page <= max; page += 1) {
    const batch = (await call("GET", `${path}${path.includes("?") ? "&" : "?"}per_page=100&page=${page}`)) ?? [];
    items.push(...batch);
    if (batch.length < 100) return items;
  }
  throw new Error(`${path.split("?")[0]}: more than ${max} pages`);
}

const refPath = (name) => name.split("/").map(encodeURIComponent).join("/");

// One branch's verdict: { verdict: delete | keep | report, rule or reason,
// issue, pr }. Reads run cheapest first and stop at the first
// verdict; a failed read reports the branch.
export async function evaluate(call, { repo, owner, defaultBranch }, branch) {
  const { name, sha } = branch;
  const keep = (reason, extra = {}) => ({ verdict: "keep", reason, ...extra });
  const report = (reason, extra = {}) => ({ verdict: "report", reason, ...extra });
  if (branch.protected) return keep("protected");
  const pulls = await pages(call, `/repos/${repo}/pulls?state=all&head=${encodeURIComponent(`${owner}:${name}`)}`);
  const openPull = pulls.find((p) => p.state === "open");
  if (openPull) return keep("open pull request", { pr: openPull.number });
  const pull = lastPull(pulls);
  const pr = pull?.number ?? null;
  let issue = laneIssue(name);
  if (issue) {
    const read = await call("GET", `/repos/${repo}/issues/${issue}`);
    if (!read) return report("its issue could not be read", { issue, pr });
    if (read.state !== "closed") return keep("its issue is open", { issue, pr });
  } else {
    if (!pull) return report("never had a pull request", {});
    for (const number of linkedIssues(pull.body, repo)) {
      const read = await call("GET", `/repos/${repo}/issues/${number}`);
      if (!read) return report(`linked issue #${number} could not be read`, { issue: number, pr });
      if (read.state !== "closed") return keep(`linked issue #${number} is open`, { issue: number, pr });
      issue ??= number;
    }
  }

  let rule;
  if (!pull) {
    rule = "lane-issue-closed";
  } else {
    const tipMoved = pull.head?.sha !== sha;
    if (pull.merged_at && !tipMoved) {
      rule = "pr-merged";
    } else if (pull.merged_at) {
      const compare = await call(
        "GET",
        `/repos/${repo}/compare/${encodeURIComponent(defaultBranch)}...${encodeURIComponent(sha)}`,
      );
      if (!Number.isSafeInteger(compare?.ahead_by)) return report("its commits ahead of the default branch could not be read", { issue, pr });
      if (compare.ahead_by > 0) return report(`merged, then ${compare.ahead_by} commit(s) ahead of ${defaultBranch}`, { issue, pr });
      rule = "pr-merged-no-commits-ahead";
    } else if (!tipMoved) {
      rule = "pr-closed";
    } else {
      return report("pull request closed unmerged, then the tip moved", { issue, pr });
    }
  }

  const rules = await call("GET", `/repos/${repo}/rules/branches/${refPath(name)}`);
  if (!Array.isArray(rules)) return report("the rules for it could not be read", { issue, pr });
  if (rules.length > 0) return keep("a ruleset applies to it", { issue, pr });
  return { verdict: "delete", rule, issue, pr };
}


// Right before the delete: the tip still at the listed SHA, and no open pull
// request from it or into it.
async function stillDeletable(call, { repo, owner }, { name, sha }) {
  const ref = await call("GET", `/repos/${repo}/git/ref/heads/${refPath(name)}`);
  if (ref?.object?.sha !== sha) return `the tip moved to ${ref?.object?.sha ?? "nothing"} since the listing`;
  const from = await call("GET", `/repos/${repo}/pulls?state=open&head=${encodeURIComponent(`${owner}:${name}`)}&per_page=1`);
  if (!Array.isArray(from) || from.length > 0) return "a pull request from it is open";
  const into = await call("GET", `/repos/${repo}/pulls?state=open&base=${encodeURIComponent(name)}&per_page=1`);
  if (!Array.isArray(into) || into.length > 0) return "a pull request into it is open";
  return null;
}

export const ZERO_OID = "0".repeat(40);

// Deletes the ref only while it points at the listed SHA: GitHub checks
// beforeOid and moves the ref in one step (GraphQL updateRefs). One branch per
// call, since one refused update would refuse the whole list.
export const DELETE_REF = `mutation($repositoryId: ID!, $name: GitRefname!, $beforeOid: GitObjectID!, $afterOid: GitObjectID!) {
  updateRefs(input: { repositoryId: $repositoryId, refUpdates: [{ name: $name, beforeOid: $beforeOid, afterOid: $afterOid }] }) { clientMutationId }
}`;

const deleteRef = (call, repositoryId, { name, sha }) =>
  call("POST", "/graphql", {
    query: DELETE_REF,
    variables: { repositoryId, name: `refs/heads/${name}`, beforeOid: sha, afterOid: ZERO_OID },
  });

// Calls one delete takes: the tip and the open pull requests from and into
// the branch re-read (stillDeletable), the delete, and a re-read of the tip
// when the delete is refused. The delete stage also reads the repository once.
const CALLS_PER_DELETE = 5;
export const deleteBudget = (deletes) => 1 + deletes * CALLS_PER_DELETE;

const RULES = new Set(["lane-issue-closed", "pr-merged", "pr-merged-no-commits-ahead", "pr-closed"]);
const SHA = /^[0-9a-f]{40}$/;
const issueRef = (value) => value === null || (Number.isSafeInteger(value) && value > 0);

const row = (cells) => `| ${cells.map((c) => String(c ?? "").replaceAll("|", "\\|")).join(" | ")} |`;

const checkRepo = (repo) => {
  if (!/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(repo ?? "")) throw new Error("REPOSITORY is not owner/repo");
  return repo;
};

// The plan stage: evaluates and returns the candidate list the delete stage
// takes, { repo, planned: [{ name, sha, rule, issue, pr }] }.
export async function plan(env, { call, loadConfig, log = console.log }) {
  const repo = checkRepo(env.REPOSITORY);
  const dryRun = env.DRY_RUN !== "false";
  const config = resolveBranchCleanup(loadConfig());
  const owner = repo.split("/")[0];
  const cap = config["max-deletes-per-run"];
  // Evaluation gets what the delete stage's share leaves of the budget.
  const evalLimit = (call.remaining?.() ?? Number.POSITIVE_INFINITY) - deleteBudget(cap);
  if (evalLimit <= 0) throw new Error(`the call budget does not cover ${cap} deletes and any reads`);
  let evalUsed = 0;
  const read = async (method, path) => {
    if (evalUsed >= evalLimit) throw new BudgetSpent(`the evaluation share of ${evalLimit} calls is spent`);
    evalUsed += 1;
    return call(method, path);
  };
  const defaultBranch = (await read("GET", `/repos/${repo}`))?.default_branch;
  if (typeof defaultBranch !== "string" || defaultBranch === "") throw new Error("the default branch could not be read");
  const context = { repo, owner, defaultBranch };

  const branches = await pages(read, `/repos/${repo}/branches`);
  // Evaluation stops once the cap is filled or its share is spent, so each run
  // starts at a point the run number moves by about a quarter of what one run
  // can read (a branch takes up to about four reads), wrapping around: kept
  // branches early in the listing cannot hide the later ones from every run.
  const stride = Number.isFinite(evalLimit) ? Math.max(1, Math.floor(evalLimit / 4)) : 0;
  const start = branches.length === 0 ? 0 : ((Number.parseInt(env.GITHUB_RUN_NUMBER ?? "", 10) || 0) * stride) % branches.length;
  const ordered = [...branches.slice(start), ...branches.slice(0, start)];
  const results = [];
  let unevaluated = 0;
  let found = 0;
  for (const [index, branch] of ordered.entries()) {
    if (cap > 0 && found >= cap) {
      unevaluated = ordered.length - index;
      break;
    }
    const name = branch.name;
    const sha = branch.commit?.sha;
    const skip = excluded(name, defaultBranch);
    if (skip) {
      results.push({ name, sha, verdict: "excluded", reason: skip });
      continue;
    }
    try {
      const verdict = await evaluate(read, context, { name, sha, protected: branch.protected });
      if (verdict.verdict === "delete") found += 1;
      results.push({ name, sha, ...verdict });
    } catch (error) {
      if (error instanceof BudgetSpent) {
        unevaluated = ordered.length - index;
        break;
      }
      results.push({ name, sha, verdict: "report", reason: `a read failed: ${error.message}` });
    }
  }

  const candidates = results.filter((r) => r.verdict === "delete");
  const planned = candidates.slice(0, cap).map(({ name, sha, rule, issue, pr }) => ({ name, sha, rule, issue: issue ?? null, pr: pr ?? null }));
  log(
    `${dryRun ? "dry-run: would delete" : "will delete"} ${planned.length} of ${candidates.length} deletable branch(es) (cap ${cap}); ${branches.length} branch(es) listed`,
  );

  const count = (verdict) => results.filter((r) => r.verdict === verdict).length;
  const lines = [
    `### Branch cleanup plan${dryRun ? " (dry-run: nothing deleted)" : ""}`,
    "",
    `${branches.length} branches: ${candidates.length} deletable, ${count("keep")} kept, ${count("report")} for a person, ${count("excluded")} excluded. Cap ${cap}.`,
    "",
    `#### ${dryRun ? "Would delete" : "Listed for the delete job"} (${planned.length})`,
    "",
    row(["Branch", "SHA", "Rule", "Issue", "PR"]),
    row(["---", "---", "---", "---", "---"]),
    ...planned.map((c) => row([`\`${c.name}\``, c.sha.slice(0, 12), c.rule, c.issue ? `#${c.issue}` : "", c.pr ? `#${c.pr}` : ""])),
  ];
  if (unevaluated > 0) {
    lines.push("", `${unevaluated} branch(es) not evaluated this run (cap ${cap} reached or call budget spent); the next run starts at a different point in the listing.`);
  }
  lines.push(
    "",
    `#### For a person (${count("report")})`,
    "",
    ...results.filter((r) => r.verdict === "report").map((r) => `- \`${r.name}\`: ${r.reason}`),
    "",
    `#### Kept (${count("keep")})`,
    "",
    ...results.filter((r) => r.verdict === "keep").map((r) => `- \`${r.name}\`: ${r.reason}`),
  );
  return { dryRun, results, candidates, planned, unevaluated, list: { repo, planned }, summary: lines.join("\n") };
}

// The candidate list as the delete stage takes it: this repository, at most
// the cap, each entry a deletable rule's shape on a branch the job may touch.
// Anything else stops the stage before it deletes.
export function readList(list, { repo, cap, defaultBranch }) {
  if (list?.repo !== repo) throw new Error("the candidate list is for another repository");
  if (!Array.isArray(list.planned)) throw new Error("the candidate list has no planned array");
  if (list.planned.length > cap) throw new Error(`the candidate list holds ${list.planned.length} branches, over the cap of ${cap}`);
  const names = new Set();
  for (const c of list.planned) {
    const ok =
      typeof c?.name === "string" &&
      c.name !== "" &&
      !excluded(c.name, defaultBranch) &&
      !names.has(c.name) &&
      SHA.test(c.sha ?? "") &&
      RULES.has(c.rule) &&
      issueRef(c.issue) &&
      issueRef(c.pr);
    if (!ok) throw new Error(`the candidate list holds an entry the delete stage refuses: ${JSON.stringify(c)}`);
    names.add(c.name);
  }
  return list.planned;
}

// The delete stage: deletes the listed branches that are still deletable.
export async function remove(env, { call, clock, loadConfig, append, list, log = console.log }) {
  const repo = checkRepo(env.REPOSITORY);
  const dryRun = env.DRY_RUN !== "false";
  const cap = resolveBranchCleanup(loadConfig())["max-deletes-per-run"];
  const repository = await call("GET", `/repos/${repo}`);
  const defaultBranch = repository?.default_branch;
  const repositoryId = repository?.node_id;
  if (typeof defaultBranch !== "string" || defaultBranch === "") throw new Error("the default branch could not be read");
  if (typeof repositoryId !== "string" || repositoryId === "") throw new Error("the repository id could not be read");
  const planned = readList(list, { repo, cap, defaultBranch });
  const context = { repo, owner: repo.split("/")[0], defaultBranch };
  log(`${dryRun ? "dry-run: would delete" : "deleting"} up to ${planned.length} listed branch(es)`);

  const deleted = [];
  const skipped = [];
  for (const candidate of planned) {
    if (dryRun) continue;
    let reason;
    try {
      reason = await stillDeletable(call, context, candidate);
    } catch (error) {
      reason = `a re-read failed: ${error.message}`;
    }
    if (reason) {
      skipped.push({ ...candidate, reason });
      continue;
    }
    const entry = {
      repo,
      branch: candidate.name,
      sha: candidate.sha,
      rule: candidate.rule,
      issue: candidate.issue ?? null,
      pr: candidate.pr ?? null,
      deletedAt: clock(),
    };
    append(entry);
    try {
      await deleteRef(call, repositoryId, candidate);
      deleted.push(entry);
    } catch (error) {
      // A tip that moved after the re-read makes GitHub refuse the update:
      // that branch is skipped, not a failed delete.
      const tip = await call("GET", `/repos/${repo}/git/ref/heads/${refPath(candidate.name)}`).catch(() => undefined);
      skipped.push({
        ...candidate,
        reason:
          tip !== undefined && tip?.object?.sha !== candidate.sha
            ? `the tip moved to ${tip?.object?.sha ?? "nothing"} before the delete; GitHub refused it`
            : `the delete failed: ${error.message}`,
      });
    }
  }

  const lines = [
    `### Branch cleanup${dryRun ? " (dry-run: nothing deleted)" : ""}`,
    "",
    dryRun ? `#### Would delete (${planned.length})` : `#### Deleted (${deleted.length})`,
    "",
    row(["Branch", "SHA", "Rule", "Issue", "PR"]),
    row(["---", "---", "---", "---", "---"]),
    ...(dryRun ? planned : planned.filter((c) => deleted.some((d) => d.branch === c.name))).map((c) =>
      row([`\`${c.name}\``, c.sha.slice(0, 12), c.rule, c.issue ? `#${c.issue}` : "", c.pr ? `#${c.pr}` : ""]),
    ),
  ];
  if (skipped.length > 0) {
    lines.push("", "#### Skipped at delete time", "", ...skipped.map((s) => `- \`${s.name}\`: ${s.reason}`));
  }
  return { dryRun, planned, deleted, skipped, summary: lines.join("\n") };
}

async function main(env = process.env) {
  const { branchCleanupFromBase } = await import(
    pathToFileURL(`${env.BASE_PATH}/.github/actions/resolve-config/resolve-config.mjs`).href
  );
  const dryRun = env.DRY_RUN !== "false";
  const loadConfig = () => branchCleanupFromBase({ BASE_PATH: env.BASE_PATH });
  const summarize = (text) => {
    if (env.GITHUB_STEP_SUMMARY) appendFileSync(env.GITHUB_STEP_SUMMARY, `${text}\n`);
    else console.log(text);
  };
  if (env.STAGE === "plan") {
    // The plan stage never writes, dry-run or not.
    const result = await plan(env, { call: client(env, { dryRun: true }), loadConfig });
    writeFileSync(env.CANDIDATES_PATH, `${JSON.stringify(result.list)}\n`);
    if (env.GITHUB_OUTPUT) appendFileSync(env.GITHUB_OUTPUT, `planned=${result.planned.length}\n`);
    summarize(result.summary);
    return;
  }
  if (env.STAGE !== "delete") throw new Error("STAGE is not plan or delete");
  const list = JSON.parse(readFileSync(env.CANDIDATES_PATH, "utf8"));
  const deletes = Array.isArray(list?.planned) ? list.planned.length : 0;
  const result = await remove(env, {
    call: client(env, { dryRun, budget: deleteBudget(deletes) }),
    clock: () => new Date().toISOString(),
    loadConfig,
    list,
    append: (entry) => {
      const line = `${JSON.stringify(entry)}\n`;
      appendFileSync(env.LEDGER_PATH, line);
      if (env.GITHUB_STEP_SUMMARY) appendFileSync(env.GITHUB_STEP_SUMMARY, `ledger: \`${line.trim()}\`\n\n`);
    },
  });
  summarize(result.summary);
  if (result.skipped.some((s) => s.reason.startsWith("the delete failed"))) process.exitCode = 1;
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  main().catch((error) => {
    console.log(`::error::${error.message}`);
    process.exitCode = 1;
  });
}
