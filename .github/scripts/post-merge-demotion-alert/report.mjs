// post-merge-demotion-alert.yml's red-main report: after a scheduled or
// dispatched pr-require-checks run on main failed, wait for its one re-run,
// confirm the red, pin the culprit merge, decide whether the bot may revert
// it, and report that in the step summary and, for a confirmed red, as one
// comment on the log issue. It pushes, opens and merges nothing. REST reads
// only, paced, within a call budget; a failed or rate-limited read stops the
// run (no retry). No model.
//
// Environment: GITHUB_TOKEN, REPOSITORY, RUN_ID, RUN_SHA, RUN_URL,
// RUN_WORKFLOW_ID, RUN_CREATED, BASE_PATH (main's checkout), CALL_BUDGET,
// GITHUB_API_URL, GITHUB_SERVER_URL, GITHUB_STEP_SUMMARY.
import { execFileSync } from "node:child_process";
import { appendFileSync } from "node:fs";
import process from "node:process";
import { setTimeout as delay } from "node:timers/promises";
import { pathToFileURL } from "node:url";

import {
  attribute,
  commitStatus,
  confirm,
  decide,
  failingChecks,
  firstParentRange,
  LOG_MARKER,
  MARKER_PATTERN,
  plannedRevert,
  renderReport,
  resolveRedMain,
} from "./red-main.mjs";

const DAY_MS = 86_400_000;
const FULL_EVENTS = new Set(["schedule", "workflow_dispatch"]);
const BOT = "github-actions[bot]";
// github-actions[bot]'s numeric user id, which the alert job also trusts.
const BOT_ID = 41898282;
const CANARY_RECORD = /^<!-- (?:babysit-merge-demotion|post-merge-failure) sha=([0-9a-f]{40}) signal=canary -->$/;

export function client(env, { pace = () => delay(300) } = {}) {
  let used = 0;
  const budget = Number(env.CALL_BUDGET ?? 200);
  return async (method, path, body) => {
    if (used >= budget) throw new Error(`call budget of ${budget} spent`);
    used += 1;
    await pace();
    const response = await fetch(`${env.GITHUB_API_URL ?? "https://api.github.com"}${path}`, {
      method,
      headers: {
        accept: "application/vnd.github+json",
        authorization: `Bearer ${env.GITHUB_TOKEN}`,
        "x-github-api-version": "2022-11-28",
        ...(body ? { "content-type": "application/json" } : {}),
      },
      body: body ? JSON.stringify(body) : undefined,
    });
    if (response.status === 404 && method === "GET") return null;
    if (!response.ok) throw new Error(`${method} ${path.split("?")[0]}: HTTP ${response.status}`);
    return response.json();
  };
}

// Every page of a list endpoint, until a short page. `key` names the array in
// an object response (jobs, workflow_runs).
async function pages(call, path, key, max = 20) {
  const items = [];
  for (let page = 1; page <= max; page += 1) {
    const response = await call("GET", `${path}${path.includes("?") ? "&" : "?"}per_page=100&page=${page}`);
    const batch = (key ? response?.[key] : response) ?? [];
    items.push(...batch);
    if (batch.length < 100) return items;
  }
  throw new Error(`${path.split("?")[0]}: more than ${max} pages`);
}

async function attemptChecks(call, repo, runId, attempt) {
  const jobs = await pages(call, `/repos/${repo}/actions/runs/${runId}/attempts/${attempt}/jobs`, "jobs");
  const annotations = {};
  for (const job of jobs.filter((j) => j.conclusion === "failure")) {
    annotations[job.id] = (await call("GET", `/repos/${repo}/check-runs/${job.id}/annotations?per_page=100`)) ?? [];
  }
  return failingChecks(jobs, annotations);
}

// Attempt 1 and the newest attempt of a run, each with its failing checks.
async function attempts(call, repo, run) {
  const first = await call("GET", `/repos/${repo}/actions/runs/${run.id}/attempts/1`);
  const result = {
    first: { attempt: 1, conclusion: first?.conclusion, checks: await attemptChecks(call, repo, run.id, 1) },
    latest: null,
  };
  if (run.run_attempt >= 2 && run.status === "completed") {
    result.latest = {
      attempt: run.run_attempt,
      conclusion: run.conclusion,
      checks: await attemptChecks(call, repo, run.id, run.run_attempt),
    };
  }
  return result;
}

// The run once a re-run of it finished, or as it stands when the wait ends.
async function awaitRerun(call, repo, runId, minutes, sleep) {
  let run = await call("GET", `/repos/${repo}/actions/runs/${runId}`);
  for (let waited = 0; waited < minutes && !(run.run_attempt >= 2 && run.status === "completed"); waited += 1) {
    await sleep(60_000);
    run = await call("GET", `/repos/${repo}/actions/runs/${runId}`);
  }
  return run;
}

// The merge-queue actor of the pull request's latest entry, as the alert's
// classify step and babysit_merge_policy.derive_auto_merge read it.
async function enqueuer(call, repo, number) {
  const events = await pages(call, `/repos/${repo}/issues/${number}/timeline`, null, 10);
  return events.filter((e) => e.event === "added_to_merge_queue").at(-1)?.actor?.login ?? "";
}

const firstLine = (body) => (body ?? "").trimStart().split("\n")[0].trimEnd();

// git merge-tree applies the revert of `sha` to main's tip in memory: a merge
// of the tip and sha's parent over sha. Exit 0 is clean, 1 a conflict.
export function revertAppliesWithGit(basePath) {
  return (sha) => {
    try {
      execFileSync("git", ["-C", basePath, "merge-tree", "--write-tree", `--merge-base=${sha}`, "HEAD", `${sha}^`], {
        stdio: "ignore",
      });
      return true;
    } catch (error) {
      return error.status === 1 ? false : null;
    }
  };
}

export async function report(env, { call, sleep, clock, loadConfig, revertApplies }) {
  const repo = env.REPOSITORY;
  if (!/^[0-9a-f]{40}$/.test(env.RUN_SHA ?? "") || !/^[1-9][0-9]*$/.test(env.RUN_ID ?? "") || !Number.isFinite(Date.parse(env.RUN_CREATED))) {
    throw new Error("RUN_SHA, RUN_ID and RUN_CREATED must be a full commit SHA, a run id and a time");
  }
  const { redMain, agentIdentity } = loadConfig();
  const config = resolveRedMain(redMain);
  const runUrl = env.RUN_URL;

  const run = await awaitRerun(call, repo, env.RUN_ID, config["confirm-wait-minutes"], sleep);
  const evidence = await attempts(call, repo, run);
  const verdict = confirm(evidence.first, evidence.latest);
  // The decision time, read after the wait: it drives the age and cap windows.
  const now = clock();
  const runInfo = { id: run.id, attempt: run.run_attempt, sha: env.RUN_SHA, url: runUrl };
  if (!verdict.confirmed) {
    return { posted: false, summary: `Red main not confirmed for ${runUrl}: ${verdict.reason}. Nothing to attribute.` };
  }

  // The range since main's last green full run, and each merge's own full run.
  // The newest 100 completed runs on main before this one: about two days of
  // full runs, which pr-merge dispatches after every merge.
  const listed = await call(
    "GET",
    `/repos/${repo}/actions/workflows/${env.RUN_WORKFLOW_ID}/runs?branch=main&status=completed&created=%3C${env.RUN_CREATED}&per_page=100`,
  );
  const runs = (listed?.workflow_runs ?? []).filter(
    (r) => r.head_branch === "main" && FULL_EVENTS.has(r.event) && r.created_at < env.RUN_CREATED,
  );
  const green = runs
    .filter((r) => r.conclusion === "success" && r.head_sha !== env.RUN_SHA)
    .sort((a, b) => b.created_at.localeCompare(a.created_at))[0];
  const base = green ? { sha: green.head_sha, url: green.html_url } : null;
  let range = null;
  let commits = [];
  if (base) {
    const compare = await call("GET", `/repos/${repo}/compare/${base.sha}...${env.RUN_SHA}`);
    commits = (compare?.commits ?? []).map((c) => ({
      sha: c.sha,
      parent: c.parents?.[0]?.sha,
      message: c.commit?.message ?? "",
      committedAt: c.commit?.committer?.date ?? "",
    }));
    // At most 25 merges, so their evidence reads fit the call budget.
    range = firstParentRange(base.sha, env.RUN_SHA, commits, 25);
  }

  const statuses = { [env.RUN_SHA]: "red" };
  const rows = [];
  for (const sha of range ?? []) {
    const commit = commits.find((c) => c.sha === sha);
    const number = Number(/\(#(\d+)\)$/.exec(firstLine(commit.message))?.[1]) || null;
    const own = runs
      .filter((r) => r.head_sha === sha)
      .sort((a, b) => b.created_at.localeCompare(a.created_at))[0];
    if (sha !== env.RUN_SHA) {
      statuses[sha] = commitStatus(own && { conclusion: own.conclusion, ...(await attempts(call, repo, own)) }, verdict.checks);
    }
    rows.push({
      sha,
      number,
      enqueuer: number ? await enqueuer(call, repo, number) : "",
      status: statuses[sha],
      evidence: sha === env.RUN_SHA ? `${runUrl}/attempts/${run.run_attempt}` : own && `${own.html_url} (${own.conclusion})`,
    });
  }

  // github-actions[bot]'s issues: the log issue, the post-merge record for
  // this run's SHA, and any canary record (a platform-side silent revert) in
  // the range. The log is the oldest issue carrying its marker, so a newer one
  // another workflow files can neither take the reports nor reset the cap.
  const issues = (await pages(call, `/repos/${repo}/issues?state=all&creator=${encodeURIComponent(BOT)}`, null)).filter(
    (i) => !i.pull_request && i.user?.id === BOT_ID,
  );
  const log = issues
    .filter((i) => firstLine(i.body) === LOG_MARKER)
    .sort((a, b) => a.number - b.number)[0];
  const record = issues.find((i) =>
    [`<!-- babysit-merge-demotion sha=${env.RUN_SHA} `, `<!-- post-merge-failure sha=${env.RUN_SHA} `].some((p) =>
      firstLine(i.body).startsWith(p),
    ),
  )?.number;
  const canary = issues.find((i) => {
    const sha = CANARY_RECORD.exec(firstLine(i.body))?.[1];
    return i.state === "open" && (range ?? []).includes(sha);
  });

  const logComments = log
    ? (await pages(call, `/repos/${repo}/issues/${log.number}/comments`, null)).filter((c) => c.user?.id === BOT_ID)
    : [];
  const markers = logComments
    .map((c) => ({ match: MARKER_PATTERN.exec(firstLine(c.body)), at: c.created_at }))
    .filter((m) => m.match);
  if (markers.some((m) => m.match[1] === String(run.id) && m.match[2] === String(run.run_attempt))) {
    return { posted: false, summary: `#${log.number} already reports ${runUrl}/attempts/${run.run_attempt}.` };
  }

  // Red full runs since the last green one that the log does not report: a
  // report the repository-wide concurrency group cancelled while pending, or
  // one that confirmed nothing or did not run. This report's range starts at
  // that green run, so it decides over their merges too; it names them, so no
  // dropped report passes unseen.
  const unreported = green
    ? runs
        .filter(
          (r) =>
            r.conclusion === "failure" &&
            String(r.id) !== String(run.id) &&
            r.created_at > green.created_at &&
            !markers.some((m) => m.match[1] === String(r.id)),
        )
        .sort((a, b) => a.created_at.localeCompare(b.created_at))
        .map((r) => ({ url: r.html_url, sha: r.head_sha }))
    : [];

  const attribution = range ? attribute(base.sha, range, statuses) : null;
  let culprit = null;
  let decision = null;
  let revert = null;
  if (attribution?.culprit) {
    const row = rows.find((r) => r.sha === attribution.culprit);
    const commit = commits.find((c) => c.sha === attribution.culprit);
    const pull = row.number ? await call("GET", `/repos/${repo}/pulls/${row.number}`) : null;
    culprit = {
      sha: row.sha,
      number: row.number,
      enqueuer: row.enqueuer,
      message: commit.message,
      labels: (pull?.labels ?? []).map((l) => l.name),
      mergedAt: pull?.merged_at ?? commit.committedAt,
    };
    // Auto-reverts in the last day and of this culprit: the lanes App's
    // auto-revert pull requests, and this log's own dry-run decisions.
    const reverts = (await call("GET", `/repos/${repo}/issues?state=all&labels=auto-revert&sort=created&direction=desc&per_page=100`)) ?? [];
    const ownReverts = reverts.filter(
      (i) => i.pull_request && (i.user?.login ?? "").toLowerCase() === agentIdentity.toLowerCase(),
    );
    const since = Date.parse(now) - DAY_MS;
    const decided = markers.filter((m) => m.match[4] === "auto-revert");
    decision = decide({
      culprit,
      agentIdentity,
      config,
      now,
      revertsToday:
        ownReverts.filter((i) => Date.parse(i.created_at) > since).length +
        decided.filter((m) => Date.parse(m.at) > since).length,
      culpritDecided:
        decided.some((m) => m.match[3] === culprit.sha) ||
        ownReverts.some((i) => (i.body ?? "").includes(`<!-- red-main-revert culprit=${culprit.sha} -->`)),
      platformFault: canary ? `canary record #${canary.number} is open on a merge in the range` : null,
      revertApplies: revertApplies(culprit.sha),
    });
    revert = config.remedy === "rollback" ? plannedRevert(culprit, decision.decision, runUrl) : null;
  }

  const body = renderReport({
    run: runInfo,
    verdict,
    base,
    range: range && rows,
    attribution,
    culprit,
    decision,
    revert,
    config,
    record,
    unreported,
  });
  let target = log?.number;
  if (!target) {
    const created = await call("POST", `/repos/${repo}/issues`, {
      title: "Red-main revert decisions (dry-run log)",
      body: `${LOG_MARKER}\n\nOne comment per confirmed red full run on main: the culprit post-merge-demotion-alert.yml's report job pinned, the evidence runs, and the revert it would open. docs/conventions/pr-pipeline/README.md, "Red main", states the rule. The job writes nothing else while \`red-main.dry-run\` is true.`,
    });
    target = created.number;
  }
  await call("POST", `/repos/${repo}/issues/${target}/comments`, { body });
  return { posted: true, target, body, summary: body };
}

async function main(env = process.env) {
  const { redMainFromBase } = await import(
    pathToFileURL(`${env.BASE_PATH}/.github/actions/resolve-config/resolve-config.mjs`).href
  );
  const result = await report(env, {
    call: client(env),
    sleep: (ms) => delay(ms),
    clock: () => new Date().toISOString(),
    loadConfig: () => redMainFromBase({ BASE_PATH: env.BASE_PATH }),
    revertApplies: revertAppliesWithGit(env.BASE_PATH),
  });
  console.log(result.posted ? `reported on #${result.target}` : result.summary);
  if (env.GITHUB_STEP_SUMMARY) appendFileSync(env.GITHUB_STEP_SUMMARY, `${result.summary}\n`);
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  main().catch((error) => {
    console.log(`::error::${error.message}`);
    process.exitCode = 1;
  });
}
