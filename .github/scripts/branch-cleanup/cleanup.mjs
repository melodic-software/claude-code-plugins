// maintenance-delete-stale-branches.yml's job: sorts every branch of this
// repository into delete, keep or report by the branch-cleanup rule
// (docs/conventions/pr-pipeline/README.md, "Branch cleanup"), prints how many
// it will delete, and deletes at most `max-deletes-per-run` of them. Before
// each delete it re-reads the branch tip and its open pull requests, skips the
// branch when either changed, and appends the ledger line. In dry-run the
// client refuses every request but GET, so nothing is written. REST only,
// paced, within a call budget. No model.
//
// Environment: GITHUB_TOKEN, REPOSITORY, DRY_RUN (`true` or `false`),
// BASE_PATH (main's checkout), LEDGER_PATH (JSON Lines file), CALL_BUDGET,
// LANES_BOT_LOGIN, GITHUB_API_URL, GITHUB_STEP_SUMMARY.
import { appendFileSync } from "node:fs";
import process from "node:process";
import { setTimeout as delay } from "node:timers/promises";
import { pathToFileURL } from "node:url";

import { parseOutcomeMarker } from "../work-resolve-issue/report-outcome.mjs";
import { ageDays, excluded, laneBranch, lastPull, linkedIssues, resolveBranchCleanup, stoppedRun } from "./rules.mjs";

export function client(env, { pace = () => delay(200), dryRun = true } = {}) {
  let used = 0;
  const budget = Number(env.CALL_BUDGET ?? 600);
  return async (method, path) => {
    if (dryRun && method !== "GET") throw new Error(`dry-run refuses ${method} ${path}`);
    if (used >= budget) throw new Error(`call budget of ${budget} spent`);
    used += 1;
    await pace();
    const response = await fetch(`${env.GITHUB_API_URL ?? "https://api.github.com"}${path}`, {
      method,
      headers: {
        accept: "application/vnd.github+json",
        authorization: `Bearer ${env.GITHUB_TOKEN}`,
        "x-github-api-version": "2022-11-28",
      },
    });
    if (response.status === 404 && method === "GET") return null;
    if (!response.ok) throw new Error(`${method} ${path.split("?")[0]}: HTTP ${response.status}`);
    return response.status === 204 ? null : response.json();
  };
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
// issue, pr, closedAt }. Reads run cheapest first and stop at the first
// verdict; a failed read reports the branch.
export async function evaluate(call, { repo, owner, bot, defaultBranch, config, now }, branch) {
  const { name, sha } = branch;
  const keep = (reason, extra = {}) => ({ verdict: "keep", reason, ...extra });
  const report = (reason, extra = {}) => ({ verdict: "report", reason, ...extra });
  if (branch.protected) return keep("protected");
  const pulls = await pages(call, `/repos/${repo}/pulls?state=all&head=${encodeURIComponent(`${owner}:${name}`)}`);
  const openPull = pulls.find((p) => p.state === "open");
  if (openPull) return keep("open pull request", { pr: openPull.number });
  const pull = lastPull(pulls);
  const pr = pull?.number ?? null;
  const lane = laneBranch(name);

  const closedTimes = [];
  let issue = null;
  if (lane) {
    issue = lane.issue;
    const read = await call("GET", `/repos/${repo}/issues/${issue}`);
    if (!read) return report("its issue could not be read", { issue, pr });
    if (read.state !== "closed") return keep("its issue is open", { issue, pr });
    const markers = (await pages(call, `/repos/${repo}/issues/${issue}/comments`))
      .filter((c) => c.user?.login === bot)
      .map((c) => parseOutcomeMarker(c.body))
      .filter(Boolean);
    if (stoppedRun(markers, lane.run)) return report("a stopped lane run's branch: a person decides", { issue, pr });
    closedTimes.push(read.closed_at);
  } else {
    if (!pull) return report("never had a pull request", {});
    for (const number of linkedIssues(pull.body, repo)) {
      const read = await call("GET", `/repos/${repo}/issues/${number}`);
      if (!read) return report(`linked issue #${number} could not be read`, { issue: number, pr });
      if (read.state !== "closed") return keep(`linked issue #${number} is open`, { issue: number, pr });
      issue ??= number;
      closedTimes.push(read.closed_at);
    }
  }

  let rule;
  if (!pull) {
    rule = "lane-issue-closed";
  } else {
    closedTimes.push(pull.closed_at);
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

  const age = ageDays(closedTimes, now);
  if (age === null) return report("a close time could not be read", { issue, pr });
  if (age < config["min-age-days"]) {
    return keep(`closed ${Math.floor(age)} d ago, under min-age-days (${config["min-age-days"]})`, { issue, pr });
  }
  const rules = await call("GET", `/repos/${repo}/rules/branches/${refPath(name)}`);
  if (!Array.isArray(rules)) return report("the rules for it could not be read", { issue, pr });
  if (rules.length > 0) return keep("a ruleset applies to it", { issue, pr });
  return { verdict: "delete", rule, issue, pr, ageDays: Math.floor(age) };
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

const row = (cells) => `| ${cells.map((c) => String(c ?? "").replaceAll("|", "\\|")).join(" | ")} |`;

export async function cleanup(env, { call, clock, loadConfig, append, log = console.log }) {
  const repo = env.REPOSITORY;
  if (!/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(repo ?? "")) throw new Error("REPOSITORY is not owner/repo");
  const dryRun = env.DRY_RUN !== "false";
  const config = resolveBranchCleanup(loadConfig());
  const owner = repo.split("/")[0];
  const bot = env.LANES_BOT_LOGIN || "melodic-automation-lanes[bot]";
  const now = clock();
  const defaultBranch = (await call("GET", `/repos/${repo}`))?.default_branch;
  if (typeof defaultBranch !== "string" || defaultBranch === "") throw new Error("the default branch could not be read");
  const context = { repo, owner, bot, defaultBranch, config, now };

  const branches = await pages(call, `/repos/${repo}/branches`);
  const results = [];
  for (const branch of branches) {
    const name = branch.name;
    const sha = branch.commit?.sha;
    const skip = excluded(name, defaultBranch);
    if (skip) {
      results.push({ name, sha, verdict: "excluded", reason: skip });
      continue;
    }
    try {
      results.push({ name, sha, ...(await evaluate(call, context, { name, sha, protected: branch.protected })) });
    } catch (error) {
      results.push({ name, sha, verdict: "report", reason: `a read failed: ${error.message}` });
    }
  }

  // Oldest first, so a capped run deletes the longest-closed branches.
  const candidates = results.filter((r) => r.verdict === "delete").sort((a, b) => b.ageDays - a.ageDays);
  const cap = config["max-deletes-per-run"];
  const planned = candidates.slice(0, cap);
  log(
    `${dryRun ? "dry-run: would delete" : "will delete"} ${planned.length} of ${candidates.length} deletable branch(es) (cap ${cap}); ${branches.length} branch(es) listed`,
  );

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
      await call("DELETE", `/repos/${repo}/git/refs/heads/${refPath(candidate.name)}`);
      deleted.push(entry);
    } catch (error) {
      skipped.push({ ...candidate, reason: `the delete failed: ${error.message}` });
    }
  }

  const count = (verdict) => results.filter((r) => r.verdict === verdict).length;
  const lines = [
    `### Branch cleanup${dryRun ? " (dry-run: nothing deleted)" : ""}`,
    "",
    `${branches.length} branches: ${candidates.length} deletable, ${count("keep")} kept, ${count("report")} for a person, ${count("excluded")} excluded. min-age-days ${config["min-age-days"]}, cap ${cap}.`,
    "",
    dryRun ? `#### Would delete (${planned.length})` : `#### Deleted (${deleted.length})`,
    "",
    row(["Branch", "SHA", "Rule", "Issue", "PR", "Closed (days)"]),
    row(["---", "---", "---", "---", "---", "---"]),
    ...(dryRun ? planned : planned.filter((c) => deleted.some((d) => d.branch === c.name))).map((c) =>
      row([`\`${c.name}\``, c.sha.slice(0, 12), c.rule, c.issue ? `#${c.issue}` : "", c.pr ? `#${c.pr}` : "", c.ageDays]),
    ),
  ];
  if (candidates.length > planned.length) {
    lines.push("", `${candidates.length - planned.length} more deletable branch(es) wait for the next run (cap ${cap}).`);
  }
  if (skipped.length > 0) {
    lines.push("", "#### Skipped at delete time", "", ...skipped.map((s) => `- \`${s.name}\`: ${s.reason}`));
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
  return { dryRun, results, candidates, planned, deleted, skipped, summary: lines.join("\n") };
}

async function main(env = process.env) {
  const { branchCleanupFromBase } = await import(
    pathToFileURL(`${env.BASE_PATH}/.github/actions/resolve-config/resolve-config.mjs`).href
  );
  const dryRun = env.DRY_RUN !== "false";
  const result = await cleanup(env, {
    call: client(env, { dryRun }),
    clock: () => new Date().toISOString(),
    loadConfig: () => branchCleanupFromBase({ BASE_PATH: env.BASE_PATH }),
    append: (entry) => {
      const line = `${JSON.stringify(entry)}\n`;
      appendFileSync(env.LEDGER_PATH, line);
      if (env.GITHUB_STEP_SUMMARY) appendFileSync(env.GITHUB_STEP_SUMMARY, `ledger: \`${line.trim()}\`\n\n`);
    },
  });
  if (env.GITHUB_STEP_SUMMARY) appendFileSync(env.GITHUB_STEP_SUMMARY, `${result.summary}\n`);
  else console.log(result.summary);
  if (result.skipped.some((s) => s.reason.startsWith("the delete failed"))) process.exitCode = 1;
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  main().catch((error) => {
    console.log(`::error::${error.message}`);
    process.exitCode = 1;
  });
}
