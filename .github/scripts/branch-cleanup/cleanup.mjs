import { appendFileSync, readFileSync, writeFileSync } from "node:fs";
import process from "node:process";
import { setTimeout as delay } from "node:timers/promises";
import { pathToFileURL } from "node:url";

import { excluded, laneIssue, lastPull, linkedIssues, resolveBranchCleanup } from "./rules.mjs";
import { BudgetSpent, budgetedClient, pages } from "../lib/github-rest.mjs";

export function client(env, { pace = () => delay(200), dryRun = true, budget = Number(env.CALL_BUDGET ?? 600) } = {}) {
  const rest = budgetedClient(env, { budget, pace });
  const call = async (method, path, body) => {
    if (dryRun && method !== "GET") throw new Error(`dry-run refuses ${method} ${path}`);
    const json = await rest(method, path, body);
    if (path === "/graphql" && (json?.errors?.length || !json?.data)) {
      throw new Error(`POST /graphql: ${json?.errors?.map((e) => e.message).join("; ") || "no data"}`);
    }
    return json;
  };
  call.remaining = rest.remaining;
  return call;
}

const refPath = (name) => name.split("/").map(encodeURIComponent).join("/");
const readTip = (call, repo, name) => call("GET", `/repos/${repo}/git/ref/heads/${refPath(name)}`);

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

async function stillDeletable(call, { repo, owner }, { name, sha }) {
  const ref = await readTip(call, repo, name);
  if (ref?.object?.sha !== sha) return `the tip moved to ${ref?.object?.sha ?? "nothing"} since the listing`;
  const from = await call("GET", `/repos/${repo}/pulls?state=open&head=${encodeURIComponent(`${owner}:${name}`)}&per_page=1`);
  if (!Array.isArray(from) || from.length > 0) return "a pull request from it is open";
  const into = await call("GET", `/repos/${repo}/pulls?state=open&base=${encodeURIComponent(name)}&per_page=1`);
  if (!Array.isArray(into) || into.length > 0) return "a pull request into it is open";
  return null;
}

export const ZERO_OID = "0".repeat(40);

export const DELETE_REF = `mutation($repositoryId: ID!, $name: GitRefname!, $beforeOid: GitObjectID!, $afterOid: GitObjectID!) {
  updateRefs(input: { repositoryId: $repositoryId, refUpdates: [{ name: $name, beforeOid: $beforeOid, afterOid: $afterOid }] }) { clientMutationId }
}`;

const deleteRef = (call, repositoryId, { name, sha }) =>
  call("POST", "/graphql", {
    query: DELETE_REF,
    variables: { repositoryId, name: `refs/heads/${name}`, beforeOid: sha, afterOid: ZERO_OID },
  });

const CALLS_PER_DELETE = 5;
export const deleteBudget = (deletes) => 1 + deletes * CALLS_PER_DELETE;

const RULES = new Set(["lane-issue-closed", "pr-merged", "pr-merged-no-commits-ahead", "pr-closed"]);
const SHA = /^[0-9a-f]{40}$/;
const issueRef = (value) => value === null || (Number.isSafeInteger(value) && value > 0);

const row = (cells) => `| ${cells.map((c) => String(c ?? "").replaceAll("|", "\\|")).join(" | ")} |`;
const TABLE_HEAD = [row(["Branch", "SHA", "Rule", "Issue", "PR"]), row(["---", "---", "---", "---", "---"])];
const candidateRow = (c) => row([`\`${c.name}\``, c.sha.slice(0, 12), c.rule, c.issue ? `#${c.issue}` : "", c.pr ? `#${c.pr}` : ""]);
const reasons = (list) => list.map((r) => `- \`${r.name}\`: ${r.reason}`);

const isDryRun = (env) => env.DRY_RUN !== "false";

const checkRepo = (repo) => {
  if (!/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(repo ?? "")) throw new Error("REPOSITORY is not owner/repo");
  return repo;
};

export async function plan(env, { call, loadConfig, log = console.log }) {
  const repo = checkRepo(env.REPOSITORY);
  const dryRun = isDryRun(env);
  const owner = repo.split("/")[0];
  const cap = resolveBranchCleanup(loadConfig())["max-deletes-per-run"];
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
  const stride = Number.isFinite(evalLimit) ? Math.max(1, Math.floor(evalLimit / 4)) : 0;
  const gcd = (a, b) => (b === 0 ? a : gcd(b, a % b));
  let step = branches.length === 0 ? 0 : stride % branches.length;
  while (stride > 0 && branches.length > 1 && gcd(step, branches.length) !== 1) step += 1;
  const start = branches.length === 0 ? 0 : ((Number.parseInt(env.GITHUB_RUN_NUMBER ?? "", 10) || 0) * step) % branches.length;
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

  const withVerdict = (verdict) => results.filter((r) => r.verdict === verdict);
  const reported = withVerdict("report");
  const kept = withVerdict("keep");
  const lines = [
    `### Branch cleanup plan${dryRun ? " (dry-run: nothing deleted)" : ""}`,
    "",
    `${branches.length} branches: ${candidates.length} deletable, ${kept.length} kept, ${reported.length} for a person, ${withVerdict("excluded").length} excluded. Cap ${cap}.`,
    "",
    `#### ${dryRun ? "Would delete" : "Listed for the delete job"} (${planned.length})`,
    "",
    ...TABLE_HEAD,
    ...planned.map(candidateRow),
  ];
  if (unevaluated > 0) {
    lines.push("", `${unevaluated} branch(es) not evaluated this run (cap ${cap} reached or call budget spent); the next run starts at a different point in the listing.`);
  }
  lines.push("", `#### For a person (${reported.length})`, "", ...reasons(reported), "", `#### Kept (${kept.length})`, "", ...reasons(kept));
  return { dryRun, results, candidates, planned, unevaluated, list: { repo, planned }, summary: lines.join("\n") };
}

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

export async function remove(env, { call, clock, loadConfig, append, list, log = console.log }) {
  const repo = checkRepo(env.REPOSITORY);
  const dryRun = isDryRun(env);
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
      issue: candidate.issue,
      pr: candidate.pr,
      deletedAt: clock(),
    };
    append(entry);
    try {
      await deleteRef(call, repositoryId, candidate);
      deleted.push(entry);
    } catch (error) {
      const tip = await readTip(call, repo, candidate.name).catch(() => undefined);
      const reason =
        tip !== undefined && tip?.object?.sha !== candidate.sha
          ? `the tip moved to ${tip?.object?.sha ?? "nothing"} before the delete; GitHub refused it`
          : `the delete failed: ${error.message}`;
      skipped.push({ ...candidate, reason });
      if (typeof tip?.object?.sha === "string") {
        append({ repo, branch: candidate.name, sha: candidate.sha, notDeletedAt: clock(), reason });
      }
    }
  }

  const lines = [
    `### Branch cleanup${dryRun ? " (dry-run: nothing deleted)" : ""}`,
    "",
    dryRun ? `#### Would delete (${planned.length})` : `#### Deleted (${deleted.length})`,
    "",
    ...TABLE_HEAD,
    ...(dryRun ? planned : planned.filter((c) => deleted.some((d) => d.branch === c.name))).map(candidateRow),
  ];
  if (skipped.length > 0) {
    lines.push("", "#### Skipped at delete time", "", ...reasons(skipped));
  }
  return { dryRun, planned, deleted, skipped, summary: lines.join("\n") };
}

async function main(env = process.env) {
  const { branchCleanupFromBase } = await import(
    pathToFileURL(`${env.BASE_PATH}/.github/actions/resolve-config/resolve-config.mjs`).href
  );
  const dryRun = isDryRun(env);
  const loadConfig = () => branchCleanupFromBase({ BASE_PATH: env.BASE_PATH, STANDARDS_DIR: env.STANDARDS_DIR });
  const summarize = (text) => {
    if (env.GITHUB_STEP_SUMMARY) appendFileSync(env.GITHUB_STEP_SUMMARY, `${text}\n`);
    else console.log(text);
  };
  if (env.STAGE === "plan") {
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
